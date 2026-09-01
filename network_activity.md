# Network activity

How this game talks over the network, why clients used to drop, and how to scale to far more units.

Transport: Godot 4 High-Level Multiplayer API on **ENet**, UDP port **8910**. Dedicated server is authoritative. Clients send orders; the server simulates movement, combat, capture, and resources. Clients **walk locally toward the last known goal**; the server only **corrects** a few units at a time.

ENet MTU in this Godot build is **1392 bytes** for a single unreliable packet. Larger unreliable RPCs are warned and **fragment / drop**. That caused WAN disconnects (XL capture sync at 1672 bytes; unbatched 40-unit position dump at ~9700 bytes). Batches stay at most 4 units / 6 capture points per packet.

---

## Mental model

```
Client                         Server                         Other clients
  |  reliable order (click)      |                                  |
  |----------------------------->|  sim (physics, combat, A*)       |
  |                              |  reliable army goal              |
  |<-----------------------------|--------------------------------->|
  |  walk locally toward goal    |                                  |
  |  unreliable: 4 units / 50ms  |  round-robin corrections         |
  |<-----------------------------|--------------------------------->|
  |  capture/resources on change |                                  |
```

Two kinds of traffic:

| Kind | Channel | If it fails |
|------|---------|-------------|
| **Orders and lifecycle** (move, draft, death, spawn, win) | `reliable` | Must arrive. ENet retries. Delay is OK; loss is not. |
| **Visual corrections / HUD** (staggered positions, HP, CP on change) | `unreliable` | A missed packet is OK. The next correction overwrites. **Oversized packets are not OK** — they cause disconnects. |

---

## How often things are sent

### Staggered unit corrections (~2 Hz per unit at 40 units)

From `_physics_process` in [`World.gd`](World.gd), after `_receive_client_world_ready`:

Every **50 ms** the server sends **one** unreliable `_receive_positions` RPC with at most `POSITION_SYNC_BATCH_SIZE` (**4**) living units, then advances `_sync_cursor`. Units are not all synced on the same tick.

| Living units | Full cycle | Per-unit rate |
|-------------:|-----------:|--------------:|
| 40 (current match) | 0.5 s | **~2 Hz** |
| 200 | 2.5 s | **~0.4 Hz** |
| 4 or fewer | 50 ms | 20 Hz (harmless) |

Payload per unit (Godot `Dictionary` / Variant) is unchanged:

| Key | Meaning | Type today |
|-----|---------|------------|
| `n` | Unit node name | `String` |
| `x`, `y` | Server XZ | `float` |
| `hp` | Hit points | `float` |
| `tx`, `ty` | Path steer waypoint | `float` × 2 |
| `fx`, `fy` | Final formation goal | `float` × 2 |
| `ic` | In combat | `bool` |
| `moving` | Has a move goal | `bool` |

`dead_names` is attached when the cursor wraps a full cycle. Deaths are also sent **reliable** via `_client_unit_died`.

**Client apply** ([`Unit3D.apply_network_sync`](Unit3D.gd)):

- Error **> 120** world units: snap to server position, then repath (desync safety net).
- Smaller error: store an XZ offset and **blend it in** at up to unit `speed` (no teleport). Keep walking the existing goal.
- HP always lerps toward `sync_target_hp` (moving or idle).
- Fight anim (`in_combat`) can lag by up to one cycle (~0.5 s). Arrows and deaths stay reliable.

New destinations still arrive immediately on **reliable** `_client_move_army` (player click, draft walk-in, aggressive chase). The staggered snapshot is catch-up, not the order channel.

### Capture and resources — on change only

`_sync_capture_state()` still runs on the 50 ms pump and after draft, but **returns without an RPC** unless:

- a capture point `owner_pid` changed, or
- any player inventory integer changed (2 s production tick, draft spend), or
- this is the **first** HUD send after world-ready.

Batching: `CAPTURE_SYNC_BATCH_SIZE := 6` if several CPs flip in one frame (XL has 11).

### On player input (rare)

Client → server, all **reliable**:

| RPC | When |
|-----|------|
| `_server_move_army` | RMB move |
| `_server_move_group_formation` | Formation / line move (array of `{n, x, y}` per soldier) |
| `_server_armies_order_attack_move` | Attack-move |
| `_server_army_order_attack` | Attack army or unit |
| `_server_armies_set_stance` | Stance buttons |
| `_server_rotate_army` | Q/E rotate |
| `request_draft_army` | Create army |
| `_server_set_all_armies_aggressive` | MockPlayer / bulk stance |

Server fans out a small **reliable** echo (`_client_move_army`, `_client_sync_army_stance`, …).

### Once per match / on events (rare)

All **reliable**:

| RPC | When | Must succeed? |
|-----|------|----------------|
| `register_player`, `set_my_color`, `_receive_ready`, `_sync_players*` | Lobby | Yes |
| `_start_match` | All ready | Yes |
| `_receive_client_world_ready` | Client finished building World | Yes — otherwise server never starts corrections |
| `_client_spawn_armies`, `_client_spawn_capture_points`, `_client_spawn_dragons` | Match start | Yes |
| `_client_spawn_drafted_army` | Draft | Yes |
| `_client_unit_died`, `_client_army_routed` | Combat | Yes (otherwise ghosts) |
| `_client_spawn_arrow` | Each ranged shot | Nice-to-have; miss = missing VFX only |
| `_announce_winner`, `_client_return_to_lobby` | End of match | Yes |

Spawn army payload is large but sent **once**. Reliable + fragmentation is acceptable here.

---

## What must arrive vs what may fail

**Must succeed:**

