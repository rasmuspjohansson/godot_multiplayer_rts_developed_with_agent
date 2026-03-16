# Automated Match Event Sequence (Events 2)

P1 (A) captures both resources, tries draft (fails), waits for 10+ horses and spears, drafts again (success). P2 takes over Stables. P1 sends drafted army to Stables and wins fight. Both send all armies to Blacksmith; P1 wins. Run with `--events=2`.

| Step | Event | Log Marker | Log File |
|------|-------|------------|----------|
| 1–6 | Server start, both connect, both ready, World loads | `TEST_001`–`TEST_006` | server.log, client logs |
| 7 | 4 starting armies + 2 capture points | `TEST_007`, `TEST_CAPTURE_SPAWN` | server.log, client logs |
| 8 | P1 (A): Move army 1 to Stables, army 2 to Blacksmith | `TEST_009_MOVE`, `TEST_CAPTURE`, `TEST_RESOURCE` | server.log, client_A.log |
| 9 | P1: Try draft with Horse+Spear → insufficient resources | `TEST_DRAFT_FAIL` | server.log |
| 10 | P1: Wait until ≥10 horses and ≥10 spears | (time ~20s+) | — |
| 11 | P1: Draft with Horse+Spear → success | `TEST_DRAFT_SUCCESS` | server.log, client_A.log |
| 12 | P2 (B): Move army to Stables (take over) | `TEST_009_MOVE_B`, `TEST_CAPTURE` | server.log, client_B.log |
| 13 | P1: Send drafted army to Stables; combat; P1 wins | `TEST_010_COMBAT`, `TEST_ROUT` (P2 army) | server.log |
| 14 | Both: Send all armies to Blacksmith; P1 wins match | `TEST_011`, `TEST_012` | server.log, client logs |
