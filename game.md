# Project: Minimal RTS Multiplayer (Godot 4.6)

## Architecture
- **Model**: Client-Server (Dedicated Server -- server is never a client).
- **Networking**: High-level Multiplayer API (`ENetMultiplayerPeer`).
- **Authority**: Server-authoritative movement and combat.
- **Port**: 8910 (default). Server binds on `*:8910`, clients connect to `localhost:8910`.

## Game View & Controls
- **Perspective**: Top-down 2D.
- **Navigation**: `NavigationRegion2D` for pathfinding.
- **Player Controls**:
  - Left-click: Select own army.
  - Right-click: Move selected army to clicked position.
  - Left/Right arrow keys (or Q/E): Rotate selected army facing direction by 15 degrees.
  - Units auto-attack enemies within range (server-driven).

## Player sides
- For 2 players: first connected = **West** (left), second = **East** (right). Drafted armies spawn from the player's side and walk in until fully visible (stop_when_visible).

## Army System (Total War Style)
- On map **S**, each player starts with **2 armies** (spear + horse). On **L** and **XL**, each player starts with **1 club army** (no equipment).
- Each army has **10 soldiers** arranged in a **2-row x 5-column** formation.
- An army has a **center position** and a **facing direction** (angle in radians).
- Soldier positions are calculated from the army center + grid offset rotated by facing angle.
- When soldiers die, surviving soldiers **repack** to fill gaps (grid shrinks).

## Drafting
- **Draft menu**: Lower-left of screen. Checkboxes **Horse**, **Spear**, and **Bow**, button **Create army**.
- **Cost**: **10 villagers** for every army, plus **10** of each checked equipment type (horse / spear / bow). Player must have enough resources.
- **Created army**: 10 soldiers, spawns off-screen on the player's side (West/East), walks in and **stops when fully visible**.
- **Unit types** (equipment priority): Horse+Bow → **bauer_horse_archer**; Bow → **bowman**; Horse → **knight**; Spear → **spearman**; none → **clubman**.
- **Equipment effects**: Horse → mounted speed/HP. Spear → higher attack/melee range. Bow / bauer_horse_archer → ranged attack. Starting armies on map S use spear/horse from JSON; L/XL start with clubmen.

## Capture Points & Resources
- Map **S**: 1 Stables, 1 Blacksmith, 1 Village (3 CPs total). Map **L**: 2 Stables, 2 Blacksmith, 3 Villages, 2 Archeries (9 CPs). Map **XL**: 3 Stables, 3 Blacksmith, 3 Villages, 2 Archeries (11 CPs), plus **2 neutral dragons**.
- Capture points start **unowned**.
- A capture point is captured when **only units from a single player** are within its capture radius (120 px). Contested (both players nearby) = no capture change.
- Once captured, each type produces **1** resource every **2 seconds**: **Stables** → horses, **Blacksmith** → spears, **Village** → villagers, **Archery** → bows.
- Capture points can be **taken over** by the opposing player using the same proximity rule.
- Each player starts with **10 horses, 10 spears, 10 bows, and 10 villagers** in inventory (`GameState.resources`).
- Resources are displayed in the top-bar HUD (CP counts + inventory).
- **Seek enemy**: If an army has been at a capture point for **5 seconds** with **no combat** occurring anywhere, the server orders that army to seek and continuously follow the **closest enemy army** (move target is updated every tick so the army follows when the enemy moves). A manual move order (right-click) cancels follow.

## Army orders and stances

Army-level control (select with LMB / marquee). Command bar appears when an army is selected.

| Control | Action |
|---------|--------|
| **Move** (default, `M`) | RMB on ground: move formation. RMB drag: line formation. |
| **Attack-Move** (`G`) | Same as Move but units engage enemies along the way. |
| **Attack** (`A`) | LMB on enemy army or dragon: pursue and attack that target. |
| **Aggressive / Defensive / Hold / Passive** | Stance buttons on command bar. Aggressive with no order auto-chases nearest enemy. |

