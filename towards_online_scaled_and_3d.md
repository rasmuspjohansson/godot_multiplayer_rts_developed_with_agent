# Towards online, scaled, and 3D

Phased roadmap. Mark steps with `- [x]` when done. Run verification after each step.

Reference: `Main.gd` PORT (line 3), `create_client("localhost", PORT)` (line 70).

---

## Phase A: Remote server and scaling prep

- [x] **A1 – Configurable server host**  
  In `Main.gd`, replace hardcoded `create_client("localhost", PORT)` with host from CLI `--host=IP` or env `GODOT_SERVER_HOST`, default `localhost`. Document in README/skills.  
  **Verification:** Run events 1 test with default host; run server + client with `--host=127.0.0.1` and confirm connection.

- [x] **A2 – Scaling constants**  
  In `World.gd` (or GameState), add constants: armies per player (2), units per army (10), map width/height (1280, 720). Use in spawn and map setup.  
  **Verification:** Run events 1; optionally change one constant and confirm behaviour.

- [x] **A3 – Optional: spatial grid for unit queries**  
  Add a 2D grid (cell size ~100–150 px) in `World.gd`; track units per cell; use for combat/capture proximity instead of scanning all units.  
  **Verification:** Run events 1 and events 2; same TEST_ markers, no regressions.

---

## Phase B: Scale (larger map, more units, more players)

- [x] **B1 – Support 3–4 players**  
  Generalize spawn and `player_side` for N players (2–4). Sides: west/east or N/S/E/W. Win: last player with non-routed army. Update lobby and "2 players" checks.  
  **Verification:** Events 1 with 2 players; optionally 3–4 clients.

- [x] **B2 – Larger map**  
  Use map size from A2; increase navigation polygon and world size; adjust spawn and capture positions.  
  **Verification:** Run events 1; manual check movement and capture.

- [x] **B3 – Sync and bandwidth**  
  Delta/dirty sync or batch `_sync_unit_positions` under MTU. No MTU warning at current unit count.  
  **Verification:** Events 1; server log without MTU warning.

---

## Phase C: 3D conversion

- [x] **C1 – 3D project setup**  
  Add `World3D.tscn` (Node3D root, flat ground, one test 3D body). Keep 2D World default; switch via flag.  
  **Verification:** Load 3D scene; no errors.

- [x] **C2 – Camera (angle + zoom)**  
  Camera3D with fixed angle (e.g. 45°), zoom (distance/FOV), optional pan.  
  **Verification:** Run 3D scene; camera view and zoom/pan work.

- [x] **C3 – Map and coordinates**  
  Same logical size (x/z = 2D x/y). Ground y=0. Raycast click to ground; (x, z) for server.  
  **Verification:** Click ground; server gets (x, z); move works.

- [x] **C4 – 3D units**  
  One 3D node per unit; position (x, 0, z) from server. Keep server logic 2D.  
  **Verification:** Spawn/move units in 3D; positions in sync.

- [x] **C5 – Integrate 3D into main flow**  
  Add `--3d` or config; load World3D instead of World; same lobby/game-over. UI stays 2D overlay.  
  **Verification:** Full run: lobby → match in 3D → game over.

---

## Phase D: Movement sync (implement last)

- [x] **D1 – "You are HERE, on your way to THERE"**  
  Server sends per unit: current position (HERE) and current move target (THERE). Client moves unit smoothly toward THERE; on each update, correct position to new HERE and continue toward new THERE.  
  **Verification:** Events 1 and 2; smooth movement, no regressions.
