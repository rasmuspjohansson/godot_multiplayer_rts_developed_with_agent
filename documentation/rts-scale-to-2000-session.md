# RTS scale to 2000 units — session wrap-up

All to-dos in the *RTS Scale To 2000 Units* plan are complete. This note records the final stretch of work and the measured end state.

## Combat stalemate

Found via the headless `test_server_match.gd`. Two small armies could sit ~20 units apart with nobody in weapon range and no anchor movement.

- Melee units on the offensive now acquire targets out to `MELEE_ACQUIRE_RADIUS` (50) and walk in.
- An idle formation with no contact closes the remaining gap instead of waiting for the target to drift 20 units.

The full multiplayer auto-test now ends with a real winner (no timeout).

## Sim performance (2000 units, profiled section by section)

- **Idle fast path:** parked units skip steering/separation on 3 of 4 ticks.
- Per-army state (`moving`, offensive, attack order) is cached in byte arrays so the unit loop does no object property reads.
- Target scan is inlined (no `query_radius` / `is_hostile` calls) plus an army-level broad phase (0.5 s round-robin) so armies with no hostile in reach skip all per-unit scans.
- Result: 2000 units marching ≈ 16 ms/tick, all idle ≈ 5 ms, dense melee ≈ 20 ms (was 24–38 ms).

## Client renderer

- Units that did not move/change are no longer rewritten each tick.
- Terrain height lookup is inlined from the height grid (no per-unit `Callable`).
- The MultiMesh buffer is uploaded only when a group changed.

## Measurement fixes

`PerfMonitor` now reports the World physics callback cost, sim step time and actual sim Hz (the engine monitor was misleading).

Auto-test clients disable vsync, because a blanked monitor made Mesa block each swap for ~1 s and report 1 fps. That was environmental, not the game.

## Stress acceptance

`./run_stress.sh --units=1000 --map=XL` (server + 2 clients on one laptop, 2040 units):

| Metric | Result |
|--------|--------|
| Server sim tick | 16.8 ms at a steady 20.0 Hz |
| Client fps | ≈ 85 |
| Upload | 33 KB/s |
| MTU warnings | 0 |
| Outcome | `STRESS_RESULT: PASS` |

## Tests and docs

- `TEST_SIM_CLIENT snaps= walk_in_place=` counters on clients (both stayed 0 through the full match) with matching `tests.json` assertions.
- NetSync pack/unpack round-trip added to `test_unit_sim.gd`.
- `run_tests.sh` and `tests.json` list the new headless tests.
- `verify_test_logs.sh` passes **42/42**.
- `documentation.md` architecture, movement/combat, script table, map and network sections were rewritten for the new design.

## Left alone

`test_camera_w_pan_zoom_out.gd` prints a `TEST_CAMERA_W_PAN_MID_FAIL` after its `_OK` marker. It is camera-only, predates this work, and `tests.json` only checks the `_OK` marker.