- Join / color / ready / start match
- “World loaded” handshake
- Spawn armies, CPs, drafted armies
- Move / attack / stance / draft *orders*
- Unit death and army rout
- Winner + return to lobby

**OK to lose a packet:**

- One staggered position correction — client keeps walking toward last known goal
- One HP correction — bar lerps on the next packet for that unit
- One capture/resource HUD update
- Arrow VFX

**Not OK even on unreliable:**

- A **single packet larger than ~1392 bytes**. Godot logs `Sending N bytes unreliably which is above the MTU`.

Rule of thumb: **unreliable = small corrections; reliable = important and rare.**

---

## Why dropouts happened (and what changed)

1. **MTU overflow** — full 40-unit dump and 11-CP HUD on unreliable. **Mitigated:** max 4 units per packet; CP batches of 6; HUD not every tick.
2. **Client still loading World** — XL `_ready` blocked for seconds while snapshots flooded. **Mitigated:** `_receive_client_world_ready` gate.
3. **Volume** — was ~480 unreliable packets/s at 40 units (20 Hz × 12 RPCs × 2 clients). **Now:** 20 position RPCs/s total (one per 50 ms per broadcast), plus CP RPCs only on capture/resource ticks (~0.5 Hz).
4. **Fat Variant dicts** — still true; packing is the next bandwidth win, not required for current counts.
5. **No delta** — idle units are still in the round-robin (cheap at 4/tick). Unchanged CPs/resources are **not** resent.

---

## Bandwidth sketch

Assumptions: Variant overhead ~80 bytes/unit; 2 clients; 40 units.

| Setup | Position traffic (order of magnitude) |
|-------|--------------------------------------|
| Old 20 Hz everyone | 40 × 80 × 20 = **~64 KB/s** per client |
| **Staggered 4 units / 50 ms (~2 Hz each)** | 4 × 80 × 20 = **~6 KB/s** per client |
| 200 units, same stagger | still **~6 KB/s** (cycle slows; each unit less often) |

Capture/resources: one small RPC per production tick (2 s) or on capture/draft, not 40 RPCs/s.

---

## Data types on the wire

GDScript `float` is IEEE-754 **double**. RPC arguments are Godot **Variants**, not a packed struct.

| Field | Current | Needed precision | Better wire type |
|-------|---------|------------------|------------------|
| Unit id | `String` name | Unique among thousands | `uint16` / `uint32` at spawn |
| Position XZ | `float` | 0.1 world-unit | quantized `uint16` or `float32` |
| Goal XZ | two `float` pairs | Same | quantize; skip if goal unchanged |
| HP | `float` | 0–300 integer | `uint8` / `uint16` |
| In combat / moving | `bool` | 1 bit | bitflags |
| CP id / type | `String` | Small enum | `uint8` |
| Owner name | `String` on CP events | HUD | `owner_pid` only |
| Resources | four `int`s on change | Already on change | keep |

A packed snapshot of one unit could be ~12–16 bytes. Useful before hundreds of units, not required at 40.

---

## Layers (what is implemented vs later)

**A. Reliable events (done)** — spawn, death, rout, orders, draft, winner, lobby.

**B. Client goal-follow (done)** — after `_client_move_army` / snapshot `fx,fy`, client A* walks locally.

**C. Unreliable staggered correction (done)** — 4 units per 50 ms, soft-blend, snap only if error > 120.

**D. Capture/resources on change (done).**

**E. Reconnect / repair snapshot (not implemented)**

If a client is silent or rejoins:

1. Client sends `request_full_state` (or server notices timeout).
2. Server sends one **reliable** packed blob: living units, CPs, resources.
3. Client replaces local state; resumes goal-follow.

Do not replay missed unreliable ticks. Snapshots are the repair.

Suggested timeout (not implemented): 10–15 s → current `peer_disconnected` path. Reconnect with same name needs numeric unit ids (names embed peer id today).

**F. Later scale work:** skip units that have not moved; drop `tx,ty` (client pathfinds to `fx,fy`); numeric ids; `PackedByteArray`; interest management (only units near camera).

---

## Scaling unit count

| Scale | What breaks first | What is in place |
|------:|-------------------|------------------|
| 40 | Used to be MTU + 20 Hz flood | Stagger + batch + world-ready + CP-on-change |
| ~200 | Correction interval ~2.5 s; combat anim lag | Raise batch size slightly, or dirty-only units |
| ~300 | Server sim CPU, then Variant size | Packed snapshots, numeric ids |
| 1000+ | Pathfinding + combat | Spatial hashing, interest |

Server remains authority for combat and capture. Clients never decide “this unit died.” They may be a fraction of a second behind on position.

---

## Debugging dropouts

1. `Sending N bytes unreliably which is above the MTU (1392)` — payload too big.
2. Disconnect before `TEST_CLIENT_WORLD_READY` — client still in `_ready`.
3. One client drops mid-match, no MTU line — NAT, stall, or GPU; `TEST_PEER_DISCONNECT` on server.
4. Ghost units after combat — missed reliable `_client_unit_died` (should be rare).

Useful markers: `TEST_CLIENT_WORLD_READY`, `TEST_PEER_DISCONNECT`, `TEST_CLIENT_DISCONNECT`, `TEST_ARMIES_SPAWNED`.

---

## Summary

- **Hot path:** one unreliable RPC every 50 ms with **4 units** (round-robin). Clients simulate movement toward goals. Soft-blend corrections; snap only if far off.
- **HUD:** capture ownership and resources only when they change.
- **Cold path:** reliable lobby, spawn, orders, death, win.
- **Next for huge armies:** packed ids/coords, skip idle units, reconnect snapshot.
