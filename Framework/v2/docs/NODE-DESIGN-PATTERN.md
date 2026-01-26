# Node Design Pattern

LibPureFiction Framework v2 - Canonical Node Architecture

## Overview

All nodes in the framework follow a consistent design pattern that ensures:
- True encapsulation (no architectural violations possible)
- Signal-only inter-node communication (full IPC)
- Deterministic discovery and composition
- Clean lifecycle management

## Core Principles

### 1. Closure-Based Privacy

Private state is truly private - it doesn't exist on the node instance at all.

```lua
local MyNode = Node.extend(function(parent)
    -- PRIVATE SCOPE - nothing here exists on the instance
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- All private state here
                internalValue = 0,
                connections = {},
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    -- Private functions (not on instance)
    local function doSomethingPrivate(self, data)
        local state = getState(self)
        -- ...
    end

    -- PUBLIC INTERFACE - only this is exposed
    return {
        name = "MyNode",
        domain = "server",
        Sys = { ... },
        In = { ... },
        Out = { ... },
    }
end)
```

**Why**: Prevents architectural violations. Claude (or any developer) cannot call `node._privateMethod()` because it doesn't exist.

### 2. Signal-Only IPC

Nodes communicate exclusively through signals. No direct method calls between nodes.

```lua
-- WRONG: Direct method call
otherNode:doSomething(data)

-- CORRECT: Signal emission
self.Out:Fire("requestSomething", { data = data })
-- Wiring delivers to: otherNode.In.onRequestSomething
```

**Why**:
- Decouples nodes completely
- Enables declarative wiring
- Makes data flow explicit and traceable
- Allows orchestrators to intercept/transform/validate

### 3. Discovery Handshake Pattern

Nodes discover external dependencies during `onStart` via synchronous handshake signals.

```lua
Sys = {
    onStart = function(self)
        local state = getState(self)

        -- Discovery: check if external component is wired
        state.hasExternalDependency = false
        self.Out:Fire("discoverDependency", { nodeId = self.id })
        -- If wired, handler sets hasExternalDependency = true synchronously

        -- Now we know whether to use internal or external
        if not state.hasExternalDependency then
            initializeInternalDefault(self)
        end
    end,
},

In = {
    -- Called synchronously if dependency responds
    onDependencyPresent = function(self, data)
        local state = getState(self)
        state.hasExternalDependency = true
        state.externalId = data.dependencyId
    end,
}
```

**Why**:
- No config flags needed (`useExternalX = true`)
- Wiring is frozen by `onStart`, so handshake is deterministic
- Self-documenting: wiring table shows all relationships

### 4. Component Composition Pattern

Every component follows this pattern:

1. **Internal defaults work out of the box** - No config required
2. **Declarative config for customization** - Attributes/config override defaults
3. **External component gets full authority** - When wired, internal is bypassed

```lua
-- Launcher has internal ammo tracking by default
-- If Magazine is wired, Magazine owns all ammo state

onStart = function(self)
    state.hasExternalMagazine = false
    self.Out:Fire("discoverMagazine", { launcherId = self.id })

    -- After handshake, we know which mode we're in
    if not state.hasExternalMagazine then
        -- Use internal ammo (self-contained operation)
        state.currentAmmo = self:getAttribute("MagazineCapacity")
    end
    -- If external, Magazine owns ammo - we just request/receive
end
```

### 5. Orchestrator Two-Phase Startup

When an Orchestrator manages multiple nodes, it MUST:

1. **Phase 1: Wire ALL nodes** - Intercept `Out.Fire` for routing
2. **Phase 2: Start ALL nodes** - Call `onStart` after all wiring is in place

```lua
enableRouting = function(self)
    state.enabled = true

    -- Phase 1: Wire all nodes (intercept Out.Fire)
    for nodeId in pairs(state.nodes) do
        wireNode(self, nodeId)
    end

    -- Phase 2: Start all nodes (now all wiring is in place)
    for nodeId in pairs(state.nodes) do
        startNode(self, nodeId)
    end
end
```

**Why**: Discovery handshakes fire during `onStart`. If Node A fires `discoverB` but Node B isn't wired yet, B's response won't be routed and the handshake fails.

### 6. Lifecycle Responsibilities

#### `onInit`
- Create instance state via `getState(self)`
- Set default attributes
- Do NOT fire signals
- Do NOT start runtime behavior

