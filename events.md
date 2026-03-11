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
| 7 | Server spawns Unit_A at (100,100) and Unit_B at (500,500) | `TEST_007` | server.log | 1s |
| 8a | Client A selects its unit | `TEST_008_SELECT` | client_A.log | 0.5s |
| 8b | Client B selects its unit | `TEST_008_SELECT_B` | client_B.log | 0.5s |
| 9a | Client A issues move command to (300,300) | `TEST_009_MOVE` | client_A.log + server.log | 0s |
| 9b | Client B issues move command to (300,300) | `TEST_009_MOVE_B` | client_B.log + server.log | 0s |
| 10 | Units meet; server initiates combat (proximity) | `TEST_010_COMBAT` | server.log | wait for outcome |
| 11 | One unit's HP reaches 0; server declares winner | `TEST_011` | server.log | 2s |
| 12 | Both clients disconnect | `TEST_012` | client_A.log + client_B.log | -- |
