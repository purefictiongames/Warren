# LibPureFiction Component Registry

> Created: 2026-01-12
> Purpose: Master list of reusable game components derived from popular Roblox genres

## Philosophy

Each component is a **standalone, composable module** that can be mixed and matched to build different game types. Components communicate via events (Router pattern) and store configuration in model attributes.

---

## Genre Coverage

| Genre | Example Games | Key Components |
|-------|---------------|----------------|
| Tower Defense | Toilet TD, All Star TD | PathFollower, Targeting, Turret, Projectile |
| Simulator | Pet Simulator, Bee Swarm | Collector, Hatcher, Multiplier, Rebirth, Pet |
| Obby | Tower of Hell, Obby Creator | Checkpoint, KillZone, MovingPlatform |
| Horror | Piggy, Murder Mystery | RoleAssigner, Objective, Ability, EscapeZone |
| Tycoon | Generic Tycoon, Raft Tycoon | Dropper, Conveyor, Rebirth, Upgrader |
| Roleplay | Brookhaven, Bloxburg | Job, Building, Vehicle, Furniture |
| Fighting | BedWars, Arsenal | Weapon, Loadout, Armor, Team |
| RPG | Blox Fruits, Doors | Quest, Leveling, Stats, Ability, Race |

---

## Component Catalog

### Navigation & Movement

#### PathFollower ✅ IMPLEMENTED
**Purpose:** Move an entity along a sequence of waypoints.
**Status:** Implemented in `Lib/Components/PathFollower.lua`

| Attribute | Type | Description |
|-----------|------|-------------|
| Speed | number | Movement speed in studs/second (default 16) |
| WaitForAck | boolean | Pause at each waypoint until ack signal (default false) |
| AckTimeout | number | Seconds to wait for ack before error (default 5) |
| CollisionMode | string | "ignore" (stay anchored), "physics" (unanchor on hit) |
| OnInterrupt | string | "stop", "pause_and_resume", "restart" |
| ResumeDelay | number | Seconds to wait after collision before resuming |

| Signal (In) | Payload | Description |
|-------------|---------|-------------|
| onControl | { entity, entityId? } | Assign entity to control |
| onWaypoints | { targets: Part[] } | Set waypoint sequence |
| onPause | - | Pause navigation |
| onResume | - | Resume navigation |
| onSetSpeed | { speed } | Change movement speed |
| onAck | - | Acknowledgment for sync mode |

| Signal (Out) | Payload | Description |
|--------------|---------|-------------|
| waypointReached | { waypoint, index, entityId } | Fired when entity reaches a waypoint |
| pathComplete | { entityId } | Fired when entity reaches final waypoint |

Supports both Humanoid-based (MoveTo) and non-Humanoid (TweenService) movement.

**Example Usage:**
```
Tower Defense: Enemies follow path from spawn to base
Horror: Killer patrols predetermined route
Cutscenes: Camera or NPC follows scripted path
```

---

#### MovingPlatform
**Purpose:** Platform that moves between points on a loop or trigger.

| Attribute | Type | Description |
|-----------|------|-------------|
| Points | string | Comma-separated Vector3 positions or part names |
| Speed | number | Movement speed in studs/second |
| PauseTime | number | Seconds to wait at each point |
| TriggerMode | string | "auto", "proximity", "button" |

| Event | Payload | Description |
|-------|---------|-------------|
| ReachedPoint | { index } | Fired when platform reaches a point |
| PlayerBoarded | { player } | Fired when player steps on |
| PlayerExited | { player } | Fired when player steps off |

**Example Usage:**
```
Obby: Platforms that move between ledges
Tycoon: Conveyor alternatives for vertical movement
Adventure: Elevators, moving bridges
```

---

### Combat & Damage

#### HealthSystem
**Purpose:** Track health, handle damage/healing, trigger death.

| Attribute | Type | Description |
|-----------|------|-------------|
| Health | number | Current health |
| MaxHealth | number | Maximum health |
| Armor | number | Flat damage reduction |
| Invulnerable | boolean | Ignore all damage when true |
| RegenRate | number | Health per second regeneration (0 = none) |

| Event | Payload | Description |
|-------|---------|-------------|
| Damaged | { amount, source, damageType } | Fired when damage taken |
| Healed | { amount, source } | Fired when healed |
| Died | { killer, damageType } | Fired when health reaches 0 |
| HealthChanged | { current, max, percent } | Fired on any health change |

**Example Usage:**
```
Tower Defense: Enemy HP, takes damage from towers
RPG: Player/NPC health with regeneration
Fighting: PvP damage tracking
Horror: Survivor health (often 1-hit kill)
Destructibles: Breakable objects with HP
```

---

#### Targeting
**Purpose:** Find valid targets within range using priority rules.

| Attribute | Type | Description |
|-----------|------|-------------|
| Range | number | Detection radius in studs |
| Priority | string | "First", "Last", "Closest", "Strongest", "Weakest", "Random" |
| TargetTag | string | CollectionService tag to filter targets |
| RequireLOS | boolean | Require line-of-sight to target |
| MaxTargets | number | Max simultaneous targets (1 = single target) |

