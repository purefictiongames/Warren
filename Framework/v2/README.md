# LibPureFiction Framework v2

Signal-driven game framework for Roblox. Nodes communicate via `Out:Fire()` -> wiring -> `In.onHandler()` pattern.

**Repository:** https://github.com/purefictiongames/LibPureFiction

## Quick Reference

### Core Architecture Rule
**NEVER call internal methods directly to drive node behavior.** Always use signals:

```lua
-- WRONG: Direct method call
node:_internalMethod()

-- CORRECT: Signal-driven
controller.Out:Fire("commandSignal", { data })
-- Routed via wiring to:
node.In.onCommandSignal(node, data)
```

### Node Structure
```lua
local MyNode = Node.extend({
    name = "MyNode",
    domain = "server",  -- or "client" or "shared"

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onSomeSignal = function(self, data) end,
    },

    Out = {
        resultSignal = {},
    },
})
```

---

## File Index

### Core System
| File | Description |
|------|-------------|
| [src/Lib/Node.lua](src/Lib/Node.lua) | Base node class with signal system |
| [src/Lib/System.lua](src/Lib/System.lua) | IPC, cross-domain communication, node registry |
| [src/Lib/init.lua](src/Lib/init.lua) | Library entry point |
| [src/Bootstrap.server.lua](src/Bootstrap.server.lua) | Server-side initialization |
| [src/Bootstrap.client.lua](src/Bootstrap.client.lua) | Client-side initialization |

### Components
| File | Description |
|------|-------------|
| [src/Lib/Components/init.lua](src/Lib/Components/init.lua) | Component index |
| [src/Lib/Components/Dropper.lua](src/Lib/Components/Dropper.lua) | Spawns entities on interval or signal |
| [src/Lib/Components/PathFollower.lua](src/Lib/Components/PathFollower.lua) | Moves entities along waypoint paths |
| [src/Lib/Components/PathedConveyor.lua](src/Lib/Components/PathedConveyor.lua) | Conveyor belt with path following |
| [src/Lib/Components/Checkpoint.lua](src/Lib/Components/Checkpoint.lua) | Waypoint checkpoints for paths |
| [src/Lib/Components/Swivel.lua](src/Lib/Components/Swivel.lua) | Physics-based rotation (HingeConstraint servos) |
| [src/Lib/Components/Targeter.lua](src/Lib/Components/Targeter.lua) | Target acquisition and tracking |
| [src/Lib/Components/Launcher.lua](src/Lib/Components/Launcher.lua) | Projectile launching |
| [src/Lib/Components/Hatcher.lua](src/Lib/Components/Hatcher.lua) | Entity lifecycle management |
| [src/Lib/Components/Zone.lua](src/Lib/Components/Zone.lua) | Spatial zone detection |
| [src/Lib/Components/NodePool.lua](src/Lib/Components/NodePool.lua) | Object pooling for nodes |
| [src/Lib/Components/Orchestrator.lua](src/Lib/Components/Orchestrator.lua) | Coordinates multi-node sequences |
| [src/Lib/Components/DamageCalculator.lua](src/Lib/Components/DamageCalculator.lua) | Damage calculation with modifiers |
| [src/Lib/Components/EntityStats.lua](src/Lib/Components/EntityStats.lua) | Health, armor, resistance tracking |
| [src/Lib/Components/StatusEffect.lua](src/Lib/Components/StatusEffect.lua) | Buff/debuff system |

### Internal Utilities
| File | Description |
|------|-------------|
| [src/Lib/Internal/init.lua](src/Lib/Internal/init.lua) | Internal utilities index |
| [src/Lib/Internal/SpawnerCore.lua](src/Lib/Internal/SpawnerCore.lua) | Template-based entity spawning |
| [src/Lib/Internal/PathFollowerCore.lua](src/Lib/Internal/PathFollowerCore.lua) | Core path following logic |
| [src/Lib/Internal/EntityUtils.lua](src/Lib/Internal/EntityUtils.lua) | Entity helper functions |
| [src/Lib/Internal/SchemaValidator.lua](src/Lib/Internal/SchemaValidator.lua) | Configuration validation |
| [src/Lib/Internal/AttributeSet.lua](src/Lib/Internal/AttributeSet.lua) | Attribute management utility |

### Demos
| File | Description |
|------|-------------|
| [src/Lib/Demos/init.lua](src/Lib/Demos/init.lua) | Demo index |
| [src/Lib/Demos/Conveyor_Demo.lua](src/Lib/Demos/Conveyor_Demo.lua) | Dropper -> PathFollower -> despawn circuit |
| [src/Lib/Demos/Turret_Demo.lua](src/Lib/Demos/Turret_Demo.lua) | Client-controlled turret with cross-domain IPC |
| [src/Lib/Demos/Targeter_Demo.lua](src/Lib/Demos/Targeter_Demo.lua) | Signal-based target acquisition |
| [src/Lib/Demos/Swivel_Demo.lua](src/Lib/Demos/Swivel_Demo.lua) | Physics-based rotation demo |
| [src/Lib/Demos/Launcher_Demo.lua](src/Lib/Demos/Launcher_Demo.lua) | Projectile launching demo |
| [src/Lib/Demos/ShootingGallery_Demo.lua](src/Lib/Demos/ShootingGallery_Demo.lua) | **SHELVED** - Turret + targets (targets not spawning) |
| [src/Lib/Demos/Combat_Demo.lua](src/Lib/Demos/Combat_Demo.lua) | Combat system demo |

