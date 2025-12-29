# LibPureFiction Framework Architecture

## Current: Simple Bootstrap (v0)

The current system uses a single-pass deployment where `System.Script` extracts service folders in order (ReplicatedStorage first, then scripts). Scripts use `WaitForChild` to wait for dependencies.

**Limitations:**
- Race conditions between scripts and events
- No guaranteed deployment order
- Each asset needs boilerplate lazy loading

---

## Planned: Stage-Wait Boot System (v1)

A staged boot system where `System.Script` is the only script that runs immediately. All other scripts wait for the appropriate boot stage before executing.

### Boot Stages

```lua
Stages = {
    SYNC    = 1,  -- Assets cloned to RuntimeAssets, folders extracted
    EVENTS  = 2,  -- All BindableEvents/RemoteEvents created and registered
    MODULES = 3,  -- ModuleScripts deployed and requireable
    SCRIPTS = 4,  -- Server scripts can run
    READY   = 5,  -- Full boot complete, clients can interact
}
```

### Key Components

1. **System.lua** - Stage constants + `WaitForStage()` helper
2. **System.BootStage** (BindableEvent) - Server scripts listen for stage transitions
3. **System.ClientBoot** (RemoteEvent) - Client ping-pong protocol
4. **CharacterAutoLoads = false** - Prevent player spawning until READY

### Critical Design Decision: No Spawning Until Ready

**Problem discovered:** Even with staged boot, players could spawn before scripts finished initializing, causing race conditions.

**Solution:** Disable character auto-loading at the very start of System.Script:

```lua
-- FIRST LINE of System.Script
Players.CharacterAutoLoads = false

-- ... bootstrap all stages ...

-- After READY stage fires:
for _, player in Players:GetPlayers() do
    player:LoadCharacter()
end
Players.CharacterAutoLoads = true  -- Re-enable for respawns
```

This ensures NO player exists until the entire system is ready. Eliminates all timing hacks.

### Server Script Pattern

```lua
-- After name guard (if present)
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Rest of initialization (guaranteed all events exist)
```

### Client Script Pattern

```lua
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- UI setup (guaranteed server is fully ready)
```

---

## Future: Lifecycle Hook System (v2)

> **Note:** Target architecture for when framework scales beyond ~20 assets.

### Concept

Assets become ModuleScripts with optional lifecycle methods called by System at each boot stage. Enables:
- True concurrency (assets initialize in parallel within each stage)
- Dependency declarations between assets
- Full visibility into boot progress

### Asset Structure

```lua
local Asset = {}

function Asset:onSync(system)
    -- Pre-cache, validate attributes
end

function Asset:onEvents(system)
    -- Create/register events, set up listeners
end

function Asset:onModules(system)
    -- Require dependencies, initialize shared state
end

function Asset:onScripts(system)
    -- Main logic, connect to other assets
end

function Asset:onReady(system)
    -- Enable player interaction
end

-- Optional: declare dependencies
Asset.dependsOn = {"Backpack", "MessageTicker"}

return Asset
```

### System Orchestration

```lua
-- For each stage:
for _, asset in assets do
    if asset["on" .. stageName] then
        task.spawn(function()
            asset["on" .. stageName](asset, system)
            system:markComplete(asset.name, stageName)
        end)
    end
end
system:waitForAllComplete(stageName)
-- Advance to next stage
```

### Benefits Over Stage-Wait
- Concurrent initialization within stages
- Explicit dependency ordering
- Better debugging (know exactly which asset is blocking)
- Code naturally organized by lifecycle phase

### Migration Path
1. Convert asset to ModuleScript
2. Move initialization code into appropriate `onStage` methods
3. Remove boilerplate `WaitForStage` calls
4. Declare dependencies if needed

---

## Lessons Learned (from failed v1 attempt)

1. **CharacterAutoLoads is essential** - Stage-wait alone isn't enough; players can spawn during boot
2. **Don't use WaitForChild as a band-aid** - If you need it after a refactor meant to eliminate it, the refactor is broken
3. **Test incrementally** - Don't change 20 files at once; test each stage
4. **Player lifecycle is separate from asset lifecycle** - Boot system controls assets; CharacterAutoLoads controls players
