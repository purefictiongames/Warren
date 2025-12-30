# Session Log: Debug Logging System Implementation
**Date:** 2025-12-29
**Duration:** ~1 hour
**Status:** Complete

## Objective

Replace direct `print()` and `warn()` calls across the codebase with a configurable debug logging system to reduce console noise and improve debugging workflow.

## Problem Statement

The codebase had 97 direct `print()`/`warn()` calls scattered across System, Subsystems, Assets, and Templates. During development and testing, the console output was noisy and made it difficult to focus on specific modules or issues.

## Solution: Debug Logging System

### Architecture

**Config Module:** `src/System/ReplicatedFirst/DebugConfig.lua`
- Located in ReplicatedFirst for earliest possible loading
- Accessible by both client and server
- Controls debug output filtering

**Debug API:** Added to `src/System/ReplicatedStorage/System.lua`
- `System.Debug:Message(source, ...)` - Regular output
- `System.Debug:Warn(source, ...)` - Warning output (yellow)
- `System.Debug:Alert(source, ...)` - Error output with [ALERT] prefix

### Debug Levels

| Level | Scope | Use Case |
|-------|-------|----------|
| 1 | System only | Core boot debugging |
| 2 | System + Subsystems | Boot + Player/Backpack debugging |
| 3 | Assets only | Gameplay debugging (hide boot noise) |
| 4 | Everything + Filter | Fine-grained control via enabled/disabled rules |

### Level 4 Filtering

iptables-style rule matching with glob pattern support:

```lua
Filter = {
    enabled = {
        "System.*",      -- Enable all System sources
        "Dispenser",     -- Enable specific asset
    },
    disabled = {
        "ZoneController", -- Disable verbose asset
    },
}
```

**Precedence:**
1. Check `enabled` - if source matches, ALLOW
2. Check `disabled` - if source matches, BLOCK
3. Default - ALLOW (permissive)

**Glob patterns:** `System.*`, `*.client`, or exact names like `Dispenser`

## Implementation

### Phase 1: Infrastructure

**New Files:**
- `src/System/ReplicatedFirst/init.meta.json` - Rojo folder metadata
- `src/System/ReplicatedFirst/DebugConfig.lua` - Config module

**Modified Files:**
- `default.project.json` - Added ReplicatedFirst mapping
- `src/System/ReplicatedStorage/System.lua` - Added Debug namespace (~100 lines)

### Phase 2: System + Subsystems (15 calls)

| File | Calls |
|------|-------|
| System.lua | 2 |
| System.Script | 2 |
| System.client | 3 |
| Player.Script | 1 |
| Backpack.Script | 6 |

### Phase 3: Assets + Templates (82 calls)

| Asset | Server | Client | Total |
|-------|--------|--------|-------|
| RoastingStick | 3 | 0 | 3 |
| Dispenser | 10 | 1 | 11 |
| Dispenser.ModuleScript | 2 | 0 | 2 |
| ZoneController | 7 | 0 | 7 |
| TimedEvaluator | 12 | 5 | 17 |
| GlobalTimer | 8 | 2 | 10 |
| Scoreboard | 7 | 3 | 10 |
| LeaderBoard | 12 | 0 | 12 |
| Orchestrator | 5 | 0 | 5 |
| MessageTicker | 0 | 2 | 2 |
| Marshmallow (Template) | 5 | 0 | 5 |

**Total migrated:** 97 calls across 22 files

## Source Naming Convention

| Category | Pattern | Examples |
|----------|---------|----------|
| Core System | `System`, `System.Script`, `System.client` | Boot stages, client ready |
| Subsystems | `System.Player`, `System.Backpack` | Player setup, item events |
| Assets (Server) | `Dispenser`, `ZoneController`, etc. | Asset-specific logic |
| Assets (Client) | `Dispenser.client`, `Scoreboard.client` | HUD updates |
| Templates | `Marshmallow` | Cloned item behavior |

## Output Format

```
Dispenser: Gave Marshmallow to Player1
System: Stage READY (5)
[ALERT] ZoneController: Error calling cook on Marshmallow - timeout
```

## Files Changed (22 total)

### New Files (2)
- `src/System/ReplicatedFirst/init.meta.json`
- `src/System/ReplicatedFirst/DebugConfig.lua`

### Modified Files (20)
- `default.project.json`
- `src/System/ReplicatedStorage/System.lua`
- `src/System/Script.server.lua`
- `src/System/StarterPlayerScripts/System.client.lua`
- `src/System/Player/_ServerScriptService/Script.server.lua`
- `src/System/Backpack/_ServerScriptService/Script.server.lua`
- `src/Assets/RoastingStick/_ServerScriptService/Script.server.lua`
- `src/Assets/Dispenser/_ServerScriptService/Script.server.lua`
- `src/Assets/Dispenser/StarterGui/LocalScript.client.lua`
- `src/Assets/Dispenser/ReplicatedStorage/ModuleScript.lua`
- `src/Assets/ZoneController/_ServerScriptService/Script.server.lua`
- `src/Assets/TimedEvaluator/_ServerScriptService/Script.server.lua`
- `src/Assets/TimedEvaluator/StarterGui/LocalScript.client.lua`
- `src/Assets/GlobalTimer/_ServerScriptService/Script.server.lua`
- `src/Assets/GlobalTimer/StarterGui/LocalScript.client.lua`
- `src/Assets/Scoreboard/_ServerScriptService/Script.server.lua`
- `src/Assets/Scoreboard/StarterGui/LocalScript.client.lua`
- `src/Assets/LeaderBoard/_ServerScriptService/Script.server.lua`
- `src/Assets/Orchestrator/_ServerScriptService/Script.server.lua`
- `src/Assets/MessageTicker/StarterGui/LocalScript.client.lua`
- `src/Templates/Marshmallow/Script.server.lua`

## Usage Examples

### Changing Debug Level

Edit `src/System/ReplicatedFirst/DebugConfig.lua`:

```lua
return {
    Level = 1,  -- Only System messages (quiet mode)
    Filter = { enabled = {}, disabled = {} },
}
```

### Filtering Specific Assets (Level 4)

```lua
return {
    Level = 4,
    Filter = {
        enabled = { "Dispenser", "RoastingStick" },  -- Only these
        disabled = {},
    },
}
```

### Hide Verbose Assets (Level 4)

```lua
return {
    Level = 4,
    Filter = {
        enabled = {},
        disabled = { "TimedEvaluator", "ZoneController" },  -- Hide these
    },
}
```

## Testing Verification

- [x] Game boots normally at Level 2 (default)
- [x] Console shows `Source:` prefix format
- [x] Level 1 filters to System only
- [x] Level 3 shows only Assets
- [x] Level 4 filtering works with enabled/disabled rules
- [x] Full gameplay loop works (dispense, cook, submit, score, reset)

## Design Decisions

1. **Nested under System.lua** - Debug methods are available everywhere System is already required, no additional imports needed

2. **Lazy config loading** - Config is loaded on first Debug call and cached, with fallback to Level 2 if config is missing

3. **Permissive default for Level 4** - If source isn't in enabled or disabled, it's allowed (whitelist is opt-in, blacklist is opt-out)

4. **Source naming mirrors file structure** - Makes it easy to filter by looking at folder names

5. **Client scripts use `.client` suffix** - Distinguishes client-side HUD messages from server-side logic

## Future Enhancements

- Add `Debug:Trace()` for verbose call stack logging
- Add timestamp option in config
- Add log file output (if Roblox supports)
- Add remote log streaming for published game debugging
