# Test Checklist

Tests correspond to events in `events1.md` and `events2.md`. Run with `--events=1` or `--events=2`. A test passes if its `TEST_XXX` marker appears in the expected log file(s).

**Invalid markers (run fails if any appear):** `TEST_3D_UNIT_HEIGHT_INVALID`, `TEST_SERVER_UNIT_POSITION_INVALID`, `TEST_3D_TEXTURE_MISSING`, `TEST_3D_TEXTURES_BAD`, and `TEST_3D_TEXTURE_LOAD_FAILED` must **not** appear in any log (server or client). If they do, the run is considered failed.

**3D client textures (when running with `--3d`):** Each client log should contain `TEST_3D_TEXTURES_OK: count=<N>` after armies spawn (and again after draft in events 2 if applicable), with N equal to the number of 3D units on that client.

**Headless asset check:** `godot --headless --path . -s test_texture_paths.gd` must print `TEST_TEXTURE_PATHS_OK: red_blue_png_readable` (verifies `res://images/red|blue/spearman/spearman.png` load the same way as `Unit3D`).

**Headless 3D spawn:** `godot --headless --path . -s test_world3d_spawn.gd` must print `TEST_WORLD3D_SPAWN_OK: units=2` (instantiates `World3D` and runs `_client_spawn_armies_impl` with a minimal army).

**Headless 3D goal arrival:** `godot --headless --path . -s test_world3d_goal_arrival.gd` must print `TEST_WORLD3D_GOALS_REACHED` (spawns two soldiers, issues `Army3D.move_army` with first-soldier anchor math, advances frames until every unit is within 3px of `sync_target_position` on XZ).

**Move orders (2D / 3D):** A short right-click (no drag) issues an **anchor move**: the first alive soldier of the first selected army is translated so its goal lies on the click; all selected units shift by the same delta (formation preserved). Orange **MoveGoalMarkers** show each unit’s current `sync_target` until a new order updates it (separate from green RMB-drag formation ghosts).

**Bundled scripts:** `./run_tests.sh` runs the headless checks above. After `./run_test.sh` finishes the auto-test, `./verify_test_logs.sh` asserts both client logs contain `TEST_3D_TEXTURES_OK`, `TEST_3D_CLIENT_UNITS_SPAWNED: units=40`, and none of the invalid markers above.

## Events 1

| Test ID | Description | Expected In |
|---------|-------------|-------------|
| `TEST_001` | Dedicated server started on port 8910 | server.log |
| `TEST_002` | Client A connected to server | server.log, client_A.log |
| `TEST_003` | Client B connected to server | server.log, client_B.log |
| `TEST_004` | Client A sent ready | server.log, client_A.log |
| `TEST_005` | Client B sent ready | server.log, client_B.log |
| `TEST_006` | Match started, World scene loaded | server.log |
| `TEST_007` | 4 armies spawned (2 per player, 10 soldiers each) | server.log |
| `TEST_3D_CLIENT_UNITS_SPAWNED` | 3D client created all units (`units=40` for 4×10) | client_A.log, client_B.log (with `--3d`) |
| `TEST_WORLD3D_SPAWN_OK` | Headless `test_world3d_spawn.gd` passed | terminal (CI) |
| `TEST_WORLD3D_GOALS_REACHED` | Headless `test_world3d_goal_arrival.gd` passed | terminal (CI) |
| `TEST_CAPTURE_SPAWN` | 2 capture points spawned (Stables, Blacksmith) | server.log, client_A.log, client_B.log |
| `TEST_008_SELECT` | Client A selected army | client_A.log |
| `TEST_008_SELECT_B` | Client B selected army | client_B.log |
| `TEST_009_MOVE` | Client A moved army to target | client_A.log, server.log |
| `TEST_009_MOVE_B` | Client B moved army to target | client_B.log, server.log |
| `TEST_GROUP_FORMATION` | Group line formation RPC exercised (client + server lines) | client_A.log, client_B.log, server.log |
| `TEST_010_COMBAT` | Combat initiated (proximity detected) | server.log |
| `TEST_CAPTURE` | Capture point captured or taken over by a player | server.log |
| `TEST_RESOURCE` | Stables/Blacksmith produced horses/spears | server.log |
| `TEST_SEEK_ENEMY` | Army at CP 5s with no combat seeks closest enemy | server.log |
| `TEST_UNIT_CLEANUP` | Dead units cleaned up on server and clients | server.log, client_A.log, client_B.log |
| `TEST_ROUT` | Army routed (below 30% alive) | server.log |
| `TEST_011` | Game over, winner declared (both armies of loser routed) | server.log |
| `TEST_012` | Both clients disconnected | client_A.log, client_B.log |

## Events 2

Includes all Events 1 markers up to and including capture/resources, plus:

| Test ID | Description | Expected In |
|---------|-------------|-------------|
| `TEST_DRAFT_FAIL` | Draft attempted with insufficient resources (need 10 horses, 10 spears) | server.log |
| `TEST_DRAFT_SUCCESS` | Draft succeeded; army created with equipment | server.log, client_A.log |
| (then combat, rout, winner as in Events 1) | `TEST_010_COMBAT`, `TEST_ROUT`, `TEST_011`, `TEST_012` | server.log, client logs |
