# Tower Defense Component Architecture

> Research Date: 2026-01-12
> Purpose: Reverse-engineer components needed to build a Tower Defense game from scratch

## Philosophy

This document identifies **new standalone components** to add to the LibPureFiction component library. These are additive modules - they don't replace existing components like TimedEvaluator or WaveController. The goal is a collection of composable pieces that can be mixed and matched for different game types.

## Market Context

Tower Defense is a top-tier Roblox genre, sitting within the Adventure/Fighting categories. Popular examples:
- **Toilet Tower Defense** - Meme-themed, gacha summoning
- **All Star Tower Defense** - Anime characters as towers
- **Tower Defense Simulator** - Classic TD mechanics

These games share common systems that can be abstracted into reusable components.

---

## New Components Needed

| Component | Purpose | Reusability Beyond TD |
|-----------|---------|----------------------|
| **PathFollower** | Waypoint-based navigation | NPCs, patrols, cutscenes |
| **HealthSystem** | Damage, death, healing | Any combat game |
| **Targeting** | Find entities by priority/range | Combat AI, auto-aim |
| **Turret** | Autonomous attack loop | Base defense, NPCs |
| **Projectile** | Spawning + hit detection | Shooters, magic games |
| **PlacementValidator** | Grid/node placement rules | Building games, tycoons |
| **Currency** | Per-player economy tracking | Any progression game |
| **UpgradePath** | Stat progression trees | RPGs, tycoons |
| **Gacha** | Weighted random summoning | Collection games |

### Existing Components That Apply

| Component | TD Role |
|-----------|---------|
| **WaveController** | Enemy spawn waves |
| **Dropper** | Spawn points |
| **ArrayPlacer** | Tower placement grid |
| **Router** | Inter-component messaging |
| **Visibility** | Show/hide on spawn/death |

---

## Detailed Component Specifications

### 1. PathSystem (NEW)

**Purpose:** Define enemy routes via waypoints

```
Inputs:
  - Spawn event from WaveController

Outputs:
  - Position updates (for interpolation)
  - ReachedEnd event (enemy got through)
  - ReachedWaypoint event (progress tracking)

Config (Attributes):
  - WaypointFolder: string (folder containing numbered parts)
  - LoopBehavior: "stop" | "loop" | "reverse"
  - SpeedMultiplier: number (global speed modifier)

Structure:
  Workspace/
    Paths/
      Path1/
        1 (Part)
        2 (Part)
        3 (Part)
        ...
```

**Implementation Notes:**
- Use `Humanoid:MoveTo()` for Humanoid-based enemies
- Use `TweenService` or manual interpolation for non-Humanoid enemies
- Fire `MoveToFinished` or custom event on waypoint arrival

---

### 2. HealthSystem (NEW)

**Purpose:** Generic health/damage system attachable to any entity

```
Attributes:
  - Health: number
  - MaxHealth: number
  - Armor: number (damage reduction, optional)
  - Invulnerable: boolean (optional)
  - DamageMultipliers: table (by damage type, optional)

Events:
  - Damaged(amount, source, damageType)
  - Healed(amount, source)
  - Died(killer)
  - HealthChanged(newHealth, oldHealth)

Methods:
  - TakeDamage(amount, damageType, source)
  - Heal(amount, source)
  - SetInvulnerable(duration)
  - ApplyEffect(effectType, duration) -- slow, stun, burn, etc.
```

**Reusability:** Any game with combat - TD enemies, RPG mobs, PvP players, destructible objects

---

### 3. Turret (NEW)

**Purpose:** Autonomous targeting and attack loop for any stationary attacker

```
Attributes:
  - Range: number (studs)
  - Damage: number
  - FireRate: number (shots per second)
  - TargetPriority: "First" | "Last" | "Strongest" | "Weakest" | "Closest"
  - ProjectileType: string (reference to projectile template)
  - CanTargetFlying: boolean
  - CanTargetGround: boolean
  - DamageType: "Normal" | "Fire" | "Ice" | "Magic"

Upgrade Path (nested config):
  - Level: number
  - StatBoosts: { Damage = 1.2, Range = 1.1, FireRate = 1.15 }
  - Cost: number
  - VisualChanges: string (model swap or material change)

Events:
  - Fired(target, projectile)
  - TargetAcquired(enemy)
  - TargetLost(enemy)
  - Upgraded(newLevel)
```

**Core Loop:**
```lua
while enabled do
    local target = findTarget(priority, range)
    if target then
        if canFire() then
            fire(target)
            cooldown = 1 / fireRate
        end
    end
    task.wait(0.1) -- tick rate
end
```

**Targeting Algorithm:**
```lua
function findTarget(priority, range)
    local enemies = getEnemiesInRange(range)
    if #enemies == 0 then return nil end

    if priority == "First" then
        -- Furthest along path (highest waypoint index)
        table.sort(enemies, function(a, b)
            return a:GetAttribute("PathProgress") > b:GetAttribute("PathProgress")
        end)
    elseif priority == "Strongest" then
        table.sort(enemies, function(a, b)
            return a:GetAttribute("Health") > b:GetAttribute("Health")
        end)
    -- etc.
    end

    return enemies[1]
end
```

---

### 4. PlacementValidator (NEW)

**Purpose:** Client-side placement preview + server validation for any placeable object

