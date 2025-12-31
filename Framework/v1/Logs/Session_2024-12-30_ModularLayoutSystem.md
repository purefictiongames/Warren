# Session Recap: Modular Layout System Implementation

**Date:** 2024-12-30

## Overview

Implemented a modular HUD layout system where assets remain independent and layout-agnostic, while the GUI system handles positioning via configuration.

## Problem Statement

The initial approach had assets (GlobalTimer, Scoreboard) placing themselves into layout regions, which required them to be aware of the layout system. The user wanted:
- Each asset to remain modular and self-contained
- Assets to work independently without layout knowledge
- Layout system to handle positioning via configuration
- Style cascade: layout defaults → asset overrides

## Solution Architecture

### 1. Assets Create Standalone GUIs

Assets create their own `ScreenGui` with a `Content` frame wrapper:

```lua
-- GlobalTimer creates its own GUI (no layout knowledge)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GlobalTimer.ScreenGui"

local content = Instance.new("Frame")
content.Name = "Content"  -- Standard wrapper name
content.Parent = screenGui

local timerLabel = GUI:Create({...})
timerLabel.Parent = content

screenGui.Parent = playerGui
```

### 2. Layout Config Defines Asset Mapping

`Layouts.lua` defines which ScreenGuis go into which regions:

```lua
["right-sidebar"] = {
    position = {0.85, 0, 0, 0},
    size = {0.15, 0, 0.4, 0},

    -- Asset-to-region mapping
    assets = {
        ["GlobalTimer.ScreenGui"] = "timer",
        ["Scoreboard.ScreenGui"] = "score",
    },

    rows = {
        { height = "50%", columns = { { id = "timer", ... } } },
        { height = "50%", columns = { { id = "score", ... } } },
    },
}
```

### 3. System.GUI Handles Positioning

The GUI client script creates layouts and repositions asset content:

```lua
-- Creates layout, watches for asset ScreenGuis
playerGui.ChildAdded:Connect(function(child)
    local regionId = assetMapping[child.Name]
    if regionId then
        local content = child:FindFirstChild("Content")
        content.Parent = regions[regionId]  -- Move to layout region
        child.Enabled = false  -- Hide original ScreenGui
    end
end)
```

## Key Decisions

1. **HUD is part of System.GUI** - Not a separate asset, since a HUD is fundamentally a GUI concern

2. **"Content" wrapper convention** - Assets wrap their GUI elements in a Frame named "Content" that the layout system can relocate

3. **ChildAdded with task.defer** - Handles script execution order by listening for assets and deferring positioning

4. **Graceful degradation** - If no layout exists, assets display their standalone ScreenGuis

## Files Changed

### Created/Modified
- `src/System/GUI/StarterPlayerScripts/Script.client.lua` - Added HUD layout system
- `src/System/GUI/ReplicatedFirst/Layouts.lua` - Added `assets` mapping to layout config
- `src/System/GUI/ReplicatedStorage/GUI.lua` - Added `GetRegion`, `HasLayout`, `PlaceInRegion` APIs
- `src/Assets/GlobalTimer/StarterGui/LocalScript.client.lua` - Standalone GUI with Content wrapper
- `src/Assets/Scoreboard/StarterGui/LocalScript.client.lua` - Standalone GUI with Content wrapper

### Deleted
- `src/Assets/HUD/` - Removed separate HUD asset (merged into System.GUI)

## Debug Notes

- HUD debug messages use "System.GUI.client" prefix (shows at Level 2)
- Asset init.meta.json must use `"className": "Model"` not `"Folder"` for deployment
- Boot stage timing: All scripts wait for READY, layout uses `task.defer` to catch assets

## Architecture Benefits

1. **Modularity** - Assets have zero knowledge of layout system
2. **Configurability** - Layout config is declarative, easy to modify
3. **Flexibility** - Assets work standalone or within layouts
4. **Maintainability** - Clear separation of concerns
5. **Extensibility** - Easy to add new assets to layout via config

## Testing Verification

- Timer displays in top region of right sidebar
- Score displays in bottom region of right sidebar
- Debug messages show successful positioning
- Assets can still work without layout (standalone mode)
