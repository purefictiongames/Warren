# LibPureFiction v2 - Test Coverage

## Running Tests

In Roblox Studio Command Bar (after game starts):

```lua
-- Run all tests
_G.Lib.Tests.IPC.runAll()

-- Run specific group
_G.Lib.Tests.IPC.runGroup("Node")
_G.Lib.Tests.IPC.runGroup("IPC Messaging")

-- Run single test
_G.Lib.Tests.IPC.run("Node.extend creates class with name")

-- List available groups
_G.Lib.Tests.IPC.list()
```

Or using require:

```lua
local Tests = require(game.ReplicatedStorage.Lib.Tests)
Tests.IPC.runAll()
```

---

## Test Groups & Coverage

### Node (11 tests)
Core Node class functionality.

| Test | What It Validates |
|------|-------------------|
| Node.extend creates class with name | Basic extend works |
| Node.extend requires name | Validation |
| Node.extend requires definition | Validation |
| Node.extend sets default domain to shared | Default domain |
| Node.extend respects custom domain | Custom domain |
| Node.extend inherits required from Node | Contract inheritance |
| Node.extend merges custom required | Contract merging |
| Node.extend inherits defaults from Node | Default inheritance |
| Node.extend copies Sys handlers | Handler copying |
| Node.extend copies In handlers | Handler copying |
| Extended node can extend further | Chain inheritance |
| Child inherits parent handlers | Handler inheritance |
| Child can override parent handlers | Handler override |

### Node Instance (13 tests)
Node instantiation and instance methods.

| Test | What It Validates |
|------|-------------------|
| Node:new creates instance with id | Basic instantiation |
| Node:new requires id | Validation |
| Node:new sets class name | Metadata |
| Node:new creates Out channel | Pin creation |
| Node:new creates Err channel | Pin creation |
| Node:new injects default handlers | Default injection |
| Node:new respects custom Sys handlers | Custom handlers |
| Node:getAttribute returns nil for missing | Attribute get |
| Node:setAttribute and getAttribute work | Attribute set/get |
| Node:getAttributes returns all | Attribute enumeration |
| Node:hasHandler finds Sys handlers | Handler check |
| Node:hasHandler finds In handlers | Handler check |
| Node:hasHandler returns false for missing | Handler check |

### IPC Registration (5 tests)
Node registration with IPC system.

| Test | What It Validates |
|------|-------------------|
| IPC.registerNode accepts valid node | Basic registration |
| IPC.registerNode requires name | Validation |
| IPC.registerNode validates contract | Contract validation |
| IPC.registerNode accepts node with defaults fulfilling required | Default fulfillment |
| IPC.getNodeClasses returns registered | Class enumeration |

### IPC Instances (8 tests)
Instance creation and management.

| Test | What It Validates |
|------|-------------------|
| IPC.createInstance creates instance | Basic creation |
| IPC.createInstance requires registered class | Validation |
| IPC.createInstance requires id | Validation |
| IPC.createInstance rejects duplicate id | Duplicate prevention |
| IPC.getInstance returns created instance | Instance lookup |
| IPC.getInstance returns nil for missing | Missing handling |
| IPC.getInstancesByClass returns all of class | Class lookup |
| IPC.getInstanceCount returns correct count | Count tracking |
| IPC.despawn removes instance | Instance removal |

### IPC Modes (7 tests)
Mode definition and switching.

| Test | What It Validates |
|------|-------------------|
| IPC.defineMode stores config | Mode storage |
| IPC.defineMode requires name | Validation |
| IPC.getMode returns nil before switch | Initial state |
| IPC.switchMode sets current mode | Mode switching |
| IPC.switchMode requires defined mode | Validation |
| IPC.switchMode applies attributes | Attribute application |
| IPC.getModes returns all defined modes | Mode enumeration |

### IPC Lifecycle (9 tests)
Lifecycle hooks and state management.

| Test | What It Validates |
|------|-------------------|
| IPC.init calls onInit on instances | Init lifecycle |
| IPC.init sets initialized flag | State tracking |
| IPC.start calls onStart on instances | Start lifecycle |
| IPC.start requires init first | Order validation |
| IPC.start sets started flag | State tracking |
| IPC.stop calls onStop on instances | Stop lifecycle |
| IPC.switchMode calls onModeChange | Mode change lifecycle |
| IPC.spawn calls lifecycle hooks | Dynamic spawn |
| IPC.despawn calls lifecycle hooks | Dynamic despawn |

### IPC Messaging (6 tests)
Message routing and delivery.

| Test | What It Validates |
|------|-------------------|
| IPC.getMessageId returns incrementing ids | ID generation |
| IPC.sendTo delivers message to instance | Direct delivery |
| IPC.sendTo requires started | State check |
| IPC.send routes through wiring | Wiring routing |
| IPC.broadcast delivers to all instances Sys | Broadcast delivery |
| Cycle detection prevents infinite loops | Cycle prevention |

### Error Handling (2 tests)
Error catching and propagation.

| Test | What It Validates |
|------|-------------------|
| Handler errors are caught and reported | Error catching |
| Err channel fires on handler error | Error propagation |

### Mode Pins (2 tests)
Mode-specific pin resolution.

| Test | What It Validates |
|------|-------------------|
| Mode-specific In handlers are called | Mode override |
| Falls back to default In when mode has no handler | Fallback behavior |

### IPC Utilities (1 test)
Utility functions.

| Test | What It Validates |
|------|-------------------|
| IPC.reset clears all state | State reset |

---

## Summary

| Group | Tests |
|-------|-------|
| Node | 13 |
| Node Instance | 13 |
| IPC Registration | 5 |
| IPC Instances | 8 |
| IPC Modes | 7 |
| IPC Lifecycle | 9 |
| IPC Messaging | 6 |
| Error Handling | 2 |
| Mode Pins | 2 |
| IPC Utilities | 1 |
| **Total** | **66** |

---

## What's NOT Tested (Manual Testing Required)

1. **Domain filtering** - Server/client domain checks require actual server/client context
2. **Model integration** - Node attachment to Roblox Instances
3. **Cross-context routing** - Server→client messaging via RemoteEvents
4. **Studio CLI** - _G.Node, _G.IPC availability
5. **Performance** - Message throughput under load
6. **Memory** - Leak detection over extended use

---

## Expected Output

Successful run:
```
═══════════════════════════════════════════════════════
  LibPureFiction v2 - IPC & Node Test Suite
═══════════════════════════════════════════════════════

▶ Node
  ✓ Node.extend creates class with name
  ✓ Node.extend requires name
  ...

▶ IPC Messaging
  ✓ IPC.getMessageId returns incrementing ids
  ✓ IPC.sendTo delivers message to instance
  ...

───────────────────────────────────────────────────────
  Results: 66/66 passed  |  ALL PASSED
───────────────────────────────────────────────────────
```

Failed run shows:
```
  ✗ Test name here
       Error: expected X, got Y
```