| Event | Payload | Description |
|-------|---------|-------------|
| TargetAcquired | { target } | Fired when new target found |
| TargetLost | { target, reason } | Fired when target leaves range/dies |
| TargetsUpdated | { targets } | Fired when target list changes |

**Example Usage:**
```
Tower Defense: Tower finds enemies to attack
RPG: Auto-targeting for abilities
Simulator: Pet finds nearest collectible
Horror: Killer detects nearest survivor
```

---

#### Turret
**Purpose:** Autonomous attack loop - acquire target, aim, fire.

| Attribute | Type | Description |
|-----------|------|-------------|
| Damage | number | Damage per shot |
| FireRate | number | Shots per second |
| Range | number | Attack range (passed to Targeting) |
| ProjectileType | string | Template name for projectile |
| RotationSpeed | number | Degrees per second for aiming |
| DamageType | string | "Normal", "Fire", "Ice", "Magic", etc. |

| Event | Payload | Description |
|-------|---------|-------------|
| Fired | { target, projectile } | Fired when attack launched |
| Reloading | { duration } | Fired when entering reload state |
| TargetKilled | { target } | Fired when turret kills target |

**Example Usage:**
```
Tower Defense: All tower types
Base Defense: Automated base turrets
NPC Combat: Ranged enemy AI
```

---

#### Projectile
**Purpose:** Spawn, move, and resolve hit detection for projectiles.

| Attribute | Type | Description |
|-----------|------|-------------|
| Speed | number | Travel speed (0 = hitscan instant) |
| Damage | number | Damage on hit |
| Lifetime | number | Max seconds before despawn |
| Piercing | number | Enemies to pierce (0 = single hit) |
| AOERadius | number | Splash damage radius (0 = single target) |
| Gravity | number | Gravity multiplier for arc (0 = straight) |

| Event | Payload | Description |
|-------|---------|-------------|
| Hit | { target, position } | Fired on impact |
| Expired | { position } | Fired when lifetime exceeded |
| Pierced | { target, remaining } | Fired when piercing through target |

**Example Usage:**
```
Tower Defense: Bullets, arrows, magic bolts
Fighting: Ranged weapon projectiles
RPG: Spell effects
```

---

#### Weapon
**Purpose:** Equippable item that deals damage via melee or ranged attacks.

| Attribute | Type | Description |
|-----------|------|-------------|
| WeaponType | string | "Melee", "Ranged", "Magic" |
| Damage | number | Base damage per hit |
| AttackSpeed | number | Attacks per second |
| Range | number | Melee reach or projectile range |
| AmmoCapacity | number | Shots before reload (0 = unlimited) |
| ReloadTime | number | Seconds to reload |

| Event | Payload | Description |
|-------|---------|-------------|
| Attacked | { target, damage } | Fired when attack lands |
| Equipped | { player } | Fired when weapon equipped |
| Unequipped | { player } | Fired when weapon unequipped |
| Reloaded | { } | Fired when reload complete |

**Example Usage:**
```
Fighting: Swords, guns, bows in BedWars/Arsenal
RPG: Player weapons with upgrades
Horror: Sheriff's gun, killer's weapon
```

---

#### Armor
**Purpose:** Damage reduction and resistance system.

| Attribute | Type | Description |
|-----------|------|-------------|
| Defense | number | Flat damage reduction |
| Resistances | table | { Fire = 0.5, Ice = 0.25 } multipliers |
| Durability | number | Hits before breaking (0 = unbreakable) |
| Slot | string | "Head", "Chest", "Legs", "Feet" |

| Event | Payload | Description |
|-------|---------|-------------|
| DamageBlocked | { original, reduced } | Fired when armor reduces damage |
| Broken | { slot } | Fired when durability depleted |

**Example Usage:**
```
Fighting: Tiered armor in BedWars
RPG: Equipment slots with resistances
```

---

### Detection & Triggers

#### Zone ✅ IMPLEMENTED
**Purpose:** Region detection with declarative filtering.
**Status:** Implemented in `Lib/Components/Zone.lua`

| Attribute | Type | Description |
|-----------|------|-------------|
| DebounceTime | number | Seconds between re-detections (default 0.5) |
| DetectOnEnter | boolean | Fire on zone entry (default true) |
| DetectOnExit | boolean | Fire on zone exit (default true) |

| Signal (In) | Payload | Description |
|-------------|---------|-------------|
| onConfigure | { filter, debounceTime, ... } | Configure zone and filters |
| onEnable | - | Enable detection |
| onDisable | - | Disable detection |

| Signal (Out) | Payload | Description |
|--------------|---------|-------------|
| entityEntered | { entity, entityId, assetId, ... } | Fired when matching entity enters |
| entityExited | { entity, entityId } | Fired when entity exits |

Supports Standard Filter Schema for declarative entity filtering.

**Example Usage:**
```
Tower Defense: End zone for path completion
Horror: Trap trigger zones
Tycoon: Collection zones
```

