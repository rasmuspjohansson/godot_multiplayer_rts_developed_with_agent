# Test Checklist

Each test corresponds to an event in `events.md`. A test passes if its `TEST_XXX` marker appears in the expected log file(s).

| Test ID | Description | Expected In |
|---------|-------------|-------------|
| `TEST_001` | Dedicated server started on port 8910 | server.log |
| `TEST_002` | Client A connected to server | server.log, client_A.log |
| `TEST_003` | Client B connected to server | server.log, client_B.log |
| `TEST_004` | Client A sent ready | server.log, client_A.log |
| `TEST_005` | Client B sent ready | server.log, client_B.log |
| `TEST_006` | Match started, World scene loaded | server.log |
| `TEST_007` | Units spawned at correct positions | server.log |
| `TEST_008_SELECT` | Client A selected its unit | client_A.log |
| `TEST_008_SELECT_B` | Client B selected its unit | client_B.log |
| `TEST_009_MOVE` | Client A issued move to (300,300) | client_A.log, server.log |
| `TEST_009_MOVE_B` | Client B issued move to (300,300) | client_B.log, server.log |
| `TEST_010_COMBAT` | Combat initiated (proximity detected) | server.log |
| `TEST_011` | Game over, winner declared | server.log |
| `TEST_012` | Both clients disconnected | client_A.log, client_B.log |
