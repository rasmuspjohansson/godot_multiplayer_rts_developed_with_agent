# Project Skills & Scripting

## [Skill: Run Server]
Starts the Godot dedicated server in headless mode (no rendering, no local player).
**Command:**
```bash
mkdir -p logs
godot --headless --path . -- --server > logs/server.log 2>&1 & echo $! > logs/server.pid
```

## [Skill: Run Client A (events N)]
Starts Client A with auto-test mock player. Use `--events=1` (default) or `--events=2` for the event sequence. Optional: `--host=IP` or env `GODOT_SERVER_HOST` to connect to a remote server (default: localhost).
**Command:**
```bash
godot --rendering-driver opengl3 --path . -- --client --name=A --auto-test --events=1 > logs/client_A.log 2>&1 & echo $! > logs/client_A.pid
```
**Remote server:** add `--host=192.168.1.10` (or `GODOT_SERVER_HOST=192.168.1.10`) to connect to another machine.

## [Skill: Run Client B (events N)]
Starts Client B with auto-test mock player. Use `--events=1` or `--events=2`. Optional: `--host=IP` or `GODOT_SERVER_HOST` for remote server.
**Command:**
```bash
godot --rendering-driver opengl3 --path . -- --client --name=B --auto-test --events=1 > logs/client_B.log 2>&1 & echo $! > logs/client_B.pid
```

## [Skill: Clean & Kill]
Stops all Godot instances and clears old logs.
**Command:**
```bash
pkill -f godot || true
rm -rf logs/*.log logs/*.pid
```

## [Skill: Extract Logs]
Search logs for test markers.
**Command:**
```bash
grep "TEST_" logs/server.log logs/client_A.log logs/client_B.log
```

## [Skill: Run Full Test (events N)]
Composite: clean, start server, start both clients with `--events=1` or `--events=2`.
**Command (events 1):**
```bash
pkill -f godot || true && rm -rf logs/*.log logs/*.pid
mkdir -p logs
godot --headless --path . -- --server > logs/server.log 2>&1 & echo $! > logs/server.pid
sleep 3
godot --rendering-driver opengl3 --path . -- --client --name=A --auto-test --events=1 > logs/client_A.log 2>&1 & echo $! > logs/client_A.pid
sleep 2
godot --rendering-driver opengl3 --path . -- --client --name=B --auto-test --events=1 > logs/client_B.log 2>&1 & echo $! > logs/client_B.pid
```
**Run events 2 test:** use `--events=2` for both client commands.
