# Automated RTS -- Godot 4.6

A minimal multiplayer RTS where two players each control one unit on a 2D arena. Units auto-attack when close. Last unit standing wins.

## Requirements

- Godot 4.6.x (standalone binary or installed via package manager)
- The examples below use `godot` as the binary name. Replace with the actual path if needed, e.g. `~/Downloads/Godot_v4.6.1-stable_linux.x86_64`.

## Architecture

One **dedicated server** (headless, no player) and **two clients** that connect to it. The server is authoritative over movement and combat.

## How to Test

### 1. Start the Dedicated Server

Open a terminal and run:

```bash
godot --headless --path . -- --server
```

The server starts on port 8910 and waits for clients. You should see:

```
TEST_001: Dedicated server started on port 8910
```

### 2. Start a Manual Client (no mock player)

Open a second terminal. This launches a normal windowed client you control with mouse clicks:

```bash
godot --rendering-driver opengl3 --path . -- --client --name=A
```

- A lobby screen appears. Click **Ready** when you want to start.
- Once the match loads: left-click your unit to select it, right-click to move.
- Units auto-attack enemies within range.

> Use `--rendering-driver opengl3` to avoid Vulkan conflicts when running multiple Godot windows on the same machine.

### 3. Start a Second Client

You need at least two clients for the match to begin. Pick one of the options below.

#### Option A: Second manual client (both players human-controlled)

Open a third terminal:

```bash
godot --rendering-driver opengl3 --path . -- --client --name=B
```

Both players click Ready in the lobby, then play manually.

#### Option B: Second client with mock player (opponent is automated)

Open a third terminal:

```bash
godot --rendering-driver opengl3 --path . -- --client --name=B --auto-test
```

The `--auto-test` flag activates `MockPlayer.gd`, which automatically:
1. Presses Ready in the lobby
2. Selects its unit
3. Sends a move command to (300, 300)
4. Waits for combat to resolve

This lets you play manually as Client A against an automated Client B.

#### Option C: Both clients automated (fully automated test)

```bash
godot --rendering-driver opengl3 --path . -- --client --name=A --auto-test
# wait a couple of seconds, then:
godot --rendering-driver opengl3 --path . -- --client --name=B --auto-test
```

The entire match runs without human input.

### 4. Stop Everything

```bash
pkill -f godot || true
```

## Logging

To capture logs to files (useful for automated testing):

```bash
mkdir -p logs

# Server
godot --headless --path . -- --server > logs/server.log 2>&1 &

# Clients
godot --rendering-driver opengl3 --path . -- --client --name=A --auto-test > logs/client_A.log 2>&1 &
godot --rendering-driver opengl3 --path . -- --client --name=B --auto-test > logs/client_B.log 2>&1 &
```

After the match completes, inspect logs:

```bash
grep "TEST_" logs/server.log logs/client_A.log logs/client_B.log
```

See `tests.md` for the full list of expected `TEST_` markers.

## Test Combinations Summary

| Server | Client A | Client B | Use Case |
|--------|----------|----------|----------|
| `--server` | `--client --name=A` | `--client --name=B` | Both players manual |
| `--server` | `--client --name=A` | `--client --name=B --auto-test` | You vs. bot |
| `--server` | `--client --name=A --auto-test` | `--client --name=B` | Bot vs. you |
| `--server` | `--client --name=A --auto-test` | `--client --name=B --auto-test` | Fully automated |
