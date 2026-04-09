# Automated Match Event Sequence

Each step has a log marker (`TEST_XXX`) that must appear in the appropriate log file.

| Step | Event | Log Marker | Log File | Delay After |
|------|-------|-----------|----------|-------------|
| 1 | Server starts in headless mode on port 8910 | `TEST_001` | server.log | 2s |
| 2 | Client A connects to server | `TEST_002` | server.log + client_A.log | 1s |
| 3 | Client B connects to server | `TEST_003` | server.log + client_B.log | 1s |
| 4 | Client A sends `set_ready(true)` | `TEST_004` | server.log + client_A.log | 0.5s |
| 5 | Client B sends `set_ready(true)` | `TEST_005` | server.log + client_B.log | 0.5s |
| 6 | Server detects all ready, loads World scene | `TEST_006` | server.log | 1s |
| 7 | Server spawns 4 armies (2 per player, 10 soldiers each) | `TEST_007` | server.log | 1s |
| 7b | Server spawns 2 capture points (Stables, Blacksmith) | `TEST_CAPTURE_SPAWN` | server.log + client_A.log + client_B.log | 0s |
| 8a | Client A selects its first army | `TEST_008_SELECT` | client_A.log | 0.5s |
| 8b | Client B selects its first army | `TEST_008_SELECT_B` | client_B.log | 0.5s |
| 9a | Client A moves army to center | `TEST_009_MOVE` | client_A.log + server.log | 0s |
| 9b | Client B moves army to center | `TEST_009_MOVE_B` | client_B.log + server.log | 0s |
| 9c | **Group line formation**: MockPlayer sends `_server_move_group_formation` with per-soldier targets (two armies → split drag segments, one formation each) | `TEST_GROUP_FORMATION: client units=N` | client_A.log, client_B.log | 0.5s |
| 9c2 | Server applies formation targets | `TEST_GROUP_FORMATION: server assigned=M sender=<pid>` | server.log | 0s |
| 9d | *(Manual / not auto)* **Marquee box select**, **RMB centroid group move**, **RMB drag** with ghost preview: verify in `--no_test` play mode (2D/3D) | — | — | — |
| 10 | Soldiers meet; server initiates combat (proximity) | `TEST_010_COMBAT` | server.log | wait |
| 10a | Armies near capture points trigger captures | `TEST_CAPTURE` | server.log | continues |
| 10a2 | Captured points produce horses (Stables) or spears (Blacksmith) every 2s | `TEST_RESOURCE` | server.log | continues |
| 10a3 | Army at CP for 5s with no combat triggers seek closest enemy | `TEST_SEEK_ENEMY` | server.log | continues |
| 10b | Dead units are cleaned up on server and clients | `TEST_UNIT_CLEANUP` | server.log + client_A.log + client_B.log | continues |
| 11 | An army drops below 30% alive; server routs it | `TEST_ROUT` | server.log | continues |
| 12 | Both armies of a player routed; server declares winner | `TEST_011` | server.log | 2s |
| 13 | Both clients disconnect | `TEST_012` | client_A.log + client_B.log | -- |
