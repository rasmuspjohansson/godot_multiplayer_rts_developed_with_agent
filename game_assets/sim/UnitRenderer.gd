extends Node3D
## GPU-instanced unit rendering: one MultiMeshInstance3D per (team colour, unit type).
## Per sim tick we write cur/prev positions + state into the multimesh buffer; the
## billboard shader interpolates between ticks and picks the spritesheet frame itself,
## so there is no per-unit GDScript work between ticks.

const UNIT_SPRITE_PATHS := preload("res://UnitSpritePaths.gd")
const SHADER := preload("res://shaders/unit_billboard.gdshader")

const ROWS: Array[String] = ["idle", "move", "attack", "die"]
const FLOATS_PER_INSTANCE := 20 # 12 transform + 4 color + 4 custom
const FOOT_HEIGHT := 22.0
const HORSE_HEIGHT := 28.0
const DRAGON_HEIGHT := 66.0
## Multiplier on authored spritesheet fps (idle/move/attack). 1.0 = JSON playback_fps.
const ANIM_SPEED_DEFAULT := 1.0
const ANIM_SPEED_MIN := 0.5
const ANIM_SPEED_MAX := 3.0
const DIE_LINGER_SEC := 1.5
const SCALE_MIN := 0.25
const SCALE_MAX := 4.0

const STATE_IDLE := 0.0
const STATE_MOVE := 1.0
const STATE_ATTACK := 2.0
const STATE_DIE := 3.0

var sim: RefCounted = null

class Group:
	var key: String
	var mmi: MultiMeshInstance3D
	var mm: MultiMesh
	var mat: ShaderMaterial
	var buf: PackedFloat32Array = PackedFloat32Array()
	var ids: PackedInt32Array = PackedInt32Array()
	var count: int = 0
	var die_duration: float = 1.0

var _groups: Array[Group] = []
var _group_by_key: Dictionary = {}
var _group_of: PackedInt32Array = PackedInt32Array()
var _slot_of: PackedInt32Array = PackedInt32Array()
var _state_of: PackedFloat32Array = PackedFloat32Array()
var _phase_of: PackedFloat32Array = PackedFloat32Array()
var _dead_since: PackedFloat32Array = PackedFloat32Array()
var _selected: PackedByteArray = PackedByteArray()
var _size_mul: PackedFloat32Array = PackedFloat32Array()
## Last written per-unit values so parked units cost nothing per tick.
var _last_x: PackedFloat32Array = PackedFloat32Array()
var _last_z: PackedFloat32Array = PackedFloat32Array()
var _last_hp: PackedFloat32Array = PackedFloat32Array()
var _last_key: PackedInt32Array = PackedInt32Array()
var _static: PackedByteArray = PackedByteArray()
var _collapsed: PackedByteArray = PackedByteArray()
## Terrain height grid (same samples World uses) for an inlined bilinear lookup.
var _hg: PackedFloat32Array = PackedFloat32Array()
var _hg_cols: int = 0
var _hg_rows: int = 0
var _hg_inv_step: float = 1.0
var _quad: QuadMesh = QuadMesh.new()
var _sheet_cache: Dictionary = {}
var _tick_dt: float = 0.05
var _tick_start: float = 0.0
var _t0_usec: int = Time.get_ticks_usec()
var _anim_speed: float = ANIM_SPEED_DEFAULT

func _ready() -> void:
	_quad.size = Vector2.ONE

## Seconds since the renderer was created (kept small so float32 shader time stays precise).
func now_sec() -> float:
	return float(Time.get_ticks_usec() - _t0_usec) * 0.000001

func set_tick_dt(dt: float) -> void:
	_tick_dt = dt

func anim_speed() -> float:
	return _anim_speed

## Live playback rate for idle/move/attack. Death clips stay at authored fps.
func set_anim_speed(s: float) -> void:
	_anim_speed = clampf(s, ANIM_SPEED_MIN, ANIM_SPEED_MAX)
	for g in _groups:
		g.mat.set_shader_parameter("anim_speed", _anim_speed)

func _ensure_unit_capacity(id: int) -> void:
	if id < _group_of.size():
		return
	var n := id + 1
	var old := _group_of.size()
	_group_of.resize(n)
	_slot_of.resize(n)
	_state_of.resize(n)
	_phase_of.resize(n)
	_dead_since.resize(n)
	_selected.resize(n)
	_size_mul.resize(n)
	_last_x.resize(n)
	_last_z.resize(n)
	_last_hp.resize(n)
	_last_key.resize(n)
	_static.resize(n)
	_collapsed.resize(n)
	for i in range(old, n):
		_group_of[i] = -1
		_slot_of[i] = -1
		_size_mul[i] = 1.0
		_last_key[i] = -1
		_static[i] = 0
		_collapsed[i] = 0

