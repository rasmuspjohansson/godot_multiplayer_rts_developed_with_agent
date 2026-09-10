# Automated RTS — Godot 4.6

A multiplayer RTS: command armies, capture stables / blacksmiths / villages / archeries, and rout the other side.

![Screenshot from the game](from_game.jpg)


---

## INSTALL

### Windows

Double-click `install_godot_windows.bat`. This downloads Godot **4.6.1** into `tools\godot\` 

### Linux

```bash
./install_godot_linux.sh
```

This downloads Godot **4.6.1** into `tools/godot/` (once; needs a network connection).

---

## TEST

Starts a dedicated server plus two bot clients (`MockPlayer`) on this machine.

### Windows

Open **Command Prompt** in this folder. Start three windows:

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --headless --path game_assets -- --server --auto-test
```

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --path game_assets -- --client --name=A --auto-test
```

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --path game_assets -- --client --name=B --auto-test --color=1
```

Optional map: add `--map=XL` to each command.

### Linux

```bash
./run_test.sh
```

Optional map: `./run_test.sh --map=XL`.

---

## STRESS (≈2000 units)

Spawns extra armies so each player has N soldiers, runs the auto-test match, then prints perf from the logs (server sim tick, client fps). Default is **1000 soldiers per player** on the XL map — about **2000 units** total.

### Linux

```bash
./run_stress.sh
```

That is the same as `./run_stress.sh --units=1000 --map=XL --seconds=90`.

Smaller / shorter:

```bash
./run_stress.sh --units=500 --map=L --seconds=60
```

Or skip the wrapper and keep the match running:

```bash
./run_test.sh --map=XL --stress-units=1000
```

### Windows

Add `--stress-units=1000 --map=XL` to the server and both client commands in **TEST** above (three Command Prompt windows).

---

## PLAY

Join a host's server, or play two humans on this machine. In the lobby, pick a color if you want, then press **Ready**.

### Windows

**Join a server** — Command Prompt in this folder (use the IP the host gives you):

```bat
connect_remote.bat SERVER_IP
```

Optional name:

```bat
connect_remote.bat SERVER_IP MyName
```

**Two humans on this PC** — three Command Prompt windows:

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --headless --path game_assets -- --server
```

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --path game_assets -- --client --name=Player1
```

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --path game_assets -- --client --name=Player2 --color=1
```

### Linux

**Join a server** (use the IP the host gives you):

```bash
./connect_remote.sh --host=SERVER_IP
```

Optional name (default is `Human`):

```bash
./connect_remote.sh --host=SERVER_IP --name=Human
```

**Two humans on this PC:**

```bash
./run_test.sh --no_test
```

Optional map: `./run_test.sh --no_test --map=XL`.

---

## MAP EDITOR

Standalone editor for terrain, capture points, start rally points, army loadouts, and map objects. Run from the repo root.

### Windows

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --rendering-driver opengl3 --path game_assets -- --map-editor
```

### Linux

```bash
godot --rendering-driver opengl3 --path game_assets -- --map-editor
```

If `godot` is not on your PATH:

```bash
./tools/godot/Godot_v4.6.1-stable_linux.x86_64 --rendering-driver opengl3 --path game_assets -- --map-editor
```

Save writes `game_assets/maps/map_<Name>.json`. That name appears in the lobby Map dropdown. Start a match with `--map=Name` (e.g. `./run_test.sh --map=MyMap`).

---

Design, maps, and agent test details: [documentation/documentation.md](documentation/documentation.md).