---

### Progression & Economy

#### Currency
**Purpose:** Track and modify per-player currency values.

| Attribute | Type | Description |
|-----------|------|-------------|
| CurrencyType | string | "Gold", "Gems", "Coins", etc. |
| StartingAmount | number | Initial value for new players |
| MaxAmount | number | Cap (0 = unlimited) |

| Event | Payload | Description |
|-------|---------|-------------|
| Changed | { player, amount, delta, source } | Fired on any change |
| Earned | { player, amount, source } | Fired when currency gained |
| Spent | { player, amount, item } | Fired when currency spent |
| Insufficient | { player, required, has } | Fired when purchase fails |

**Example Usage:**
```
Tower Defense: Gold from kills, spent on towers
Tycoon: Money from droppers, spent on upgrades
Simulator: Coins from collection
RPG: Gold/gems for items and abilities
```

---

#### Leveling
**Purpose:** XP-based level progression with configurable curves.

| Attribute | Type | Description |
|-----------|------|-------------|
| Level | number | Current level |
| XP | number | Current XP toward next level |
| MaxLevel | number | Level cap (0 = unlimited) |
| XPCurve | string | "linear", "exponential", "custom" |
| BaseXP | number | XP required for level 2 |
| XPMultiplier | number | Multiplier per level for exponential |

| Event | Payload | Description |
|-------|---------|-------------|
| XPGained | { amount, source, total } | Fired when XP earned |
| LevelUp | { newLevel, rewards } | Fired on level increase |
| MaxLevelReached | { } | Fired when hitting cap |

**Example Usage:**
```
RPG: Player leveling from quests/kills
Simulator: Account level unlocking features
Fighting: Prestige/rank progression
```

---

#### Stats
**Purpose:** Named stat values with base + modifier support.

| Attribute | Type | Description |
|-----------|------|-------------|
| StatNames | string | Comma-separated: "Strength,Defense,Speed" |
| BaseValues | string | Comma-separated defaults: "10,10,10" |
| PointsPerLevel | number | Stat points awarded per level |

| Event | Payload | Description |
|-------|---------|-------------|
| StatChanged | { stat, oldValue, newValue } | Fired on stat change |
| PointsAllocated | { stat, points } | Fired when player assigns points |
| ModifierApplied | { stat, modifier, duration } | Fired when buff/debuff applied |

**Example Usage:**
```
RPG: Melee, Defense, Sword, Gun stats in Blox Fruits
Fighting: Character stat builds
Simulator: Pet stats
```

---

#### UpgradePath
**Purpose:** Define upgrade tiers with costs and stat modifications.

| Attribute | Type | Description |
|-----------|------|-------------|
| MaxLevel | number | Maximum upgrade level |
| CurrentLevel | number | Current upgrade level |
| CostCurve | string | "linear", "exponential" |
| BaseCost | number | Cost for first upgrade |
| StatBoosts | string | JSON: {"Damage": 1.2, "Range": 1.1} per level |

| Event | Payload | Description |
|-------|---------|-------------|
| Upgraded | { level, cost, stats } | Fired on successful upgrade |
| MaxReached | { } | Fired when max level hit |
| UpgradeFailed | { reason } | Fired when upgrade fails (cost, etc.) |

**Example Usage:**
```
Tower Defense: Tower upgrades
Tycoon: Dropper/conveyor upgrades
RPG: Weapon enhancement
Simulator: Tool upgrades
```

---

#### Rebirth
**Purpose:** Prestige system - reset progress for permanent bonuses.

| Attribute | Type | Description |
|-----------|------|-------------|
| RebirthCount | number | Current rebirth count |
| BonusPerRebirth | number | Multiplier added per rebirth (e.g., 0.5 = +50%) |
| RequiredLevel | number | Level required to rebirth |
| RequiredCurrency | number | Currency required to rebirth |
| ResetItems | boolean | Whether items reset on rebirth |

| Event | Payload | Description |
|-------|---------|-------------|
| Rebirthed | { count, bonus } | Fired on rebirth |
| RebirthAvailable | { } | Fired when requirements met |
| RequirementsMet | { level, currency } | Check if can rebirth |

**Example Usage:**
```
Tycoon: Reset factory for income multiplier
Simulator: Prestige for permanent boosts
RPG: New Game+ mechanics
```

---

#### Multiplier
**Purpose:** Stack and apply multipliers to values (income, XP, damage).

| Attribute | Type | Description |
|-----------|------|-------------|
| BaseValue | number | Starting multiplier (usually 1.0) |
| MultiplierType | string | "Income", "XP", "Damage", "Speed" |
| StackMode | string | "additive" or "multiplicative" |

| Event | Payload | Description |
|-------|---------|-------------|
| MultiplierChanged | { total, sources } | Fired when multiplier changes |
| SourceAdded | { source, value, duration } | Fired when new source added |
| SourceExpired | { source } | Fired when timed source expires |

**Example Usage:**
```
Simulator: 2x income events, pet bonuses
Tycoon: Rebirth bonuses, upgrades
RPG: Damage buffs, XP boosts
```

