# Session Log: PathFollower Component Implementation

**Date:** 2026-01-13
**Focus:** Building the first v2 component library entry - PathFollower

---

## Session Summary

This session established the component library architecture for v2 and implemented the PathFollower navigation component with collision handling.

## Key Decisions Made

### 1. Component Library Strategy

Researched popular Roblox game genres to identify reusable components:
- Tower Defense, Simulator, Obby, Horror, Tycoon, Roleplay, Fighting, RPG

Created `COMPONENT_REGISTRY.md` documenting 34 components across 8 categories with:
- Attribute specifications
- Event schemas
- Usage examples per genre
- Build priority tiers

### 2. Components Folder Structure

Established new folder pattern:
```
Framework/v2/src/Lib/
├── Components/
│   ├── init.lua          # Exports all components
│   └── PathFollower.lua  # First component
```

Access pattern: `Lib.Components.PathFollower`

### 3. PathFollower Architecture

**Signal-driven design:**
- Waits for TWO signals before starting: `onControl` (entity) + `onWaypoints` (targets)
- All control via signals: pause, resume, speed changes
- One-way trips only (loop = send new waypoints on complete)

**Movement support:**
- Humanoid-based: Uses `Humanoid:MoveTo()`
- Non-Humanoid: Uses TweenService with auto-anchoring

### 4. Node Locking System

Added system-level support for blocking signal waits:
- `Node:waitForSignal(signalName, timeout)` - blocks until signal received
- `Node:isLocked()` - check if node is waiting
- IPC queues messages to locked nodes, replays on unlock

### 5. Err Channel Reframe

Reframed the Err channel as a **detour/exception channel** rather than just errors:
- Used for non-linear flow (collisions, timeouts, interruptions)
- Similar to try/catch exception patterns
- Can be wired to different handlers per mode

### 6. Collision Handling

Implemented comprehensive collision response system:

| Attribute | Options | Description |
|-----------|---------|-------------|
| CollisionMode | `ignore`, `physics` | How to handle physics on collision |
| OnInterrupt | `stop`, `pause_and_resume`, `restart` | What to do when interrupted |
| ResumeDelay | number | Seconds before resume/restart |

---

## Files Created

| File | Purpose |
|------|---------|
| `Lib/Components/init.lua` | Component library index |
| `Lib/Components/PathFollower.lua` | Navigation component (~500 lines) |
| `Logs/COMPONENT_REGISTRY.md` | Master component catalog |
| `Logs/TOWER_DEFENSE_COMPONENTS.md` | TD-specific analysis |

## Files Modified

| File | Changes |
|------|---------|
| `Lib/Node.lua` | Added `waitForSignal()`, `isLocked()`, `_flushMessageQueue()` |
| `Lib/System.lua` | Added lock check to IPC dispatch |
| `Lib/init.lua` | Added Components export |
| `Lib/Tests/IPC_Node_Tests.lua` | Added 15+ tests for locking and PathFollower |

---

## PathFollower API Reference

### Attributes

```lua
Speed: number (default 16)           -- Studs per second
WaitForAck: boolean (default false)  -- Pause at waypoints for ack
AckTimeout: number (default 5)       -- Seconds before ack timeout
CollisionMode: string (default "ignore")  -- "ignore" | "physics"
OnInterrupt: string (default "stop")      -- "stop" | "pause_and_resume" | "restart"
ResumeDelay: number (default 1)           -- Seconds before resume
```

### Input Signals (In)

| Signal | Payload | Description |
|--------|---------|-------------|
| `onControl` | `{ entity: Model, entityId?: string }` | Assign entity to control |
| `onWaypoints` | `{ targets: Part[] }` | Provide waypoint list |
| `onPause` | `{}` | Pause navigation |
| `onResume` | `{}` | Resume navigation |
| `onSetSpeed` | `{ speed: number }` | Change speed mid-navigation |
| `onAck` | `{}` | Acknowledgment for sync mode |

### Output Signals (Out)

| Signal | Payload | Description |
|--------|---------|-------------|
| `waypointReached` | `{ waypoint, index, entityId }` | Fired at each waypoint |
| `pathComplete` | `{ entityId }` | Fired when path finished |

### Detour Signals (Err)

| Reason | When |
|--------|------|
| `collision` | Collision detected during navigation |
| `collision_resumed` | After pause_and_resume delay |
| `collision_restart` | Before restarting from waypoint 1 |
| `ack_timeout` | WaitForAck timed out |

---

## Testing

Run from Studio Command Bar:
```lua
require(game.ReplicatedStorage.Lib.Tests.IPC_Node_Tests).runGroup("PathFollower Integration")
```

Integration tests create actual parts in workspace and verify navigation.

---

## Next Steps

1. **Projectile component** - Next visual component to implement
2. **Test collision handling** - Add integration tests for collision modes
3. **Additional components** - HealthSystem, Currency, Checkpoint per registry

---

## Architecture Notes

### Signal Flow Patterns

**Normal flow:**
```
In → process → Out
```

**Detour flow (exception handling):**
```
In → process → [unexpected condition] → Err → different handler
```

### Component Composition

Components are designed to be composed via IPC wiring:
```
Spawner.Out → PathFollower.In (onControl)
WaypointBuilder.Out → PathFollower.In (onWaypoints)
PathFollower.Out → NextBehavior.In (pathComplete)
PathFollower.Err → CollisionHandler.In (collision)
```

### Domain Considerations

PathFollower uses `domain = "shared"` for Command Bar testing.
Production components that modify physics should use `domain = "server"`.