Behaviour spec: `RTS_Unit_Behaviour_Spec.md`. Move orders are **not** cancelled when attacked. Attack orders lock onto the commanded target. Ranged units (bow, horse archer) can attack while moving.

## Physics / collision
- Units have a `CollisionShape3D` box (14×22×14) on each `CharacterBody3D`. **Enemy teams block each other** during movement; **friendlies pass through** (same collision layer).
- **Combat** uses distance checks in `Unit3D._try_attack()`, not physics contact.
- **Collision layers** (`World.gd`):
  - Layer `2` — ground / terrain (used by `get_ground_height_at()` and `_raycast_ground_at_screen()`)
  - Layers `1`, `4`, `8`, `16` — one per player team (`TEAM_COLLISION_LAYERS`)
- **Toggle:** `UNIT_PASS_THROUGH` in `World.gd`. `false` (current) — enemies block via `_enemy_collision_mask_for_peer()`; friendlies pass. `true` — all units pass through (`collision_mask = 0`).
- **Friendly blocking too:** extend `_enemy_collision_mask_for_peer()` to also OR in the unit's own team layer (or use a single shared unit layer with a mask that includes it).

## Unit Stats (Defaults)
| Stat    | Value |
|---------|-------|
| Speed   | 67    |
| HP      | 100   |
| Attack  | 10    |
| Defense | 2     |
| Range   | 50.0  |

## Lobby
- **Name input field**: Player can enter display name. Pre-filled from `--name=<value>` if provided, otherwise **Unknown Player**. Name is sent to the server when pressing Ready (duplicate names are allowed; army identity uses peer id).
- **Color picker**: Players choose one of 5 colors by clicking a colored box. First player gets the first color preselected; each new player gets the first not-already-used color. Taken colors are greyed out; players can change to any free color. Units in the game use the chosen color.

## Top Bar HUD
- A `CanvasLayer` UI bar at the top of the screen during gameplay.
- **Left**: `Stab/Blk/Vill/Arch` CP counts owned, then `H/S/B/V` inventory (horses, spears, bows, villagers).
- **Right**: `Player: <display name>`.
- Updated every sync tick from the server.

## Rout & Win Condition
- When an army drops below **30%** soldiers alive (3 of 10), it **routs**.
- Routed army's remaining soldiers flee and are removed.
- A player **loses** when **both** of their armies have routed.
- Server declares the other player the winner.

## Scene Structure
| Scene           | Purpose |
|-----------------|---------|
| `Main.tscn`     | Entry point: parses CLI args, creates network peer, switches to Lobby. |
| `Lobby.tscn`    | Shows name input, color picker (5 boxes), connected players, ready states. "Ready" toggle button. |
| `World.tscn`    | 3D arena (ground mesh + physics). Server and clients spawn armies here. |
| `Unit3D`        | `CharacterBody3D` soldier (server sim + client billboard mesh). |
| (capture)       | Capture points are pillars + server-side logic in `World.gd` (no separate CP scene). |
| `GameOver.tscn` | Displays winner. Clients auto-disconnect after a delay. |

## Script Files
| Script          | Role |
|-----------------|------|
| `Main.gd`       | Networking setup, scene switching. |
| `Lobby.gd`      | Ready-state RPCs, player list UI. |
| `World.gd`      | Army spawning, capture points, selection, camera, rout/win checking, sync. |
| `Army3D.gd`     | Formation math, movement, rotation, repack on death, rout detection (XZ). |
| `Unit3D.gd`     | Soldier: move/attack on server; interpolate and visuals on client. |
| `TopBar.gd`     | HUD overlay: shows resources and capture point ownership. |
| `GameOver.gd`   | Winner display, disconnect logic. |
| `MockPlayer.gd` | Automated test client (activated by `--auto-test`). |

## Automation Strategy
- **Decoupled Logic**: Every action (Select Army, Ready, Move Army, Rotate) is a standalone function callable by MockPlayer.
- **Agent Entry**: Clients pass `--auto-test` to activate `MockPlayer.gd`.
- **Logging**: Every significant event prints a `TEST_XXX` marker for automated verification.
- **Dedicated Server**: The server process runs headless (`--headless`) and never joins as a player.
