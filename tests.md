# Test Checklist

Tests correspond to events in `events1.md` and `events2.md`. Run with `--events=1` or `--events=2`. A test passes if its `TEST_XXX` marker appears in the expected log file(s).

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
| `TEST_CAPTURE_SPAWN` | 2 capture points spawned (Stables, Blacksmith) | server.log, client_A.log, client_B.log |
| `TEST_008_SELECT` | Client A selected army | client_A.log |
| `TEST_008_SELECT_B` | Client B selected army | client_B.log |
| `TEST_009_MOVE` | Client A moved army to target | client_A.log, server.log |
| `TEST_009_MOVE_B` | Client B moved army to target | client_B.log, server.log |
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
