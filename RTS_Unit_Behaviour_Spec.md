# RTS Unit Movement, Control & Combat Behaviour

## Purpose

This document defines the baseline design rules for unit movement, player control, local avoidance, and combat behaviour in this Godot RTS.

**For humans:** use these rules as the gameplay specification when changing unit behaviour. Preserve the distinction between player orders, movement, and combat unless a deliberate design change is being made.

**For AI coding agents:** treat this document as the behavioural contract for the RTS. Before changing movement/combat code, check these rules first. Do not introduce behaviour that contradicts them without explicitly identifying the design trade-off. Keep player commands higher priority than autonomous reactions.

The goal is a responsive RTS similar in feel to **Age of Empires**, combined with some tactical distinctions associated with **Total War**.

---

## 1. Core principle

A unit has three largely independent concerns:

1. **Player Order** — what the player told the unit to do.
2. **Movement** — how the unit physically gets there and avoids obstacles/other units.
3. **Combat** — whether and how the unit attacks nearby enemies.

Being attacked must **not automatically cancel the player's movement order**.

Example:

```text
Player Order:  Move to X
Movement:      Moving toward X
Combat:        Attacking enemy while moving
```

This separation is fundamental.

---

## 2. Player orders

### Move

> Go to the destination. Do not deliberately pursue enemies.

If attacked while moving, the default behaviour is to **continue toward the destination**.

### Attack

> Attack the specified enemy.

The unit may pursue that enemy according to its unit type and stance.

If another enemy attacks the unit, do not automatically abandon the commanded target.

### Attack-Move

> Move toward the destination, but engage suitable enemies encountered along the way.

This is a major RTS command and should be supported.

### Hold Position

> Stay near the current position and engage enemies according to stance/range.

Do not pursue enemies beyond the allowed pursuit distance.

### Stop

> Cancel movement and reassess the situation.

---

## 3. Stances

Units should support simple behavioural stances:

### Aggressive
- Automatically engage nearby enemies.
- May pursue enemies.
- Suitable for melee units.

### Defensive
- Engage enemies that enter the combat area.
- Limited pursuit.
- Prefer maintaining position.

### Hold Position
- Do not voluntarily move toward enemies.
- Attack enemies within appropriate range.

### Passive
- Do not automatically initiate attacks.
- Still defend/respond according to explicit player commands.

---

## 4. Unit behaviour categories

Use reusable behaviour archetypes rather than a completely separate AI for every unit.

### Melee infantry
Examples: sword, spear, club.

Default:
- Move normally.
- On Attack/Attack-Move, approach enemies.
- Enter melee range and fight.
- Can break combat when given a new Move order.
- Do not become permanently locked into combat.

### Ranged infantry
Example: bow.

Default:
- Prefer maintaining distance.
- Can attack while moving if the weapon/system supports it.
- On normal Move orders, prioritize reaching the destination.
- On Attack-Move, engage enemies encountered.
- Pursuit should be limited.

### Melee cavalry
Examples: sword/spear/club on horse.

Default:
- High mobility.
- Can pursue enemies.
- Should be easier to disengage than infantry.
- Should support a charge-style attack.
- Cavalry movement should feel meaningfully different from infantry.

### Horse archer
Default:
- High mobility.
- Can attack while moving.
- Prefer maintaining distance.
- Limited pursuit is preferable to blindly entering melee.
- Should be able to disengage and continue moving.

---

## 5. Recommended behaviour matrix

| Unit | Move order while attacked | Attack-Move | Auto chase | Attack while moving |
|---|---|---|---|---|
| Sword infantry | Continue | Fight | Yes | No |
| Spear infantry | Continue | Fight | Yes | No |
| Club infantry | Continue | Fight | Yes | No |
| Bow infantry | Continue | Shoot | Limited | Yes |
| Sword cavalry | Continue | Charge/fight | Yes | Usually no |
| Spear cavalry | Continue | Charge/fight | Yes | Usually no |
| Club cavalry | Continue | Charge/fight | Yes | Usually no |
| Horse archer | Continue | Shoot | Limited | Yes |

