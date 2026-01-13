# LibPureFiction Framework v2 - Architecture

## Overview

LibPureFiction is a Roblox game framework designed for developer ergonomics. It follows an **Arduino-like model** where games are composed of modular components wired together through a unified messaging bus.

## Design Principles

1. **Single ModuleScript per system** - All subsystem code lives in nested modules within one file
2. **No code runs on load** - Bootstrap script controls execution order
3. **Explicit registration** - Declarative manifest defines components and wiring (no auto-discovery)
4. **Closure-protected internals** - Public API surface, private implementation via local functions
5. **Singleton/Factory pattern** - Each system module acts as singleton or factory
6. **Minimal dependencies** - Systems are isolated, communicate via IPC

## Package Structure

```
LibPureFiction/
├── src/
│   ├── Lib/
│   │   ├── init.lua              <- Main entry (exports System, Node, Components)
│   │   ├── System.lua            <- Core subsystems (Debug, IPC, Asset, etc.)
│   │   ├── Node.lua              <- Base class for all game components
│   │   ├── Components/           <- Reusable component library
│   │   │   ├── init.lua
│   │   │   └── PathFollower.lua  <- Navigation component
│   │   └── Tests/
│   │       └── IPC_Node_Tests.lua
│   ├── Game/                     <- Game-specific nodes
│   │   └── init.lua
│   └── Bootstrap/
│       ├── Bootstrap.server.lua
│       └── Bootstrap.client.lua
├── docs/
│   ├── ARCHITECTURE.md           <- This file
│   └── IPC_NODE_SPEC.md          <- Detailed node/IPC specification
└── Logs/
    └── COMPONENT_REGISTRY.md     <- Master component catalog
```

Games using this library (separate repos):
```
SomeGame/
├── src/
│   ├── Manifest.lua         <- Structure + wiring
│   └── Style.lua            <- Presentation
├── wally.toml               <- Depends on LibPureFiction
└── default.project.json
```

## The Arduino Model

Each asset module is like a sensor/motor with standardized I/O:

```
┌─────────────────────────────────────────────────────────────┐
│                      ORCHESTRATOR                           │
│                    (main logic board)                       │
└─────────────────┬───────────────────┬───────────────────────┘
                  │                   │
        ┌─────────▼─────────┐ ┌───────▼─────────┐
        │   WaveController  │ │   Scoreboard    │  <- Asset Modules
        │  [In] [Out] [Dbg] │ │ [In] [Out] [Dbg]│     (ICUs)
        └─────────┬─────────┘ └───────┬─────────┘
                  │                   │
    ┌─────────────▼───────────────────▼─────────────┐
    │                  IPC BUS                       │  <- Routes signals
    │          (context-aware routing)               │     by runtime state
    └──┬──────────┬──────────┬──────────┬───────────┘
       │          │          │          │
   ┌───▼───┐  ┌───▼───┐  ┌───▼───┐  ┌───▼───┐
   │Dropper│  │Dropper│  │Dropper│  │Dropper│  <- Asset Modules
   │  [I/O]│  │  [I/O]│  │  [I/O]│  │  [I/O]│     (sensors/motors)
   └───────┘  └───────┘  └───────┘  └───────┘
```

### Module Channels (Pin Model)

Every node has 4 standardized channels (pins):

| Pin | Direction | Purpose |
|-----|-----------|---------|
| **Sys.In** | System → Node | Lifecycle signals (init, start, stop, modeChange) |
| **In** | Node → Node | Game signals from other nodes via wiring |
| **Out** | Node → Node | Outbound signals to other nodes via wiring |
| **Err** | Node → System/Handlers | Detour/exception signals for non-linear flow |

#### The Err Channel (Detour Pattern)

The Err channel is NOT just for errors - it's a **detour/exception channel** for handling non-linear flow:

```
Normal flow:    In → process → Out
Detour flow:    In → process → [unexpected condition] → Err → different handler
```

Use cases:
- Collision during navigation → Err with collision info
- Timeout waiting for acknowledgment → Err with timeout info
- Resource unavailable → Err with fallback options

This is similar to try/catch exception patterns - routing variant conditions without nested if/else logic. Err signals can be wired to different handlers per mode.

## Two Declarative Files (Game-Side)

