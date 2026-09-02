# Automated RTS — Godot 4.6

A multiplayer RTS: command armies, capture stables / blacksmiths / villages / archeries, and rout the other side.

![Screenshot from the game](from_game.jpg)


---

## INSTALL

### Windows

Double-click `install_godot_windows.bat`. This downloads Godot **4.6.1** into `tools\godot\` 

### Linux

Install Godot **4.6.x** so the `godot` command works, or set `GODOT_BIN` to the binary:

```bash
godot --version    # expect 4.6.x
# if the binary is not named godot:
export GODOT_BIN=/path/to/Godot_v4.6.1-stable_linux.x86_64
```

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

Design, maps, map editor, and agent test details: [documentation/documentation.md](documentation/documentation.md).