These are **default behaviours**, not absolute restrictions.

---

## 6. Player command priority

Player commands should normally have higher priority than autonomous combat reactions.

### Example: Move order

```text
Player: Move unit to X
Enemy: attacks unit

Expected:
Unit continues toward X
```

### Example: Attack order

```text
Player: Attack enemy A
Enemy B: attacks unit

Expected:
Unit normally continues attacking A
```

### Example: Attack-Move

```text
Player: Attack-Move to X
Enemy appears

Expected:
Unit engages enemy while progressing toward X
```

### Example: Stop

```text
Player: Stop

Expected:
Movement/combat navigation is reassessed immediately
```

---

## 7. Combat commitment

Do not represent combat as simply `fighting = true/false`.

Units should have different levels of willingness to remain engaged.

Conceptually:

- **Low commitment:** archers/horse archers
  - Prefer movement and distance.
  - Easily disengage.
- **Medium commitment:** cavalry
  - Engage, but can disengage.
- **High commitment:** melee infantry
  - Prefer staying in melee once engaged.

This can be implemented through parameters such as:

- `combat_commitment`
- `pursuit_distance`
- `disengage_distance`
- `attack_while_moving`
- `can_charge`

Do not add all parameters immediately if they are not needed. Prefer simple data-driven properties.

---

## 8. Movement and collision

**Movement avoidance is not combat.**

If another unit blocks a path, this means:

> "Something is physically in my way."

It does NOT automatically mean:

> "I should attack it."

Therefore keep these systems conceptually separate:

```text
Desired movement
       ↓
Pathfinding
       ↓
Local/unit avoidance
       ↓
Final movement
```

and separately:

```text
Enemy detection
       ↓
Target selection
       ↓
Combat behaviour
       ↓
Attack
```

Use **soft/local avoidance** rather than hard physics-style unit collision wherever practical. Units should be able to move around one another and large groups should not easily become permanently stuck.

---

## 9. Mounted units

Mounted units should have meaningful behavioural differences from ground units.

Recommended differences:

- Higher movement speed.
- Larger effective avoidance radius where appropriate.
- Better disengagement.
- Ability to exploit momentum.
- Optional charge mechanics.
- Cavalry should not behave like infantry with a speed multiplier.

A charge can conceptually work like:

```text
Cavalry moving at speed
        ↓
    Enemy contact
        ↓
   Charge attack
        ↓
   Brief engagement
        ↓
   Disengage/reposition
```

---

## 10. Spears

Spears should have a distinct tactical role.

Recommended:
- Strong against cavalry.
- Can have a brace/anti-charge behaviour when stationary.
- Normal spear attacks when moving/engaging.
- Do not make spear units universally stronger than swords; their advantage should be situational.

---

## 11. Data-driven unit configuration

Prefer defining unit behaviour through properties rather than hard-coded checks for every unit name.

Useful properties include:

```text
mounted
weapon_type
move_speed
attack_range
attack_speed
damage
attack_while_moving
can_charge
charge_power
combat_commitment
pursuit_distance
disengage_distance
anti_cavalry
```

For example:

```text
Bow + Ground
    mounted = false
    attack_while_moving = true
    pursuit_distance = low

Sword + Ground
    mounted = false
    attack_while_moving = false
    combat_commitment = high

Sword + Horse
    mounted = true
    attack_while_moving = false
    can_charge = true
    combat_commitment = medium
```

Keep these as configurable data where practical so balancing does not require rewriting AI logic.

---

## 12. Suggested Godot architecture

The exact node/script structure can differ, but keep responsibilities separated.

