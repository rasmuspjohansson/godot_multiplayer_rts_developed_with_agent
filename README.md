# Automated RTS -- Godot 4.6

A minimal multiplayer RTS where two players each control one unit on a 2D arena. Units auto-attack when close. Last unit standing wins.

## Agent-Driven Development

This project is designed to be developed and tested iteratively by an AI agent (e.g. Cursor Agent mode). The workflow is driven by a set of markdown files that each serve a specific purpose:

| File | Purpose |
|------|---------|
| `prompts.txt` | Master instructions for the agent. Describes the overall workflow: read all files, improve docs, build the game, run automated tests, read logs, fix errors, repeat. Point the agent here to kick off a full development cycle. |
| `game.md` | Game design document. Describes architecture, scenes, unit stats, controls, and automation strategy. The agent builds the game according to this spec. |
| `events.md` | Ordered sequence of events that should happen during an automated test match (connect, ready, spawn, select, move, combat, game over, disconnect). Each event has a `TEST_XXX` log marker. |
| `tests.md` | Checklist of test markers derived from `events.md`. Each marker maps to a log file where it should appear. The agent uses this to verify pass/fail. |
| `skills.md` | Shell commands for starting the server, clients, extracting logs, and cleaning up. The agent runs these commands directly. |

### How to use with an agent

1. Open the project in Cursor (or similar AI-assisted editor).
2. Switch to Agent mode.
3. Tell the agent: *"Read all the files in this repo. In the prompts.txt file are instructions for you to implement."*
4. The agent will:
   - Read all `.md` files and `prompts.txt`
   - Suggest improvements to the documentation
   - Implement or update the game code according to `game.md`
   - Run the server and two mock-player clients using commands from `skills.md`
   - Extract logs and check for `TEST_` markers listed in `tests.md`
   - Fix any errors found in the logs
   - Repeat the test-fix loop (up to 5 iterations or until all tests pass)

### Adding new features

To extend the game with the agent:

1. Update `game.md` with the new feature description.
2. Add the expected event sequence to `events.md` with new `TEST_` markers.
3. Add corresponding test entries to `tests.md`.
4. Tell the agent to re-read the files and implement the changes.

The agent will follow the same build-test-fix loop for the new feature.

---

## Requirements

- Godot 4.6.x (standalone binary or installed via package manager)
- The examples below use `godot` as the binary name. Replace with the actual path if needed, e.g. `~/Downloads/Godot_v4.6.1-stable_linux.x86_64`.

## Architecture

One **dedicated server** (headless, no player) and **two clients** that connect to it. The server is authoritative over movement and combat.

## How to Test Manually

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
