extends RefCounted
## Packed unit snapshots. Wire format (little endian):
##   header: tick u32, chunk u8, reserved u8
##   per unit: id u16, x u16, z u16 (quantised over the map), hp u8 (percent), flags u8
## Server side also owns the send schedule: units that changed since their last send go
## first (round-robin so nobody starves), idle units are refreshed every IDLE_INTERVAL ticks.

const HEADER_BYTES := 6
const UNIT_BYTES := 8
const MAX_CHUNK_BYTES := 1200
const MAX_UNITS_PER_CHUNK := int((MAX_CHUNK_BYTES - HEADER_BYTES) / UNIT_BYTES)
const IDLE_INTERVAL_TICKS := 40
## Snapshot target: each changed unit about every 8 ticks (2.5 Hz at 20 Hz sim).
const CHANGED_RESEND_TICKS := 8
const MIN_BUDGET := 40
const MAX_BUDGET := 450

var map_w: float = 1.0
var map_h: float = 1.0
var _qx: float = 1.0
var _qz: float = 1.0
var _inv_qx: float = 1.0
var _inv_qz: float = 1.0

# Server scheduling state.
var last_sent_tick: PackedInt32Array = PackedInt32Array()
var _cursor: int = 0

# Client reconciliation state.
var last_applied_tick: PackedInt32Array = PackedInt32Array()

func setup(w: float, h: float) -> void:
	map_w = maxf(w, 1.0)
	map_h = maxf(h, 1.0)
	_qx = 65535.0 / map_w
	_qz = 65535.0 / map_h
	_inv_qx = map_w / 65535.0
	_inv_qz = map_h / 65535.0

func _ensure(n: int) -> void:
	if last_sent_tick.size() < n:
		var old := last_sent_tick.size()
		last_sent_tick.resize(n)
		last_applied_tick.resize(n)
		for i in range(old, n):
			last_sent_tick[i] = -1000000
			last_applied_tick[i] = -1

## Per-tick budget of unit records for `alive` living units.
func budget_for(alive: int) -> int:
	return clampi(int(ceil(float(alive) * 2.5 / 20.0)), MIN_BUDGET, MAX_BUDGET)

## Picks unit ids to send this tick. `dirty_tick[id]` is the sim tick a unit last changed.
func select_units(sim: RefCounted, tick: int, budget: int) -> PackedInt32Array:
	var n: int = sim.count
	_ensure(n)
	var out := PackedInt32Array()
	if n == 0:
		return out
	var flags: PackedByteArray = sim.flags
	var dirty: PackedInt32Array = sim.dirty_tick
	var f_alive: int = sim.F_ALIVE
	var sent := last_sent_tick
	var idle_cut := tick - IDLE_INTERVAL_TICKS
	var resend_cut := tick - CHANGED_RESEND_TICKS
	var start := _cursor
	var i := start
	var visited := 0
	while visited < n and out.size() < budget:
		if i >= n:
			i = 0
		var st := sent[i]
		if (flags[i] & f_alive) != 0 or dirty[i] > st:
			if (dirty[i] > st and st <= resend_cut) or st <= idle_cut:
				out.append(i)
				sent[i] = tick
		i += 1
		visited += 1
	_cursor = i
	return out

func pack(sim: RefCounted, ids: PackedInt32Array, first: int, count: int, tick: int, chunk: int) -> PackedByteArray:
	var px: PackedFloat32Array = sim.pos_x
	var pz: PackedFloat32Array = sim.pos_z
	var hp: PackedFloat32Array = sim.hp
	var mhp: PackedFloat32Array = sim.max_hp
	var flags: PackedByteArray = sim.flags
	var b := StreamPeerBuffer.new()
	b.resize(HEADER_BYTES + count * UNIT_BYTES)
	b.put_u32(tick)
	b.put_u8(chunk)
	b.put_u8(0)
	for k in range(first, first + count):
		var id := ids[k]
		b.put_u16(id)
		b.put_u16(clampi(int(px[id] * _qx), 0, 65535))
		b.put_u16(clampi(int(pz[id] * _qz), 0, 65535))
		var pct := 0
		if mhp[id] > 0.0:
			pct = clampi(int(round(hp[id] * 100.0 / mhp[id])), 0, 100)
		b.put_u8(pct)
		b.put_u8(flags[id])
	return b.data_array

## Packs all `ids` into <= MAX_CHUNK_BYTES chunks.
func pack_chunks(sim: RefCounted, ids: PackedInt32Array, tick: int) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var n := ids.size()
	var first := 0
	var chunk := 0
	while first < n:
		var cnt := mini(MAX_UNITS_PER_CHUNK, n - first)
		out.append(pack(sim, ids, first, cnt, tick, chunk))
		first += cnt
		chunk += 1
	return out

## Returns {tick, ids, xs, zs, hp_pct, flags}; empty Dictionary on malformed input.
func unpack(bytes: PackedByteArray) -> Dictionary:
	var size := bytes.size()
	if size < HEADER_BYTES or (size - HEADER_BYTES) % UNIT_BYTES != 0:
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var tick := b.get_u32()
	var _chunk := b.get_u8()
	b.get_u8()
	var n := int((size - HEADER_BYTES) / UNIT_BYTES)
	var ids := PackedInt32Array()
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var hp := PackedByteArray()
	var fl := PackedByteArray()
	ids.resize(n)
	xs.resize(n)
	zs.resize(n)
	hp.resize(n)
	fl.resize(n)
	for k in range(n):
		ids[k] = b.get_u16()
		xs[k] = float(b.get_u16()) * _inv_qx
		zs[k] = float(b.get_u16()) * _inv_qz
		hp[k] = b.get_u8()
		fl[k] = b.get_u8()
	return {"tick": tick, "ids": ids, "xs": xs, "zs": zs, "hp_pct": hp, "flags": fl}

## Client side: apply a snapshot to the local sim. Returns the number of units updated.
func apply_snapshot(sim: RefCounted, snap: Dictionary) -> int:
	if snap.is_empty():
		return 0
	var tick: int = snap["tick"]
	var ids: PackedInt32Array = snap["ids"]
	_ensure(sim.count)
	var applied := 0
	var xs: PackedFloat32Array = snap["xs"]
	var zs: PackedFloat32Array = snap["zs"]
	var hp: PackedByteArray = snap["hp_pct"]
	var fl: PackedByteArray = snap["flags"]
	for k in range(ids.size()):
		var id := ids[k]
		if id < 0 or id >= sim.count:
			continue
		if last_applied_tick[id] > tick:
			continue
		last_applied_tick[id] = tick
		sim.reconcile(id, xs[k], zs[k], float(hp[k]) * 0.01, fl[k])
		applied += 1
	return applied