```
Features:
  - Grid snapping (configurable grid size)
  - Node-based placement (predefined valid spots)
  - Range indicator preview (circle decal/part)
  - Collision/overlap detection
  - Cost validation before placement
  - Ghost preview (transparent model follows mouse)

Client Flow:
  1. Player selects tower from UI
  2. Ghost preview follows mouse
  3. Valid spots highlight green, invalid red
  4. Click to request placement
  5. Server validates and spawns

Server Validation:
  - Check currency
  - Check position validity
  - Check no overlap with existing towers
  - Deduct currency
  - Spawn object
  - Fire PlacementComplete event
```

**Reusability:** Tower defense, tycoons, building games, furniture placement, base builders

---

### 5. Projectile (NEW)

**Purpose:** Visual projectiles + hit detection

```
Types:
  - Hitscan: Instant damage, raycast
  - Projectile: Travel time, physical or interpolated
  - AOE: Splash damage on impact
  - Beam: Continuous damage while active

Config:
  - Speed: number (studs/sec, for projectile type)
  - VisualModel: string (template reference)
  - TrailEffect: string (optional)
  - ImpactEffect: string (optional)
  - Piercing: number (0 = single target, N = pierce N enemies)

Optimizations:
  - Object pooling for frequent projectiles
  - Client-side visuals, server-side hit detection
  - Hybrid: client predicts, server confirms
```

**Reusability:** Shooters, magic games, tower defense, any ranged combat

---

### 6. Currency (NEW)

**Purpose:** Track gold/gems per player

```
Data Structure (per player):
  - Gold: number (earned from kills, spent on towers)
  - Gems: number (premium/rare currency)
  - StartingGold: number (configurable per map)

Events:
  - CurrencyChanged(player, currencyType, newAmount, delta)
  - PurchaseAttempted(player, item, cost, success)

Integration Points:
  - HealthSystem.Died → Award currency
  - PlacementValidator → Deduct currency
  - UpgradePath → Deduct currency
  - Gacha → Deduct premium currency
```

**Reusability:** Any game with economy - tycoons, simulators, RPGs, tower defense

---

### 7. UpgradePath (NEW)

**Purpose:** Generic stat progression trees for any upgradeable entity

```
Data Structure:
  UpgradeTrees = {
    ["BasicTower"] = {
      { Cost = 100, Damage = 1.2, Range = 1.0 },
      { Cost = 250, Damage = 1.5, Range = 1.1 },
      { Cost = 500, Damage = 2.0, Range = 1.2, Special = "Piercing" },
    }
  }

UI Flow:
  1. Player selects entity
  2. Show current stats + next upgrade preview
  3. Show cost and "Upgrade" button
  4. Validate currency, apply upgrade, update visuals
```

**Reusability:** Tower defense upgrades, RPG skills, weapon upgrades, pet leveling

---

### 8. Gacha (NEW - Optional)

**Purpose:** Unit summoning with rarity tiers (modern TD monetization)

```
Rarity Tiers:
  - Common (60%)
  - Uncommon (25%)
  - Rare (10%)
  - Epic (4%)
  - Legendary (0.9%)
  - Mythic (0.1%)

Features:
  - Single summon vs multi-summon (10x)
  - Pity system (guaranteed rare after N pulls)
  - Banner system (rate-up for specific units)
  - Inventory management
  - Duplicate handling (convert to upgrade currency)
```

**Reusability:** Pet simulators, anime games, loot boxes, card games, any collection mechanic

---

## Component Composition Example

A Tower Defense game would compose these modules:

```
Existing v1 Components:
  - WaveController → controls enemy spawn waves
  - Dropper → individual spawn points
  - ArrayPlacer → pre-defined tower positions
  - Router → message passing between components
  - Visibility → show/hide effects

New Components (from this doc):
  - PathFollower → enemy navigation
  - HealthSystem → enemy HP and damage
  - Targeting → tower target acquisition
  - Turret → tower attack loop
  - Projectile → bullets/effects
  - PlacementValidator → tower placement rules
  - Currency → gold/gems economy
  - UpgradePath → tower upgrades
```

Each component is standalone and reusable in other game types.

---

## Build Priority

### Phase 1: Core Combat
1. **PathFollower** - Entity navigation along waypoints
2. **HealthSystem** - Universal damage/healing system
3. **Targeting** - Range-based entity acquisition
4. **Turret** - Autonomous attack loop

### Phase 2: Player Interaction
5. **Projectile** - Visual effects + hit detection
6. **PlacementValidator** - Object placement rules
7. **Currency** - Player economy tracking

### Phase 3: Progression
8. **UpgradePath** - Stat progression trees
9. **Gacha** - Weighted random summoning (optional)

---

## Reference Sources

- [Roblox DevForum - Tower Defense Guide](https://devforum.roblox.com/t/an-in-depth-guide-to-a-tower-defense-game-part-1/3019857)
- [Tower Defense Simulator Wiki](https://tds.fandom.com/wiki/How_to_Play)
- [Sportskeeda - Top 5 TD Games](https://www.sportskeeda.com/roblox-news/top-5-tower-defense-games-roblox)
- [Try Hard Guides - Popular Roblox Genres](https://tryhardguides.com/the-most-popular-roblox-game-genres/)