---

### Collection & Inventory

#### Inventory
**Purpose:** Store and manage player items with slots and stacking.

| Attribute | Type | Description |
|-----------|------|-------------|
| MaxSlots | number | Inventory capacity |
| StackSize | number | Max items per stack |
| AllowedTypes | string | Comma-separated item types allowed |

| Event | Payload | Description |
|-------|---------|-------------|
| ItemAdded | { item, slot, count } | Fired when item added |
| ItemRemoved | { item, slot, count } | Fired when item removed |
| SlotsFull | { item } | Fired when can't add item |
| ItemMoved | { item, fromSlot, toSlot } | Fired when item repositioned |

**Example Usage:**
```
RPG: Player inventory for weapons/items
Simulator: Collected items before selling
Tycoon: Stored materials
Horror: Key items for puzzles
```

---

#### Collector
**Purpose:** Automatically gather nearby collectibles into inventory/currency.

| Attribute | Type | Description |
|-----------|------|-------------|
| Range | number | Collection radius |
| CollectTag | string | Tag of collectible items |
| AutoCollect | boolean | Collect on touch vs manual |
| Capacity | number | Max items before needing to deposit |

| Event | Payload | Description |
|-------|---------|-------------|
| Collected | { item, value } | Fired when item collected |
| CapacityFull | { } | Fired when at max capacity |
| Deposited | { total } | Fired when depositing collection |

**Example Usage:**
```
Simulator: Bee Swarm pollen collection
RPG: Loot pickup
Tycoon: Resource gathering
```

---

#### Hatcher ✅ IMPLEMENTED
**Purpose:** Gacha/egg system - random rewards with weighted rarity.
**Status:** Implemented in `Lib/Components/Hatcher.lua`

| Attribute | Type | Description |
|-----------|------|-------------|
| HatchTime | number | Seconds to hatch (0 = instant) |
| Cost | number | Currency cost per hatch |
| CostType | string | Currency type required |
| PityThreshold | number | Guaranteed rare after N hatches (0 = none) |

| Signal (In) | Payload | Description |
|-------------|---------|-------------|
| onConfigure | { pool } | Set reward pool with weights |
| onHatch | { player? } | Trigger a hatch attempt |
| onCostConfirmed | { player, approved } | Response to cost check |
| onSetPity | { player, count } | Set pity counter for player |

| Signal (Out) | Payload | Description |
|--------------|---------|-------------|
| costCheck | { player, cost, costType } | Fired before hatch (external validation) |
| hatchStarted | { player, hatchTime } | Fired when hatch begins |
| hatched | { player, result, rarity, assetId, pityTriggered } | Fired on completion |
| hatchFailed | { player, reason } | Fired if hatch cannot proceed |

Pool format: `{{ template = "CommonPet", rarity = "Common", weight = 60, pity = false }, ...}`

**Example Usage:**
```
Simulator: Pet eggs, unit summoning
Tower Defense: Gacha tower summoning
RPG: Loot boxes, item crafting
```

---

#### Pet
**Purpose:** AI companion that follows player and provides bonuses.

| Attribute | Type | Description |
|-----------|------|-------------|
| FollowDistance | number | Distance to maintain from owner |
| FollowSpeed | number | Movement speed |
| BonusType | string | "Damage", "Collection", "Speed", etc. |
| BonusValue | number | Multiplier or flat bonus |
| Rarity | string | "Common", "Rare", "Legendary", etc. |

| Event | Payload | Description |
|-------|---------|-------------|
| Equipped | { owner } | Fired when pet equipped |
| Unequipped | { owner } | Fired when pet unequipped |
| ActionPerformed | { action } | Fired when pet does something |
| LeveledUp | { level } | Fired when pet gains level |

**Example Usage:**
```
Simulator: Collection pets in Pet Simulator
RPG: Combat companions
Adventure: Helper NPCs
```

---

### Game Flow & Objectives

#### Checkpoint
**Purpose:** Save player progress position, respawn on death.

| Attribute | Type | Description |
|-----------|------|-------------|
| CheckpointNumber | number | Order in sequence |
| SpawnOffset | Vector3 | Offset from checkpoint for spawn |
| ActivateOnce | boolean | Can only be activated once |
| ShowIndicator | boolean | Visual feedback on activation |

| Event | Payload | Description |
|-------|---------|-------------|
| Activated | { player, number } | Fired when checkpoint reached |
| PlayerRespawned | { player, checkpoint } | Fired when player respawns here |

**Example Usage:**
```
Obby: Progress saves through obstacle course
Horror: Safe rooms in survival games
Adventure: World exploration progress
```

---

#### KillZone
**Purpose:** Region that damages or kills players on contact.

| Attribute | Type | Description |
|-----------|------|-------------|
| Damage | number | Damage per tick (9999 = instant kill) |
| DamageInterval | number | Seconds between damage ticks |
| DamageType | string | "Lava", "Void", "Spikes", etc. |
| RespawnToCheckpoint | boolean | Send to checkpoint vs default spawn |