## Give the renderer the terrain height samples so it never calls back into World per unit.
func set_height_grid(heights: PackedFloat32Array, cols: int, rows: int, step: float) -> void:
	_hg = heights
	_hg_cols = cols
	_hg_rows = rows
	_hg_inv_step = 1.0 / maxf(step, 0.001)

## Register a unit for rendering. `unit_type` is a UnitSpritePaths type name, `color` a team folder.
func add_unit(id: int, color: String, unit_type: String) -> void:
	_ensure_unit_capacity(id)
	var g := _group_for(color, unit_type)
	var gi: int = _groups.find(g)
	var slot := g.count
	g.count += 1
	if g.ids.size() < g.count:
		g.ids.resize(maxi(g.count, g.ids.size() * 2 if g.ids.size() > 0 else 64))
	g.ids[slot] = id
	_group_of[id] = gi
	_slot_of[id] = slot
	_state_of[id] = STATE_IDLE
	_phase_of[id] = randf() * 10.0
	_dead_since[id] = 0.0
	_selected[id] = 0
	_size_mul[id] = 3.0 if unit_type == "dragon" else 1.0
	_last_key[id] = -1
	_static[id] = 0
	_collapsed[id] = 0
	if g.buf.size() < g.count * FLOATS_PER_INSTANCE:
		var cap: int = maxi(g.count, g.mm.instance_count * 2 if g.mm.instance_count > 0 else 64)
		g.mm.instance_count = cap
		var nb := PackedFloat32Array()
		nb.resize(cap * FLOATS_PER_INSTANCE)
		for i in range(mini(g.buf.size(), nb.size())):
			nb[i] = g.buf[i]
		g.buf = nb
	g.mm.visible_instance_count = g.count

func set_selected_ids(ids: PackedInt32Array, selected: bool) -> void:
	for id in ids:
		if id >= 0 and id < _selected.size():
			_selected[id] = 1 if selected else 0
			_static[id] = 0

func clear_selection() -> void:
	_selected.fill(0)
	_static.fill(0)

