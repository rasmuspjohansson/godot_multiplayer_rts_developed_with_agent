extends CanvasLayer
## Bottom command bar (Total War / Age of Empires style). One dark strip across the bottom
## of the screen with three blocks:
##   left   - order mode (Move / Attack / Attack-Move) and stance toggles for the selection
##   centre - one portrait button per selected army (unit sprite, soldier count, stance)
##   right  - Show range toggle and a Draft button that pops the draft panel above the bar
## World owns the selection model; the bar only mirrors `selected_armies` (see set_armies)
## and reports clicks (army_pressed with the Shift state) so World can replace or toggle.

signal order_mode_changed(mode: int)
signal stance_pressed(stance: int)
signal army_pressed(army, shift: bool)
signal show_range_toggled(pressed: bool)

const UnitSpritePaths := preload("res://UnitSpritePaths.gd")
const SpritesheetAnim := preload("res://SpritesheetAnim.gd")
const UnitSim := preload("res://sim/UnitSim.gd")

enum OrderMode { MOVE, ATTACK, ATTACK_MOVE }

const BAR_HEIGHT := 110
const PORTRAIT_PX := 72
const ORDER_LABELS := ["Move", "Attack", "Attack-Move"]
const ORDER_KEYS := ["M", "A", "G"]
const STANCE_LABELS := ["Aggressive", "Defensive", "Hold", "Passive"]
const STANCE_GLYPHS := ["AGG", "DEF", "HLD", "PAS"]
const BAR_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const SELECTED_BORDER := Color(0.95, 0.85, 0.35, 1.0)

var _root: Control
var _order_buttons: Array[Button] = []
var _stance_buttons: Array[Button] = []
var _order_mode: int = OrderMode.MOVE
var _portraits: HBoxContainer
var _portrait_cache: Dictionary = {}
var _hint: Label
var _draft_button: Button
var _draft_panel: PanelContainer
var _show_range_cb: CheckBox
var _armies: Array = []
var sim = null

func _ready() -> void:
	layer = 45
	_root = Control.new()
	_root.name = "SelectionBarRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_root.offset_top = -BAR_HEIGHT
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.name = "BarBG"
	bg.color = BAR_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var top_line := ColorRect.new()
	top_line.color = Color(1, 1, 1, 0.15)
	top_line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_line.offset_bottom = 1
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top_line)

	var row := HBoxContainer.new()
	row.name = "Blocks"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.offset_top = 8
	row.offset_bottom = -8
	row.add_theme_constant_override("separation", 16)
	_root.add_child(row)

	row.add_child(_build_orders_block())
	row.add_child(_make_vsep())
	var centre := _build_centre_block()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(centre)
	row.add_child(_make_vsep())
	row.add_child(_build_right_block())
	_build_draft_panel()
	set_armies([])

func _make_vsep() -> VSeparator:
	var s := VSeparator.new()
	s.modulate = Color(1, 1, 1, 0.35)
	return s

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return l

## Left block: order mode toggles on top, stance buttons below.
func _build_orders_block() -> Control:
	var box := VBoxContainer.new()
	box.name = "Orders"
	box.add_theme_constant_override("separation", 4)
	box.add_child(_section_label("ORDER"))
	var order_row := HBoxContainer.new()
	order_row.add_theme_constant_override("separation", 4)
	box.add_child(order_row)
	for i in range(ORDER_LABELS.size()):
		var btn := Button.new()
		btn.text = "%s (%s)" % [ORDER_LABELS[i], ORDER_KEYS[i]]
		btn.toggle_mode = true
		btn.button_pressed = i == OrderMode.MOVE
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 30)
		var mode := i
		btn.pressed.connect(func(): _set_order_mode(mode))
		order_row.add_child(btn)
		_order_buttons.append(btn)
	box.add_child(_section_label("STANCE"))
	var stance_row := HBoxContainer.new()
	stance_row.add_theme_constant_override("separation", 4)
	box.add_child(stance_row)
	for i in range(STANCE_LABELS.size()):
		var btn := Button.new()
		btn.text = STANCE_LABELS[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 30)
		var stance := i
		btn.pressed.connect(func(): stance_pressed.emit(stance))
		stance_row.add_child(btn)
		_stance_buttons.append(btn)
	return box