| Event | Payload | Description |
|-------|---------|-------------|
| PlayerEntered | { player } | Fired when player enters zone |
| PlayerDamaged | { player, damage } | Fired when damage dealt |
| PlayerKilled | { player } | Fired when player dies in zone |

**Example Usage:**
```
Obby: Lava, spikes, void zones
Horror: Trap areas
Adventure: Environmental hazards
```

---

#### Objective
**Purpose:** Trackable goal with completion conditions.

| Attribute | Type | Description |
|-----------|------|-------------|
| ObjectiveType | string | "Collect", "Kill", "Reach", "Survive", "Interact" |
| TargetCount | number | Amount required (items, kills, etc.) |
| CurrentCount | number | Current progress |
| TimeLimit | number | Seconds to complete (0 = unlimited) |
| Required | boolean | Must complete to proceed |

| Event | Payload | Description |
|-------|---------|-------------|
| ProgressMade | { current, target } | Fired on progress |
| Completed | { time } | Fired when objective met |
| Failed | { reason } | Fired when objective fails |
| TimeWarning | { remaining } | Fired at low time |

**Example Usage:**
```
Horror: Find keys, solve puzzles, escape
RPG: Quest objectives
Tutorial: Guided tasks
```

---

#### Quest
**Purpose:** Multi-objective mission with rewards.

| Attribute | Type | Description |
|-----------|------|-------------|
| QuestName | string | Display name |
| Description | string | Quest description |
| Objectives | string | JSON array of Objective configs |
| Rewards | string | JSON: {"XP": 100, "Gold": 50, "Item": "Sword"} |
| Repeatable | boolean | Can be completed multiple times |
| Cooldown | number | Seconds before repeatable quest resets |

| Event | Payload | Description |
|-------|---------|-------------|
| Started | { quest } | Fired when quest accepted |
| ObjectiveComplete | { index, objective } | Fired per objective done |
| Completed | { rewards } | Fired when all objectives done |
| Abandoned | { } | Fired when quest dropped |

**Example Usage:**
```
RPG: Main story and side quests
Simulator: Daily/weekly missions
Adventure: Exploration tasks
```

---

#### RoleAssigner
**Purpose:** Assign players to roles/teams at round start.

| Attribute | Type | Description |
|-----------|------|-------------|
| Roles | string | JSON: {"Survivor": 7, "Killer": 1, "Sheriff": 1} |
| AssignMode | string | "random", "volunteer", "rotation" |
| AllowSwitch | boolean | Can players change roles mid-round |
| MinPlayers | number | Minimum players to start |

| Event | Payload | Description |
|-------|---------|-------------|
| RolesAssigned | { assignments } | Fired when roles distributed |
| PlayerRoleChanged | { player, oldRole, newRole } | Fired on role change |
| RoleEliminated | { role } | Fired when all of role dead |

**Example Usage:**
```
Horror: Killer vs Survivors, Murder Mystery roles
Fighting: Team assignment
Social Deduction: Werewolf/Mafia roles
```

---

#### EscapeZone
**Purpose:** Win condition zone - reach to complete objective.

| Attribute | Type | Description |
|-----------|------|-------------|
| RequiredItems | string | Comma-separated items needed to enter |
| RequiredObjectives | number | Objectives that must be complete |
| ExitTime | number | Seconds to stand in zone to escape |
| AllPlayersRequired | boolean | Everyone must be in zone |

| Event | Payload | Description |
|-------|---------|-------------|
| PlayerEntered | { player } | Fired when player enters |
| PlayerEscaped | { player } | Fired when player escapes |
| EscapeBlocked | { player, reason } | Fired when requirements not met |
| AllEscaped | { } | Fired when all survivors escape |

**Example Usage:**
```
Horror: Exit doors in Piggy
Adventure: Level end zones
Obby: Finish line
```

---

### Ability & Effects

#### Ability
**Purpose:** Activatable power with cooldown and resource cost.

| Attribute | Type | Description |
|-----------|------|-------------|
| AbilityName | string | Display name |
| Cooldown | number | Seconds between uses |
| EnergyCost | number | Resource cost to activate |
| Duration | number | Active duration (0 = instant) |
| EffectType | string | "Damage", "Heal", "Buff", "Utility" |
| TargetType | string | "Self", "Single", "AOE", "Projectile" |

| Event | Payload | Description |
|-------|---------|-------------|
| Activated | { user, targets } | Fired when ability used |
| EffectApplied | { target, effect } | Fired when effect lands |
| CooldownStarted | { duration } | Fired when cooldown begins |
| CooldownReady | { } | Fired when ability available |

**Example Usage:**
```
RPG: Devil Fruit abilities in Blox Fruits
Horror: Survivor/Killer abilities in Piggy
Fighting: Kit abilities in BedWars
```

---

#### StatusEffect
**Purpose:** Temporary buff/debuff applied to entities.