```text
Unit
├── PlayerOrder
│   ├── Move
│   ├── Attack
│   ├── AttackMove
│   ├── Hold
│   └── Stop
│
├── MovementController
│   ├── Pathfinding
│   ├── LocalAvoidance
│   └── Movement
│
├── CombatController
│   ├── EnemyDetection
│   ├── TargetSelection
│   ├── AttackRange
│   └── AttackExecution
│
├── BehaviourController
│   ├── Stance
│   ├── CombatCommitment
│   ├── Pursuit
│   └── Disengagement
│
└── UnitData
    ├── Weapon properties
    ├── Mounted properties
    └── Behaviour properties
```

The exact implementation should follow the existing Godot project architecture. **Do not restructure the entire project merely to match this diagram.**

---

## 13. AI-agent implementation rules

When modifying the game:

1. **Preserve player control.** Autonomous behaviour should assist the player's order, not routinely override it.
2. **Do not make "attacked" automatically mean "stop moving."**
3. **Keep movement avoidance separate from combat targeting.**
4. **Use data/configuration for unit differences where possible.**
5. **Avoid duplicating complete AI implementations for every weapon/unit combination.**
6. **Prefer small, testable changes.**
7. **Do not change unrelated systems while implementing movement/combat behaviour.**
8. **Before changing an existing behaviour, inspect the current implementation and determine whether another system already owns that responsibility.**
9. **If a requested feature conflicts with these rules, explain the conflict and identify which rule would need to change.**
10. **Test the important combinations after movement/combat changes.**

---

## 14. Minimum behaviour tests

Any significant change to movement/combat should test at least:

- Ground melee moves through/around friendly units.
- Ground melee is attacked while receiving a Move order.
- Ground melee is attacked while receiving an Attack order.
- Archer moves while attacked.
- Archer Attack-Moves and stops/engages appropriately.
- Horse archer attacks while moving.
- Cavalry charges.
- Cavalry disengages.
- Spear interacts correctly with cavalry.
- Hold Position prevents unwanted pursuit.
- Aggressive stance allows appropriate pursuit.
- Passive stance does not initiate unwanted combat.
- Units do not become permanently stuck against other units.

The goal is a system that feels **responsive like Age of Empires**, while allowing **meaningful tactical differences between unit types like Total War**.


---

# 15. Formation-based battle model

**Important design context:** all units operate in **Total War-style formations**, arranged in rows and columns. Formation width and depth can be changed by the player.

The formation, rather than the individual soldier, is the primary tactical object.

The individual units should still move and fight independently enough to produce convincing contact, but formation-level rules should determine:
- frontage
- depth
- spacing
- destination
- facing
- charge behaviour
- local pressure

The desired result is **Total War-style battles**, rather than an Age of Empires-style blob of individually pathfinding units.

---

## 16. Formation width and depth

Formation depth should have gameplay consequences.

### Front rank
The front rank is the primary contact line.

It should:
- make the majority of initial melee contact
- receive the strongest direct pressure
- perform the main attack
- determine the formation's immediate frontage

### Rear ranks
Rear ranks should not simply behave as independent units standing behind the front.

They should contribute through:
- replacing casualties in the front
- adding pressure when appropriate
- supporting attacks
- increasing formation staying power
- providing depth against charges

A deeper formation should generally be:
- harder to break/push through
- better at absorbing a charge
- able to sustain casualties longer
- less manoeuvrable
- potentially less effective at spreading damage across a wide frontage

A wider formation should generally be:
- better at covering frontage
- harder to flank across its entire width
- more vulnerable to being penetrated if too shallow
- easier to manoeuvre only if the formation is not excessively wide

Do not assume "more depth = more damage". Depth should primarily affect **mass, resilience, replacement of front ranks, and resistance to disruption**.

---

## 17. Formation changes

Changing formation shape should be possible without units becoming permanently stuck.

The current rule:

> Friendly units can pass through each other; hostile units cannot.

is a **good starting solution** for formation reshaping.

Do NOT replace this with simple physical collision between every individual soldier.

