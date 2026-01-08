> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# LibPureFiction Framework - Procedures Manual

**Purpose:** Operational guide for Claude instances working on this project
**Version:** Draft 1.0
**Last Updated:** December 30, 2025

---

# Table of Contents

1. [Core Principles](#1-core-principles)
2. [Session Startup](#2-session-startup)
3. [Understanding the Codebase](#3-understanding-the-codebase)
4. [Task Classification](#4-task-classification)
5. [Development Procedures](#5-development-procedures)
6. [Testing Procedures](#6-testing-procedures)
7. [Documentation Procedures](#7-documentation-procedures)
8. [Debugging Procedures](#8-debugging-procedures)
9. [Communication Patterns](#9-communication-patterns)
10. [Code Standards](#10-code-standards)
11. [Common Pitfalls](#11-common-pitfalls)
12. [Decision Framework](#12-decision-framework)

---

# 1. Core Principles

## 1.1 CRITICAL: Architectural Consistency

**Once an architectural pattern is established, it MUST be used. No exceptions. No fallbacks to "traditional" Roblox methods.**

This is the most important principle in this codebase. When we build an abstraction layer, all future work uses that layer. Period.

### Examples:

| System | MUST Use | NEVER Use |
|--------|----------|-----------|
| GUI Creation | `GUI:Create()` | `Instance.new("TextLabel")` for UI |
| Layouts | `Layouts.lua` config + `GUI:CreateLayout()` | Manual positioning in code |
| Styles (GUI) | `Styles.lua` classes | Inline property assignment |
| Styles (Assets) | `Styles.lua` + `GUI:StyleAsset()` | Manual CFrame/position setting |
| Asset Positioning | Declarative via `StyleClass` attribute | Hardcoded `Model:PivotTo()` calls |
| Debug Output | `System.Debug:Message()` | `print()` or `warn()` |
| Boot Sequencing | `System:WaitForStage()` | Raw `WaitForChild()` chains |
| Events | Folder-based event creation | `Instance.new("BindableEvent")` inline |

### Why This Matters:

1. **Consistency** - All code works the same way
2. **Maintainability** - Change one place, affects everything
3. **Discoverability** - New code follows known patterns
4. **Testing** - Unified behavior is easier to test
5. **The User's Intent** - The abstractions exist for a reason

### Violation Detection:

If you find yourself writing:
- `Instance.new("TextLabel")` for UI → STOP, use `GUI:Create()`
- `element.TextColor3 = Color3.new(...)` → STOP, use `Styles.lua` class
- `model:PivotTo(CFrame.new(...))` → STOP, use `GUI:StyleAsset()` with `Styles.lua`
- `part.CFrame = CFrame.new(...)` for positioning → STOP, use declarative styles
- `print("something")` → STOP, use `System.Debug:Message()`
- `UDim2.new(...)` scattered in code → STOP, define in Layouts.lua

### What To Do When Tempted:

1. **Ask:** "Does our system handle this?"
2. **If yes:** Use the system, even if it seems like more work
3. **If no:** Propose extending the system first, then implement

### Extending Systems:

If an abstraction doesn't support what you need:

1. **Propose the extension** to the user
2. **Implement the extension** in the system
3. **Then use the system** for your feature

Never bypass. Always extend.

---

## 1.2 Modularity

Assets are self-contained. They don't know about each other. They communicate via events. This enables:

- Dropping assets into different projects
- Testing assets in isolation
- Adding/removing assets without breaking others

## 1.3 Configuration Over Code

Prefer declarative configuration (Attributes, Layouts.lua, Styles.lua) over imperative code. This makes behavior visible without reading code.

## 1.4 Explicit Over Implicit

- Name guards make execution explicit
- WaitForStage makes timing explicit
- Event names include source prefix
- No magic or hidden behavior

## 1.5 REQUIRED: Copyright Boilerplate

**Every source file and document MUST include the copyright boilerplate.**

This is a legal requirement, not optional. All new files must have the boilerplate added before commit.

### For Lua Scripts

Add at the very top of every `.lua` file:

```lua
--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]
```

### For Markdown Documents

Add at the very top of every `.md` file:

```markdown
> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---
```

### Reference Documents

See `Logs/Copyright Boilerplate.md` for the canonical boilerplate text.
See `Logs/LibPureFiction — Intellectual Property Statement.md` for full IP policy.

---

# 2. Session Startup

## 2.1 Context Recovery Procedure

At the start of each session, recover context in this order:

1. **Check git status** - Understand current branch, uncommitted changes
2. **Read recent session logs** - Start with most recent in `Framework/v1/Logs/`
3. **Read ARCHITECTURE.md** - Refresh on design principles
4. **Scan SYSTEM_REFERENCE.md** - If working on specific subsystem
5. **Read PROJECT_JOURNAL.md** - If session logs are unclear on history

```bash
# Quick context commands
git status
git log --oneline -10
ls -la Framework/v1/Logs/
```

## 2.2 First Response Pattern

After reading context, acknowledge what you understand before proceeding:

```
Based on the session logs, we're working on [X]. Last session we:
- Completed [A]
- Hit a blocker on [B]
- Left off at [C]

Ready to continue with [next step]?
```

## 2.3 When Context is Unclear

If session logs don't make the current state clear:

1. Ask the user for clarification on where we left off
2. Run the game in Studio to observe current behavior
3. Read the specific files mentioned in recent commits

---

# 3. Understanding the Codebase

## 3.1 Key Files to Know

| File | Purpose | When to Read |
|------|---------|--------------|
| `System/Script.server.lua` | Bootstrap logic | Debugging boot issues |
| `System/ReplicatedStorage/System.lua` | Stage API, Debug API | Adding stages, debug features |
| `System/ReplicatedFirst/DebugConfig.lua` | Debug filtering | Adjusting console output |
| `System/GUI/ReplicatedStorage/GUI.lua` | GUI API | Any UI work |
| `System/GUI/ReplicatedFirst/Layouts.lua` | Layout config | Changing HUD layout |
| `System/GUI/ReplicatedFirst/Styles.lua` | Style definitions | Changing visual styling |

## 3.2 Asset Exploration Pattern

When exploring an asset:

1. Read `init.meta.json` for className
2. Check for `.rbxm` files (physical components)
3. Read server script first (`_ServerScriptService/Script.server.lua`)
4. Read client script if exists (`StarterGui/LocalScript.client.lua`)
5. Check `ReplicatedStorage/` for shared modules and events
6. Note Model Attributes (documented in SYSTEM_REFERENCE.md Appendix C)

## 3.3 Event Flow Tracing

To understand how assets communicate:

1. Search for `:Fire(` in server scripts to find event sources
2. Search for `.Event:Connect` to find listeners
3. Check Orchestrator - it listens to most events
4. Refer to SYSTEM_REFERENCE.md Appendix B for event reference

---

# 4. Task Classification

## 4.1 Task Types

| Type | Characteristics | Approach |
|------|-----------------|----------|
| **New Asset** | Add new game functionality | Full asset creation procedure |
| **New Template** | Add new cloneable item | Template creation procedure |
| **Bug Fix** | Something doesn't work | Debugging procedure |
| **Enhancement** | Improve existing feature | Understand first, modify carefully |
| **Refactor** | Restructure without changing behavior | High caution, incremental commits |
| **Documentation** | Update docs | Read current state, update accurately |

## 4.2 Complexity Assessment

Before starting, assess complexity:

**Low Complexity:**
- Single file change
- Clear requirements
- Follows existing pattern

**Medium Complexity:**
- 2-5 files
- New pattern needed
- Requires testing

**High Complexity:**
- System-wide changes
- New subsystem
- Breaking changes possible

For medium/high complexity: Create a plan, confirm with user before implementing.

---

# 5. Development Procedures

## 5.1 Creating a New Asset

**The Motion:**

1. **Plan Structure**
   ```
   src/Assets/<AssetName>/
   ├── init.meta.json
   ├── <Physical>.rbxm (if needed)
   ├── ReplicatedStorage/ (if has shared modules/events)
   ├── StarterGui/ (if has client UI)
   └── _ServerScriptService/
       └── Script.server.lua
   ```

2. **Create init.meta.json**
   ```json
   {
     "className": "Model"
   }
   ```

3. **Create Server Script with Standard Pattern**
   ```lua
   -- AssetName.Script (Server)
   -- [Brief description]

   -- Guard: Only run if this is the deployed version
   if not script.Name:match("^AssetName%.") then
       return
   end

   local ReplicatedStorage = game:GetService("ReplicatedStorage")

   -- Wait for boot system
   local System = require(ReplicatedStorage:WaitForChild("System.System"))
   System:WaitForStage(System.Stages.SCRIPTS)

   -- Dependencies
   local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
   local model = runtimeAssets:WaitForChild("AssetName")

   -- Setup function
   local function setupAssetName(model)
       -- Configuration from attributes
       -- Find components
       -- Connect events
       -- Expose control functions
   end

   setupAssetName(model)

   -- Apply declarative positioning (if asset has world presence)
   local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
   model:SetAttribute("StyleClass", "AssetName")  -- Define in Styles.lua
   GUI:StyleAsset(model)

   System.Debug:Message("AssetName", "Setup complete")
   ```

4. **Define Asset Positioning in Styles.lua**
   ```lua
   -- In src/System/GUI/ReplicatedFirst/Styles.lua
   classes = {
       ["AssetName"] = {
           position = {x, y, z},  -- World position in studs
           rotation = {x, y, z},  -- Rotation in degrees
       },
   }
   ```

5. **Create Client Script if Needed - USING GUI SYSTEM**
   ```lua
   -- AssetName.LocalScript (Client)

   -- Guard
   if not script.Name:match("^AssetName%.") then
       return
   end

   local ReplicatedStorage = game:GetService("ReplicatedStorage")
   local Players = game:GetService("Players")

   local System = require(ReplicatedStorage:WaitForChild("System.System"))
   System:WaitForStage(System.Stages.READY)

   -- MUST use GUI system for all UI creation
   local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

   local player = Players.LocalPlayer
   local playerGui = player:WaitForChild("PlayerGui")

   -- Create UI using GUI system - NEVER Instance.new() for UI
   local screenGui = Instance.new("ScreenGui")
   screenGui.Name = "AssetName.ScreenGui"

   local content = Instance.new("Frame")
   content.Name = "Content"
   content.Size = UDim2.new(1, 0, 1, 0)
   content.BackgroundTransparency = 1
   content.Parent = screenGui

   -- Use GUI:Create() for all elements
   local label = GUI:Create({
       type = "TextLabel",
       class = "hud-text",  -- Use style classes, not inline properties
       text = "Content",
   })
   label.Parent = content

   screenGui.Parent = playerGui
   ```

6. **Test Incrementally**
   - Verify Rojo syncs the asset
   - Verify boot completes
   - Verify asset functions
   - Test full gameplay loop

7. **Commit Individually**
   - One commit per asset
   - Clear commit message describing what the asset does

## 5.2 Creating Events

**For BindableEvent (Server-to-Server):**

Create folder structure:
```
ReplicatedStorage/
└── MyEvent/
    └── init.meta.json
```

With content:
```json
{
  "className": "BindableEvent"
}
```

**For RemoteEvent (Server-to-Client):**

Same structure but:
```json
{
  "className": "RemoteEvent"
}
```

**NEVER:** `Instance.new("BindableEvent")` inline in scripts (except for internal, non-shared events).

## 5.3 Creating Physical Components

1. Build component in Roblox Studio
2. Right-click → Save to File → Choose `.rbxm` format
3. Save to appropriate asset folder
4. Let Rojo sync it back
5. Delete the duplicate in Studio (Rojo now owns it)

## 5.4 Modifying Existing Code

1. **Read First** - Always read the entire file before modifying
2. **Understand Intent** - Know why the code exists
3. **Minimal Changes** - Only change what's necessary
4. **Preserve Patterns** - Match existing code style
5. **Use Established Systems** - Don't introduce raw Roblox calls
6. **Test After** - Run the game, verify nothing broke

## 5.5 Adding UI to an Asset

**ALWAYS use this pattern:**

1. Define styles in `Styles.lua` if needed
2. Add to layout in `Layouts.lua` if part of HUD
3. Use `GUI:Create()` for element creation
4. Use style classes, not inline properties
5. Wrap content in a "Content" Frame for layout integration

**NEVER:**
- `Instance.new("TextLabel")` with manual property setting
- Hardcoded positions/sizes in script
- Inline color/font values

---

# 6. Testing Procedures

## 6.1 Minimum Test Suite

After any change, verify:

1. **Boot Completes** - All 5 stages fire, no errors
2. **Players Spawn** - Character appears after READY
3. **Core Loop Works:**
   - Dispense marshmallow
   - Mount on stick
   - Cook in zone (color changes)
   - Submit to evaluator
   - Score updates on HUD
   - Round resets

## 6.2 Testing Specific Systems

| System | How to Test |
|--------|-------------|
| Boot System | Watch Output for stage messages |
| Dispenser | Trigger prompt, check backpack |
| ZoneController | Walk into zone, watch Output for tick messages |
| TimedEvaluator | Wait for timer, submit item |
| Scoreboard | Submit and watch HUD |
| GlobalTimer | Watch HUD countdown |
| LeaderBoard | Complete round, check in-world display |
| MessageTicker | Dispense item, watch for notification |

## 6.3 Debug Level for Testing

Set in `DebugConfig.lua`:

```lua
-- For full visibility during testing
return {
    Level = 4,
    Filter = {
        enabled = {},
        disabled = {},
    },
}
```

## 6.4 When Tests Fail

1. Check Output window for errors
2. Set debug level to 4 for full visibility
3. Add temporary `System.Debug:Message()` calls if needed
4. Isolate the failing component
5. Fix and re-test full loop

---

# 7. Documentation Procedures

## 7.1 Session Logging

At the end of each significant session, create a log:

**Filename:** `Logs/YYYY-MM-DD_HH-MM-SS_session-log.md` or descriptive name

**Template:**
```markdown
# Session Log: [Date] ([Session N])

## Overview

[1-2 sentence summary of what was accomplished]

## 1. [Major Topic]

### Problem/Goal
[What we were trying to do]

### Solution
[What we did]

### Key Code/Commands
```code blocks```

## N. Files Changed

### New Files
- list

### Modified Files
- list

## Next Steps

1. [What remains to be done]
```

## 7.2 When to Update Core Docs

| Document | Update When |
|----------|-------------|
| ARCHITECTURE.md | Design principles change |
| SYSTEM_REFERENCE.md | APIs change, new assets added |
| PROJECT_JOURNAL.md | Major milestones, significant failures |
| PROCEDURES.md | Workflow improvements discovered |

## 7.3 Code Comments

- **Do:** Comment non-obvious logic
- **Do:** Document public API functions
- **Don't:** Comment obvious code
- **Don't:** Leave TODO comments without context

---

# 8. Debugging Procedures

## 8.1 Boot Failures

**Symptoms:** Game hangs, scripts don't run, players don't spawn

**Procedure:**
1. Check Output for errors during boot
2. Verify `System.Script` runs (look for "Stage SYNC" message)
3. Check for missing dependencies (WaitForChild timeouts)
4. Verify Rojo is connected and synced

## 8.2 Duplicate Execution

**Symptoms:** Events fire twice, duplicate objects, race conditions

**Procedure:**
1. Check for missing name guards in scripts
2. Verify `_ServerScriptService` folder naming
3. Search for scripts that might be running from both locations

## 8.3 Events Not Firing

**Symptoms:** Listeners never trigger, game state doesn't update

**Procedure:**
1. Verify event exists (check ReplicatedStorage in Explorer)
2. Verify event is being fired (add debug message before `:Fire()`)
3. Verify listener is connected (add debug message in handler)
4. Check for typos in event names

## 8.4 Client/Server Mismatch

**Symptoms:** Client shows wrong state, actions don't work

**Procedure:**
1. Check if using RemoteEvent vs BindableEvent correctly
2. Verify client waits for READY stage
3. Check attribute replication (attributes set on server replicate automatically)

## 8.5 Rojo Sync Issues

**Symptoms:** Changes don't appear in Studio

**Procedure:**
1. Disconnect and reconnect Rojo plugin
2. Check Rojo server is running
3. Touch the file to force re-sync: `touch <filepath>`
4. Check `default.project.json` for correct paths

---

# 9. Communication Patterns

## 9.1 Asking Clarifying Questions

When requirements are unclear:

```
I want to confirm the expected behavior:
- When [condition], should it [A] or [B]?
- Should this affect [X]?
- Is there a preference for [approach 1] vs [approach 2]?
```

## 9.2 Proposing Changes

For non-trivial changes:

```
To implement [feature], I'm thinking:

1. [Step 1] - [brief reason]
2. [Step 2] - [brief reason]
3. [Step 3] - [brief reason]

This approach [advantages]. Alternative would be [alternative] but [tradeoff].

Sound good?
```

## 9.3 Reporting Progress

During long tasks:

```
Progress update:
- [x] Completed: [thing 1]
- [x] Completed: [thing 2]
- [ ] In progress: [thing 3]
- [ ] Remaining: [thing 4]

[Any blockers or decisions needed]
```

## 9.4 Reporting Failures

When something doesn't work:

```
Hit an issue with [component]:

**Expected:** [what should happen]
**Actual:** [what happens]
**Tried:** [what I attempted]

Possible causes:
1. [Theory 1]
2. [Theory 2]

Recommend: [next step to try]
```

## 9.5 User's Communication Style

Based on our work together:

- **Direct** - Get to the point, avoid preamble
- **Technical** - Comfortable with code and architecture discussions
- **Iterative** - Prefers working solutions over perfect solutions
- **Explains reasoning** - Shares the "why" behind decisions
- **Values modularity** - Strong preference for separation of concerns
- **Expects consistency** - Once a pattern is set, it must be followed

---

# 10. Code Standards

## 10.1 File Naming

| Type | Convention | Example |
|------|------------|---------|
| Server scripts | `Script.server.lua` | `Script.server.lua` |
| Client scripts | `LocalScript.client.lua` or `Script.client.lua` | `LocalScript.client.lua` |
| Modules | `ModuleScript.lua` or `<Name>.lua` | `GUI.lua` |
| Physical components | `<Name>.rbxm` | `Anchor.rbxm` |
| Metadata | `init.meta.json` | `init.meta.json` |

## 10.2 Script Structure

```lua
-- [AssetName].[ScriptType] ([Server/Client])
-- [Brief description of purpose]

-- Guard (if in System hierarchy)
if not script.Name:match("^AssetName%.") then
    return
end

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- ... other services

-- Wait for boot
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)  -- or READY for clients

-- Dependencies
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
-- ... other dependencies

-- Constants
local SOME_VALUE = 10

-- Local functions
local function helperFunction()
end

-- Main setup function
local function setupAsset(model)
    -- Configuration
    -- Component lookup
    -- Event connections
    -- Exposed functions
end

-- Initialization
setupAsset(model)
System.Debug:Message("AssetName", "Setup complete")
```

## 10.3 Variable Naming

- **Services:** PascalCase (`ReplicatedStorage`)
- **Constants:** UPPER_SNAKE_CASE (`MAX_CAPACITY`)
- **Functions:** camelCase (`setupDispenser`)
- **Local variables:** camelCase (`itemType`)
- **Loop variables:** short names (`i`, `v`, `k`)

## 10.4 Debug Messages

Format: `System.Debug:Message("Source", "message", variable)`

```lua
-- Good
System.Debug:Message("Dispenser", "Gave", item.Name, "to", player.Name)

-- WRONG - Never do this
print("gave item")  -- No source, not filterable
```

## 10.5 Event Naming

Pattern: `AssetName.EventName`

```lua
-- Good
"Scoreboard.RoundComplete"
"GlobalTimer.TimerExpired"

-- Bad
"RoundComplete"  -- No prefix, could conflict
```

## 10.6 GUI Creation

```lua
-- CORRECT - Using GUI system
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local label = GUI:Create({
    type = "TextLabel",
    class = "hud-text",
    text = "Score: 0",
})

-- WRONG - Never do this
local label = Instance.new("TextLabel")
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 24
label.Font = Enum.Font.GothamBold
```

## 10.7 Asset Positioning and Styling

```lua
-- CORRECT - Declarative positioning via style system
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Define in Styles.lua first:
-- classes = {
--     ["Camper"] = {
--         position = {0, 0.5, 0},
--         rotation = {0, 90, 0},
--     },
-- }

-- Then apply in asset script:
model:SetAttribute("StyleClass", "Camper Camper1")
GUI:StyleAsset(model)

-- WRONG - Manual positioning
model:PivotTo(CFrame.new(10, 0, 5) * CFrame.Angles(0, math.rad(90), 0))
```

### Asset Transform Properties

| Property | Type | Example | Purpose |
|----------|------|---------|---------|
| `position` | `{x, y, z}` | `{10, 2, 5}` | World position offset (studs) |
| `rotation` | `{x, y, z}` | `{0, 90, 0}` | Rotation in **degrees** |
| `offset` | `{x, y, z}` | `{0, 0, -2}` | Local space translation |
| `scale` | `n` or `{x,y,z}` | `1.5` | Requires `AllowScale=true` attribute |

### Scaling Safety

```lua
-- In Studio: Set AllowScale attribute on BasePart first
part:SetAttribute("AllowScale", true)

-- In Styles.lua:
["LargeCrate"] = {
    scale = 1.5,  -- 150% size (uniform)
}
-- OR
["FlatPlatform"] = {
    scale = {2, 0.5, 2},  -- Non-uniform: wide and flat
}

-- Then apply:
part:SetAttribute("StyleClass", "LargeCrate")
GUI:StyleAsset(part)
```

---

# 11. Common Pitfalls

## 11.1 Script Auto-Execution

**Pitfall:** Scripts in `System/` hierarchy run automatically because they're descendants of `ServerScriptService`.

**Prevention:** Always include name guard at top of script.

## 11.2 Stale Instance References

**Pitfall:** Backpack instance becomes stale after character respawn.

**Prevention:** Re-establish connections on `CharacterAdded`.

```lua
player.CharacterAdded:Connect(function()
    local backpack = player:FindFirstChild("Backpack")
    connectToBackpack(player, backpack)
end)
```

## 11.3 Race Conditions on Boot

**Pitfall:** Script tries to access something that doesn't exist yet.

**Prevention:** Use `System:WaitForStage()` before accessing dependencies.

## 11.4 Touch Detection with CanCollide=false

**Pitfall:** `GetTouchingParts()` is unreliable with non-collidable parts.

**Prevention:** Use touch counting pattern (see SYSTEM_REFERENCE.md section 13.6).

## 11.5 Forgetting Name Prefix After Deployment

**Pitfall:** Looking for `ModuleScript` but it's now `Dispenser.ModuleScript`.

**Prevention:** Always use the prefixed name in `WaitForChild()`.

## 11.6 BillboardGui from .rbxm

**Pitfall:** BillboardGui exported from Studio mysteriously doesn't render.

**Prevention:** Create BillboardGuis in code using GUI system instead.

## 11.7 Bypassing Established Systems

**Pitfall:** Writing `Instance.new("TextLabel")` because it "seems faster."

**Prevention:** STOP. Use `GUI:Create()`. The abstraction exists for consistency. See Section 1.1.

## 11.8 Modifying Template While Clones Exist

**Pitfall:** Changes to template don't affect already-cloned instances.

**Prevention:** This is expected behavior. If instances need updating, update them directly or destroy and re-clone.

## 11.9 Blocking WaitForChild Without Timeout

**Pitfall:** `WaitForChild("Thing")` blocks forever if Thing never appears.

**Prevention:** Add timeout for optional dependencies: `WaitForChild("Thing", 10)`

## 11.10 Inline Styling

**Pitfall:** Setting `element.TextColor3 = ...` directly instead of using classes.

**Prevention:** Define style in `Styles.lua`, apply via `class` in definition.

## 11.11 Manual Asset Positioning

**Pitfall:** Hardcoding `model:PivotTo(CFrame.new(...))` or `part.CFrame = ...` in asset scripts.

**Prevention:** Define position/rotation in `Styles.lua`, apply via `GUI:StyleAsset()`.

## 11.12 Forgetting AllowScale Attribute

**Pitfall:** Defining `scale` in styles but part doesn't scale, no visible error.

**Prevention:** Set `AllowScale = true` attribute on BasePart in Studio before applying scale styles. Check Output for warnings.

## 11.13 Applying Scale to Models

**Pitfall:** Trying to scale a Model instance (not currently supported).

**Prevention:** Only apply `scale` to BaseParts. For models, scale individual parts or adjust in Studio.

## 11.14 Rotation in Radians

**Pitfall:** Using `math.rad()` values in style definitions.

**Prevention:** Style system expects **degrees**. Use `{0, 90, 0}` not `{0, 1.57, 0}`.

---

# 12. Decision Framework

## 12.1 When to Create a New Asset vs Extend Existing

**Create New Asset When:**
- Fundamentally different behavior
- Would complicate existing asset significantly
- Reusable in other contexts

**Extend Existing When:**
- Variation on existing behavior
- Shares most code
- Closely related functionality

## 12.2 When to Use BindableEvent vs RemoteEvent

| Use | Type |
|-----|------|
| Server script to server script | BindableEvent |
| Server to all clients | RemoteEvent (FireAllClients) |
| Server to one client | RemoteEvent (FireClient) |
| Client to server | RemoteEvent (FireServer) |

## 12.3 When to Use Attributes vs Events

**Attributes:**
- Simple state that clients need to observe
- Automatically replicates
- Good for: remaining count, current score, time remaining

**Events:**
- One-time notifications
- Need to pass complex data
- Need to trigger specific actions
- Good for: round complete, timer expired, item dispensed

## 12.4 When to Create Events via Code vs Folders

**Folders (Preferred):**
- Event always exists
- Cleaner file structure
- Visible in repo

**Code:**
- Event created conditionally
- Event tied to specific instance lifecycle
- Internal/private events

## 12.5 When to Ask vs Proceed

**Ask First:**
- Architectural decisions
- Deleting/removing features
- Changing public APIs
- Uncertain requirements
- Multiple valid approaches
- Considering bypassing an established pattern

**Proceed:**
- Clear requirements
- Following established patterns
- Bug fixes with obvious solutions
- Implementation details within agreed design

## 12.6 When to Commit

- After each discrete, working change
- Before starting something risky
- When switching to different area of codebase
- At end of session (work in progress is okay)

## 12.7 When to Extend a System vs Work Around It

**ALWAYS extend. NEVER work around.**

If the GUI system doesn't support what you need:
1. Propose adding the capability to the GUI system
2. Implement it in GUI.lua/Styles.lua/etc.
3. Then use the extended system

If the boot system doesn't handle a case:
1. Propose extending the stage system
2. Implement the extension
3. Then use the extended system

The moment you bypass a system "just this once," you've created inconsistency that will haunt future work.

---

# Appendix: Quick Reference Checklists

## New Session Checklist

- [ ] Read most recent session log
- [ ] Check git status for uncommitted changes
- [ ] Verify Rojo connection
- [ ] Confirm understanding with user

## New Asset Checklist

- [ ] Create folder structure
- [ ] Create init.meta.json with className: "Model"
- [ ] **Add copyright boilerplate to all new scripts**
- [ ] Create server script with guard and WaitForStage
- [ ] Create client script if needed (with guard and WaitForStage)
- [ ] **Use GUI system for all UI elements**
- [ ] **Use Styles.lua for all styling (GUI and asset positioning)**
- [ ] **Define asset position/rotation in Styles.lua**
- [ ] **Apply positioning with GUI:StyleAsset()**
- [ ] **Use System.Debug for all logging**
- [ ] Export .rbxm for physical components
- [ ] Set AllowScale attribute if using scale styles
- [ ] Create events via folder structure
- [ ] Test boot completes
- [ ] Test asset functionality
- [ ] Test full gameplay loop
- [ ] Commit with descriptive message

## Pre-Commit Checklist

- [ ] **All new files have copyright boilerplate**
- [ ] Game boots without errors
- [ ] Core gameplay loop works
- [ ] No `print()` or `warn()` calls (use System.Debug)
- [ ] No `Instance.new()` for UI (use GUI:Create)
- [ ] No inline styling (use Styles.lua classes)
- [ ] No manual asset positioning (use GUI:StyleAsset)
- [ ] Asset transforms defined in Styles.lua
- [ ] Debug messages use System.Debug API
- [ ] File names follow conventions
- [ ] Commit message is descriptive

## End of Session Checklist

- [ ] All work committed or saved
- [ ] Session log created (if significant work done)
- [ ] Note any blockers or next steps
- [ ] Update SYSTEM_REFERENCE.md if APIs changed
- [ ] Update PROCEDURES.md if new patterns discovered

## "Am I About to Violate Architecture?" Check

Before writing code, ask:

- [ ] Am I using `Instance.new()` for UI? → Use `GUI:Create()` instead
- [ ] Am I setting GUI properties directly? → Use style classes instead
- [ ] Am I using `model:PivotTo()` or `part.CFrame = ...`? → Use `GUI:StyleAsset()` instead
- [ ] Am I hardcoding asset positions/rotations? → Define in Styles.lua instead
- [ ] Am I using `print()`? → Use `System.Debug:Message()` instead
- [ ] Am I using `Instance.new("BindableEvent")`? → Use folder structure instead
- [ ] Am I hardcoding GUI positions/sizes? → Use Layouts.lua instead
- [ ] Am I waiting with WaitForChild chains? → Use `WaitForStage()` instead

If you answered yes to any: STOP and use the established system.
