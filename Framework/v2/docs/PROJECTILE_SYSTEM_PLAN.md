# Projectile System - Implementation Plan

> Status: IN PROGRESS
> Created: 2026-01-14

## Overview

Comprehensive projectile system for turrets, catapults, player weapons, and environmental hazards. Supports multiple movement types, targeting modes, fire patterns, and impact behaviors.

---

## Phase 1: Core Components

| # | Component | Description | Dependencies | Status |
|---|-----------|-------------|--------------|--------|
| 1 | **Projectile** | Base projectile with linear movement, collision, lifespan | SpawnerCore, Zone | **Implemented** |
| 2 | **Turret** | Launcher with targeting, cooldown, fire patterns | Projectile, NodePool | Pending |

---

## Phase 2: Movement Types

| # | Feature | Description | Adds To | Status |
|---|---------|-------------|---------|--------|
| 3 | **Ballistic trajectory** | Arc/parabola with gravity | Projectile | Pending |
| 4 | **Homing** | Track and follow target | Projectile | Pending |
| 5 | **Raycast/Hitscan** | Instant hit, no travel time | Turret | Pending |

---

## Phase 3: Targeting Modes

| # | Feature | Description | Adds To | Status |
|---|---------|-------------|---------|--------|
| 6 | **Auto-target** | Find nearest enemy in range | Turret | Pending |
| 7 | **Predictive aim** | Lead target based on velocity | Turret | Pending |
| 8 | **Manual aim** | Player-controlled direction | Turret | Pending |

---

## Phase 4: Fire Patterns

| # | Feature | Description | Adds To | Status |
|---|---------|-------------|---------|--------|
| 9 | **Burst fire** | N shots with delay between | Turret | Pending |
| 10 | **Spread/Shotgun** | Multiple projectiles in cone | Turret | Pending |
| 11 | **Beam/Continuous** | Sustained damage stream | Turret (new mode) | Pending |

---

## Phase 5: Impact Behaviors

| # | Feature | Description | Adds To | Status |
|---|---------|-------------|---------|--------|
| 12 | **Explosion/AoE** | Damage all in radius on impact | Projectile | Pending |
| 13 | **Pierce** | Continue through targets | Projectile | Pending |
| 14 | **Bounce/Ricochet** | Reflect off surfaces | Projectile | Pending |

---

## Phase 6: Advanced

| # | Feature | Description | Adds To | Status |
|---|---------|-------------|---------|--------|
| 15 | **Projectile pooling** | Reuse via NodePool integration | Projectile + Turret | Pending |
| 16 | **Ammo/Reload** | Limited shots, reload mechanic | Turret | Pending |
| 17 | **Charge shot** | Hold to increase power/size | Turret | Pending |

---

## Component Specifications

### Projectile Component

**Signals:**

```
IN (receives):
    onLaunch({ origin: Vector3, direction: Vector3, speed?: number, target?: Instance, damage?: number })
        - Launch the projectile from origin in direction
        - Optional target for homing projectiles
        - Optional damage value to pass through on hit

    onConfigure({ speed?, lifespan?, maxDistance?, collisionFilter?, movementType?, onHit? })
        - Configure projectile behavior
        - movementType: "linear" | "ballistic" | "homing"
        - onHit: "despawn" | "pierce" | "bounce" | "explode"

    onAbort()
        - Cancel the projectile mid-flight

OUT (emits):
    launched({ origin, direction, speed })
        - Fired when projectile begins flight

    hit({ target: Instance, position: Vector3, normal: Vector3, damage?: number })
        - Fired when projectile hits something
        - target is the hit Instance
        - normal is the surface normal at impact

    expired({ position: Vector3, traveled: number, reason: "lifespan" | "maxDistance" })
        - Fired when projectile expires without hitting

Err (detour):
    noTarget({ reason: "lost" | "destroyed" })
        - Homing projectile lost its target
```

