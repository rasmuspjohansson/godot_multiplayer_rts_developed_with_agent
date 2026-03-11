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
  - Left-click: Select own unit.
  - Right-click: Issue move command to clicked position.
  - Units auto-attack enemies within range (server-driven).

## Unit Stats (Defaults)
| Stat    | Value |
|---------|-------|
| Speed   | 200   |
| HP      | 100   |
| Attack  | 10    |
| Defense | 2     |
| Range   | 50.0  |

## Gameplay Mechanics
- Each player spawns with one "Commander" unit.
- Melee auto-attack when within `range` of enemy; damage = `max(1, attack - enemy.defense)` per hit (1 hit/sec).
- Win Condition: Enemy unit HP reaches 0. Server declares winner, all clients transition to GameOver scene and disconnect.

## Scene Structure
| Scene           | Purpose |
|-----------------|---------|
| `Main.tscn`     | Entry point: parses CLI args, creates network peer, switches to Lobby. |
| `Lobby.tscn`    | Shows connected players and ready states. "Ready" toggle button. |
| `World.tscn`    | 2D arena with `NavigationRegion2D`. Server spawns units here. |
| `Unit.tscn`     | `CharacterBody2D` with `NavigationAgent2D`. Player-controlled entity. |
| `GameOver.tscn` | Displays winner. Clients auto-disconnect after a delay. |

## Script Files
| Script          | Role |
|-----------------|------|
| `Main.gd`       | Networking setup, scene switching. |
| `Lobby.gd`      | Ready-state RPCs, player list UI. |
| `World.gd`      | Unit spawning, win-condition checking. |
| `Unit.gd`       | Movement, combat, HP sync. |
| `GameOver.gd`   | Winner display, disconnect logic. |
| `MockPlayer.gd` | Automated test client (activated by `--auto-test`). |

## Automation Strategy
- **Decoupled Logic**: Every action (Select, Ready, Move, Attack) is a standalone function callable by MockPlayer.
- **Agent Entry**: Clients pass `--auto-test` to activate `MockPlayer.gd`.
- **Logging**: Every significant event prints a `TEST_XXX` marker for automated verification.
- **Dedicated Server**: The server process runs headless (`--headless`) and never joins as a player.
