> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# LibPureFiction Framework - System Reference

**Version:** 1.0
**Last Updated:** December 30, 2025

A comprehensive technical reference for the LibPureFiction Roblox game framework.

---

# Table of Contents

1. [Quick Start](#1-quick-start)
2. [Architecture Overview](#2-architecture-overview)
3. [Boot System](#3-boot-system)
4. [System Module API](#4-system-module-api)
5. [Asset Development](#5-asset-development)
6. [Template Development](#6-template-development)
7. [GUI System](#7-gui-system)
8. [Subsystems](#8-subsystems)
9. [Event Patterns](#9-event-patterns)
10. [Debug System](#10-debug-system)
11. [Rojo Configuration](#11-rojo-configuration)
12. [File Structure Reference](#12-file-structure-reference)
13. [Common Patterns](#13-common-patterns)

---

# 1. Quick Start

## 1.1 Prerequisites

- Rojo 7.6+ installed
- Roblox Studio with Rojo plugin
- VS Code or preferred editor

## 1.2 Starting a New Session

```bash
cd /path/to/LibPureFiction/Framework/v1
rojo serve
```

In Roblox Studio: Connect to Rojo, then Play.

## 1.3 File Locations

| What | Where |
|------|-------|
| System bootstrap | `src/System/Script.server.lua` |
| Boot stages & API | `src/System/ReplicatedStorage/System.lua` |
| Debug config | `src/System/ReplicatedFirst/DebugConfig.lua` |
| Assets | `src/Assets/<AssetName>/` |
| Templates | `src/Templates/<TemplateName>/` |
| GUI system | `src/System/GUI/` |

---

# 2. Architecture Overview

## 2.1 Core Concept: Self-Bootstrapping Assets

Assets are self-contained units that include their own scripts and events. During boot, the System extracts these to the appropriate Roblox services:

```
src/Assets/Dispenser/
├── init.meta.json              <- Model metadata
├── Anchor.rbxm                 <- Physical component
├── ReplicatedStorage/          <- Extracted to ReplicatedStorage
│   └── ModuleScript.lua
├── StarterGui/                 <- Extracted to StarterGui
│   └── LocalScript.client.lua
└── _ServerScriptService/       <- Extracted to ServerScriptService
    └── Script.server.lua
```

After extraction:
- `Dispenser.ModuleScript` exists in `ReplicatedStorage`
- `Dispenser.LocalScript` exists in `StarterGui`
- `Dispenser.Script` exists in `ServerScriptService`
- Cleaned `Dispenser` Model exists in `Workspace.RuntimeAssets`

## 2.2 Service Folder Mapping

| Folder Name | Extracted To | Runs On |
|-------------|--------------|---------|
| `ReplicatedStorage` | `ReplicatedStorage` | - |
| `_ServerScriptService` | `ServerScriptService` | Server |
| `StarterGui` | `StarterGui` | Client |
| `StarterPlayerScripts` | `StarterPlayer.StarterPlayerScripts` | Client |

**Note:** The underscore prefix (`_ServerScriptService`) prevents scripts from auto-running before extraction.

## 2.3 Boot Flow

```
1. System.Script runs (only auto-running script)
2. Players.CharacterAutoLoads = false (prevent spawning)
3. System bootstraps itself and child modules
4. System deploys Assets to RuntimeAssets
5. Boot stages fire in order: SYNC -> EVENTS -> MODULES -> SCRIPTS -> READY
6. Players.CharacterAutoLoads = true, spawn waiting players
```

## 2.4 Communication Model

Assets communicate via Roblox events, never directly:

```
Server ─── BindableEvent ───> Server
Server ─── RemoteEvent ────> Client
Client ─── RemoteEvent ────> Server
```

---

# 3. Boot System

## 3.1 Boot Stages

```lua
System.Stages = {
    SYNC    = 1,  -- Assets cloned to RuntimeAssets, folders extracted
    EVENTS  = 2,  -- All BindableEvents/RemoteEvents created
    MODULES = 3,  -- ModuleScripts deployed and requireable
    SCRIPTS = 4,  -- Server scripts can run
    READY   = 5,  -- Full boot complete, clients can interact
}
```

## 3.2 Server Script Pattern

```lua
-- Guard: Only run if this is the deployed version
if not script.Name:match("^AssetName%.") then
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Dependencies (guaranteed to exist after SCRIPTS stage)
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("AssetName")

-- Your code here
```

## 3.3 Client Script Pattern

```lua
-- Guard: Only run if this is the deployed version
if not script.Name:match("^AssetName%.") then
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Your code here
```

## 3.4 Why Name Guards?

Scripts in the System folder hierarchy are descendants of `ServerScriptService`, so they auto-run even before extraction. The name guard ensures only the deployed version (with the asset prefix) actually executes:

```lua
-- Original location: System/Backpack/_ServerScriptService/Script
-- script.Name = "Script" -> guard fails, script exits

-- After deployment: ServerScriptService/Backpack.Script
-- script.Name = "Backpack.Script" -> guard passes, script runs
```

## 3.5 Client Ping-Pong Protocol

For late-joining clients:

```
Client: PING -> Server
Server: PONG(currentStage) -> Client
Client: Updates internal stage, unblocks waiting scripts
Client: READY -> Server (confirmation)
```

---

# 4. System Module API

**Location:** `src/System/ReplicatedStorage/System.lua`
**Access:** `require(ReplicatedStorage:WaitForChild("System.System"))`

## 4.1 Stage Constants

```lua
System.Stages.SYNC    -- 1
System.Stages.EVENTS  -- 2
System.Stages.MODULES -- 3
System.Stages.SCRIPTS -- 4
System.Stages.READY   -- 5
```

## 4.2 Stage Methods

### WaitForStage(stage)

Yields until the specified stage is reached.

```lua
System:WaitForStage(System.Stages.SCRIPTS)
-- Execution resumes when SCRIPTS stage fires
```

### GetCurrentStage()

Returns the current stage number (non-blocking).

```lua
local stage = System:GetCurrentStage()
```

### GetStageName(stage)

Returns the human-readable name of a stage.

```lua
local name = System:GetStageName(3)  -- "MODULES"
```

### IsStageReached(stage)

Non-blocking check if a stage has been reached.

```lua
if System:IsStageReached(System.Stages.READY) then
    -- Safe to access client features
end
```

## 4.3 Debug Methods

### System.Debug:Message(source, ...)

Regular debug output. Filtered by debug level.

```lua
System.Debug:Message("Dispenser", "Gave item to", player.Name)
-- Output: Dispenser: Gave item to Player1
```

### System.Debug:Warn(source, ...)

Warning output (yellow in console).

```lua
System.Debug:Warn("Dispenser", "Template not found:", itemType)
```

### System.Debug:Alert(source, ...)

Error/alert output with `[ALERT]` prefix.

```lua
System.Debug:Alert("ZoneController", "Failed to call callback")
-- Output: [ALERT] ZoneController: Failed to call callback
```

---

# 5. Asset Development

## 5.1 Asset Structure

```
src/Assets/<AssetName>/
├── init.meta.json              # Required: className "Model"
├── <Component>.rbxm            # Physical parts (exported from Studio)
├── ReplicatedStorage/          # Shared modules, events
│   ├── <Name>.rbxm             # Events (BindableEvent/RemoteEvent)
│   └── ModuleScript.lua        # Shared code
├── StarterGui/                 # Client UI
│   └── LocalScript.client.lua
└── _ServerScriptService/       # Server logic
    └── Script.server.lua
```

## 5.2 Required init.meta.json

```json
{
  "className": "Model"
}
```

This tells Rojo to create a Model instance, not a Folder. Required for assets that have physical presence in the world.

## 5.3 Creating Events via Folders

Instead of .rbxm, create events with folders:

```
ReplicatedStorage/
└── MyEvent/
    └── init.meta.json
```

Where `init.meta.json` contains:

```json
{
  "className": "BindableEvent"
}
```

Or for RemoteEvent:

```json
{
  "className": "RemoteEvent"
}
```

## 5.4 Model Attributes Pattern

Configure assets via Roblox Attributes (set in Studio):

```lua
local function setupAsset(model)
    local itemType = model:GetAttribute("ItemType") or "Default"
    local capacity = model:GetAttribute("Capacity") or 10

    -- Use configuration
end
```

**Common Attributes:**

| Attribute | Type | Purpose |
|-----------|------|---------|
| Config values | string/number | Asset configuration |
| State values | number | Current state (auto-replicates to clients) |

## 5.5 Exposing Control Functions

Allow external control via BindableFunctions:

```lua
local resetFunction = Instance.new("BindableFunction")
resetFunction.Name = "Reset"
resetFunction.OnInvoke = function()
    -- Reset logic
    return true
end
resetFunction.Parent = model
```

External code calls:

```lua
local resetFn = model:WaitForChild("Reset")
resetFn:Invoke()
```

## 5.6 Complete Server Script Example

```lua
-- Dispenser.Script (Server)
-- Guard
if not script.Name:match("^Dispenser%.") then
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Dependencies
local Dispenser = require(ReplicatedStorage:WaitForChild("Dispenser.ModuleScript"))
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("Dispenser")

-- Setup
local itemType = model:GetAttribute("DispenseItem") or "Marshmallow"
local capacity = model:GetAttribute("Capacity") or 10
local dispenser = Dispenser.new(itemType, capacity)

local anchor = model:FindFirstChild("Anchor")
local prompt = anchor:FindFirstChild("ProximityPrompt")

-- Event handling
prompt.Triggered:Connect(function(player)
    local item = dispenser:dispense()
    if item then
        item.Parent = player.Backpack
        model:SetAttribute("Remaining", dispenser.remaining)
        System.Debug:Message("Dispenser", "Gave", item.Name, "to", player.Name)
    end
end)

-- Expose reset
local resetFn = Instance.new("BindableFunction")
resetFn.Name = "Reset"
resetFn.OnInvoke = function()
    dispenser:refill()
    model:SetAttribute("Remaining", dispenser.remaining)
    return true
end
resetFn.Parent = model

System.Debug:Message("Dispenser", "Setup complete")
```

---

# 6. Template Development

## 6.1 Template vs Asset

| Aspect | Asset | Template |
|--------|-------|----------|
| Purpose | World object | Cloneable item |
| Location | `src/Assets/` | `src/Templates/` |
| Deployed to | `Workspace.RuntimeAssets` | `ReplicatedStorage.Templates` |
| Instance type | Usually Model | Usually Tool |

## 6.2 Template Structure

```
src/Templates/<TemplateName>/
├── init.meta.json              # className: "Tool"
├── Handle.rbxm                 # Required for Tools
├── <callback>/                 # BindableFunction folders
│   └── init.meta.json          # className: "BindableFunction"
└── Script.server.lua           # Template logic
```

## 6.3 Tool Handle Requirement

Roblox Tools require a Part named `Handle`. Create in Studio and export as `.rbxm`.

## 6.4 Callback Pattern (ZoneController Integration)

Templates can expose BindableFunction callbacks that ZoneController invokes:

```lua
-- Marshmallow.Script
local tool = script.Parent
local cookFunction = tool:WaitForChild("cook")

local toastLevel = 0
local maxToastLevel = 100

tool:SetAttribute("ToastLevel", toastLevel)

cookFunction.OnInvoke = function(state)
    local heat = state.heat or 10
    local dt = state.deltaTime or 0.5

    toastLevel = math.min(toastLevel + (heat * dt), maxToastLevel)
    tool:SetAttribute("ToastLevel", toastLevel)

    -- Update visual
    local handle = tool:FindFirstChild("Handle")
    if handle then
        handle.Color = getToastColor(toastLevel)
    end

    return toastLevel
end
```

ZoneController finds and invokes:

```lua
local callback = instance:FindFirstChild("cook")
if callback and callback:IsA("BindableFunction") then
    callback:Invoke(state)
end
```

---

# 7. GUI System

**Location:** `src/System/GUI/`

## 7.1 System Structure

```
System/GUI/
├── ReplicatedFirst/
│   ├── Layouts.lua             # Layout definitions
│   └── Styles.lua              # Style definitions
├── ReplicatedStorage/
│   ├── GUI.lua                 # Main API
│   ├── ElementFactory.lua      # Element creation
│   ├── LayoutBuilder.lua       # Layout construction
│   ├── StyleResolver.lua       # Style cascade
│   ├── StateManager.lua        # State binding
│   └── ValueConverter.lua      # Value conversion
└── StarterPlayerScripts/
    └── Script.client.lua       # Client initialization
```

## 7.2 GUI API Reference

**Access:** `require(ReplicatedStorage:WaitForChild("GUI.GUI"))`

### GUI:Create(definition)

Create a single GUI element from a declarative definition.

```lua
local label = GUI:Create({
    type = "TextLabel",
    class = "hud-text",
    id = "score-display",
    text = "Score: 0",
    size = { 0, 200, 0, 50 },
})
label.Parent = screenGui
```

### GUI:CreateMany(definitions)

Create multiple elements at once.

```lua
local elements = GUI:CreateMany({
    { type = "TextLabel", text = "Label 1" },
    { type = "TextLabel", text = "Label 2" },
})
```

### GUI:CreateLayout(layoutName, content)

Create a layout from Layouts.lua definition.

```lua
local screenGui, regions = GUI:CreateLayout("right-sidebar", {
    timer = timerLabel,
    score = scoreLabel,
})
screenGui.Parent = playerGui
```

### GUI:GetRegion(layoutName, regionId)

Get a region Frame from an active layout.

```lua
local timerRegion = GUI:GetRegion("right-sidebar", "timer")
myElement.Parent = timerRegion
```

### GUI:PlaceInRegion(layoutName, regionId, content)

Place content into a layout region with proper alignment.

```lua
GUI:PlaceInRegion("right-sidebar", "timer", myLabel)
```

### GUI:SetClass(element, className)

Replace all classes on an element.

```lua
GUI:SetClass(label, "warning-text")
```

### GUI:AddClass(element, className)

Add a class to an element.

```lua
GUI:AddClass(label, "highlighted")
```

### GUI:RemoveClass(element, className)

Remove a class from an element.

```lua
GUI:RemoveClass(label, "highlighted")
```

### GUI:HasClass(element, className)

Check if element has a specific class.

```lua
if GUI:HasClass(label, "active") then
    -- ...
end
```

### GUI:ToggleClass(element, className)

Toggle a class on/off.

```lua
GUI:ToggleClass(button, "selected")
```

## 7.3 Definition Properties

```lua
{
    type = "TextLabel",         -- Required: Roblox GUI class
    class = "hud-text",         -- CSS-like class(es), space-separated
    id = "my-element",          -- Unique ID for lookup

    -- Direct properties (lowercase mapped to Roblox properties)
    text = "Hello",
    textColor = Color3.new(1, 1, 1),
    backgroundColor = "#FF0000",     -- Hex colors supported
    size = { 0, 100, 0, 50 },        -- UDim2 as array
    position = { 0.5, 0, 0.5, 0 },
    anchorPoint = { 0.5, 0.5 },      -- Vector2 as array
    font = "GothamBold",             -- Font name as string

    -- Children
    children = {
        { type = "TextLabel", text = "Child" }
    },
}
```

## 7.4 Styles.lua Structure

```lua
return {
    -- Base styles for element types
    base = {
        TextLabel = {
            backgroundColor = "transparent",
            textColor = "#FFFFFF",
            font = "Gotham",
        },
        Frame = {
            backgroundColor = "#000000",
            backgroundTransparency = 0.5,
        },
    },

    -- Class styles (like CSS classes)
    classes = {
        ["hud-text"] = {
            textSize = 24,
            font = "GothamBold",
        },
        ["warning"] = {
            textColor = "#FF0000",
        },
    },

    -- ID styles (highest specificity)
    ids = {
        ["score-display"] = {
            textSize = 36,
        },
    },
}
```

## 7.5 Layouts.lua Structure

```lua
return {
    -- Breakpoint definitions
    breakpoints = {
        desktop = { minWidth = 1200 },
        tablet = { minWidth = 768, maxWidth = 1199 },
        phone = { maxWidth = 767 },
    },

    -- Layout definitions
    ["right-sidebar"] = {
        position = { 0.85, 0, 0, 0 },
        size = { 0.15, 0, 0.4, 0 },

        -- Map asset ScreenGuis to regions
        assets = {
            ["GlobalTimer.ScreenGui"] = "timer",
            ["Scoreboard.ScreenGui"] = "score",
        },

        -- Row/column structure
        rows = {
            { height = "50%", columns = { { id = "timer", align = "center" } } },
            { height = "50%", columns = { { id = "score", align = "center" } } },
        },
    },
}
```

## 7.6 Asset Integration Pattern

Assets create standalone ScreenGuis with a `Content` wrapper:

```lua
-- In asset's LocalScript
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GlobalTimer.ScreenGui"

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.Parent = screenGui

-- Create GUI elements
local timerLabel = GUI:Create({ ... })
timerLabel.Parent = content

screenGui.Parent = playerGui
```

The GUI system watches for these and repositions `Content` into layout regions.

---

# 8. Subsystems

## 8.1 Player Subsystem

**Location:** `src/System/Player/`

Handles player setup on spawn.

### Event Flow

```
PlayerAdded -> Player.Script
    -> CharacterAdded -> Spawn handling
```

## 8.2 Backpack Subsystem

**Location:** `src/System/Backpack/`

Centralized backpack event handling.

### Events

| Event | Direction | Purpose |
|-------|-----------|---------|
| `Backpack.ItemAdded` | Server -> Listeners | Item added to backpack |
| `Backpack.ForceItemDrop` | Any -> Backpack | Drop item on ground |
| `Backpack.ForceItemPickup` | Any -> Backpack | Add item to backpack |

### ItemAdded Payload

```lua
{
    player = Player,
    item = Tool,
}
```

### Usage Example

```lua
-- Listening for items
local itemAdded = ReplicatedStorage:WaitForChild("Backpack.ItemAdded")
itemAdded.Event:Connect(function(data)
    if data.item.Name == "Marshmallow" then
        mountMarshmallow(data.player, data.item)
    end
end)

-- Forcing a drop
local forceDrop = ReplicatedStorage:WaitForChild("Backpack.ForceItemDrop")
forceDrop:Fire({ player = player, item = item })
```

---

# 9. Event Patterns

## 9.1 Event Naming Convention

Events are prefixed with their source asset name:

```
Scoreboard.RoundComplete       -- BindableEvent from Scoreboard
GlobalTimer.TimerExpired       -- BindableEvent from GlobalTimer
GlobalTimer.TimerUpdate        -- RemoteEvent from GlobalTimer
MessageTicker.MessageTicker    -- RemoteEvent for notifications
```

## 9.2 Event Flow Diagram

```
                     ┌─────────────────────────────────────────────┐
                     │                 ORCHESTRATOR                 │
                     │    (Listens to all, coordinates resets)     │
                     └─────────────────────────────────────────────┘
                                          ▲
         ┌────────────────────────────────┼────────────────────────┐
         │                                │                        │
 RoundComplete                    TimerExpired              Dispenser.Empty
         │                                │                        │
    ┌────┴────┐                    ┌──────┴──────┐           ┌─────┴─────┐
    │SCOREBOARD│                   │ GLOBALTIMER │           │ DISPENSER │
    └────┬────┘                    └─────────────┘           └───────────┘
         │
  EvaluationComplete
         │
  ┌──────┴──────┐
  │TIMEDEVALUATOR│
  └─────────────┘
```

## 9.3 BindableEvent Pattern (Server to Server)

```lua
-- Creating (in asset folder structure)
ReplicatedStorage/
└── MyEvent/
    └── init.meta.json   # className: "BindableEvent"

-- Firing
local myEvent = ReplicatedStorage:WaitForChild("AssetName.MyEvent")
myEvent:Fire({ key = "value" })

-- Listening
myEvent.Event:Connect(function(data)
    print(data.key)  -- "value"
end)
```

## 9.4 RemoteEvent Pattern (Server to Client)

```lua
-- Creating (in asset folder structure)
ReplicatedStorage/
└── MyUpdate/
    └── init.meta.json   # className: "RemoteEvent"

-- Server firing to one client
local myUpdate = ReplicatedStorage:WaitForChild("AssetName.MyUpdate")
myUpdate:FireClient(player, { score = 100 })

-- Server firing to all clients
myUpdate:FireAllClients({ timeRemaining = 30 })

-- Client listening
myUpdate.OnClientEvent:Connect(function(data)
    updateHUD(data)
end)
```

---

# 10. Debug System

**Config Location:** `src/System/ReplicatedFirst/DebugConfig.lua`

## 10.1 Debug Levels

| Level | Scope | Use Case |
|-------|-------|----------|
| 1 | System only | Core boot debugging |
| 2 | System + Subsystems | Boot + Player/Backpack (default) |
| 3 | Assets only | Gameplay debugging |
| 4 | Filtered | Fine-grained control |

## 10.2 Configuration

```lua
return {
    Level = 2,  -- Change this to adjust verbosity
    Filter = {
        enabled = {},   -- Patterns to always show
        disabled = {},  -- Patterns to always hide
    },
}
```

## 10.3 Level 4 Filtering

Supports glob patterns:

```lua
return {
    Level = 4,
    Filter = {
        enabled = {
            "System.*",      -- All System sources
            "Dispenser",     -- Specific asset
        },
        disabled = {
            "ZoneController", -- Hide verbose asset
        },
    },
}
```

**Precedence:** enabled > disabled > allow by default

## 10.4 Source Naming Convention

| Category | Pattern | Examples |
|----------|---------|----------|
| Core System | `System`, `System.Script`, `System.client` | Boot stages |
| Subsystems | `System.Player`, `System.Backpack` | Player/item handling |
| Assets (Server) | `AssetName` | `Dispenser`, `ZoneController` |
| Assets (Client) | `AssetName.client` | `Dispenser.client` |
| Templates | `TemplateName` | `Marshmallow` |

---

# 11. Rojo Configuration

**File:** `default.project.json`

## 11.1 Current Configuration

```json
{
  "name": "v1",
  "tree": {
    "$className": "DataModel",

    "ReplicatedFirst": {
      "System": { "$path": "src/System/ReplicatedFirst" },
      "GUI": { "$path": "src/System/GUI/ReplicatedFirst" }
    },

    "ReplicatedStorage": {
      "Assets": { "$path": "src/Assets" },
      "Templates": { "$path": "src/Templates" }
    },

    "ServerScriptService": {
      "System": { "$path": "src/System" }
    },

    "StarterPlayer": {
      "StarterPlayerScripts": {}
    }
  }
}
```

## 11.2 Key Points

- `System` is synced to `ServerScriptService.System`
- `Assets` and `Templates` are synced to `ReplicatedStorage`
- `ReplicatedFirst` contains debug config and GUI configs (loads earliest)
- System's bootstrap extracts service folders to their actual locations

---

# 12. File Structure Reference

## 12.1 Complete Tree

```
Framework/v1/
├── default.project.json
├── wally.toml
├── .gitignore
├── ARCHITECTURE.md
├── README.md
├── PROJECT_JOURNAL.md
├── SYSTEM_REFERENCE.md
├── Logs/                           # Session logs
│
└── src/
    ├── Assets/
    │   ├── Dispenser/
    │   │   ├── init.meta.json
    │   │   ├── Anchor.rbxm
    │   │   ├── ReplicatedStorage/
    │   │   │   └── ModuleScript.lua
    │   │   ├── StarterGui/
    │   │   │   └── LocalScript.client.lua
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   ├── GlobalTimer/
    │   │   ├── init.meta.json
    │   │   ├── ReplicatedStorage/
    │   │   │   ├── TimerUpdate/init.meta.json
    │   │   │   └── TimerExpired/init.meta.json
    │   │   ├── StarterGui/
    │   │   │   └── LocalScript.client.lua
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   ├── LeaderBoard/
    │   │   ├── init.meta.json
    │   │   ├── Billboard.rbxm
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   ├── MessageTicker/
    │   │   ├── init.meta.json
    │   │   ├── ReplicatedStorage/
    │   │   │   └── MessageTicker/init.meta.json
    │   │   └── StarterGui/
    │   │       └── LocalScript.client.lua
    │   │
    │   ├── Orchestrator/
    │   │   ├── init.meta.json
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   ├── RoastingStick/
    │   │   ├── init.meta.json
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   ├── Scoreboard/
    │   │   ├── init.meta.json
    │   │   ├── ReplicatedStorage/
    │   │   │   ├── ScoreUpdate.rbxm
    │   │   │   └── RoundComplete/init.meta.json
    │   │   ├── StarterGui/
    │   │   │   └── LocalScript.client.lua
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   ├── TimedEvaluator/
    │   │   ├── init.meta.json
    │   │   ├── Anchor.rbxm
    │   │   ├── StarterGui/
    │   │   │   └── LocalScript.client.lua
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   └── ZoneController/
    │       ├── init.meta.json
    │       ├── Zone.rbxm
    │       └── _ServerScriptService/
    │           └── Script.server.lua
    │
    ├── Templates/
    │   ├── Marshmallow/
    │   │   ├── init.meta.json
    │   │   ├── Handle.rbxm
    │   │   ├── cook/init.meta.json
    │   │   └── Script.server.lua
    │   │
    │   └── RoastingStick/
    │       ├── init.meta.json
    │       └── Handle.rbxm
    │
    ├── System/
    │   ├── init.meta.json
    │   ├── Script.server.lua           # Main bootstrap
    │   │
    │   ├── ReplicatedFirst/
    │   │   └── DebugConfig.lua
    │   │
    │   ├── ReplicatedStorage/
    │   │   ├── System.lua              # Stage API + Debug
    │   │   ├── BootStage/init.meta.json
    │   │   └── ClientBoot/init.meta.json
    │   │
    │   ├── StarterPlayerScripts/
    │   │   └── System.client.lua       # Client boot handler
    │   │
    │   ├── Player/
    │   │   ├── init.meta.json
    │   │   ├── ReplicatedStorage/
    │   │   │   └── ModuleScript.lua
    │   │   ├── StarterPlayerScripts/
    │   │   │   └── Script.client.lua
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   ├── Backpack/
    │   │   ├── init.meta.json
    │   │   ├── ReplicatedStorage/
    │   │   │   ├── ItemAdded/init.meta.json
    │   │   │   ├── ForceItemDrop/init.meta.json
    │   │   │   └── ForceItemPickup/init.meta.json
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   └── GUI/
    │       ├── init.meta.json
    │       ├── ReplicatedFirst/
    │       │   ├── Layouts.lua
    │       │   └── Styles.lua
    │       ├── ReplicatedStorage/
    │       │   ├── GUI.lua
    │       │   ├── ElementFactory.lua
    │       │   ├── LayoutBuilder.lua
    │       │   ├── StyleResolver.lua
    │       │   ├── StateManager.lua
    │       │   └── ValueConverter.lua
    │       └── StarterPlayerScripts/
    │           └── Script.client.lua
    │
    └── Authentication/                 # Pre-existing, not part of core framework
        ├── Client/
        ├── Server/
        └── Shared/
```

---

# 13. Common Patterns

## 13.1 Creating a New Asset

1. Create folder structure:
```bash
mkdir -p src/Assets/MyAsset/{ReplicatedStorage,StarterGui,_ServerScriptService}
```

2. Create `init.meta.json`:
```json
{
  "className": "Model"
}
```

3. Export physical components from Studio as `.rbxm`

4. Create server script with proper guards and stage wait

5. Create client script if needed (with guards)

6. Test with full gameplay loop

## 13.2 Creating Events Between Assets

```lua
-- In AssetA's server script
local myEvent = Instance.new("BindableEvent")
myEvent.Name = "AssetA.SomethingHappened"
myEvent.Parent = ReplicatedStorage

-- Fire when something happens
myEvent:Fire({ data = "value" })

-- In AssetB's server script
local somethingHappened = ReplicatedStorage:WaitForChild("AssetA.SomethingHappened")
somethingHappened.Event:Connect(function(data)
    -- React to event
end)
```

## 13.3 Attribute-Driven State Replication

Server sets attribute:
```lua
model:SetAttribute("Remaining", count)
```

Client reacts to changes:
```lua
model:GetAttributeChangedSignal("Remaining"):Connect(function()
    local remaining = model:GetAttribute("Remaining")
    updateDisplay(remaining)
end)
```

## 13.4 Lazy Event Loading Pattern

For events that may not exist at script start:

```lua
local messageTicker = nil
task.spawn(function()
    messageTicker = ReplicatedStorage:WaitForChild("MessageTicker.MessageTicker", 10)
end)

-- Later, with nil check
if messageTicker then
    messageTicker:FireClient(player, "Message")
end
```

## 13.5 Timer Generation Pattern

Prevent stale timers from interfering:

```lua
local timerGeneration = 0

local function startTimer()
    timerGeneration = timerGeneration + 1
    local myGeneration = timerGeneration

    task.spawn(function()
        while condition and myGeneration == timerGeneration do
            -- Timer logic
            task.wait(1)
        end

        -- Only execute if still current
        if myGeneration == timerGeneration then
            onTimerComplete()
        end
    end)
end

local function stopTimer()
    timerGeneration = timerGeneration + 1  -- Invalidates running timer
end
```

## 13.6 Touch Counting for Zone Detection

```lua
local touchCounts = {}

zone.Touched:Connect(function(hit)
    local entity = getEntityRoot(hit)
    if entity then
        touchCounts[entity] = (touchCounts[entity] or 0) + 1
        if touchCounts[entity] == 1 then
            onEntityEnter(entity)
        end
    end
end)

zone.TouchEnded:Connect(function(hit)
    local entity = getEntityRoot(hit)
    if entity and touchCounts[entity] then
        touchCounts[entity] = touchCounts[entity] - 1
        if touchCounts[entity] <= 0 then
            touchCounts[entity] = nil
            onEntityExit(entity)
        end
    end
end)
```

## 13.7 ViewportFrame for 3D UI Preview

```lua
local viewportFrame = Instance.new("ViewportFrame")
viewportFrame.Size = UDim2.new(0, 100, 0, 100)
viewportFrame.BackgroundTransparency = 1

-- Clone the object
local preview = object:Clone()
preview.CFrame = CFrame.new(0, 0, 0)
preview.Parent = viewportFrame

-- Create camera
local camera = Instance.new("Camera")
camera.CFrame = CFrame.new(Vector3.new(1, 0.8, 1), Vector3.new(0, 0, 0))
viewportFrame.CurrentCamera = camera
camera.Parent = viewportFrame

-- Add lighting
local light = Instance.new("PointLight")
light.Parent = preview

viewportFrame.Parent = parentFrame
```

---

# Appendix A: Asset Quick Reference

| Asset | Server Script | Client Script | Events Fired | Events Listened |
|-------|---------------|---------------|--------------|-----------------|
| Dispenser | Yes | Yes | `Dispenser.Empty` | - |
| ZoneController | Yes | No | - | - |
| TimedEvaluator | Yes | Yes | `Anchor.EvaluationComplete` | - |
| Scoreboard | Yes | Yes | `Scoreboard.RoundComplete` | `Anchor.EvaluationComplete` |
| GlobalTimer | Yes | Yes | `GlobalTimer.TimerExpired` | - |
| Orchestrator | Yes | No | - | `RoundComplete`, `TimerExpired`, `Dispenser.Empty` |
| LeaderBoard | Yes | No | - | `RoundComplete`, `TimerExpired`, `Dispenser.Empty` |
| RoastingStick | Yes | No | - | `Backpack.ItemAdded` |
| MessageTicker | No | Yes | - | - |

---

# Appendix B: Event Reference

| Event | Type | Source | Payload |
|-------|------|--------|---------|
| `System.BootStage` | BindableEvent | System | `stage` (number) |
| `System.ClientBoot` | RemoteEvent | System | `"PING"` / `"PONG"` |
| `Backpack.ItemAdded` | BindableEvent | Backpack | `{player, item}` |
| `Backpack.ForceItemDrop` | BindableEvent | Any | `{player, item}` |
| `Backpack.ForceItemPickup` | BindableEvent | Any | `{player, item}` |
| `Dispenser.Empty` | BindableEvent | Dispenser | - |
| `Anchor.EvaluationComplete` | BindableEvent | TimedEvaluator | `{submitted, submittedValue, targetValue, score, player, timeRemaining, countdown}` |
| `Scoreboard.RoundComplete` | BindableEvent | Scoreboard | `{player, roundScore, totalScore, timeout}` |
| `Scoreboard.ScoreUpdate` | RemoteEvent | Scoreboard | `{roundScore, totalScore, submitted, submittedValue, targetValue}` |
| `GlobalTimer.TimerExpired` | BindableEvent | GlobalTimer | - |
| `GlobalTimer.TimerUpdate` | RemoteEvent | GlobalTimer | `{timeRemaining, formatted, isRunning}` |
| `MessageTicker.MessageTicker` | RemoteEvent | Any | `message` (string) |

---

# Appendix C: Model Attributes Reference

| Asset | Attribute | Type | Purpose |
|-------|-----------|------|---------|
| Dispenser | `DispenseItem` | string | Template name to clone |
| Dispenser | `Capacity` | number | Max items |
| Dispenser | `Remaining` | number | Current count (state) |
| ZoneController | `MatchCallback` | string | BindableFunction name to find |
| ZoneController | `TickRate` | number | Seconds between callbacks |
| TimedEvaluator | `AcceptType` | string | Item type to accept |
| TimedEvaluator | `EvalTarget` | string | Attribute to read from item |
| TimedEvaluator | `TargetMin` | number | Min random target |
| TimedEvaluator | `TargetMax` | number | Max random target |
| TimedEvaluator | `Countdown` | number | Timer duration |
| TimedEvaluator | `TargetValue` | number | Current target (state) |
| TimedEvaluator | `TimeRemaining` | number | Current countdown (state) |
| TimedEvaluator | `Satisfaction` | number | Customer satisfaction (state) |
| GlobalTimer | `CountdownStart` | number | Duration in M.SS format |
| GlobalTimer | `TimeRemaining` | number | Current seconds (state) |
| Marshmallow | `ToastLevel` | number | Cooking progress (state) |