Instead use:

### Friendly units
- May temporarily overlap/pass through one another when reorganising.
- Formation movement has priority over local individual separation.
- They should gradually settle into their new formation positions.
- Avoid visible permanent overlap when the formation becomes stationary.

### Enemy units
- Should not freely pass through each other.
- Their formations should create physical/tactical resistance.
- Contact should produce a front rather than allowing units to walk through the enemy formation.

This preserves easy formation changes while still allowing battle lines to have physical meaning.

---

## 18. Do not use hard collision as the formation system

Avoid:

```text
every soldier = rigid physical body
```

This tends to cause:
- deadlocks
- formation reshaping problems
- jitter
- units pushing each other indefinitely
- expensive physics simulation
- formations getting stuck

Instead think in terms of:

```text
Formation goal positions
        ↓
Unit movement toward assigned slot
        ↓
Friendly local overlap allowed
        ↓
Enemy resistance / combat contact
        ↓
Formation 
```

The formation controller should be able to temporarily tolerate overlap while reorganising.

---

## 19. Friendly unit pushing

Friendly units should generally **not physically push each other like rigid bodies**.

Instead, use a soft separation/ model.

For example:

```text
Formation wants:
A B C
D E F
G H I

If E moves:
A B C
D   F
G H I

Other units can temporarily move through the space
and then converge on their new slots.
```

A small amount of local separation is useful for visual quality, but it should not be strong enough to prevent formation changes.

Recommended principle:

> **Formation slot assignment has priority over individual avoidance between friendly units.**

---

# 20. Enemy formation contact

Enemy formations should behave differently.

When two formations meet:

```text
AAAAAA
BBBBBB
```

they should form a **battle line**, not simply pass through one another.

At contact:
- front ranks engage
- movement into occupied enemy space is resisted
- units attempt to maintain formation 
- rear ranks provide pressure/support
- individual units may shift locally to maintain contact

The result should look like:

```text
AAAAAA
BBBBBB
```

becoming a connected combat front rather than:

```text
ABABABABAB
```

where units freely interpenetrate.

---

# 21. Formation pressure

Introduce the concept of **formation pressure**, rather than relying entirely on physics.

Pressure can be affected by:

- number of ranks
- unit mass
- current movement speed
- charge state
- unit type
- frontage
- enemy formation depth
- terrain

This allows the game to simulate the tactical effect of mass without requiring rigid-body physics.

For example:

```text
Deep infantry
████████
████████
████████
████████
       ↓
   high pressure
```

versus:

```text
Thin infantry
████████
       ↓
   lower pressure
```

---

# 22. Cavalry shock / charge

Cavalry should **not** simply receive a permanent damage bonus while moving.

A charge should be a temporary combat state.

Conceptually:

```text
Cavalry
████████
   ↓
   ↓ accelerating
   ↓
   ↓
████████
Enemy formation
```

### Charge phases

1. **Approach**
   - Cavalry moves toward target.
   - Speed is important.

2. **Charge**
   - Cavalry reaches sufficient speed.
   - Charge bonus becomes active.

3. **Impact**
   - First contact produces a strong shock effect.
   - Enemy formation may suffer disruption/pushback.
   - Front ranks receive most of the immediate effect.

4. **Melee**
   - Charge bonus decays.
   - Cavalry fights normally.

5. **Disengagement**
   - Cavalry can retreat/reposition.
   - A new charge can potentially be prepared.

The charge should therefore reward:

> distance + speed + suitable target + formation geometry.

---

# 23. What makes a cavalry charge powerful?

A useful conceptual charge strength formula is:

```text
charge_strength =
    unit_mass
  × movement_speed
  × charge_bonus
  × 
  × target_modifier
```

This does not need to be implemented literally.

The important design idea is:

**A stationary cavalry unit should not have the same shock effect as cavalry arriving at full speed.**

---

# 24. Formation depth and cavalry charges