## Write the current sim state into every group's buffer. Call once per sim tick.
## Units whose position/state/hp/selection did not change since the last write are skipped
## (their instance already holds a zero interpolation delta), so parked armies are free.
func write_tick() -> void:
	if sim == null:
		return
	var t := now_sec()
	_tick_start = t
	var px: PackedFloat32Array = sim.pos_x
	var pz: PackedFloat32Array = sim.pos_z
	var qx: PackedFloat32Array = sim.prev_x
	var qz: PackedFloat32Array = sim.prev_z
	var hp: PackedFloat32Array = sim.hp
	var mhp: PackedFloat32Array = sim.max_hp
	var flags: PackedByteArray = sim.flags
	var f_alive: int = sim.F_ALIVE
	var f_moving: int = sim.F_MOVING
	var f_combat: int = sim.F_IN_COMBAT
	var f_right: int = sim.F_FACING_RIGHT
	var hg := _hg
	var hg_cols := _hg_cols
	var hg_rows := _hg_rows
	var hg_inv := _hg_inv_step
	var has_ground := hg_cols >= 2 and hg_rows >= 2
	var last_x := _last_x
	var last_z := _last_z
	var last_hp := _last_hp
	var last_key := _last_key
	var stat := _static
	var collapsed := _collapsed
	var state_of := _state_of
	var phase_of := _phase_of
	var dead_since := _dead_since
	var selected := _selected
	var size_mul := _size_mul
	for g in _groups:
		var buf := g.buf
		var ids := g.ids
		var n := g.count
		var dirty := false
		for slot in range(n):
			var id := ids[slot]
			if collapsed[id] != 0:
				continue
			var o := slot * FLOATS_PER_INSTANCE
			var fl := flags[id]
			var state: float
			if (fl & f_alive) == 0:
				if dead_since[id] == 0.0:
					dead_since[id] = t
					phase_of[id] = t
				if t - dead_since[id] > g.die_duration + DIE_LINGER_SEC:
					# Collapse the quad: scale 0; never touched again.
					buf[o] = 0.0
					buf[o + 5] = 0.0
					buf[o + 10] = 0.0
					collapsed[id] = 1
					dirty = true
					continue
				state = STATE_DIE
			elif (fl & f_combat) != 0:
				state = STATE_ATTACK
				if state_of[id] != STATE_ATTACK:
					phase_of[id] = t
			elif (fl & f_moving) != 0:
				state = STATE_MOVE
			else:
				state = STATE_IDLE
			state_of[id] = state
			var x := px[id]
			var z := pz[id]
			var h := hp[id]
			var key: int = int(state) * 4 + (2 if (fl & f_right) != 0 else 0) + (1 if selected[id] != 0 else 0)
			if stat[id] != 0 and key == last_key[id] and x == last_x[id] and z == last_z[id] and h == last_hp[id]:
				continue
			var ox := qx[id]
			var oz := qz[id]
			if state == STATE_MOVE and ox == x and oz == z:
				sim.walk_in_place_count += 1
			var y := 0.0
			var py := 0.0
			if has_ground:
				y = _height_inline(hg, hg_cols, hg_rows, hg_inv, x, z)
				py = y if (ox == x and oz == z) else _height_inline(hg, hg_cols, hg_rows, hg_inv, ox, oz)
			var s := size_mul[id]
			buf[o] = s
			buf[o + 3] = x
			buf[o + 5] = s
			buf[o + 7] = y
			buf[o + 10] = s
			buf[o + 11] = z
			buf[o + 12] = ox - x
			buf[o + 13] = py - y
			buf[o + 14] = oz - z
			buf[o + 15] = h / maxf(mhp[id], 1.0)
			buf[o + 16] = state
			# Veo sheets face right (see UnitSpritePaths.art_faces_right_for_unit):
			# mirror only when the unit is facing left.
			buf[o + 17] = 0.0 if (fl & f_right) != 0 else 1.0
			buf[o + 18] = phase_of[id]
			buf[o + 19] = 1.0 if selected[id] != 0 else 0.0
			last_x[id] = x
			last_z[id] = z
			last_hp[id] = h
			last_key[id] = key
			# Idle with zero delta: the instance is now self-sufficient until something changes.
			stat[id] = 1 if (state == STATE_IDLE and ox == x and oz == z) else 0
			dirty = true
		g.buf = buf
		if dirty and g.mm.instance_count * FLOATS_PER_INSTANCE == buf.size():
			g.mm.buffer = buf
		g.mat.set_shader_parameter("tick_start", _tick_start)
		g.mat.set_shader_parameter("tick_dt", _tick_dt)

func _height_inline(hg: PackedFloat32Array, cols: int, rows: int, inv_step: float, x: float, z: float) -> float:
	var gx: float = clampf(x * inv_step, 0.0, float(cols - 1))
	var gz: float = clampf(z * inv_step, 0.0, float(rows - 1))
	var i0: int = int(gx)
	var j0: int = int(gz)
	var i1: int = mini(i0 + 1, cols - 1)
	var j1: int = mini(j0 + 1, rows - 1)
	var tx: float = gx - float(i0)
	var tz: float = gz - float(j0)
	var r0: int = j0 * cols
	var r1: int = j1 * cols
	var h0: float = hg[r0 + i0] + (hg[r0 + i1] - hg[r0 + i0]) * tx
	var h1: float = hg[r1 + i0] + (hg[r1 + i1] - hg[r1 + i0]) * tx
	return h0 + (h1 - h0) * tz

func _process(_delta: float) -> void:
	var t := now_sec()
	for g in _groups:
		g.mat.set_shader_parameter("time_now", t)

func _group_for(color: String, unit_type: String) -> Group:
	var key := color + "/" + unit_type
	if _group_by_key.has(key):
		return _group_by_key[key]
	var g := Group.new()
	g.key = key
	g.mm = MultiMesh.new()
	g.mm.transform_format = MultiMesh.TRANSFORM_3D
	g.mm.use_colors = true
	g.mm.use_custom_data = true
	g.mm.mesh = _quad
	g.mmi = MultiMeshInstance3D.new()
	g.mmi.name = "Units_" + color + "_" + unit_type
	g.mmi.multimesh = g.mm
	g.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Huge custom AABB: instances are positioned in the shader so the mesh AABB is meaningless.
	g.mmi.custom_aabb = AABB(Vector3(-100000, -10000, -100000), Vector3(200000, 20000, 200000))
	g.mat = ShaderMaterial.new()
	g.mat.shader = SHADER
	g.mmi.material_override = g.mat
	_configure_sheet(g, color, unit_type)
	add_child(g.mmi)
	_groups.append(g)
	_group_by_key[key] = g
	return g