#### `onStart`
- Fire discovery handshake signals
- Initialize runtime behavior (loops, connections)
- Safe to fire signals (wiring is in place)

#### `onStop`
- Stop all runtime behavior (loops, connections)
- Call `cleanupState(self)` - CRITICAL for memory
- Do NOT fire signals

```lua
Sys = {
    onInit = function(self)
        local state = getState(self)

        -- Set defaults
        if self:getAttribute("Speed") == nil then
            self:setAttribute("Speed", 10)
        end
    end,

    onStart = function(self)
        local state = getState(self)

        -- Discovery handshakes
        self.Out:Fire("discoverDependency", {})

        -- Start runtime
        state.updateConnection = RunService.Heartbeat:Connect(function(dt)
            update(self, dt)
        end)
    end,

    onStop = function(self)
        local state = getState(self)

        -- Stop runtime
        if state.updateConnection then
            state.updateConnection:Disconnect()
        end

        -- CRITICAL: Clean up state
        cleanupState(self)
    end,
}
```

## Orchestrator as IC (Integrated Circuit)

Orchestrators present a simple external interface while managing internal complexity:

```lua
-- External view: simple In/Out
orchestrator.In.onFire(orchestrator, { target = pos })
-- Internally: routes to Launcher, which requests from Magazine, etc.

-- Declarative wiring with "Out" forwarding
wiring = {
    -- Internal routing
    { from = "Launcher", signal = "requestAmmo", to = "Magazine", handler = "onDispense" },

    -- Forward to orchestrator's own Out (for external consumers)
    { from = "Launcher", signal = "fired", to = "Out" },
    { from = "Magazine", signal = "ammoChanged", to = "Out" },
}
```

## Signal Naming Conventions

### Input Handlers (`In`)
- Prefix: `on`
- Examples: `onFire`, `onConfigure`, `onMagazinePresent`, `onAmmoReceived`

### Output Signals (`Out`)
- No prefix, past tense or noun
- Examples: `fired`, `configured`, `ammoChanged`, `discoverMagazine`

### Discovery Signals
- Output: `discover{Thing}` - "I'm looking for a Thing"
- Input: `on{Thing}Present` - "I am the Thing you're looking for"

## Standard Signal Pairs

### Handshake (discovery)
```
NodeA.Out.discoverB     → NodeB.In.onDiscoverB (optional, if B needs data)
NodeB.Out.bPresent      → NodeA.In.onBPresent
```

### Request/Response
```
NodeA.Out.requestThing  → NodeB.In.onRequestThing
NodeB.Out.thingReady    → NodeA.In.onThingReady
```

### State Change Notification
```
NodeA.Out.stateChanged  → (any subscriber)
```

## File Template

```lua
--[[
    LibPureFiction Framework v2
    {ComponentName}.lua - {Brief Description}

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    {What this component does, its purpose in the system}

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        on{Signal}({ param1, param2 })
            - Description

    OUT (emits):
        {signal}({ param1, param2 })
            - Description

    ============================================================================
    ATTRIBUTES
    ============================================================================

    {AttributeName}: {type} (default {value})
        Description

--]]

local Node = require(script.Parent.Parent.Node)

local {ComponentName} = Node.extend(function(parent)
    -- Per-instance state registry
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Private state
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    -- Private functions

    return {
        name = "{ComponentName}",
        domain = "server",  -- or "client" or "shared"

        Sys = {
            onInit = function(self)
                local state = getState(self)
                -- Set default attributes
            end,

            onStart = function(self)
                local state = getState(self)
                -- Discovery handshakes
                -- Start runtime
            end,

            onStop = function(self)
                local state = getState(self)
                -- Stop runtime
                cleanupState(self)
            end,
        },

        In = {
            onConfigure = function(self, data)
                -- Handle configuration
            end,
        },

        Out = {
            -- Signal declarations
        },
    }
end)

return {ComponentName}
```

## Summary

1. **Privacy**: Closure pattern makes violations impossible
2. **Communication**: Signal-only IPC, no direct calls
3. **Discovery**: Handshake pattern in `onStart`, deterministic
4. **Composition**: Internal defaults, config overrides, external authority
5. **Orchestrator**: Two-phase startup (wire all, then start all)
6. **Lifecycle**: Init (state), Start (signals/runtime), Stop (cleanup)
