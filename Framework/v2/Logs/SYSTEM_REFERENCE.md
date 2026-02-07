> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# Warren Framework - System Reference

**Version:** 2.2
**Last Updated:** January 10, 2026

A comprehensive technical reference for the Warren Roblox game framework.

---

# Table of Contents

1. [Quick Start](#1-quick-start)
2. [Architecture Overview](#2-architecture-overview)
3. [Boot System](#3-boot-system)
4. [System Module API](#4-system-module-api)
5. [Asset Development](#5-asset-development)
6. [Template Development](#6-template-development)
7. [Unified Styling System](#7-unified-styling-system)
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
cd /path/to/Warren/Framework/v1
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
| Styling system | `src/System/GUI/` |
| Styles config | `src/System/GUI/ReplicatedFirst/Styles.lua` |
| Layouts config | `src/System/GUI/ReplicatedFirst/Layouts.lua` |

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
5. Boot stages fire in order: SYNC -> EVENTS -> MODULES -> SCRIPTS -> ASSETS -> ORCHESTRATE -> READY
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

### Server Stages

```lua
System.Stages = {
    SYNC        = 1,  -- Assets cloned to RuntimeAssets, folders extracted
    EVENTS      = 2,  -- All BindableEvents/RemoteEvents created
    MODULES     = 3,  -- ModuleScripts deployed and requireable
    REGISTER    = 4,  -- Server modules register via RegisterModule
    INIT        = 5,  -- All module:init() called
    START       = 6,  -- All module:start() called (also ASSETS for compat)
    ORCHESTRATE = 7,  -- Orchestrator applies initial mode
    READY       = 8,  -- Full boot complete, clients can interact
}
```

### Client Stages (Deterministic Discovery)

```lua
System.ClientStages = {
    WAIT     = 1,  -- Wait for server READY signal
    DISCOVER = 2,  -- System discovers all client ModuleScripts
    INIT     = 3,  -- All client module:init() (topologically sorted)
    START    = 4,  -- All client module:start() (topologically sorted)
    READY    = 5,  -- Client fully ready
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

## 3.3 Client Module Pattern (v1.1 - Recommended)

Client modules are **ModuleScripts** discovered and managed by System. No guards, no WaitForStage, no self-registration needed.

```lua
-- Camera/StarterPlayerScripts/Script.lua (ModuleScript)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local System = require(ReplicatedStorage:WaitForChild("System.System"))

return {
    dependencies = { "GUI.Transition" },  -- Modules that must init before this one

    init = function(self)
        -- Phase 1: Get references, create state
        -- Do NOT connect to events from other modules here
        self.player = Players.LocalPlayer
        self.camera = workspace.CurrentCamera
        self.pendingStyle = nil
    end,

    start = function(self)
        -- Phase 2: Connect events, safe to use dependencies
        -- Dependencies are guaranteed to be initialized
        local transitionEvent = ReplicatedStorage:FindFirstChild("Camera.TransitionCovered")
        if transitionEvent then
            transitionEvent.Event:Connect(function()
                self:applyPendingCamera()
            end)
        end
        System.Debug:Message("Camera.client", "Started")
    end,
}
```

### Key Points

- **File extension**: `.lua` (ModuleScript), not `.client.lua` (LocalScript)
- **No name guard**: System controls when module is required
- **No WaitForStage**: System calls init/start at correct time
- **No RegisterClientModule**: Discovery is automatic
- **Declare dependencies**: Array of module names that must init first

## 3.3.1 Legacy Client Script Pattern (Assets)

Asset client scripts (in StarterGui) still use the LocalScript pattern with guards:

```lua
-- Dispenser/StarterGui/LocalScript.client.lua
if not script.Name:match("^Dispenser%.") then
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Asset-specific UI code
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

For late-joining clients, the server waits until READY before responding:

```
Client: PING -> Server
Server: (waits until READY stage)
Server: PONG(8) -> Client  -- Always responds with READY
Client: Updates internal stage, unblocks WaitForStage
Client: READY -> Server (confirmation)
```

**Important:** The server defers PONG until READY to prevent race conditions. If the server responded with an intermediate stage (e.g., stage 6), the client would wait forever for stage 8.

```lua
-- Server: Script.server.lua
ClientBoot.OnServerEvent:Connect(function(player, message)
    if message == "PING" then
        task.spawn(function()
            while System._currentStage < System.Stages.READY do
                task.wait(0.05)
            end
            ClientBoot:FireClient(player, "PONG", System._currentStage)
        end)
    end
end)
```

## 3.6 Client Module Discovery & Dependency Resolution

The client boot system (v1.1) uses explicit discovery instead of self-registration:

### Discovery Phase

System finds all ModuleScripts in:
- `PlayerScripts` (direct children)
- `PlayerGui` (all descendants, including inside ScreenGuis)

```lua
-- System discovers and requires each ModuleScript
for _, descendant in ipairs(container:GetDescendants()) do
    if descendant:IsA("ModuleScript") then
        local module = require(descendant)
        -- Register with name = descendant.Name
    end
end
```

### Dependency Declaration

Modules declare what they depend on:

```lua
return {
    dependencies = { "GUI.Script", "GUI.Transition" },
    -- ...
}
```

Dependency names must match the **deployed module name** (e.g., `"GUI.Transition"` not just `"Transition"`).

### Topological Sort (Kahn's Algorithm)

System orders modules so dependencies are always initialized first:

```
Example dependency graph:
  GUI.Script (no deps)
  GUI.Transition → depends on GUI.Script
  Camera.Script → depends on GUI.Transition
  Tutorial.LocalScript → depends on GUI.Script

Init order: GUI.Script → GUI.Transition → Camera.Script → Tutorial.LocalScript
```

### Timing Guarantees

- **During DISCOVER**: All modules are found and required
- **During INIT**: `init()` called in topological order (dependencies first)
- **During START**: `start()` called in same order (safe to connect events)

**No timing hacks needed.** If module A depends on module B, B's `start()` completes before A's `start()` is called.

---

# 4. System Module API

**Location:** `src/System/ReplicatedStorage/System.lua`
**Access:** `require(ReplicatedStorage:WaitForChild("System.System"))`

## 4.1 Stage Constants

### Server Stages

```lua
System.Stages.SYNC        -- 1
System.Stages.EVENTS      -- 2
System.Stages.MODULES     -- 3
System.Stages.REGISTER    -- 4
System.Stages.INIT        -- 5
System.Stages.START       -- 6 (also ASSETS for compat)
System.Stages.ORCHESTRATE -- 7
System.Stages.READY       -- 8
```

### Client Stages

```lua
System.ClientStages.WAIT     -- 1
System.ClientStages.DISCOVER -- 2
System.ClientStages.INIT     -- 3
System.ClientStages.START    -- 4
System.ClientStages.READY    -- 5
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

## 4.3 Client Module Methods (v1.1)

### GetClientModuleOrder()

Returns the topologically sorted list of client module names.

```lua
local order = System:GetClientModuleOrder()
-- { "GUI.Script", "GUI.Transition", "Camera.Script", ... }
```

### IsClientModuleReady(name)

Check if a client module has completed initialization (both init and start).

```lua
if System:IsClientModuleReady("GUI.Transition") then
    -- Safe to use Transition features
end
```

### GetRegisteredClientModules()

Returns array of all registered client module names.

```lua
local modules = System:GetRegisteredClientModules()
for _, name in ipairs(modules) do
    print(name)
end
```

### WaitForClientStage(stage)

Yields until the specified client stage is reached.

```lua
System:WaitForClientStage(System.ClientStages.READY)
-- Client is fully ready
```

### GetClientStageName(stage)

Returns human-readable name of a client stage.

```lua
local name = System:GetClientStageName(2)  -- "DISCOVER"
```

## 4.4 Debug Methods

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

# 4.5 Router API (Message Routing)

**Access:** `System.Router` (available after requiring System.System)

The Router provides centralized message routing between assets, supporting both targeted and static wiring patterns.

## Router:Send(source, message)

Send a message from an asset. Routing depends on message content:

**Targeted Routing** (message has `target` field):
```lua
System.Router:Send(assetName, {
    target = "MarshmallowBag",
    command = "reset",
})
-- Message goes to: MarshmallowBag.Input
```

**Static Wiring** (message has no `target`):
```lua
System.Router:Send(assetName, {
    action = "gameStarted",
})
-- Message goes to all destinations wired from assetName.Output in GameManifest
```

## Router:SetContext(key, value)

Set context values for rule-based filtering:

```lua
System.Router:SetContext("gameActive", true)
System.Router:SetContext("currentWave", 3)
```

## Router:AddRule(rule)

Add a filtering rule. Messages matching the rule are only routed if the condition returns true:

```lua
System.Router:AddRule({
    action = "camperFed",
    condition = function(ctx)
        return ctx.gameActive == true
    end,
})
```

## GameManifest Wiring Configuration

Static routes are defined in `System/ReplicatedStorage/GameManifest.lua`:

```lua
wiring = {
    -- Action-based events (no target field)
    { from = "Orchestrator.Output", to = "WaveController.Input" },
    { from = "CampPlacer.Output", to = "WaveController.Input" },
    { from = "CampPlacer.Output", to = "Scoreboard.Input" },
    { from = "Scoreboard.Output", to = "LeaderBoard.Input" },

    -- System events
    { from = "RunModes.ModeChanged", to = "Orchestrator.Input" },
}
```

---

# 4.6 Visibility API

**Access:** `require(ReplicatedStorage:WaitForChild("System.Visibility"))`

Utilities for model visibility, anchor resolution, and physics binding.

## Visibility.hideModel(model)

Hide all visual/audio elements in a model. Stores original values in attributes for restoration.

```lua
Visibility.hideModel(camperModel)
-- Sets Transparency=1, CanCollide=false, CanTouch=false
-- Disables particles, lights, stops sounds
-- Original values stored in VisibleTransparency, VisibleCanCollide, etc.
```

## Visibility.showModel(model)

Restore model visibility from stored attributes.

```lua
Visibility.showModel(camperModel)
-- Restores all properties from stored attributes
```

## Visibility.isHidden(model)

Check if a model is currently hidden.

```lua
if Visibility.isHidden(model) then
    Visibility.showModel(model)
end
```

## Visibility.resolveAnchor(model)

Resolve the anchor part for a model. Returns `anchor, isBodyPart`.

**Resolution order:**
1. `AnchorPart` attribute (e.g., `"Head"`) - explicit body part
2. Literal `"Anchor"` child part - dedicated anchor
3. Auto-detect for Humanoids - prefers Head, falls back to HumanoidRootPart

```lua
local anchor, isBodyPart = Visibility.resolveAnchor(model)

if isBodyPart then
    -- Body part (e.g., Head): keep visible, allow interactions
    anchor.CanTouch = true
else
    -- Dedicated Anchor: make invisible, non-collideable
    anchor.Anchored = true
    anchor.Transparency = 1
    anchor.CanCollide = false
end
```

**Use cases:**
- Static assets: Use dedicated "Anchor" part
- Humanoid NPCs: Auto-detect Head as anchor (HUD follows NPC naturally)
- Configurable: Set `AnchorPart` attribute to specify any body part

## Visibility.bindToAnchor(model, options)

Bind model parts to follow the Anchor using physics constraints. For Humanoids, this function returns early (they handle their own physics).

```lua
local constraints = Visibility.bindToAnchor(model, {
    responsiveness = 200,  -- How quickly parts follow
    maxForce = math.huge,  -- Force limit
})
```

## Visibility.unbindFromAnchor(model)

Remove all anchor bindings from a model.

```lua
Visibility.unbindFromAnchor(model)
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
| `StyleClass` | string | Space-separated style classes for positioning |
| `StyleId` | string | Unique style ID (optional, defaults to Name) |
| `AllowScale` | boolean | Allow style system to scale this part |

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

## 5.6 Asset Positioning with Styles

Assets can be positioned declaratively using the styling system:

```lua
-- In asset server script, after model is deployed
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Set style class on the model
model:SetAttribute("StyleClass", "Camper Camper1")

-- Apply transform styles (position, rotation from Styles.lua)
GUI:StyleAsset(model)

System.Debug:Message("Camper", "Positioned via style system")
```

See [Section 7: Unified Styling System](#7-unified-styling-system) for details.

## 5.7 Complete Server Script Example

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

-- Apply positioning styles (optional)
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
model:SetAttribute("StyleClass", "Dispenser")
GUI:StyleAsset(model)

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

# 7. Unified Styling System

**Location:** `src/System/GUI/`

The styling system provides a single declarative language for styling both GUI elements and 3D assets (Models, Parts, Attachments). Same selectors, same cascade rules, different property domains.

## 7.1 System Architecture

```
System/GUI/
├── ReplicatedFirst/
│   ├── Layouts.lua             # Layout definitions
│   └── Styles.lua              # Style definitions (GUI + Asset)
├── ReplicatedStorage/
│   ├── GUI.lua                 # Main API
│   ├── DomainAdapter.lua       # Adapter interface
│   ├── GuiAdapter.lua          # GUI domain handler
│   ├── AssetAdapter.lua        # Asset domain handler (transforms)
│   ├── StyleEngine.lua         # Unified style resolution
│   ├── ElementFactory.lua      # GUI element creation
│   ├── LayoutBuilder.lua       # Layout construction
│   ├── StyleResolver.lua       # Style cascade
│   ├── StateManager.lua        # State binding
│   └── ValueConverter.lua      # Value conversion
└── StarterPlayerScripts/
    └── Script.client.lua       # Client initialization
```

### Domain Adapters

The system uses **domain adapters** to apply styles to different instance types:

- **GuiAdapter**: Handles GuiObject properties (Size, Position, TextColor, etc.)
- **AssetAdapter**: Handles 3D transform properties (position, rotation, scale, etc.)

Both domains share:
- Same selector syntax (type, `.class`, `#id`)
- Same cascade order (base → class → id → inline)
- Same value syntax (`{x, y, z}` arrays)
- Same style resolution algorithm

## 7.2 GUI API Reference

**Access:** `require(ReplicatedStorage:WaitForChild("GUI.GUI"))`

### GUI Element Creation

#### GUI:Create(definition)

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

#### GUI:CreateMany(definitions)

Create multiple elements at once.

```lua
local elements = GUI:CreateMany({
    { type = "TextLabel", text = "Label 1" },
    { type = "TextLabel", text = "Label 2" },
})
```

### Layout Management

#### GUI:CreateLayout(layoutName, content)

Create a layout from Layouts.lua definition.

```lua
local screenGui, regions = GUI:CreateLayout("right-sidebar", {
    timer = timerLabel,
    score = scoreLabel,
})
screenGui.Parent = playerGui
```

#### GUI:GetRegion(layoutName, regionId)

Get a region Frame from an active layout.

```lua
local timerRegion = GUI:GetRegion("right-sidebar", "timer")
myElement.Parent = timerRegion
```

#### GUI:PlaceInRegion(layoutName, regionId, content)

Place content into a layout region with proper alignment.

```lua
GUI:PlaceInRegion("right-sidebar", "timer", myLabel)
```

### Runtime Style Manipulation (GUI)

#### GUI:SetClass(element, className)

Replace all classes on an element.

```lua
GUI:SetClass(label, "warning-text")
```

#### GUI:AddClass(element, className)

Add a class to an element.

```lua
GUI:AddClass(label, "highlighted")
```

#### GUI:RemoveClass(element, className)

Remove a class from an element.

```lua
GUI:RemoveClass(label, "highlighted")
```

#### GUI:HasClass(element, className)

Check if element has a specific class.

```lua
if GUI:HasClass(label, "active") then
    -- ...
end
```

#### GUI:ToggleClass(element, className)

Toggle a class on/off.

```lua
GUI:ToggleClass(button, "selected")
```

### Asset Styling (NEW)

#### GUI:StyleAsset(asset, inlineStyles)

Apply styles to a single 3D asset (Model, BasePart, Attachment).

```lua
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local model = workspace.RuntimeAssets.Dispenser

-- Set style class via attribute
model:SetAttribute("StyleClass", "Dispenser")

-- Apply styles from Styles.lua
GUI:StyleAsset(model)

-- Or with inline style overrides
GUI:StyleAsset(model, {
    position = {5, 0, 10},  -- Override X, Z position
})
```

**Reads from attributes:**
- `StyleClass` - Space-separated class names
- `StyleId` - Unique ID (optional, defaults to instance Name)

#### GUI:StyleAssetTree(rootAsset, inlineStyles)

Apply styles to an entire asset tree (root + all descendants).

```lua
-- Style model and all child parts
GUI:StyleAssetTree(model)
```

Each descendant gets its own style resolution based on its `StyleClass` and `StyleId` attributes.

## 7.3 Style Definition Properties

### GUI Properties

```lua
{
    type = "TextLabel",         -- Required: Roblox GUI class
    class = "hud-text",         -- CSS-like class(es), space-separated
    id = "my-element",          -- Unique ID for lookup

    -- Direct properties (lowercase mapped to Roblox properties)
    text = "Hello",
    textColor = {255, 255, 255},     -- Color3 as RGB 0-255
    backgroundColor = {20, 20, 20},
    textSize = 24,
    font = "GothamBold",             -- Font name as string
    size = { 0, 100, 0, 50 },        -- UDim2 as array
    position = { 0.5, 0, 0.5, 0 },
    anchorPoint = { 0.5, 0.5 },      -- Vector2 as array

    -- UI modifiers (create child instances)
    cornerRadius = 12,               -- Creates UICorner
    stroke = { color = {255,255,255}, thickness = 2 },  -- Creates UIStroke
    padding = { all = 8 },           -- Creates UIPadding
    listLayout = { direction = "Vertical" },  -- Creates UIListLayout

    -- Children
    children = {
        { type = "TextLabel", text = "Child" }
    },
}
```

### Asset Properties (NEW)

```lua
{
    -- Transform properties (for Models, BaseParts, Attachments)
    position = {x, y, z},       -- Vector3: world position offset
    rotation = {x, y, z},       -- Vector3: rotation in DEGREES
    pivot = CFrame,             -- Explicit pivot CFrame (advanced)
    offset = {x, y, z},         -- Vector3: local space offset after rotation
    scale = {x, y, z},          -- Vector3 or number: scale multiplier

    -- Note: Scale requires AllowScale=true attribute on BasePart
}
```

## 7.4 Styles.lua Structure

```lua
return {
    -- Base styles applied to all elements of a type
    base = {
        -- GUI base styles
        TextLabel = {
            backgroundTransparency = 1,
            font = "SourceSans",
            textColor = {255, 255, 255},
        },
        Frame = {
            backgroundTransparency = 0.1,
            backgroundColor = {30, 30, 30},
        },

        -- Asset base styles (NEW)
        Model = {
            -- Defaults for all models
        },
        BasePart = {
            -- Defaults for all parts
        },
    },

    -- Class styles (like CSS classes)
    classes = {
        -- GUI classes
        ["hud-text"] = {
            textSize = 24,
            font = "GothamBold",
        },

        -- Asset classes (NEW)
        ["Camper"] = {
            position = {0, 0.5, 0},  -- Y=0.5 studs above ground
        },
        ["Camper1"] = {
            rotation = {0, 0, 0},     -- Face north (0 degrees)
        },
        ["Camper2"] = {
            rotation = {0, 90, 0},    -- Face east (90 degrees)
        },
        ["Dispenser"] = {
            position = {0, 1, 0},     -- Y=1 stud above ground
            rotation = {0, 0, 0},
        },
        ["Crate"] = {
            scale = {1.2, 1.2, 1.2},  -- 120% size (requires AllowScale attribute)
        },
    },

    -- ID styles (highest specificity)
    ids = {
        ["main-dispenser"] = {
            position = {10, 2, 5},    -- Specific position override
        },
    },
}
```

## 7.5 Value Conversion Reference

The system automatically converts array syntax to Roblox types:

### GUI Value Types

| Input | Converts To | Example |
|-------|-------------|---------|
| `{s, o, s, o}` | `UDim2` | `{0.5, 0, 0.5, 0}` |
| `{r, g, b}` | `Color3` | `{255, 170, 0}` (0-255 range) |
| `{x, y}` | `Vector2` | `{0.5, 0.5}` |
| `"FontName"` | `Enum.Font` | `"GothamBold"` |
| `"Left"` | Alignment Enum | `"Center"`, `"Right"` |

### Asset Value Types (NEW)

| Property | Input | Converts To | Notes |
|----------|-------|-------------|-------|
| `position` | `{x, y, z}` | `Vector3` | World position offset |
| `rotation` | `{x, y, z}` | `Vector3` | **Degrees** (converted to radians internally) |
| `offset` | `{x, y, z}` | `Vector3` | Local space translation |
| `scale` | `{x, y, z}` or `n` | `Vector3` | Uniform: `1.5`, Non-uniform: `{2, 1, 2}` |
| `pivot` | `CFrame` | `CFrame` | Explicit pivot (advanced) |

## 7.6 Transform Composition Rules

When multiple transform properties are specified, they're applied in this order:

1. **Base CFrame**: Start from current transform (or explicit `pivot`)
2. **Position**: Apply world position offset (`+position`)
3. **Rotation**: Apply rotation (`* CFrame.Angles(...)`)
4. **Offset**: Apply local space translation (`* CFrame.new(offset)`)
5. **Scale**: Apply to BasePart.Size (separate, idempotent)

Example:

```lua
["WeaponRack"] = {
    position = {10, 0, 5},    -- Move to (10, 0, 5)
    rotation = {0, 45, 0},    -- Rotate 45° around Y axis
    offset = {0, 0, -2},      -- Move 2 studs forward in local space
}
```

## 7.7 Scaling System

Asset scaling is **opt-in** for safety:

1. Set `AllowScale = true` attribute on the BasePart in Studio
2. Define `scale` property in styles
3. System stores baseline size in `__StyleBaseSize` attribute
4. Repeated applications are idempotent (always compute from baseline)

```lua
-- In Styles.lua
["Crate"] = {
    scale = 1.5,  -- Uniform 150% scale
}

-- Or non-uniform
["FlatPlatform"] = {
    scale = {2, 0.5, 2},  -- Wide and flat
}
```

**Warning:** If `AllowScale` attribute is not set, scale will be blocked with a debug warning.

## 7.8 Selector Matching

Both GUI and Asset domains use the same selector syntax:

### Type Selector

Matches by `ClassName`:

```lua
base = {
    TextLabel = { ... },  -- All TextLabels
    Model = { ... },      -- All Models
    BasePart = { ... },   -- All BaseParts
}
```

### Class Selector

Matches by `StyleClass` attribute:

```lua
classes = {
    ["hud-text"] = { ... },  -- Elements with class "hud-text"
    ["Camper"] = { ... },    -- Assets with class "Camper"
}
```

Space-separated classes apply in order:

```lua
-- Attribute: StyleClass = "Camper Camper1"
-- Applies: base.Model → classes.Camper → classes.Camper1
```

### ID Selector

Matches by `StyleId` attribute:

```lua
ids = {
    ["main-dispenser"] = { ... },  -- Element/Asset with id="main-dispenser"
}
```

For assets, `StyleId` defaults to instance `Name` if not set.

## 7.9 Cascade Order (Specificity)

Styles are resolved in this order (later overrides earlier):

1. **Base** (by type)
2. **Classes** (in order from attribute string)
3. **ID**
4. **Inline** (passed to StyleAsset/Create)

Example:

```lua
-- Styles.lua
base = {
    Model = { position = {0, 0, 0} }
}
classes = {
    ["Camper"] = { position = {0, 1, 0} },
    ["Camper1"] = { rotation = {0, 0, 0} }
}
ids = {
    ["special-camper"] = { position = {5, 1, 0} }
}

-- Asset with: StyleClass = "Camper Camper1", StyleId = "special-camper"
-- Final computed style:
--   position = {5, 1, 0}      (from ID, highest specificity)
--   rotation = {0, 0, 0}      (from class Camper1)
```

## 7.10 Layouts.lua Structure

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

## 7.11 GUI Asset Integration Pattern

Assets create standalone ScreenGuis with a `Content` wrapper:

```lua
-- In asset's LocalScript
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GlobalTimer.ScreenGui"

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.Parent = screenGui

-- Create GUI elements using style system
local timerLabel = GUI:Create({
    type = "TextLabel",
    class = "hud-value",
    text = "0:00",
})
timerLabel.Parent = content

screenGui.Parent = playerGui
```

The GUI system watches for these and repositions `Content` into layout regions.

## 7.12 Complete Asset Styling Example

```lua
-- Camper.Script (Server)
if not script.Name:match("^Camper%.") then return end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local runtimeAssets = workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("Camper")

-- Set up asset functionality
local prompt = model.Anchor.ProximityPrompt
prompt.Triggered:Connect(function(player)
    -- Handle interaction
end)

-- Apply declarative positioning via style system
model:SetAttribute("StyleClass", "Camper Camper1")  -- Position + rotation
GUI:StyleAsset(model)

System.Debug:Message("Camper", "Initialized and positioned")
```

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

## 8.3 RunModes Subsystem

**Location:** `src/System/RunModes/`

Per-player game mode state machine.

### Modes

- **standby** - Player exploring, game inactive
- **practice** - Game active with guidance, scores don't persist
- **play** - Full game, scores persist, badges awarded

### Configuration

`RunModesConfig.lua` defines asset and input behavior per mode:

```lua
{
    standby = {
        assets = {
            Camper = { active = true },
            Dispenser = { active = false },
            -- ...
        },
        input = {
            prompts = { "Camper" },
            gameControls = false,
        },
    },
    practice = {
        assets = {
            RoastingStick = { active = true },
            Dispenser = { active = true },
            -- ...
        },
        input = {
            prompts = { "Dispenser", "TimedEvaluator" },
            gameControls = true,
        },
    },
}
```

### API

```lua
local RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))

-- Get player's current mode
local mode = RunModes:GetMode(player)  -- "standby", "practice", "play"

-- Set player's mode
RunModes:SetMode(player, "practice")

-- Listen for mode changes
local modeChanged = ReplicatedStorage:WaitForChild("RunModes.ModeChanged")
modeChanged.Event:Connect(function(player, newMode, oldMode)
    -- React to mode change
end)
```

## 8.4 Input Subsystem

**Location:** `src/System/Input/`

Manages per-player input state (ProximityPrompts, modals).

### Features

- Per-player allowed ProximityPrompts (controlled by RunModes config)
- Modal stack tracking (disables world input when modal active)
- Server-authoritative state with client synchronization

### API

```lua
-- Server-side: Check if prompt should be active
local InputManager = require(ReplicatedStorage:WaitForChild("Input.InputManager"))
if InputManager:IsPromptAllowed(player, "Dispenser") then
    -- Activate prompt for this player
end

-- Server-side: Push/pop modals
local pushModal = ReplicatedStorage:WaitForChild("Input.PushModal")
pushModal:Invoke(player, "tutorial-popup")

local popModal = ReplicatedStorage:WaitForChild("Input.PopModal")
popModal:Invoke(player, "tutorial-popup")
```

## 8.5 Tutorial Subsystem

**Location:** `src/System/Tutorial/`

Guides new players through game mechanics.

### States

- `inactive` - Not started
- `completed` - Already finished tutorial
- `rules` - Showing rules popup
- `mode_select` - Choosing practice/play mode
- `practice` - In practice mode with task list

### Integration

- Listens to Camper interaction to start tutorial
- Uses Modal system for popups
- Tracks task completion
- Transitions players to practice mode
- Resets when returning to standby

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
├── Logs/                           # Documentation and session logs
│   ├── SYSTEM_REFERENCE.md         # This file
│   ├── PROCEDURES.md               # Operational procedures
│   ├── STYLING_SYSTEM.md           # Comprehensive styling guide
│   ├── PROJECT_JOURNAL.md          # Development history
│   └── SESSION_*.md                # Session-specific logs
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
    │   ├── Scoreboard/
    │   ├── TimedEvaluator/
    │   ├── ZoneController/
    │   ├── Orchestrator/
    │   ├── Camper/
    │   ├── LeaderBoard/
    │   ├── MessageTicker/
    │   └── RoastingStick/
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
    │   │   ├── System.lua              # Stage API, discovery, topological sort
    │   │   ├── Debug.lua               # Debug system (bootstrapped first)
    │   │   ├── Visibility.lua          # Visibility utilities
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
    │   ├── RunModes/
    │   │   ├── init.meta.json
    │   │   ├── ReplicatedFirst/
    │   │   │   └── RunModesConfig.lua
    │   │   ├── ReplicatedStorage/
    │   │   │   ├── RunModes.lua
    │   │   │   ├── ModeChanged/init.meta.json
    │   │   │   └── ModeRequest/init.meta.json
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   ├── Input/
    │   │   ├── init.meta.json
    │   │   ├── ReplicatedStorage/
    │   │   │   ├── InputManager.lua
    │   │   │   ├── StateChanged/init.meta.json (RemoteEvent)
    │   │   │   ├── PushModalRemote/init.meta.json
    │   │   │   ├── PopModalRemote/init.meta.json
    │   │   │   ├── PushModal/init.meta.json (BindableFunction)
    │   │   │   ├── PopModal/init.meta.json (BindableFunction)
    │   │   │   └── IsPromptAllowed/init.meta.json (BindableFunction)
    │   │   ├── StarterPlayerScripts/
    │   │   │   └── Script.client.lua
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   ├── Tutorial/
    │   │   ├── init.meta.json
    │   │   ├── StarterGui/
    │   │   │   └── LocalScript.client.lua
    │   │   └── _ServerScriptService/
    │   │       └── Script.server.lua
    │   │
    │   └── GUI/
    │       ├── init.meta.json
    │       ├── ReplicatedFirst/
    │       │   ├── Layouts.lua
    │       │   └── Styles.lua
    │       ├── ReplicatedStorage/
    │       │   ├── GUI.lua              # Main API
    │       │   ├── DomainAdapter.lua    # Adapter interface
    │       │   ├── GuiAdapter.lua       # GUI domain
    │       │   ├── AssetAdapter.lua     # Asset domain (NEW)
    │       │   ├── StyleEngine.lua      # Unified resolution (NEW)
    │       │   ├── ElementFactory.lua
    │       │   ├── LayoutBuilder.lua
    │       │   ├── StyleResolver.lua
    │       │   ├── StateManager.lua
    │       │   ├── ValueConverter.lua
    │       │   └── Modal.lua
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

6. Apply positioning styles (optional):
```lua
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
model:SetAttribute("StyleClass", "MyAsset")
GUI:StyleAsset(model)
```

7. Test with full gameplay loop

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

## 13.8 Declarative Asset Positioning (NEW)

Position multiple assets in a circular arrangement:

```lua
-- In Styles.lua
classes = {
    ["CircleFormation"] = {
        position = {0, 0, 0},  -- Center position
    },
    ["North"] = { rotation = {0, 0, 0} },
    ["East"] = { rotation = {0, 90, 0} },
    ["South"] = { rotation = {0, 180, 0} },
    ["West"] = { rotation = {0, 270, 0} },
}

-- In asset server scripts
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Position campers in circle
local camper1 = runtimeAssets.Camper1
camper1:SetAttribute("StyleClass", "CircleFormation North")
GUI:StyleAsset(camper1, { position = {0, 0, -10} })  -- Inline override for radius

local camper2 = runtimeAssets.Camper2
camper2:SetAttribute("StyleClass", "CircleFormation East")
GUI:StyleAsset(camper2, { position = {10, 0, 0} })
```

## 13.9 Idempotent Scaling (NEW)

Scale parts safely with repeated applications:

```lua
-- Set AllowScale attribute in Studio first!
part:SetAttribute("AllowScale", true)

-- In Styles.lua
classes = {
    ["LargeCrate"] = {
        scale = 1.5,  -- 150% size
    },
}

-- In asset script
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
part:SetAttribute("StyleClass", "LargeCrate")
GUI:StyleAsset(part)
-- Applying multiple times won't drift - always 1.5x baseline
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
| Camper | Yes | No | - | `RunModes.ModeChanged` |

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
| `RunModes.ModeChanged` | BindableEvent | RunModes | `{player, newMode, oldMode}` |
| `Input.StateChanged` | RemoteEvent | Input | `{allowedPrompts, modalStack}` |

---

# Appendix C: Model Attributes Reference

| Asset | Attribute | Type | Purpose |
|-------|-----------|------|---------|
| **All Assets** | `StyleClass` | string | Space-separated style classes (NEW) |
| **All Assets** | `StyleId` | string | Unique style ID (NEW, optional) |
| **BaseParts** | `AllowScale` | boolean | Allow style system scaling (NEW) |
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

---

# Appendix D: Style Property Reference (NEW)

## GUI Properties

| Property | Type | Example | Roblox Property |
|----------|------|---------|-----------------|
| `size` | UDim2 array | `{0.5, 0, 0.5, 0}` | `Size` |
| `position` | UDim2 array | `{0.5, 0, 0.5, 0}` | `Position` |
| `anchorPoint` | Vector2 array | `{0.5, 0.5}` | `AnchorPoint` |
| `backgroundColor` | Color3 array | `{20, 20, 20}` | `BackgroundColor3` |
| `textColor` | Color3 array | `{255, 255, 255}` | `TextColor3` |
| `textSize` | number | `24` | `TextSize` |
| `font` | string | `"GothamBold"` | `Font` (enum) |
| `text` | string | `"Hello"` | `Text` |
| `visible` | boolean | `true` | `Visible` |
| `cornerRadius` | number/UDim | `12` | UICorner child |
| `stroke` | table | `{color={255,255,255}, thickness=2}` | UIStroke child |
| `padding` | number/table | `8` or `{all=8}` | UIPadding child |

## Asset Properties (NEW)

| Property | Type | Example | Notes |
|----------|------|---------|-------|
| `position` | Vector3 array | `{10, 2, 5}` | World position offset (studs) |
| `rotation` | Vector3 array | `{0, 90, 0}` | Rotation in **degrees** (XYZ) |
| `pivot` | CFrame | `CFrame.new(...)` | Explicit pivot (advanced) |
| `offset` | Vector3 array | `{0, 0, -2}` | Local space translation |
| `scale` | number or Vector3 | `1.5` or `{2, 1, 2}` | Requires `AllowScale=true` |

---

**End of System Reference**