Formation depth should directly affect the result of a charge.

### Shallow formation

Example:

```text
CCCCCCCC
```

Pros:
- wide frontage
- many units can initially make contact

Cons:
- less depth behind the front
- easier to disrupt
- less ability to absorb the charge

### Deep formation

Example:

```text
CCCC
CCCC
CCCC
CCCC
```

Pros:
- more mass behind the front
- better ability to absorb impact
- better  after impact
- harder to penetrate

Cons:
- fewer units initially contact the enemy
- less frontage
- slower/more cumbersome

The exact balance should be tuned experimentally.

---

# 25. Charge into different formations

A cavalry charge should produce different results depending on the target.

### Charge into shallow infantry

Potential result:
- strong disruption
- temporary displacement
- penetration may occur
- infantry formation may lose 

### Charge into deep infantry

Potential result:
- strong initial impact
- less penetration
- cavalry loses momentum more quickly
- formation absorbs the shock

### Charge into spearmen

Potential result:
- cavalry receives a strong counter-effect
- charge may be stopped
- stationary/braced spearmen should be particularly dangerous

### Charge into another cavalry formation

Potential result:
- high shock on both sides
- momentum and formation depth matter
- battle becomes a moving melee rather than a simple instant collision

---

# 26. Pushback should be limited

Do not make every melee hit physically push an individual soldier backward.

That tends to create chaotic "ping-pong" combat.

Instead model **formation displacement/disruption**.

For example:

```text
Before:

AAAAAA
BBBBBB

After strong charge:

  AAAAAA
BBBBBB
```

The entire front can shift slightly while maintaining approximate formation structure.

Use individual displacement mainly for:
- visual impact
- casualties
- gaps
- local contact resolution

The formation controller remains responsible for the overall shape.

---

# 27. Penetration

A useful Total War-style concept is that a formation can sometimes **penetrate** another formation.

However, penetration should be controlled.

A cavalry unit should not simply walk through enemy infantry because the pathfinder says there is space.

Enemy resistance should increase as it enters the enemy formation.

Conceptually:

```text
Enemy formation
████████████

Cavalry
   ↓
   ↓
   ↓
████████████
```

At first:
- charge impact

Then:
- resistance increases

Then:
- cavalry loses speed

Eventually:
- cavalry either becomes engaged or exits the formation

This creates the feeling of mass without rigid collision.

---

# 28. Formation 

Formation  should be an important variable.

# 29. Ranged formations

Ranged units should still use formations.

A bow formation:

```text
BBBBBBBB
BBBBBBBB
BBBBBBBB
```

should have:
- frontage
- depth
- facing
- formation slots

But ranged units should generally avoid unnecessary melee contact.

A bow formation receiving a Move order should not automatically stop because an enemy is nearby.

An Attack-Move should allow it to:
- advance
- acquire targets
- stop/slow as necessary
- fire
- continue depending on its configured behaviour

---

# 30. Formation-level versus unit-level AI

Use two levels of behaviour.

### Formation controller

Responsible for:
- destination
- formation shape
- width/depth
- facing
- formation slots
- movement speed
- overall combat order

### Individual unit controller

Responsible for:
- moving toward its slot
- local avoidance
- target selection
- attack execution
- animation
- local combat reaction

The individual unit should **not independently decide to completely abandon the formation** unless the formation/controller explicitly allows it.

---

# 31. Recommended priority hierarchy

When deciding what a unit should do, use approximately:

```text
1. Explicit player order
2. Formation requirements
3. Combat objective
4. Local avoidance
5. Opportunistic autonomous behaviour
```

For example, if an individual soldier wants to chase an enemy but doing so would leave its formation, the formation controller should normally prevent the chase.

This is especially important for Total War-style battles.

---

# 32. Implementation guidance for AI coding agents

When changing the Godot implementation:

