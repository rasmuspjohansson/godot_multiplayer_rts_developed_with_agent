# Architecture

How the code is organised and how the server and clients stay in sync. Game rules are in [game_design.md](game_design.md).

## Overview

- Dedicated **headless** server (authoritative for combat, deaths, routs, capture points, resources and the aggressive-seek logic) and two **3D** clients on port 8910.
- **Data-oriented unit simulation** (`game_assets/sim/`): units are integer ids into `PackedFloat32Array`/`PackedByteArray` columns in `UnitSim.gd`; there are no unit nodes, no `CharacterBody3D` and no physics bodies for units anywhere. The sim runs at a fixed **20 Hz** on server and clients from an accumulator in `World._physics_process`.
- **Formation-level orders**: a `FormationController` per army owns the order, one A* path per order and an anchor that advances along it; soldiers steer to fixed slots (`slot_index`, anchor + rotated offset). Spacing is rigid while marching (slots every tick, anchor-speed in-rank movement, cohesion crawl when stragglers exceed 25 %). Orders are tick-scheduled reliable RPCs; server and clients apply them at the same `exec_tick` and run the same movement sim locally.
- **Snapshots are corrections, not movement**: the server sends packed 8-byte unit records (`NetSync.gd`) on `unreliable_ordered`, prioritising units that changed; clients blend small errors and snap only on real desync.
- **GPU instancing**: clients draw all units with one `MultiMeshInstance3D` per (team colour, unit type) (`UnitRenderer.gd` + `shaders/unit_billboard.gdshader`); the shader does billboarding, spritesheet frame selection, flip, selection tint and interpolation between sim ticks. Audio is a 16-player pool parked at army clusters (`UnitAudio.gd`).
- Map sizes S/L/XL (`maps/map_*.json`); terrain height is a bilinear grid lookup (`_terrain_grid_height_at`), never a per-unit raycast. 3D camera pitches from bird's-eye to near-horizontal as you zoom in.
- Design target: 2 players, ~2000–2500 units total. Measured on one laptop running server + 2 clients (XL, 2040 units): server sim tick ≈ 17 ms at a steady 20 Hz, clients ≈ 85 fps, ≈ 33 KB/s server upload. `./run_stress.sh` reproduces this and asserts the thresholds.

- **Navigation**: grid `AStarGrid2D` walkability (water + steep slopes) in `WalkabilityGrid.gd`; **one A* path per army order**, computed identically on server and clients. Soldiers only get an individual (throttled) path when they are stuck behind an obstacle.
- **Autoloads**: `GameState` (players, resources, CLI flags), `MapConfig` (loads `maps/map_*.json`), `AudioSettings`.

## Scene Structure
| Scene           | Purpose |
|-----------------|---------|
| `Main.tscn`     | Entry point: parses CLI args, creates network peer, switches to Lobby. |
| `Lobby.tscn`    | Shows name input, color picker (5 boxes), connected players, ready states. "Ready" toggle button. |
| `World.tscn`    | 3D arena (ground mesh + terrain collider). Server and clients spawn armies into the sim here. |
| (units)         | No unit scene: units are rows in `sim/UnitSim.gd`, drawn by `sim/UnitRenderer.gd` (MultiMesh). |
| (capture)       | Capture points are billboard sprites + server-side logic in `World.gd` (no separate CP scene). |
| `GameOver.tscn` | Displays the winner, then the server returns everyone to the lobby. |
| `MapEditor.tscn` | Standalone map editor (`--map-editor`), see [maps.md](maps.md). |