### Tests
| File | Description |
|------|-------------|
| [src/Lib/Tests/init.lua](src/Lib/Tests/init.lua) | Test runner |
| [src/Lib/Tests/IPC_Node_Tests.lua](src/Lib/Tests/IPC_Node_Tests.lua) | Cross-domain IPC tests |
| [src/Lib/Tests/Dropper_Tests.lua](src/Lib/Tests/Dropper_Tests.lua) | Dropper component tests |
| [src/Lib/Tests/Swivel_Tests.lua](src/Lib/Tests/Swivel_Tests.lua) | Swivel component tests |
| [src/Lib/Tests/Targeter_Tests.lua](src/Lib/Tests/Targeter_Tests.lua) | Targeter component tests |
| [src/Lib/Tests/Launcher_Tests.lua](src/Lib/Tests/Launcher_Tests.lua) | Launcher component tests |
| [src/Lib/Tests/PathFollower_Tests.lua](src/Lib/Tests/PathedConveyor_Tests.lua) | PathFollower tests |
| [src/Lib/Tests/Checkpoint_Tests.lua](src/Lib/Tests/Checkpoint_Tests.lua) | Checkpoint tests |
| [src/Lib/Tests/Zone_Tests.lua](src/Lib/Tests/Zone_Tests.lua) | Zone tests |
| [src/Lib/Tests/Hatcher_Tests.lua](src/Lib/Tests/Hatcher_Tests.lua) | Hatcher tests |
| [src/Lib/Tests/Orchestrator_Tests.lua](src/Lib/Tests/Orchestrator_Tests.lua) | Orchestrator tests |
| [src/Lib/Tests/SchemaValidator_Tests.lua](src/Lib/Tests/SchemaValidator_Tests.lua) | Schema validation tests |
| [src/Lib/Tests/AttributeSet_Tests.lua](src/Lib/Tests/AttributeSet_Tests.lua) | AttributeSet tests |
| [src/Lib/Tests/ConveyorBelt_Tests.lua](src/Lib/Tests/ConveyorBelt_Tests.lua) | Conveyor belt tests |

---

## Architecture Documentation

| File | Description |
|------|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Main architecture overview |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Detailed architecture docs |
| [docs/IPC_NODE_SPEC.md](docs/IPC_NODE_SPEC.md) | Inter-process communication specification |
| [docs/ORCHESTRATOR_DESIGN.md](docs/ORCHESTRATOR_DESIGN.md) | Multi-node coordination design |
| [docs/TURRET_SYSTEM_PLAN.md](docs/TURRET_SYSTEM_PLAN.md) | Turret system implementation plan |
| [docs/TEST_COVERAGE.md](docs/TEST_COVERAGE.md) | Test coverage documentation |

## TODO / Active Work

| File | Description |
|------|-------------|
| [docs/TODO-shooting-gallery.md](docs/TODO-shooting-gallery.md) | ShootingGallery resume point (shelved) |
| [docs/TODO-closure-privacy-refactor.md](docs/TODO-closure-privacy-refactor.md) | **MAJOR** - Replace _ prefix with closures |
| [docs/TODO-signal-architecture-refactor.md](docs/TODO-signal-architecture-refactor.md) | Signal architecture improvements |
| [docs/TODO-input-capture-enhancements.md](docs/TODO-input-capture-enhancements.md) | Input system enhancements |

## Debug Sessions / Logs

| File | Description |
|------|-------------|
| [docs/debug-sessions/2026-01-14-turret-signal-architecture.md](docs/debug-sessions/2026-01-14-turret-signal-architecture.md) | Turret debugging session |
| [Logs/PROJECT_JOURNAL.md](Logs/PROJECT_JOURNAL.md) | Project development journal |
| [Logs/COMPONENT_REGISTRY.md](Logs/COMPONENT_REGISTRY.md) | Component registry and status |
| [Logs/SYSTEM_REFERENCE.md](Logs/SYSTEM_REFERENCE.md) | System API reference |
| [Logs/PROCEDURES.md](Logs/PROCEDURES.md) | Development procedures |
| [Logs/TOWER_DEFENSE_COMPONENTS.md](Logs/TOWER_DEFENSE_COMPONENTS.md) | Tower defense component designs |
| [Logs/STYLING_SYSTEM.md](Logs/STYLING_SYSTEM.md) | UI styling system docs |

## Game Configuration

| File | Description |
|------|-------------|
| [src/Game/init.lua](src/Game/init.lua) | Game-specific configuration |
| [src/ReplicatedFirst/Config.lua](src/ReplicatedFirst/Config.lua) | Client-first configuration |

---

## Key Patterns

### Signal Wiring (Manual - for demos)
```lua
-- Sender.Out -> Receiver.In
sender.Out = {
    Fire = function(self, signal, data)
        if signal == "mySignal" then
            receiver.In.onMySignal(receiver, data)
        end
    end,
}
```

### Cross-Domain IPC (Client <-> Server)
```lua
-- Client fires to server
System.fireCrossDomain("MyServerNode", "onClientInput", { key = "W" })

-- Server receives in node's In handler
In = {
    onClientInput = function(self, data, player)
        -- data.key == "W", player is the firing player
    end,
}
```

### Dropper -> PathFollower Circuit
```lua
-- Dropper spawns entity, fires "spawned"
-- Wiring routes to PathFollower.In.onEntityEntered
-- PathFollower moves entity along path, fires "completed"
-- Wiring routes back to Dropper.In.onReturn for pooling
```

---

## Current State (2026-01-14)

**Working:**
- Core node system with signals
- Cross-domain IPC (client <-> server)
- Turret demo (client input -> server physics)
- Swivel, Targeter, Launcher components
- Conveyor demo (Dropper -> PathFollower circuit)

**Shelved:**
- ShootingGallery target spawning (signal chain not triggering)

**Planned:**
- Closure-based privacy refactor (replace _ prefix convention)
- Standalone TargetRow demo for debugging