func _configure_sheet(g: Group, color: String, unit_type: String) -> void:
	var info: Dictionary = _stacked_sheet(color, unit_type)
	g.mat.set_shader_parameter("sheet", info["texture"])
	g.mat.set_shader_parameter("sheet_cols", float(info["cols"]))
	g.mat.set_shader_parameter("frames", info["frames"])
	g.mat.set_shader_parameter("fps", info["fps"])
	g.mat.set_shader_parameter("feet", info["feet"])
	g.mat.set_shader_parameter("row_scale", info["row_scale"])
	var base_h := FOOT_HEIGHT
	if unit_type == "dragon":
		base_h = DRAGON_HEIGHT / 3.0 # size_mul 3 for dragons
	elif unit_type in ["knight", "bauer_horse_archer"]:
		base_h = HORSE_HEIGHT
	g.mat.set_shader_parameter("base_height", base_h)
	g.mat.set_shader_parameter("anim_speed", _anim_speed)
	g.die_duration = float(info["die_duration"])

## Builds (and caches) a single texture with the four clips stacked vertically.
func _stacked_sheet(color: String, unit_type: String) -> Dictionary:
	var key := color + "/" + unit_type
	if _sheet_cache.has(key):
		return _sheet_cache[key]
	var clips: Array = []
	var max_cols := 1
	var frame_w := 256
	var frame_h := 256
	for row in ROWS:
		var c := _load_clip(color, unit_type, row)
		if c.is_empty() and color != "blue":
			c = _load_clip("blue", unit_type, row)
		if c.is_empty() and unit_type != "spearman":
			c = _load_clip(color, "spearman", row)
		if not c.is_empty():
			frame_w = int(c["fw"])
			frame_h = int(c["fh"])
			max_cols = maxi(max_cols, int(c["count"]))
		clips.append(c)
	var img := Image.create(max_cols * frame_w, 4 * frame_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var frames := Vector4(1, 1, 1, 1)
	var fps := Vector4(8, 8, 8, 8)
	var feet := Vector4(0.05, 0.05, 0.05, 0.05)
	var char_h := [frame_h, frame_h, frame_h, frame_h]
	var die_duration := 1.0
	for r in range(4):
		var c: Dictionary = clips[r]
		if c.is_empty():
			continue
		var src: Image = c["image"]
		var count: int = int(c["count"])
		img.blit_rect(src, Rect2i(0, 0, count * frame_w, frame_h), Vector2i(0, r * frame_h))
		frames[r] = float(count)
		fps[r] = float(c["fps"])
		# Feet: lowest opaque row across frames; character height: max opaque height across frames.
		var lowest := 0
		var tallest := 1
		for f in range(count):
			var sub: Image = src.get_region(Rect2i(f * frame_w, 0, frame_w, frame_h))
			var used: Rect2i = sub.get_used_rect()
			if used.size.y <= 0:
				continue
			lowest = maxi(lowest, used.position.y + used.size.y - 1)
			tallest = maxi(tallest, used.size.y)
		if lowest <= 0:
			lowest = frame_h - 1
		feet[r] = float(frame_h - 1 - lowest) / float(frame_h)
		char_h[r] = tallest
		if r == 3:
			die_duration = float(count) / maxf(fps[r], 0.01)
	var ref_h: float = float(char_h[1])
	var row_scale := Vector4(1, 1, 1, 1)
	for r in range(4):
		row_scale[r] = clampf(ref_h / maxf(float(char_h[r]), 1.0), SCALE_MIN, SCALE_MAX)
	var tex := ImageTexture.create_from_image(img)
	var info := {
		"texture": tex, "cols": max_cols, "frames": frames, "fps": fps, "feet": feet,
		"row_scale": row_scale, "die_duration": die_duration,
	}
	_sheet_cache[key] = info
	return info

func _load_clip(color: String, unit_type: String, action: String) -> Dictionary:
	var folder := UNIT_SPRITE_PATHS.ai_sprite_folder(color, unit_type, action)
	var manifest_path := folder.path_join("spritesheet.json")
	var png_path := folder.path_join("spritesheet.png")
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(png_path):
		return {}
	var f := FileAccess.open(manifest_path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(png_path))
	if img == null:
		return {}
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return {
		"image": img,
		"fw": int(d.get("frame_width", 256)),
		"fh": int(d.get("frame_height", 256)),
		"count": maxi(1, int(d.get("frame_count", 1))),
		"fps": maxf(0.1, float(d.get("playback_fps", 8.0))),
	}
