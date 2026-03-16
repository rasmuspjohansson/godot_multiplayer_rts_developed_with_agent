# Automated RTS — Godot 4.6

A minimal multiplayer RTS where two players each control **two armies** on a 2D arena. Each army has 10 soldiers in a formation; you select and move armies, capture **Stables** and **Blacksmith** points (producing horses and spears), and win by routing both of the opponent’s armies. If an army sits at a capture point for 5 seconds with no combat, it automatically seeks and follows the closest enemy army.
<img width="1915" height="1054" alt="image" src="https://github.com/user-attachments/assets/c8d8ca0a-c531-4e66-88d1-19060a02b6ad" />


## Agent-Driven Development

This project is designed to be developed and tested iteratively by an AI agent (e.g. Cursor Agent mode). The workflow is driven by a set of markdown files:

| File | Purpose |
|------|---------|
| `prompts.txt` | Master instructions for the agent: read all files, improve docs, build the game, run automated tests, read logs, fix errors, repeat. Point the agent here to start a full development cycle. |
| `game.md` | Game design document. Architecture, scenes, unit stats, army system, capture points, resources, controls, rout/win and seek-enemy rules. The agent implements the game from this spec. |
| `events.md` | Ordered sequence of events in an automated test (connect, ready, spawn armies and capture points, select/move, combat, capture, resources, seek enemy, rout, game over, disconnect). Each step has a `TEST_XXX` log marker. |
| `tests.md` | Checklist of test markers from `events.md` and which log file(s) they appear in. The agent uses this to verify pass/fail. |
| `skills.md` | Shell commands for starting the server, clients, managing logs, and cleanup. The agent runs these directly. |

### How to use with an agent

1. Open the project in Cursor (or similar).
2. Switch to Agent mode.
3. Ask the agent to read the repo and follow the instructions in `prompts.txt`.
4. The agent will read the `.md` files, update docs as needed, implement from `game.md`, run server + two mock-player clients (using `skills.md`), check logs for the `TEST_` markers in `tests.md`, fix issues, and repeat until tests pass.

### Adding new features

1. Update `game.md` with the new feature.
2. Add the event step(s) and markers to `events.md`.
3. Add the test row(s) to `tests.md`.
4. Ask the agent to re-read and implement; it will run the same build–test–fix loop.

---

## Requirements

- **Godot 4.6.x** (standalone binary or package manager). Examples use `godot`; replace with your binary path (e.g. `~/Downloads/Godot_v4.6.1-stable_linux.x86_64`).

## Architecture

- **Dedicated server** (headless, no player) and **two clients** on port 8910.
- Server is authoritative for movement, combat, capture points, resources, and seek-enemy logic.

## How to Test Manually

### 1. Start the server

```bash
godot --headless --path . -- --server
```

Server listens on port 8910. You should see `TEST_001: Dedicated server started on port 8910`.

### 2. Start your client

```bash
godot --rendering-driver opengl3 --path . -- --client --name=A
```

By default the client connects to **localhost**. To connect to a server on another machine (or explicitly to localhost), use `--host=IP` or set `GODOT_SERVER_HOST`:

```bash
godot --rendering-driver opengl3 --path . -- --client --name=A --host=192.168.1.10
# or same machine:
godot --rendering-driver opengl3 --path . -- --client --name=A --host=127.0.0.1
```

To run the match in **3D view** (same game logic, 3D camera and units), add `--3d`:

```bash
godot --rendering-driver opengl3 --path . -- --client --name=A --3d
```

The server always runs the 2D simulation; only the client’s view changes. In 3D you get a tilted camera, zoom (scroll), pan (drag or WASD), and click-to-move via raycast on the ground.

Use `--rendering-driver opengl3` to avoid Vulkan issues when running several Godot instances.

- **Lobby**: Enter your name (pre-filled from `--name=` or "Unknown Player"), then click **Ready** when you want to start.
- **In game**:
  - **Left-click** near an army to select it (yours only).
  - **Right-click** to move the selected army.
  - **Arrow keys** or **Q / E** to rotate the selected army.
- **Top bar**: left side shows **Stables / Blacksmith** (capture points you control) and **Horses / Spears** (inventory); right side shows **Player: &lt;your name&gt;**.
- Two **capture points** (Stables, Blacksmith) start unowned; when only your units are near one, you capture it. Stables produce horses and Blacksmith produces spears every 2 seconds.
- If your army stays at a capture point for **5 seconds with no combat** anywhere, it will automatically move toward and follow the closest enemy army (until you give a new move order).
- Armies **auto-attack** enemies in range. An army below 30% strength **routs**; you lose when **both** your armies have routed.

### 3. Second player

You need two clients for a match.

- **Both human**: start a second client with `--client --name=B` (no `--auto-test`). Both click Ready and play.
- **You vs bot**: start the second client with `--client --name=B --auto-test`. MockPlayer will ready, select its armies, and move them toward the capture points; you play as A.
- **Fully automated**: start both clients with `--client --name=A --auto-test` and `--client --name=B --auto-test`. The full match runs with no input.

### 4. Stop

```bash
pkill -f godot
# or: pkill -f Godot_v4
```

## Logging

To record logs (e.g. for automated runs):

```bash
mkdir -p logs

godot --headless --path . -- --server > logs/server.log 2>&1 &
godot --rendering-driver opengl3 --path . -- --client --name=A --auto-test > logs/client_A.log 2>&1 &
godot --rendering-driver opengl3 --path . -- --client --name=B --auto-test > logs/client_B.log 2>&1 &
```

Then inspect markers:

```bash
grep "TEST_" logs/server.log logs/client_A.log logs/client_B.log
```

See `tests.md` for the full list of markers (e.g. `TEST_007`, `TEST_CAPTURE_SPAWN`, `TEST_CAPTURE`, `TEST_RESOURCE`, `TEST_SEEK_ENEMY`, `TEST_ROUT`, `TEST_011`, etc.).

## run_test.sh

From the project root you can run:

```bash
./run_test.sh              # auto-test with events 1 (default)
./run_test.sh --events=2   # auto-test with events 2 (draft sequence)
./run_test.sh --3d         # auto-test with events 1 in 3D view (both clients)
./run_test.sh --events=2 --3d   # events 2 in 3D view
./run_test.sh --no_test    # two human-play clients (no mock)
```

**For the two game windows to appear**, run the script from a **terminal that has a display** (e.g. gnome-terminal, not a headless SSH session). The script starts the server in the background, then two client processes; those clients need a display to open their windows. If you run the script from an IDE "Run" or a session that exits immediately, the client processes may not get a display or may be torn down. Set `GODOT_BIN` to the full path to your Godot executable if `godot` is not in your PATH.

## Test combinations

| Server | Client A | Client B | Use case |
|--------|----------|----------|----------|
| `--server` | `--client --name=A` | `--client --name=B` | Both manual |
| `--server` | `--client --name=A` | `--client --name=B --auto-test` | You vs bot |
| `--server` | `--client --name=A --auto-test` | `--client --name=B` | Bot vs you |
| `--server` | `--client --name=A --auto-test` | `--client --name=B --auto-test` | Fully automated |
| `--server` | `--client --name=A --3d` | `--client --name=B --3d` | Same as above, 3D view |