| Attribute | Type | Description |
|-----------|------|-------------|
| EffectType | string | "Burn", "Slow", "Stun", "Shield", "Haste" |
| Duration | number | Seconds effect lasts |
| Intensity | number | Effect strength (damage/slow %) |
| Stackable | boolean | Can multiple instances stack |
| MaxStacks | number | Maximum stacks allowed |

| Event | Payload | Description |
|-------|---------|-------------|
| Applied | { target, stacks } | Fired when effect applied |
| Ticked | { target, damage } | Fired on DoT tick |
| Expired | { target } | Fired when effect ends |
| Cleansed | { target, source } | Fired when effect removed early |

**Example Usage:**
```
RPG: Poison, burn, freeze effects
Tower Defense: Slow towers, damage over time
Fighting: Stun, knockback effects
```

---

### Tycoon Specific

#### Dropper ✅ IMPLEMENTED (v2)
**Purpose:** Interval-based entity spawning with return handling.
**Status:** Implemented in `Lib/Components/Dropper.lua`

| Attribute | Type | Description |
|-----------|------|-------------|
| Interval | number | Seconds between spawns (default 2) |
| TemplateName | string | Template model name |
| MaxActive | number | Max spawned at once (0 = unlimited) |
| AutoStart | boolean | Start spawning on init (default false) |

| Signal (In) | Payload | Description |
|-------------|---------|-------------|
| onConfigure | { templateName, interval, maxActive, ... } | Configure dropper |
| onStart | - | Start spawn loop |
| onStop | - | Stop spawn loop |
| onReturn | { assetId } | Despawn entity by ID (from Zone, etc.) |
| onDespawnAll | - | Despawn all spawned entities |

| Signal (Out) | Payload | Description |
|--------------|---------|-------------|
| spawned | { assetId, instance, entityId } | Fired when entity spawned |
| despawned | { assetId, entityId } | Fired when entity despawned |
| loopStarted | - | Fired when spawn loop begins |
| loopStopped | - | Fired when spawn loop ends |

Uses SpawnerCore internally for spawn/despawn mechanics.

---

#### Conveyor
**Purpose:** Move parts along a path to destination.

| Attribute | Type | Description |
|-----------|------|-------------|
| Speed | number | Studs per second |
| Direction | Vector3 | Movement direction |
| Length | number | Conveyor length |
| AcceptTag | string | Tag of items to move |

| Event | Payload | Description |
|-------|---------|-------------|
| ItemEntered | { item } | Fired when item enters |
| ItemExited | { item } | Fired when item exits |
| ItemProcessed | { item, destination } | Fired when item reaches end |

**Example Usage:**
```
Tycoon: Move drops to collector/upgrader
Factory: Assembly line mechanics
```

---

#### Upgrader
**Purpose:** Modify passing items (increase value, transform type).

| Attribute | Type | Description |
|-----------|------|-------------|
| Multiplier | number | Value multiplier (e.g., 1.5 = +50%) |
| FlatBonus | number | Flat value added |
| ProcessTime | number | Seconds to process item |
| MaxUses | number | Times item can be upgraded (0 = unlimited) |
| TransformTo | string | Change item type (empty = keep type) |

| Event | Payload | Description |
|-------|---------|-------------|
| ItemUpgraded | { item, oldValue, newValue } | Fired when item processed |
| ItemRejected | { item, reason } | Fired when item can't be upgraded |

**Example Usage:**
```
Tycoon: Value multipliers on conveyor
Factory: Item transformation/crafting
```

---

### Social & Teams

#### Team
**Purpose:** Group players into teams with shared properties.

| Attribute | Type | Description |
|-----------|------|-------------|
| TeamName | string | Display name |
| TeamColor | BrickColor | Team color |
| MaxPlayers | number | Player limit per team |
| FriendlyFire | boolean | Can teammates damage each other |
| SharedResources | boolean | Share currency/items |

| Event | Payload | Description |
|-------|---------|-------------|
| PlayerJoined | { player, team } | Fired when player joins team |
| PlayerLeft | { player, team } | Fired when player leaves team |
| TeamEliminated | { team } | Fired when all players eliminated |
| TeamWon | { team } | Fired when team wins |

**Example Usage:**
```
Fighting: Red vs Blue in BedWars
Horror: Survivors team
RPG: Pirate vs Marine factions
```

---

#### Loadout
**Purpose:** Pre-defined equipment/ability sets players can select.

| Attribute | Type | Description |
|-----------|------|-------------|
| LoadoutName | string | Display name |
| Weapons | string | Comma-separated weapon templates |
| Abilities | string | Comma-separated ability names |
| Stats | string | JSON stat modifiers |
| UnlockCost | number | Currency to unlock (0 = free) |

| Event | Payload | Description |
|-------|---------|-------------|
| Selected | { player, loadout } | Fired when loadout chosen |
| Equipped | { player } | Fired when loadout applied |
| Unlocked | { player, loadout } | Fired when loadout purchased |

**Example Usage:**
```
Fighting: Kit selection in BedWars
Shooter: Class selection in Arsenal
RPG: Character builds
```

---

#### Job
**Purpose:** Role-based activity that earns currency over time.

