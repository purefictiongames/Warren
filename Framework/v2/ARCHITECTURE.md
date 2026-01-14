# LibPureFiction v2 Architecture

## CRITICAL: Event-Driven Signal Architecture

**THIS IS NON-NEGOTIABLE.**

### The Rule

Components communicate via **signals**, not direct API calls.

```lua
-- WRONG: Direct handler call
swivel.In.onRotate(swivel, { direction = "forward" })

-- CORRECT: Fire signal through Out channel
controller.Out:Fire("rotate", { direction = "forward" })
```

### Why This Matters

1. **Decoupling** - Components don't need direct references to each other
2. **IPC Routing** - Signals can be routed across network boundaries (server/client)
3. **Sync Mode** - Signals can block and wait for acknowledgment
4. **Debugging** - All communication flows through observable channels
5. **Wiring** - Connections between components are explicit and configurable

### Signal Flow

```
┌─────────────┐    Out:Fire()    ┌─────────┐    In.onSignal()    ┌─────────────┐
│  Component  │ ──────────────► │   IPC   │ ─────────────────► │  Component  │
│      A      │                  │ Router  │                     │      B      │
└─────────────┘                  └─────────┘                     └─────────────┘
```

### Node Pin Architecture

Every Node has four pin types:

- **Sys** - Lifecycle signals (onInit, onStart, onStop)
- **In** - Input handlers (receive signals)
- **Out** - Output emitters (fire signals)
- **Err** - Error channel (propagate errors)

### Correct Patterns

```lua
-- Emitting a signal
self.Out:Fire("targetAcquired", { position = pos, distance = dist })

-- Sync signal (blocks until ack)
local success, ackData = self.Out:Fire("fire", { target = t }, { sync = true })

-- Wiring (done by IPC or manually for demos)
nodeA.Out = {
    Fire = function(self, signal, data)
        if signal == "rotate" then
            -- Route to nodeB's In handler
            nodeB.In.onRotate(nodeB, data)
        end
    end,
}
```

### Anti-Patterns (NEVER DO THIS)

```lua
-- WRONG: Direct handler invocation from outside the node
otherNode.In.onFire(otherNode, data)

-- WRONG: Reaching into another node's state
local angle = otherNode._currentAngle

-- WRONG: Calling methods directly instead of signals
otherNode:rotate("forward")
```

### Exception: Lifecycle Initialization

The ONLY acceptable direct calls are for lifecycle setup before IPC is running:

```lua
-- OK during setup (before IPC routing is active)
local node = MyNode:new({ id = "foo", model = part })
node.Sys.onInit(node)
node.In.onConfigure(node, { ... })  -- Initial config before wiring
```

Once nodes are wired and running, ALL communication must be via signals.