### Manifest (Structure + Wiring)
Like an HTML document - defines what components exist and how they connect:
- Component instances
- Input/Output wiring between modules
- Runtime context rules (when connections are active)

### Style (Presentation)
Defines visual properties:
- 3D transforms and arrangement
- GUI layouts and styling
- Audio properties
- Tween configurations

## System Submodules

All system code lives in `System.lua` as nested modules:

| Submodule | Purpose | Client | Server |
|-----------|---------|--------|--------|
| **Debug** | Logging, telemetry, dev tools | ✓ | ✓ |
| **IPC** | Unified messaging bus, routing, context-aware transport | ✓ | ✓ |
| **State** | Shared state with client/server boundaries | ✓ | ✓ |
| **Asset** | Template registry, spawning, lifecycle | - | ✓ |
| **Store** | DataStore abstraction, persistence | - | ✓ |
| **View** | Presentation (GUI, 3D, audio, tweens) | ✓ | - |

### IPC Details

The IPC subsystem provides unified messaging that abstracts:
- **BindableEvent** - Same-context communication (server↔server, client↔client)
- **RemoteEvent** - Cross-boundary communication (client↔server)

Same grammar/API regardless of transport. Context-aware routing under the hood.

### View Details

The View subsystem handles all presentation:
- ScreenGui / BillboardGui creation
- Model/Part transforms and visibility
- TweenService integration
- SoundService integration
- Lighting/atmosphere (future)

## Boot Stages

Simplified from v1's 8 stages to 3:

| Stage | What Happens |
|-------|--------------|
| **INIT** | Create state, events. No connections yet. |
| **START** | Connect events, begin logic. |
| **READY** | Everything live, game playable. |

Bootstrap script calls each stage in order. Modules register via manifest and are initialized according to dependency order (topological sort).

## Client/Server Separation

- **Shared code** where possible (same module, context-aware behavior)
- **Server-authoritative** game state (anti-cheat)
- **Client-side** visuals and most physics
- Server receives physics state reports where gameplay requires validation

## Dependency Resolution

Modules declare dependencies. System performs topological sort to determine initialization order. This scales as the library grows without manual tracking.

## Component Library

Reusable game components live in `Lib/Components/`. These extend the Node base class and follow the pin model.

### Available Components

| Component | Purpose | Status |
|-----------|---------|--------|
| **PathFollower** | Navigate entities through waypoints | Implemented |
| **Projectile** | Spawn and manage projectiles | Planned |
| **HealthSystem** | Damage, healing, death | Planned |
| **Currency** | Player economy tracking | Planned |

See `Logs/COMPONENT_REGISTRY.md` for the full catalog of planned components.

### Usage

```lua
local Lib = require(game.ReplicatedStorage.Lib)
local PathFollower = Lib.Components.PathFollower

-- Register with Asset system
Lib.System.Asset.register(PathFollower)

-- Create instance via IPC
local pf = Lib.System.IPC.createInstance("PathFollower", {
    id = "PathFollower_1",
    attributes = { Speed = 16, CollisionMode = "physics" },
})
```

### Creating Custom Components

Extend Node for game-specific components:

```lua
local Node = require(game.ReplicatedStorage.Lib).Node

local MyComponent = Node.extend({
    name = "MyComponent",
    domain = "server",  -- or "client", "shared"

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onSomeSignal = function(self, data)
            -- Handle input
            self.Out:Fire("response", { result = true })
        end,
    },

    Out = {
        response = {},  -- Schema documentation
    },
})
```

## Node Locking (Sync Behavior)

Nodes can block waiting for a signal using `waitForSignal()`. During the wait:
- Node is automatically locked
- IPC queues incoming messages instead of dispatching
- On signal received or timeout, node unlocks and queued messages replay

```lua
-- In a node handler:
local ack = self:waitForSignal("onAck", 5)  -- Wait up to 5 seconds
if not ack then
    self.Err:Fire({ reason = "ack_timeout" })
    return
end
-- Continue processing...
```

This enables synchronous request/response patterns while keeping the IPC architecture async.

## Licensing

LibPureFiction is proprietary software. Games built using this framework under subcontract receive license rights as part of the service agreement.

---

*v2 is a ground-up rewrite of v1, focusing on simplicity, isolation, and developer ergonomics.*