1. Treat the **formation as the primary tactical entity**.
2. Do not solve formation movement by adding stronger physics collisions.
3. Preserve the current ability for friendly units to pass through each other during formation changes unless testing shows a better mechanism is required.
4. Keep hostile formations resistant to interpenetration.
5. Prefer soft formation pressure over rigid-body pushing.
6. Implement cavalry charges as a temporary state with speed/momentum requirements.
7. Make formation depth affect resilience, pressure, and charge absorption.
8. Avoid making depth simply multiply damage.
9. Keep individual units subordinate to formation orders.
10. Do not let local combat AI permanently destroy the formation unless the game rules explicitly call for it.
11. Test formation resizing during movement and combat.
12. Test wide vs deep formations against cavalry.
13. Test shallow vs deep formations against infantry.
14. Test friendly formations moving through/reforming around one another.
15. Test whether enemy formations form stable battle lines instead of interpenetrating.

---

## 33. Core design target

The desired battlefield should visually and mechanically resemble:

```text
                 ARCHERS
        ███████████████████
                 ↓
                 ↓

       SPEARMEN       SWORDSMEN
       ███████         ███████
       ███████         ███████
       ███████         ███████

                         ↓
                    CAVALRY
                   █████████
                      ↓
                      ↓
                  CHARGE!
```

The important emergent behaviour is:

- formations maintain shape
- formations can change width/depth
- friendly units can reorganise without getting stuck
- enemy formations resist each other
- melee creates battle lines
- deep formations absorb pressure
- shallow formations provide frontage
- cavalry uses speed and impact rather than permanent collision damage
- spears provide an anti-cavalry role
- ranged units remain mobile and avoid unnecessary melee
- player orders remain authoritative

The objective is **not** to simulate every individual soldier physically. The objective is to create the **tactical appearance and consequences of massed formations** with stable, responsive RTS controls.

---

## 28. NPC and monster units

The game also contains **NPC/monster units**, such as dragons and other creatures.

These units are not controlled through the normal player formation system.

Their default behaviour is proximity-based:

> If an appropriate enemy comes close enough, the NPC can decide to attack it.

Examples:
- dragon
- large monster
- other autonomous creatures

### Important distinction

NPCs should still use the same underlying concepts for:

- movement
- target detection
- attack range
- attack execution
- local avoidance
- enemy/friendly identification

But they do **not** need to follow player formation orders.

Their high-level behaviour can be:

```text
IDLE
  ↓
Detect enemy within aggro/attack range
  ↓
Choose target
  ↓
Approach / attack
  ↓
Target leaves range or dies
  ↓
Reassess
```

### NPC target detection

NPCs should have configurable parameters such as:

```text
aggro_range
attack_range
preferred_target_types
pursuit_range
attack_cooldown
```

The exact parameters depend on the creature.

A dragon might:
- detect units at a relatively large distance
- attack multiple nearby units
- use area attacks
- attack both infantry and cavalry
- ignore formation rules

A smaller monster might:
- detect enemies at shorter range
- select one nearby target
- fight primarily in melee

### NPCs and formations

NPCs should interact with formations as **enemy units**, but they should not themselves be forced into formation slots.

For example:

```text
PLAYER FORMATION
████████████
████████████
████████████

        ↓

      DRAGON
        🐉
```

The formation should react according to its normal combat rules, while the dragon independently chooses targets.

### NPCs and movement

NPCs should not be treated as a special exception in the low-level movement system.

Instead:

```text
NPC AI
  ↓
Movement target
  ↓
Movement controller
  ↓
Local avoidance
```

This allows monsters to use the same movement infrastructure as player units while having completely different high-level decision-making.

### NPCs and player commands

NPCs are not controlled by player commands unless a specific game mechanic later allows this.

Do not add formation-specific logic to the generic unit movement system merely because NPCs exist.

Keep:

```text
Player-controlled formation AI
```

and:

```text
NPC autonomous AI
```

as separate high-level decision layers sharing lower-level movement/combat functionality.

---