## Centre block: portraits of the selected armies, or a hint when nothing is selected.
func _build_centre_block() -> Control:
	var box := VBoxContainer.new()
	box.name = "Selection"
	box.add_theme_constant_override("separation", 4)
	box.add_child(_section_label("SELECTED ARMIES   (click: select only  |  Shift+click: add / remove)"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_portraits = HBoxContainer.new()
	_portraits.name = "Portraits"
	_portraits.add_theme_constant_override("separation", 6)
	scroll.add_child(_portraits)
	_hint = Label.new()
	_hint.text = "No army selected — left-click or drag a box over your soldiers."
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portraits.add_child(_hint)
	return box

## Right block: range toggle and the draft popup button.
func _build_right_block() -> Control:
	var box := VBoxContainer.new()
	box.name = "Tools"
	box.add_theme_constant_override("separation", 4)
	box.add_child(_section_label("TOOLS"))
	_show_range_cb = CheckBox.new()
	_show_range_cb.name = "ShowRangeCheck"
	_show_range_cb.text = "Show range"
	_show_range_cb.focus_mode = Control.FOCUS_NONE
	_show_range_cb.toggled.connect(func(p: bool): show_range_toggled.emit(p))
	box.add_child(_show_range_cb)
	_draft_button = Button.new()
	_draft_button.name = "DraftButton"
	_draft_button.text = "Draft army"
	_draft_button.toggle_mode = true
	_draft_button.focus_mode = Control.FOCUS_NONE
	_draft_button.custom_minimum_size = Vector2(120, 30)
	_draft_button.toggled.connect(func(p: bool): _draft_panel.visible = p)
	box.add_child(_draft_button)
	return box

## Empty draft panel docked above the bar's right edge; World fills it (see draft_panel()).
func _build_draft_panel() -> void:
	_draft_panel = PanelContainer.new()
	_draft_panel.name = "DraftPanel"
	_draft_panel.visible = false
	_draft_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_draft_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_draft_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_draft_panel.offset_right = -10
	_draft_panel.offset_bottom = -BAR_HEIGHT - 6
	_draft_panel.offset_left = -240
	_draft_panel.offset_top = -BAR_HEIGHT - 6 - 190
	add_child(_draft_panel)

## Container World puts the draft controls into.
func draft_panel() -> PanelContainer:
	return _draft_panel

func hide_draft_panel() -> void:
	_draft_button.button_pressed = false
	_draft_panel.visible = false

func get_order_mode() -> int:
	return _order_mode

func _set_order_mode(mode: int) -> void:
	_order_mode = mode
	for i in range(_order_buttons.size()):
		_order_buttons[i].button_pressed = i == mode
	order_mode_changed.emit(mode)

## Enable the order/stance block only while something is selected.
func _set_orders_enabled(enabled: bool) -> void:
	for b in _order_buttons:
		b.disabled = not enabled
	for b in _stance_buttons:
		b.disabled = not enabled

## Mirror the selection: one portrait per army, in selection order.
func set_armies(armies: Array) -> void:
	_armies = []
	for a in armies:
		if a != null and is_instance_valid(a) and not a.is_routed:
			_armies.append(a)
	for c in _portraits.get_children():
		if c != _hint:
			c.queue_free()
	_hint.visible = _armies.is_empty()
	_set_orders_enabled(not _armies.is_empty())
	for a in _armies:
		_portraits.add_child(_make_portrait(a))

## Cheap periodic refresh of counts / stance glyphs without rebuilding buttons.
func refresh_counts() -> void:
	for c in _portraits.get_children():
		if c == _hint or not c.has_meta("army"):
			continue
		var a = c.get_meta("army")
		if a == null or not is_instance_valid(a) or a.is_routed:
			continue
		var count_label: Label = c.get_node_or_null("Count")
		if count_label != null:
			count_label.text = str(_alive_count(a))
		var stance_label: Label = c.get_node_or_null("Stance")
		if stance_label != null:
			stance_label.text = STANCE_GLYPHS[clampi(a.stance, 0, STANCE_GLYPHS.size() - 1)]

func _alive_count(a) -> int:
	if sim != null and a.fc != null:
		return sim.army_alive_count(a.fc)
	return a.soldier_count()

func _make_portrait(a) -> Control:
	var btn := TextureButton.new()
	btn.name = "Army_" + a.army_id
	btn.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_normal = _portrait_texture(a)
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "%s — %d soldiers\nClick: select only this army\nShift+click: remove from selection" % [a.army_id, _alive_count(a)]
	btn.set_meta("army", a)
	var army = a
	btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			army_pressed.emit(army, ev.shift_pressed)
			btn.accept_event()
	)
	# Frame: dark plate behind the sprite, gold border marks it as part of the selection.
	var plate := Panel.new()
	plate.name = "Plate"
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.show_behind_parent = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.14, 0.9)
	sb.border_color = SELECTED_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	plate.add_theme_stylebox_override("panel", sb)
	btn.add_child(plate)
	var count := Label.new()
	count.name = "Count"
	count.text = str(_alive_count(a))
	count.add_theme_font_size_override("font_size", 14)
	count.add_theme_color_override("font_color", Color.WHITE)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 3)
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	count.offset_right = -4
	count.offset_bottom = -2
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(count)
	var stance := Label.new()
	stance.name = "Stance"
	stance.text = STANCE_GLYPHS[clampi(a.stance, 0, STANCE_GLYPHS.size() - 1)]
	stance.add_theme_font_size_override("font_size", 10)
	stance.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	stance.add_theme_color_override("font_outline_color", Color.BLACK)
	stance.add_theme_constant_override("outline_size", 3)
	stance.position = Vector2(4, 2)
	stance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(stance)
	return btn

## Idle frame 0 of the army's unit sprite (256x256, faces right), cached per colour/type.
func _portrait_texture(a) -> Texture2D:
	var color := "red" if a.is_npc or (a.fc != null and a.fc.is_npc) else UnitSpritePaths.color_folder_for_peer(a.owner_id)
	var unit_type := UnitSpritePaths.unit_type_for_equipment(a.has_horse, a.has_spear, a.has_bow)
	if sim != null and a.fc != null and a.fc.members.size() > 0:
		unit_type = UnitSim.unit_type_name(sim.utype[a.fc.members[0]])
	var key := "%s/%s" % [color, unit_type]
	if _portrait_cache.has(key):
		return _portrait_cache[key]
	var tex: Texture2D = null
	var anim = SpritesheetAnim.load_from_folder(UnitSpritePaths.ai_sprite_folder(color, unit_type, "idle"))
	if anim != null:
		var at: AtlasTexture = anim.get_frame_texture()
		at.region = Rect2(0, 0, anim.get_frame_width(), anim.get_frame_height())
		tex = at
	if tex == null:
		tex = UnitSpritePaths.load_static_spearman_texture(color)
	_portrait_cache[key] = tex
	return tex
