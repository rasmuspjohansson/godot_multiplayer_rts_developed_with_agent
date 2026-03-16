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
- Each player starts with **2 armies** (no equipment).
- Each army has **10 soldiers** arranged in a **2-row x 5-column** formation.
- An army has a **center position** and a **facing direction** (angle in radians).
- Soldier positions are calculated from the army center + grid offset rotated by facing angle.
- When soldiers die, surviving soldiers **repack** to fill gaps (grid shrinks).

## Drafting
- **Draft menu**: Lower-left of screen. Checkboxes **Horse** and **Spear**, button **Create army**.
- **Cost**: 10 horses if Horse checked, 10 spears if Spear checked (both = 10 of each). Player must have enough resources.
- **Created army**: 10 soldiers, spawns off-screen on the player's side (West/East), walks in and **stops when fully visible**.
- **Equipment effects**: Horse → speed 200 → 280. Spear → attack 10 → 13, range 50 → 65. Both = both bonuses. Starting armies have no equipment.

## Physics / collision
- Units have a collision shape and **collide with each other** (they block each other; no pass-through).

## Unit Stats (Defaults)
| Stat    | Value |
|---------|-------|
| Speed   | 200   |
| HP      | 100   |
| Attack  | 10    |
| Defense | 2     |
| Range   | 50.0  |

## Capture Points & Resources
- The map has **2 capture points**: one **Stables** and one **Blacksmith**.
- Capture points start **unowned**.
- A capture point is captured when **only units from a single player** are within its capture radius (120 px). Contested (both players nearby) = no capture change.
- Once captured: **Stables** produces **horses** (inventory resource), **Blacksmith** produces **spears** (inventory resource), each **1** every **2 seconds**.
- Capture points can be **taken over** by the opposing player using the same proximity rule.
- Resources (horses, spears) are tracked per player in `GameState` and displayed in the top-bar HUD.
- **Seek enemy**: If an army has been at a capture point for **5 seconds** with **no combat** occurring anywhere, the server orders that army to seek and continuously follow the **closest enemy army** (move target is updated every tick so the army follows when the enemy moves). A manual move order (right-click) cancels follow.

## Lobby
- **Name input field**: Player can enter display name. Pre-filled from `--name=<value>` if provided, otherwise **Unknown Player**. Name is sent to the server when pressing Ready (duplicate names are allowed; army identity uses peer id).
- **Color picker**: Players choose one of 5 colors by clicking a colored box. First player gets the first color preselected; each new player gets the first not-already-used color. Taken colors are greyed out; players can change to any free color. Units in the game use the chosen color.

## Top Bar HUD
- A `CanvasLayer` UI bar at the top of the screen during gameplay.
- **Left**: `Stables: <N>  Blacksmith: <N>  Horses: <N>  Spears: <N>` (capture point counts owned by the player, then horses/spears in inventory).
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
| `World.tscn`    | 2D arena with `NavigationRegion2D`. Server spawns armies here. |
| `Unit.tscn`     | `CharacterBody2D` with `NavigationAgent2D`. Individual soldier. |
| `CapturePoint.tscn` | Visual marker for a capture point (colored circle + label). |
| `GameOver.tscn` | Displays winner. Clients auto-disconnect after a delay. |

## Script Files
| Script          | Role |
|-----------------|------|
| `Main.gd`       | Networking setup, scene switching. |
| `Lobby.gd`      | Ready-state RPCs, player list UI. |
| `World.gd`      | Army spawning, capture points, selection, rotation input, rout/win checking, sync. |
| `Army.gd`       | Formation math, movement, rotation, repack on death, rout detection. |
| `Unit.gd`       | Individual soldier: navigate, auto-attack, take damage, die. |
| `CapturePoint.gd` | Capture logic, proximity check, resource production timer. |
| `TopBar.gd`     | HUD overlay: shows resources and capture point ownership. |
| `GameOver.gd`   | Winner display, disconnect logic. |
| `MockPlayer.gd` | Automated test client (activated by `--auto-test`). |

## Automation Strategy
- **Decoupled Logic**: Every action (Select Army, Ready, Move Army, Rotate) is a standalone function callable by MockPlayer.
- **Agent Entry**: Clients pass `--auto-test` to activate `MockPlayer.gd`.
- **Logging**: Every significant event prints a `TEST_XXX` marker for automated verification.
- **Dedicated Server**: The server process runs headless (`--headless`) and never joins as a player.
