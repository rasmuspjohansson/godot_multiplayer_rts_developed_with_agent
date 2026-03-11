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

## Army System (Total War Style)
- Each player starts with **2 armies**.
- Each army has **10 soldiers** arranged in a **2-row x 5-column** formation.
- An army has a **center position** and a **facing direction** (angle in radians).
- Soldier positions are calculated from the army center + grid offset rotated by facing angle.
- When soldiers die, surviving soldiers **repack** to fill gaps (grid shrinks).

## Unit Stats (Defaults)
| Stat    | Value |
|---------|-------|
| Speed   | 200   |
| HP      | 100   |
| Attack  | 10    |
| Defense | 2     |
| Range   | 50.0  |

## Rout & Win Condition
- When an army drops below **30%** soldiers alive (3 of 10), it **routs**.
- Routed army's remaining soldiers flee and are removed.
- A player **loses** when **both** of their armies have routed.
- Server declares the other player the winner.

## Scene Structure
| Scene           | Purpose |
|-----------------|---------|
| `Main.tscn`     | Entry point: parses CLI args, creates network peer, switches to Lobby. |
| `Lobby.tscn`    | Shows connected players and ready states. "Ready" toggle button. |
| `World.tscn`    | 2D arena with `NavigationRegion2D`. Server spawns armies here. |
| `Unit.tscn`     | `CharacterBody2D` with `NavigationAgent2D`. Individual soldier. |
| `GameOver.tscn` | Displays winner. Clients auto-disconnect after a delay. |

## Script Files
| Script          | Role |
|-----------------|------|
| `Main.gd`       | Networking setup, scene switching. |
| `Lobby.gd`      | Ready-state RPCs, player list UI. |
| `World.gd`      | Army spawning, selection, rotation input, rout/win checking, sync. |
| `Army.gd`       | Formation math, movement, rotation, repack on death, rout detection. |
| `Unit.gd`       | Individual soldier: navigate, auto-attack, take damage, die. |
| `GameOver.gd`   | Winner display, disconnect logic. |
| `MockPlayer.gd` | Automated test client (activated by `--auto-test`). |

## Automation Strategy
- **Decoupled Logic**: Every action (Select Army, Ready, Move Army, Rotate) is a standalone function callable by MockPlayer.
- **Agent Entry**: Clients pass `--auto-test` to activate `MockPlayer.gd`.
- **Logging**: Every significant event prints a `TEST_XXX` marker for automated verification.
- **Dedicated Server**: The server process runs headless (`--headless`) and never joins as a player.