| Attribute | Type | Description |
|-----------|------|-------------|
| JobName | string | Display name |
| PayRate | number | Currency per completion |
| TaskDuration | number | Seconds per task |
| TaskType | string | "Click", "Hold", "Minigame" |
| XPReward | number | XP per completion |

| Event | Payload | Description |
|-------|---------|-------------|
| TaskStarted | { player, job } | Fired when task begins |
| TaskCompleted | { player, earnings } | Fired when task done |
| JobChanged | { player, oldJob, newJob } | Fired when switching jobs |

**Example Usage:**
```
Roleplay: Jobs in Bloxburg
Tycoon: Manual income sources
Simulator: Minigame tasks
```

---

### Infrastructure

#### NodePool ✅ IMPLEMENTED
**Purpose:** Generic node pooling with fixed or elastic modes.
**Status:** Implemented in `Lib/Components/NodePool.lua`

| Attribute | Type | Description |
|-----------|------|-------------|
| PoolMode | string | "fixed" (pre-allocate) or "elastic" (grow/shrink) |
| MinSize | number | Minimum pool size (elastic mode) |
| MaxSize | number | Maximum pool size |
| ShrinkDelay | number | Seconds idle before shrinking (elastic mode) |

| Signal (In) | Payload | Description |
|-------------|---------|-------------|
| onConfigure | { nodeClass, poolMode, checkoutSignals, ... } | Configure pool |
| onCheckout | { entity, entityId, ... } | Request a node from pool |
| onRelease | { nodeId } | Return node to pool |

| Signal (Out) | Payload | Description |
|--------------|---------|-------------|
| checkedOut | { nodeId, entityId } | Fired when node checked out |
| released | { nodeId, entityId } | Fired when node released |
| exhausted | { entityId, maxSize } | Fired when pool at capacity |
| nodeCreated | { nodeId } | Fired when new node created (elastic) |
| nodeDestroyed | { nodeId } | Fired when idle node destroyed (elastic) |

Features:
- **Checkout signals**: Auto-send configured signals to checked-out nodes
- **Auto-release**: Listen for signal (e.g., "pathComplete") to auto-return nodes
- **Context injection**: `$variableName` syntax for shared context in signal mapping

**Example Usage:**
```lua
pool.In.onConfigure(pool, {
    nodeClass = "PathFollower",
    poolMode = "elastic",
    minSize = 2, maxSize = 15,
    checkoutSignals = {
        { signal = "onControl", map = { entity = "entity" } },
        { signal = "onWaypoints", map = { targets = "$waypoints" } },
    },
    releaseOn = "pathComplete",
    context = { waypoints = { wp1, wp2, wp3 } },
})
```

---

#### Timer
**Purpose:** Countdown or countup timer with events.

| Attribute | Type | Description |
|-----------|------|-------------|
| Duration | number | Total seconds |
| Direction | string | "down" or "up" |
| AutoStart | boolean | Start immediately |
| WarningTime | number | Seconds remaining to trigger warning |

| Event | Payload | Description |
|-------|---------|-------------|
| Started | { duration } | Fired when timer starts |
| Tick | { remaining, elapsed } | Fired each second |
| Warning | { remaining } | Fired at warning threshold |
| Completed | { } | Fired when timer ends |
| Paused | { remaining } | Fired when paused |
| Resumed | { remaining } | Fired when resumed |

**Example Usage:**
```
Horror: Round timer
Tower Defense: Wave intermission
Obby: Speedrun timer
Fighting: Match duration
```

---

#### Spawner
**Purpose:** Spawn entities at location with optional pooling.

| Attribute | Type | Description |
|-----------|------|-------------|
| Template | string | Model to spawn |
| SpawnOffset | Vector3 | Offset from spawner position |
| MaxActive | number | Max spawned at once |
| RespawnDelay | number | Seconds before respawning |
| UsePooling | boolean | Reuse instances for performance |

| Event | Payload | Description |
|-------|---------|-------------|
| Spawned | { instance } | Fired when entity spawned |
| Despawned | { instance, reason } | Fired when entity removed |
| PoolExhausted | { } | Fired when max active reached |

**Example Usage:**
```
Tower Defense: Enemy spawning (via Dropper)
RPG: NPC/mob spawning
Simulator: Collectible respawning
```

---

#### Leaderboard
**Purpose:** Track and display ranked player statistics.

| Attribute | Type | Description |
|-----------|------|-------------|
| StatName | string | Stat to track |
| SortOrder | string | "Descending" or "Ascending" |
| MaxEntries | number | Entries to display |
| Scope | string | "Server", "Global", "Friends" |
| ResetInterval | string | "Never", "Daily", "Weekly" |

| Event | Payload | Description |
|-------|---------|-------------|
| Updated | { entries } | Fired when rankings change |
| PlayerRankChanged | { player, oldRank, newRank } | Fired on rank change |
| NewHighScore | { player, score } | Fired on new record |

**Example Usage:**
```
All genres: Kills, level, currency display
Obby: Fastest completion times
Simulator: Collection totals
```

---