## Script Files
| Script          | Role |
|-----------------|------|
| `Main.gd`       | Networking setup, scene switching. |
| `Lobby.gd`      | Ready-state RPCs, player list UI. |
| `World.gd`      | Orchestration: order RPCs (validate + echo), sim stepping, snapshots/events, spawning, capture points, selection, camera, rout/win checking. |
| `Army3D.gd`     | Thin per-army handle: id, owner, selection, equipment flags, reference to the sim's `FormationController`. |
| `sim/UnitSim.gd` | Data-oriented unit simulation (SoA arrays): steering, separation, walkability, combat, deaths, routs. Server and clients run the same code; only the authority resolves damage. |
| `sim/FormationController.gd` | Per-army orders (move / attack-move / attack / stances / rotate), slot layout for 10–200 soldiers, one A* path per order, anchor advance and contact pausing. |
| `sim/SpatialHash.gd` | Counting-sort uniform grid over the map; radius / nearest queries for separation, combat, capture points, dragon AI and picking. |
| `sim/NetSync.gd` | Packed 8-byte unit snapshots (<= 1200 B chunks), dirty/idle send scheduling, client reconciliation with per-unit tick check. |
| `sim/UnitRenderer.gd` | GPU-instanced billboards: one MultiMesh per (colour, type), stacked spritesheet textures, per-tick buffer writes, shader-side interpolation. |
| `sim/UnitAudio.gd` | Pooled positional audio (16 cluster players + 6 death one-shots) instead of one player per unit. |
| `GroupFormation.gd` | Line-formation math for RMB drag orders (segments per army, ghost preview positions). |
| `SelectionBar.gd` | Bottom bar: order modes, stances, army portraits, Show range, draft panel. |
| `MapConfig.gd`  | Loads the map JSON; analytical terrain height (`sample_height`), start positions, loadouts. |
| `WalkabilityGrid.gd` | Walkable-cell grid and A* pathfinding. |
| `WaterBuilder.gd` / `VegetationBuilder.gd` | Lake meshes and vegetation billboards built from the map. |
| `ArrowProjectile.gd` / `ArrowTrajectory.gd` | Cosmetic arrow flight. |
| `UnitSpritePaths.gd` / `SpritesheetAnim.gd` | Sprite folder lookup per colour/type/action and portrait loading. |
| `PerfMonitor.gd` | `TEST_PERF_*` markers every 5 s (frame/physics/sim times, sim Hz, fps, memory, bytes/s) and `TEST_SIM_CLIENT` health counters. |
| `TopBar.gd`     | HUD overlay: shows resources and capture point ownership. |
| `GameOver.gd`   | Winner display, disconnect logic. |
| `MockPlayer.gd` | Automated test client (activated by `--auto-test`), see [ai_development.md](ai_development.md). |

## Networking

How this game talks over the network and why it scales to thousands of units. Transport: Godot 4
High-Level Multiplayer API on **ENet**, UDP port **8910**. The dedicated server is authoritative
for combat, deaths, routs, capture points and resources; **movement is simulated on both sides**
from the same order stream and the server only sends compact corrections.

ENet MTU in this Godot build is **1392 bytes** for a single unreliable packet; every unreliable
message below stays under **1200 bytes** by construction (chunking), so nothing fragments.

---

### Mental model

```
Client                                 Server                              Other clients
  |  reliable order (army ids, dest,     |                                       |
  |  facing, seq)  ------------------->  |  validate ownership, stamp seq,       |
  |                                      |  apply to authoritative UnitSim       |
  |  <------ reliable order echo ------- | ------- reliable order echo --------> |
  |  apply to local UnitSim (same code)  |  UnitSim 20 Hz: paths, slots,         |
  |  UnitSim 20 Hz: same movement        |  separation, combat, deaths           |
  |  <--- unreliable_ordered snapshot -- | ---- 8-byte records, <= 1200 B -----> |
  |  reconcile: ignore stale, blend,     |  changed units first, idle ones       |
  |  snap only on real desync            |  every 2 s                            |
  |  <--- reliable batched events ------ | ---- deaths, routs, spawns ---------> |
  |  <--- unreliable arrows/tick ------- |                                       |
```

| Kind | Channel | If it fails |
|------|---------|-------------|
| **Orders and lifecycle** (move / attack / stance / rotate echoes, draft, spawn payloads, deaths, routs, capture/resources, win) | `reliable` | Must arrive. ENet retries; delay is OK, loss is not. |
| **Snapshots** (`_client_snapshot`) | `unreliable_ordered` | A missed chunk is fine: the next one for that unit overwrites. Out-of-order chunks are dropped per unit by sim tick. |
| **Arrow VFX** (`_client_arrows`) | `unreliable` | Purely cosmetic. |

