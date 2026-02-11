> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# Session Log: 2026-01-14 - Turret System Design

## Overview

Designed a multi-component turret system after reverting an initial implementation that was built without proper discussion. Established new procedure requiring design discussion before implementing new components.

---

## 1. Initial Projectile Implementation (Reverted)

### What Happened

Claude implemented a Projectile component based on an existing plan file without discussing the design with the user first. The implementation used code-controlled movement (Heartbeat position updates) with features like:
- Linear, ballistic, homing movement types
- Touch/raycast collision detection
- OnHit behaviors (despawn, pierce, bounce, explode)

### Problem

This didn't match the user's vision at all. The user wanted:
- **Physics-based** projectiles (Roblox physics handles flight after launch)
- **Separate components** for targeting, aiming, and firing
- **Geometry-driven** direction (surface orientation, not configured Vector3)

### Resolution

- Deleted `Projectile.lua` and `Projectile_Tests.lua`
- Reverted all exports and documentation
- Updated `PROCEDURES.md` with new policy requiring design discussion

---

## 2. Procedures Update

Added to Section 12.5 "When to Ask vs Proceed":

```markdown
**CRITICAL: New Components Require Discussion**

When implementing a new component (even if a plan file exists):
1. Walk through the proposed signals (In/Out/Err)
2. Explain the key behaviors and attributes
3. Discuss implementation approach (what internal modules, patterns)
4. Get confirmation before writing code

A plan file is a starting point, not authorization to implement.
```

---

## 3. Turret System Design

### User's Vision

Instead of a monolithic projectile component, the user wanted composable pieces:

1. **Surface emits ray** → detects target → gets coordinates
2. **Spawns projectile** → physics launches toward coordinates
3. **No target lock** → snapshot position at acquisition, physics takes over

This led to decomposition into multiple components.

### Component Architecture

```
Turret (Orchestrator wiring)
├── Swivel (yaw)
│   └── Swivel (pitch)
│       ├── Targeter (raycast scanner)
│       └── Launcher (muzzle)
```

### Swivel

Single-axis rotation with two modes:
- **Continuous**: Rotates while signal active (like a continuous servo) - introduces play
- **Stepped**: Fixed increment per signal (like a stepper motor) - precise positioning

Key attributes: `Axis`, `Mode`, `Speed`, `StepSize`, `MinAngle`, `MaxAngle`

### Targeter

Raycast-based detection with configurable beam modes:
- **Pinpoint**: Single ray
- **Cylinder**: Parallel rays in radius
- **Cone**: Spreading rays from origin

Tracking modes:
- **Once**: Emit on first detection
- **Lock**: Continuous `tracking` signal while targets in beam

Returns ALL targets sorted by proximity (closest first). Receiver decides which to focus on.

Uses standard filter schema for target filtering.

### Launcher

Physics-based projectile firing:
- **Mode A**: Receives target coordinates, aims and fires
- **Mode B**: Blind fire in muzzle direction

Launch methods:
- **Impulse**: VectorForce/AssemblyLinearVelocity
- **Spring**: SpringConstraint release

Uses SpawnerCore for projectile templates. After launch, physics takes over completely.

---

## 4. Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Direction source | Surface geometry (LookVector) | Rotate the part, direction follows |
| Swivel modes | Both continuous and stepped | Different precision needs |
| Targeter beam | Support pinpoint, cylinder, cone | Flexibility for different use cases |
| Target signal | All targets in one signal, sorted | Let receiver decide focus |
| Tracking | Support once and lock modes | Fire-and-forget vs target lock |
| Projectile physics | Roblox physics after launch | Simpler, more realistic |

---

## 5. Deferred Decisions

1. **Projectile impact detection** - Will be handled by projectile, target, or collision manager. TBD when we implement.
2. **TurretController** - May be Orchestrator wiring or dedicated node for complex aim logic.
3. **Visual beam rendering** - Optional debug/effects feature for Targeter.

---

## 6. Files Changed

### Deleted
- `Components/Projectile.lua` (code-controlled movement - wrong approach)
- `Tests/Projectile_Tests.lua`
- `docs/PROJECTILE_SYSTEM_PLAN.md` (obsolete plan)

### Created
- `docs/TURRET_SYSTEM_PLAN.md` (new multi-component design)
- `Logs/2026-01-14_turret-system-design.md` (this file)

### Modified
- `Logs/PROCEDURES.md` - Added "New Components Require Discussion" policy
- `Components/init.lua` - Removed Projectile export
- `Tests/init.lua` - Removed Projectile_Tests export
- `docs/ARCHITECTURE.md` - Removed Projectile from component list
- `docs/TEST_COVERAGE.md` - Removed Projectile tests (back to 140 total)

---

## 7. Next Steps

Implementation order for next session:

1. **Swivel** - Foundation component, others mount to it
2. **Targeter** - Detection logic with filter integration
3. **Launcher** - Physics firing with SpawnerCore integration

Each component requires:
- Component implementation
- Test suite
- Export updates
- Documentation updates

**Remember**: Discuss implementation approach before writing code.

---

## 8. Commits This Session

1. `56c204b` - feat(v2): Add Projectile component (later reverted)
2. `3b22d28` - revert(v2): Remove Projectile component - redesigning as multi-component system
3. (pending) - docs(v2): Add Turret System design plan
