# Project Skills & Scripting

All automated-test behaviour is defined in `tests.json`. The MockPlayer reads it and executes the `action`s for its player; `verify_test_logs.sh` scrapes every `events[].marker` and runs every `other_tests[].implementation`.

## [Skill: Run Server]
Starts the Godot dedicated server in headless mode (no rendering, no local player).
**Command:**
```bash
mkdir -p logs
godot --headless --path . -- --server > logs/server.log 2>&1 & echo $! > logs/server.pid
```

## [Skill: Run Client A]
Starts Client A with the auto-test MockPlayer. Optional: `--host=IP` or env `GODOT_SERVER_HOST` to connect to a remote server (default: localhost).
**Command:**
```bash
godot --rendering-driver opengl3 --path . -- --client --name=A --auto-test > logs/client_A.log 2>&1 & echo $! > logs/client_A.pid
```

## [Skill: Run Client B]
Starts Client B with the auto-test MockPlayer. Optional: `--host=IP` or `GODOT_SERVER_HOST` for a remote server.
**Command:**
```bash
godot --rendering-driver opengl3 --path . -- --client --name=B --auto-test > logs/client_B.log 2>&1 & echo $! > logs/client_B.pid
```

## [Skill: Clean & Kill]
Stops dedicated server / client game processes only (does not kill the Godot editor). Clears old logs.
**Command:**
```bash
pkill -f -- '[g]odot.*-- --server' || true
pkill -f -- 'Godot.*-- --server' || true
pkill -f -- '[g]odot.*-- --client' || true
pkill -f -- 'Godot.*-- --client' || true
rm -rf logs/*.log logs/*.pid
```

## [Skill: Extract Logs]
Search logs for test markers.
**Command:**
```bash
grep "TEST_" logs/server.log logs/client_A.log logs/client_B.log
```

## [Skill: Run Full Test]
Composite: clean, start server, start both auto-test clients.
**Command:**
```bash
./run_test.sh
```
Then wait until `TEST_GAME_OVER` appears in `logs/server.log` (`./wait_for_test_end.sh`), and verify:
```bash
./verify_test_logs.sh
```

## [Skill: Run Full Test with Remote debugging]
Open the project in the Godot editor and enable **Debug → Keep Debug Server Open**, then from the repo root:
```bash
./run_test.sh --remote-debug
```
Optional: `./run_test.sh --remote-debug --server-window` for a visible server window. Use **Debugger → session** and **Scene → Remote** in the editor to inspect each running process.