---

### Orders (client -> server -> tick-scheduled on everyone)

All orders are **formation level**: they carry army ids, not unit goals. Sizes are a few dozen
bytes regardless of army size, and the client does **no** pathfinding work before sending.

| RPC (client -> server) | Payload | Server does | Broadcast |
|---|---|---|---|
| `_server_order_move(army_ids, dests, facings, widths, attack_move)` | ids + `PackedFloat32Array`s | ownership check, schedule at `exec_tick` | `_client_order(seq, exec, MOVE, …)` |
| `_server_move_army(aid, target)` (MockPlayer) | id + Vector2 | same for one army | `_client_order` |
| `_server_armies_order_attack(…)` | ids + target | schedule ATTACK | `_client_order` |
| `_server_armies_set_stance(…)` | ids + int | schedule STANCE | `_client_order` |
| `_server_rotate_army(aid, delta)` | id + float | schedule ROTATE | `_client_order` |
| `_server_set_all_armies_aggressive()` | none | STANCE for sender's armies | `_client_order` |
| `request_draft_army(…)` | equipment + count | resources, `_create_army` | `_client_spawn_drafted_army` |

**Scheduling.** The server does not apply a player order when the RPC lands. It enqueues
`exec_tick = sim.tick + ORDER_DELAY` (minimum 4 ticks, raised from the slowest peer's RTT) and
sends `(seq, exec_tick, kind, payload)` reliably to every peer. Both sides pop due orders in
`_run_due_orders()` immediately before `_sim.step()` for that tick, so the order hits identical
sim state on server and clients (same anchor recentre, same A* path, same movement).

**Anchor confirmation.** After the server applies a MOVE at `exec_tick` it sends
`_client_order_applied(seq, [aid, anchor_x, anchor_z, …])`. If a client's anchor differs by
more than `ANCHOR_CONFIRM_TOLERANCE` (2 units) it adopts the server's anchor and replays elapsed
time via `FormationController.repath_from`.

**Army sync.** Every 10 ticks the server sends each army's anchor, dest, moving and
`paused_for_contact` (`_client_army_sync`, unreliable). Clients fold this through
`FormationController.sync_from_server` (anchor blended via `anchor_corr`) so combat-driven
discrete decisions (contact pause, attack re-path, arrival) stay server-owned without slot drift.

**Match start.** Armies spawn idle; the server waits for every client to report World ready, sends
the spawn payload, then waits for every client to report armies built (`_client_match_barrier`).
While that barrier is up the server sim is paused, the client sim and clock are frozen, and
player move/attack RPCs are deferred until the opening spawn march is scheduled so test/player
orders cannot overwrite it at the same exec tick. Then `_client_clock_reseed`, a full snapshot,
and the spawn march as a normal scheduled order.

`seq` is a per-server monotonically increasing counter. A move order is never re-sent per
soldier: A* runs once per army.

---

### Snapshots (`sim/NetSync.gd`)

Wire format, little endian, written with `StreamPeerBuffer`:

```
header  : tick u32 | chunk u8 | reserved u8                     (6 bytes)
per unit: id u16 | x u16 | z u16 | hp u8 (percent) | flags u8   (8 bytes)
```

- `x`/`z` are quantised over the map size (`65535 / map_w`), i.e. < 0.1 unit error on XL.
- `flags` is the sim flag byte (alive, moving, in_combat, facing_right, ranged, horse, neutral).
- A chunk holds at most `MAX_UNITS_PER_CHUNK` (149) records = **1198 bytes**.

**Scheduling (server, per 20 Hz tick).** `budget_for(alive)` = `alive * 2.5 / 20` records,
clamped to [40, 450]: every changed unit is refreshed about every 8 ticks (2.5 Hz). `select_units`
walks the unit list round-robin and takes units whose `dirty_tick` (last tick the unit moved or
changed hp/flags) is newer than their last send and at least `CHANGED_RESEND_TICKS` old, plus
idle units every `IDLE_INTERVAL_TICKS` (40 ticks = 2 s). Nobody starves; parked armies cost
almost nothing.

**Reconciliation (client).** For each record: drop it if `last_applied_tick[id]` is newer;
otherwise `UnitSim.reconcile` sets hp from the percentage, kills the unit if the server says
dead, and corrects the position against the **historical** position at the snapshot tick when
known (ring buffer `HIST_TICKS`), so latency does not pull soldiers backwards. Error &lt; 2 units
is ignored (widened if the snapshot tick is ahead of the local tick), &lt; 60 units is blended
direction-safely (35 % per tick; components opposing the soldier's steering or the army heading
are dropped), larger errors snap. **A snapshot never triggers a repath**; paths come from orders.
Hard snaps are counted (`TEST_SIM_CLIENT snaps=`) and must stay 0 in tests.

**Client clock.** After spawn, the client sim tick is slaved to the server via snapshot ticks and
periodic `_client_tick_sync`. `_step_sim_slaved` steps until `sim.tick == target_tick` with a
per-frame wall-time budget; backlog beyond `SIM_RESYNC_TICKS` fast-forwards once
(`TEST_SIM_RESYNC`). `TEST_SIM_CLIENT` reports `tick_drift`, `corr`, and `late_orders`.

**Bandwidth.** 2040 units on XL with every army parked: ~1 KB/s. Everything marching or
fighting: the budget caps at 450 records/tick = 3.6 KB/tick = **~72 KB/s per client** worst case;
measured stress run averaged **33 KB/s** server upload for two clients.

---

### Events (reliable, batched per tick)

| RPC | When | Payload |
|---|---|---|
| `_client_units_died(ids: PackedInt32Array)` | any death this tick | one RPC per tick, all ids |
| `_client_army_routed(army_id)` | army under the rout threshold | id |
| `_client_spawn_armies(payloads)` / `_client_spawn_dragons` / `_client_spawn_drafted_army` | match start / draft | per army: id, owner, name, anchor, direction, `count`, `first_id`, unit type, equipment flags, optional packed `xs`/`zs` |
| `_client_update_capture` batches (`CAPTURE_SYNC_BATCH_SIZE` = 6) | every 0.5 s / on change | capture ownership + resources |
| `_client_arrows(PackedFloat32Array)` (unreliable) | ranged attacks this tick | 6 floats per arrow, capped at `MAX_ARROWS_PER_TICK` |

Unit ids are assigned by the server at spawn (`_next_unit_id`) and are the only unit identity on
the wire; there are no node paths or names in hot messages.

---

### Debugging

- Server: `TEST_PERF_TICK_MS avg= max= sim_avg= sim_max= sim_hz= ... tx_kbs=` every 5 s.
- Clients: `TEST_PERF_FRAME_MS ... rx_kbs=` and `TEST_SIM_CLIENT snaps= walk_in_place= units=`.
- `./run_stress.sh --units=1000 --map=XL` runs server + two auto-test clients and asserts
  server sim tick <= 25 ms at >= 19 Hz and clients >= 45 fps. Auto-test clients disable vsync
  (`Main.gd`) so a blanked monitor cannot masquerade as a frame-rate problem.
- `above the MTU` warnings in `server.log` mean an unreliable RPC grew past 1392 bytes; the
  stress script counts them (expected 0).

### Summary

- **Hot path:** 20 Hz sim on both peers; server sends 8-byte records for changed units at
  ~2.5 Hz per unit in <= 1200 B chunks. Clients blend, snap only on real desync, never repath.
- **Orders:** formation level, reliable, echoed once with a sequence number; A* once per army.
- **Cold path:** reliable lobby, spawn, deaths, routs, capture/resources, win.
- **Possible next steps:** interest management (prioritise on-screen units using a camera rect
  from the client), reconnect snapshot, porting `UnitSim.step` to a GDExtension for 4 players.