**Attributes:**

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| Speed | number | 50 | Units per second |
| Lifespan | number | 5 | Max seconds before expire |
| MaxDistance | number | 500 | Max studs before expire |
| MovementType | string | "linear" | "linear", "ballistic", "homing" |
| CollisionMode | string | "touch" | "touch", "raycast", "none" |
| OnHit | string | "despawn" | "despawn", "pierce", "bounce", "explode" |
| Damage | number | 10 | Damage value passed to hit signal |
| Gravity | number | 196.2 | For ballistic trajectory |
| HomingStrength | number | 5 | Turn rate for homing |
| PierceCount | number | 1 | How many targets to pierce |
| BounceCount | number | 1 | How many bounces allowed |
| ExplosionRadius | number | 10 | AoE radius for explode mode |

---

### Turret Component

**Signals:**

```
IN (receives):
    onConfigure({ fireRate?, range?, targetFilter?, projectileConfig?, ... })
        - Configure turret behavior

    onEnable() / onDisable()
        - Start/stop auto-firing

    onFire({ direction?: Vector3, target?: Instance })
        - Manual fire command
        - If no direction/target, uses current aim

    onSetTarget({ target: Instance })
        - Manually set current target

    onAim({ direction: Vector3 })
        - Set aim direction (for manual mode)

OUT (emits):
    fired({ projectileId, target?, direction })
        - Fired when turret shoots

    targetAcquired({ target, distance })
        - Fired when auto-target finds enemy

    targetLost({ target, reason })
        - Fired when target leaves range or dies

    reloading({ duration })
        - Fired when reload starts

    reloaded()
        - Fired when reload completes

Err (detour):
    noTarget({ reason })
        - No valid target in range

    onCooldown({ remaining })
        - Fire attempted during cooldown
```

**Attributes:**

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| FireRate | number | 1 | Shots per second |
| Range | number | 100 | Detection/firing range |
| TargetingMode | string | "auto" | "auto", "predictive", "manual", "fixed" |
| FirePattern | string | "single" | "single", "burst", "spread", "beam" |
| BurstCount | number | 3 | Shots per burst |
| BurstDelay | number | 0.1 | Seconds between burst shots |
| SpreadAngle | number | 15 | Degrees for spread pattern |
| SpreadCount | number | 5 | Projectiles per spread |
| RotationSpeed | number | 180 | Degrees per second for aiming |
| Ammo | number | -1 | -1 for infinite |
| ReloadTime | number | 2 | Seconds to reload |

---

## Integration Examples

### Tower Defense Turret

```lua
local orch = Orchestrator:new({ id = "TowerDefenseOrch" })
orch.In.onConfigure(orch, {
    nodes = {
        Turret1 = {
            class = "Turret",
            config = {
                targetingMode = "auto",
                fireRate = 2,
                range = 50,
                targetFilter = { class = "Enemy" },
            }
        },
    },
    wiring = {
        { from = "Turret1", signal = "fired", to = "GameManager", handler = "onTurretFired" },
    },
})
```

### Catapult (Ballistic)

```lua
local catapult = Turret:new({ id = "Catapult1" })
catapult.In.onConfigure(catapult, {
    firePattern = "single",
    targetingMode = "manual",
    projectileConfig = {
        movementType = "ballistic",
        speed = 30,
        gravity = 196.2,
        onHit = "explode",
        explosionRadius = 15,
    },
})
```

### Player Weapon

```lua
local weapon = Turret:new({ id = "PlayerRifle" })
weapon.In.onConfigure(weapon, {
    firePattern = "single",
    targetingMode = "manual",
    fireRate = 5,
    ammo = 30,
    reloadTime = 1.5,
    projectileConfig = {
        movementType = "linear",
        speed = 200,
        damage = 25,
    },
})

-- Wire to player input
playerInput.onFire:Connect(function(aimDirection)
    weapon.In.onFire(weapon, { direction = aimDirection })
end)
```

---

## Notes

- Projectile uses RunService.Heartbeat for movement updates
- Collision detection via TouchedEvent or workspace:Raycast()
- Turret rotation via CFrame lerp or TweenService
- Consider using NodePool for high-volume projectile scenarios
- HealthSystem integration planned for damage application
