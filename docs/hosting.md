# Hosting and local play

All commands run from the repo root after installing Godot once (`install_godot_windows.bat` or `./install_godot_linux.sh`, which download Godot 4.6.1 into `tools/godot/`). Launch scripts use that binary if present, otherwise `GODOT_BIN` or `godot` on your PATH.

## Run a dedicated server

The server is headless, never plays itself, and listens on UDP port **8910** (open/forward that port for remote players). Up to 4 clients; the map's `start_positions` count limits how many can join.

Windows:

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --headless --path game_assets -- --server
```

Linux:

```bash
./tools/godot/Godot_v4.6.1-stable_linux.x86_64 --headless --path game_assets -- --server
```

Players then join with `connect_remote.bat SERVER_IP` / `./connect_remote.sh --host=SERVER_IP` (see the README). The map is picked in the lobby; `--map=NAME` on the server sets the initial choice.

## Two humans on one PC

Linux (starts a server plus two client windows):

```bash
./run_test.sh --no_test
./run_test.sh --no_test --map=XL
```

Windows, three Command Prompt windows:

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --headless --path game_assets -- --server
tools\godot\Godot_v4.6.1-stable_win64.exe --path game_assets -- --client --name=Player1
tools\godot\Godot_v4.6.1-stable_win64.exe --path game_assets -- --client --name=Player2 --color=1
```

## Client command-line flags

Pass these after `--` on the Godot command line (or as extra arguments to `connect_remote.*`):

| Flag | Meaning |
|------|---------|
| `--client` / `--server` | Start as client or dedicated server |
| `--host=IP` | Server address (default `localhost`, or env `GODOT_SERVER_HOST`) |
| `--name=NAME` | Player name shown in the lobby |
| `--color=N` | Preferred color index 0–4 (red, blue, green, orange, purple) |
| `--map=NAME` | Initial map (`S`, `L`, `XL` or any `maps/map_NAME.json`) |
| `--no-vsync` | Disable vsync |
| `--map-editor` | Open the map editor instead of the game (see [maps.md](maps.md)) |

Flags used by automated tests (`--auto-test`, `--stress-units`, `--match-timeout`, `--dragons`) are described in [ai_development.md](ai_development.md).

## Stop all game processes

Leaves the Godot editor running:

```bash
pkill -f -- '/[Gg]odot[^ ]* .*--path [^ ]* -- --server' || true
pkill -f -- '/[Gg]odot[^ ]* .*--path [^ ]* -- --client' || true
```

## Remote debugging

Open the project in the Godot editor, enable **Debug → Keep Debug Server Open** (default `tcp://127.0.0.1:6007`), then:

```bash
./run_test.sh --remote-debug
./run_test.sh --remote-debug --server-window   # also give the server a visible window
GODOT_REMOTE_DEBUG=tcp://127.0.0.1:6007 ./run_test.sh
```

Use **Debugger → session** and **Scene → Remote** in the editor to inspect any of the three live processes.
