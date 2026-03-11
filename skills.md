# Project Skills & Scripting

## [Skill: Run Server]
Starts the Godot dedicated server in headless mode (no rendering, no local player).
**Command:**
```bash
mkdir -p logs
godot --headless --path . -- --server > logs/server.log 2>&1 & echo $! > logs/server.pid
```

## [Skill: Run Client A]
Starts Client A with auto-test mock player. Uses opengl3 to avoid Vulkan conflicts with multiple instances.
**Command:**
```bash
godot --rendering-driver opengl3 --path . -- --client --name=A --auto-test > logs/client_A.log 2>&1 & echo $! > logs/client_A.pid
```

## [Skill: Run Client B]
Starts Client B with auto-test mock player. Uses opengl3 to avoid Vulkan conflicts with multiple instances.
**Command:**
```bash
godot --rendering-driver opengl3 --path . -- --client --name=B --auto-test > logs/client_B.log 2>&1 & echo $! > logs/client_B.pid
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

## [Skill: Run Full Test]
Composite: clean, start server, wait, start both clients.
**Command:**
```bash
pkill -f godot || true && rm -rf logs/*.log logs/*.pid
mkdir -p logs
godot --headless --path . -- --server > logs/server.log 2>&1 & echo $! > logs/server.pid
sleep 3
godot --rendering-driver opengl3 --path . -- --client --name=A --auto-test > logs/client_A.log 2>&1 & echo $! > logs/client_A.pid
sleep 2
godot --rendering-driver opengl3 --path . -- --client --name=B --auto-test > logs/client_B.log 2>&1 & echo $! > logs/client_B.pid
```
