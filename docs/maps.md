# Maps and map editor

Every `game_assets/maps/map_<Name>.json` file shows up in the lobby **Map** dropdown; the server's choice is synced to all clients. `--map=Name` sets the initial choice (default **S**). [`MapConfig.gd`](../game_assets/MapConfig.gd) loads the selected file.

Built-in maps:

| Map | Size | Armies per player | Capture points | Dragons |
|-----|------|-------------------|----------------|---------|
| **S** | 1280×720 | 2 (spear + horse) | 1 Stables, 1 Blacksmith, 1 Village | 1 (center) |
| **L** | 2560×1440 | 1 club army | 2 Stables, 2 Blacksmith, 3 Villages, 2 Archeries | none |
| **XL** | 3840×2160 | 2 (spear + horse) | 3 Stables, 3 Blacksmith, 3 Villages, 2 Archeries | none (mountainous) |

`New`, `New2` and `demo` are maps made with the editor.

## Map JSON format

The arena is described entirely by the chosen map JSON. This is the single place to change map size, capture-point locations, player start rally points, army loadouts, or army sizes (`"soldiers": N` per army entry, 10–200; default 10). For stress runs `./run_test.sh --stress-units=1000` adds extra armies per player until that many soldiers exist (`./run_stress.sh` wraps this and checks the perf markers).

```json
{
  "name": "S",
  "size": {"width": 1280, "height": 720},
  "terrain": {"type": "hills", "features": []},
  "capture_points": [
    {"id": "Stables", "type": "Stables", "x": 499.2, "y": 201.6},
    {"id": "Blacksmith", "type": "Blacksmith", "x": 780.8, "y": 496.8},
    {"id": "Village", "type": "Village", "x": 640.0, "y": 580.0}
  ],
  "start_positions": [
    {"x": 199.68, "y": 180.0},
    {"x": 1050.0, "y": 540.0},
    {"x": 1050.0, "y": 180.0},
    {"x": 199.68, "y": 540.0}
  ],
  "player_starts": [
    {"slot": 0, "corner": "NW", "armies": [{"spear": true}, {"horse": true}]},
    {"slot": 1, "corner": "SE", "armies": [...]},
    {"slot": 2, "corner": "NE", "armies": [...]},
    {"slot": 3, "corner": "SW", "armies": [...]}
  ]
}
```

- `size` — play-area width (X) and height (Z in 3D). All camera and movement clamping uses these.
- `terrain.type` / `terrain.features` — analytical terrain built at startup. Height is **max(positive features, 5 starting ground) − carves**. Valleys and craters may go below 5. Feature schemas:
  - **hill** — radial Gaussian bump: `{type, x, y, base_width, height}` (`y` is map Z).
  - **ridge** — straight Gaussian spine: `{type, x1, y1, x2, y2, width, height}`.
  - **spline_ridge** — curved Gaussian spine through control points: `{type, points: [{x, y}, ...], width, height}` (≥2 points; Catmull-Rom spline).
  - **plateau** — flat top with smooth rim: `{type, x, y, radius, falloff, height}`.
  - **plateau_polygon** — flat polygon top with smooth exterior falloff: `{type, points: [{x, y}, ...], height, falloff}` (≥3 points).
  - **valley** — radial Gaussian carve: `{type, x, y, base_width, depth}`.
  - **crater** — radial inverse of hill (same Gaussian, subtracted): `{type, x, y, base_width, depth}`.
  - **valley_polygon** — polygon carve, no rim: `{type, points: [{x, y}, ...], depth, falloff}` (≥3 points).
- `capture_points[]` — capturable objectives; types: `Stables`, `Blacksmith`, `Village`, `Archery`. IDs `Stables` and `Blacksmith` are used by the auto-test on all map sizes.
- `start_positions[]` — rally markers. Count = max players for that map. Join order assigns slot 0, 1, … At match start each player's armies spawn off the nearer of the west and east edges and march to that marker. The map editor **Start** tool places these.
- `player_starts[]` — per-slot army **loadout** (`horse`/`spear`/`bow`, optional `soldiers`). Army `x,y` is ignored for spawn (kept for older maps). An empty `armies` list defaults to spear + horse. Legacy `corner` is unused; armies enter from the nearer of the west and east edges of that slot's start marker.
- `lighting` (optional) — directional sun applied at runtime after terrain is built. [`World.gd`](../game_assets/World.gd) scales sun orbit and shadow distance from map size and final max terrain height.
  - `sun_azimuth_deg` — compass bearing where the sun sits: **0 = north (−Z)**, **90 = east (+X)**, **180 = south (+Z)**. Default **275**.
  - `sun_elevation_deg` — degrees above the horizon. Default **0** (low horizontal sun).
  - `energy` — directional light strength (vertex height tint remains the primary summit signal). Default **0.12**.
  - `color` — RGB array, e.g. `[1.0, 0.98, 0.95]`.
  - `shadow_max_distance` — `null` = auto (`max(800, map_diagonal × 0.35 + max_terrain_height × 1.5)`); or a fixed number.
- `walkability` (optional) — which terrain cells units may enter; built after terrain and lakes at startup.
  - `max_slope_deg` — steeper slopes are blocked (default **45**). Blocked cells use `steep_hills.png` on the ground shader; lakes are always blocked.
- `neutral_dragon` (S) or `neutral_dragons[]` (optional on other maps) — optional map guardians.

`MockPlayer` never opens map JSON; it asks the live game state (armies and capture-point nodes received from the server) for anything it needs. That way a single JSON edit drives server, client rendering, and the bot simultaneously.

## Map editor

A standalone editor for terrain, capture points, start rally points, army loadouts and map objects. Run it from the repo root:

```bash
./tools/godot/Godot_v4.6.1-stable_linux.x86_64 --rendering-driver opengl3 --path game_assets -- --map-editor
```

```bat
tools\godot\Godot_v4.6.1-stable_win64.exe --rendering-driver opengl3 --path game_assets -- --map-editor
```

Save writes `game_assets/maps/map_<Name>.json`, which then appears in the lobby Map dropdown.

- **Start** places rally markers (`start_positions`); their count is the map's max players.
- **Army** sets the per-slot loadout (`horse`/`spear`/`bow`).