#### DataPersistence
**Purpose:** Save and load player data across sessions.

| Attribute | Type | Description |
|-----------|------|-------------|
| DataKeys | string | Comma-separated keys to save |
| AutoSaveInterval | number | Seconds between auto-saves |
| SaveOnLeave | boolean | Save when player leaves |
| UseOrderedStore | boolean | Use OrderedDataStore for leaderboards |

| Event | Payload | Description |
|-------|---------|-------------|
| Loaded | { player, data } | Fired when data loaded |
| Saved | { player } | Fired when data saved |
| SaveFailed | { player, error } | Fired on save error |
| DataMigrated | { player, version } | Fired when data schema updated |

**Example Usage:**
```
All genres: Progress persistence
Simulator: Pet/item collections
RPG: Character stats and inventory
```

---

## Component Composition Matrix

Shows which components typically combine for each genre:

| Component | TD | Sim | Obby | Horror | Tycoon | RP | Fight | RPG |
|-----------|:--:|:---:|:----:|:------:|:------:|:--:|:-----:|:---:|
| PathFollower | X | | | X | | | | |
| MovingPlatform | | | X | | | | | |
| HealthSystem | X | | | X | | | X | X |
| Targeting | X | X | | | | | | |
| Turret | X | | | | | | | |
| Projectile | X | | | | | | X | X |
| Weapon | | | | X | | | X | X |
| Armor | | | | | | | X | X |
| Currency | X | X | | | X | X | | X |
| Leveling | | X | | | | | X | X |
| Stats | | | | | | | | X |
| UpgradePath | X | X | | | X | | | X |
| Rebirth | | X | | | X | | | |
| Multiplier | | X | | | X | | | |
| Inventory | | X | | X | | X | | X |
| Collector | | X | | | X | | | X |
| Hatcher | X | X | | | | | | |
| Pet | | X | | | | | | X |
| Checkpoint | | | X | X | | | | |
| KillZone | | | X | X | | | | |
| Objective | | | | X | | | | X |
| Quest | | X | | | | | | X |
| RoleAssigner | | | | X | | | X | |
| EscapeZone | | | X | X | | | | |
| Ability | | | | X | | | X | X |
| StatusEffect | X | | | | | | X | X |
| Dropper | | | | | X | | | |
| Conveyor | | | | | X | | | |
| Upgrader | | | | | X | | | |
| Team | | | | X | | | X | X |
| Loadout | | | | | | | X | X |
| Job | | | | | | X | | |
| Timer | X | | X | X | | | X | |
| Spawner | X | X | | X | | | | X |
| Leaderboard | X | X | X | | X | | X | X |
| DataPersistence | X | X | X | X | X | X | X | X |

---

## Existing v1 Components

These components already exist and can be reused:

| Component | Location | Status |
|-----------|----------|--------|
| WaveController | Lib/WaveController | Production |
| Dropper | Lib/Dropper | Production |
| ArrayPlacer | Lib/ArrayPlacer | Production |
| TimedEvaluator | Lib/TimedEvaluator | Production |
| Router | System/Router | Production |
| Visibility | System/Visibility | Production |
| GUI System | System/GUI | Production |
| GlobalTimer | Lib/GlobalTimer | Production |
| Leaderboard | Lib/LeaderBoard | Production |
| ZoneController | Lib/ZoneController | Production |

---

## Build Priority

### Tier 1: Universal (used by 5+ genres)
1. HealthSystem
2. Currency
3. Inventory
4. Timer
5. DataPersistence

### Tier 2: High-Value (used by 3-4 genres)
6. Leveling
7. Ability
8. Checkpoint
9. Quest/Objective
10. Team

### Tier 3: Genre-Specific
11. PathFollower (TD, Horror)
12. Targeting + Turret (TD)
13. Projectile + Weapon (Combat)
14. Rebirth + Multiplier (Tycoon, Sim)
15. Hatcher + Pet (Simulator)
16. Conveyor + Upgrader (Tycoon)
17. RoleAssigner + EscapeZone (Horror)

---

## Reference Sources

- [Roblox DevForum - Tower Defense Guide](https://devforum.roblox.com/t/an-in-depth-guide-to-a-tower-defense-game-part-1/3019857)
- [Bee Swarm Simulator Wiki](https://bee-swarm-simulator.fandom.com/wiki/Bee_Swarm_Simulator_Wiki)
- [Roblox DevForum - Obby Checkpoint Tutorial](https://devforum.roblox.com/t/how-to-create-an-obby-part-1-checkpoints-system-and-lava-bricks/874825)
- [Piggy Wiki](https://piggy.fandom.com/wiki/Piggy_(Game))
- [Tycoon Incremental Wiki - Progression](https://tycoon-incremental.fandom.com/wiki/Progression)
- [Brookhaven Wiki](https://official-brookhaven.fandom.com/wiki/Brookhaven)
- [BedWars Wiki](https://robloxbedwars.fandom.com/wiki/Category:Weapons)
- [Blox Fruits Wiki](https://blox-fruits.fandom.com/wiki/Quests)
