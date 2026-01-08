> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# Session Log - Input & Visibility Refactor

**Date:** January 8, 2026
**Duration:** Extended session (with context continuation)
**Outcome:** All 4 phases implemented and tested successfully

---

## Overview

Implemented a comprehensive refactor addressing architectural gaps identified in PROJECT_JOURNAL.md:
1. **Phase 1:** Extract duplicated visibility code to shared utility
2. **Phase 2:** Standardize Enable/Disable protocol across assets
3. **Phase 3:** Create centralized InputManager with per-player ProximityPrompt control
4. **Phase 4:** Build reusable Modal system integrated with InputManager

---

## Files Created

### `src/System/ReplicatedStorage/Visibility.lua`
Shared visibility utilities replacing duplicated code in 3 assets.

**Key Functions:**
- `Visibility.hideModel(model)` - Sets all BaseParts to Transparency=1, stores original in `VisibleTransparency` attribute
- `Visibility.showModel(model)` - Restores original transparency from attribute

### `src/System/Input/init.meta.json`
Rojo metadata for Input subsystem folder.

### `src/System/Input/ReplicatedStorage/InputManager.lua`
Centralized input state management module.

**Key Features:**
- Per-player input state tracking (allowed prompts, modal stack)
- `InputManager:IsPromptAllowed(player, assetName)` - Check if prompt should be active
- Internal methods for server-side state management (`_initPlayer`, `_cleanupPlayer`, `_setAllowedPrompts`, `_pushModal`, `_popModal`)

### `src/System/Input/_ServerScriptService/Script.server.lua`
Server-side input coordination.

**Key Features:**
- Listens for RunModes.ModeChanged events
- Applies input config from RunModesConfig to each player
- Creates communication channels:
  - `Input.StateChanged` (RemoteEvent) - Server→Client state updates
  - `Input.PushModalRemote` / `Input.PopModalRemote` (RemoteEvents) - Client→Server modal requests
  - `Input.PushModal` / `Input.PopModal` (BindableFunctions) - Server→Server modal control
  - `Input.IsPromptAllowed` (BindableFunction) - Server-side prompt check

### `src/System/Input/StarterPlayerScripts/Script.client.lua`
Client-side input state receiver.

**Key Features:**
- Listens for `Input.StateChanged` events
- Logs state updates for debugging

### `src/System/GUI/ReplicatedStorage/Modal.lua`
Reusable modal dialog system.

**Key Features:**
- `Modal.new(config)` - Create modal instance with title, body, buttons
- `Modal:Show()` / `Modal:Hide()` / `Modal:Destroy()` - Lifecycle management
- `Modal.Alert(title, message, callback)` - Quick alert dialog
- `Modal.Confirm(title, message, onConfirm, onCancel)` - Quick confirm dialog
- Automatic gamepad navigation (focuses primary button)
- Integration with InputManager via RemoteEvents

### `Logs/QA_TEST_SUITE_Input_Visibility_Refactor.md`
Comprehensive test suite with 24 test cases across all phases.

---

## Files Modified

### `src/Assets/Dispenser/_ServerScriptService/Script.server.lua`
- Added `require` for Visibility module
- Replaced local `hideModel`/`showModel` with `Visibility.hideModel`/`Visibility.showModel`

### `src/Assets/TimedEvaluator/_ServerScriptService/Script.server.lua`
- Added `require` for Visibility module
- Replaced local visibility functions with Visibility module calls
- **Critical Fix:** Removed `reset()` call from `Enable()` function (was causing duplicate timers)

### `src/Assets/Camper/_ServerScriptService/Script.server.lua`
- Added `require` for Visibility module
- Replaced local visibility functions with Visibility module calls

### `src/System/RunModes/ReplicatedFirst/RunModesConfig.lua`
- Added `input` configuration block to each mode:
  - `standby`: prompts = { "Camper" }, gameControls = false
  - `practice`: prompts = { "Dispenser", "TimedEvaluator" }, gameControls = true
  - `play`: prompts = { "Dispenser", "TimedEvaluator" }, gameControls = true

### `src/System/Tutorial/StarterGui/LocalScript.client.lua`
- Refactored `createPopup()` to use Modal system instead of manual UI creation
- Buttons now use Modal's callback system with `closeOnClick = false` (server confirms state change)

---

## Bugs Encountered & Fixed

### Bug 1: Infinite Yield on RunModesConfig Path
**Symptom:** Server script hung on `ReplicatedFirst:WaitForChild("RunModesConfig")`

**Root Cause:** RunModesConfig isn't extracted to ReplicatedFirst during boot. Rojo syncs `src/System` to `ServerScriptService.System`, so the file lives at `ServerScriptService.System.RunModes.ReplicatedFirst.RunModesConfig`.

**Fix:** Changed path in Input server script:
```lua
-- Before (wrong)
local RunModesConfig = require(ReplicatedFirst:WaitForChild("RunModesConfig"))

-- After (correct)
local ServerScriptService = game:GetService("ServerScriptService")
local RunModesConfig = require(ServerScriptService:WaitForChild("System"):WaitForChild("RunModes"):WaitForChild("ReplicatedFirst"):WaitForChild("RunModesConfig"))
```

### Bug 2: Modal Popups Not Transitioning
**Symptom:** Rules popup appeared, but clicking button didn't show mode_select popup.

**Root Cause:** Modal.lua (client) was calling `:Invoke()` on BindableFunctions (`Input.PushModal`/`Input.PopModal`), but BindableFunctions only work for server-to-server communication. Client cannot invoke server BindableFunctions.

**Fix:** Added RemoteEvents for client-to-server communication:
1. Created `Input.PushModalRemote` and `Input.PopModalRemote` RemoteEvents on server
2. Added `OnServerEvent` handlers for these RemoteEvents
3. Updated Modal.lua to use `:FireServer()` instead of `:Invoke()`

```lua
-- Before (Modal.lua - broken)
local pushModal = ReplicatedStorage:FindFirstChild("Input.PushModal")
if pushModal then
    pushModal:Invoke(player, self.id)  -- ERROR: Can't invoke server BindableFunction from client
end

-- After (Modal.lua - working)
local pushModalRemote = ReplicatedStorage:FindFirstChild("Input.PushModalRemote")
if pushModalRemote then
    pushModalRemote:FireServer(self.id)
end
```

---

## Architecture Decisions

### Per-Player Prompt Control Strategy
Roblox ProximityPrompts don't have native per-player enable/disable. The InputManager tracks allowed prompts per player, and assets can query `InputManager:IsPromptAllowed(player, assetName)` to determine if their prompt should respond.

### Separation of BindableFunctions and RemoteEvents
- **BindableFunctions** (`Input.PushModal`, `Input.PopModal`, `Input.IsPromptAllowed`): For server-to-server communication (e.g., Tutorial server script controlling modal state)
- **RemoteEvents** (`Input.PushModalRemote`, `Input.PopModalRemote`): For client-to-server communication (e.g., Modal.lua notifying server of modal state changes)

### Modal Ownership
Modal.lua manages its own UI lifecycle but delegates input state tracking to InputManager. This separation allows:
- Modal system to work standalone (gracefully handles missing InputManager)
- InputManager to track modal state for prompt blocking
- Clean cleanup when modals are destroyed

---

## Testing Results

| Phase | Status |
|-------|--------|
| Phase 1: Visibility utility | Passed |
| Phase 2: Enable/Disable protocol | Passed |
| Phase 3: InputManager subsystem | Passed |
| Phase 4: Modal system | Passed |

Full game loop tested:
1. Spawn in standby mode - Camper visible, game assets hidden
2. Talk to Camper - Welcome popup appears (Modal system)
3. Click through Tutorial - Rules popup, then mode_select popup
4. Choose Practice - Assets appear, game starts
5. Game loop functions correctly

---

## Summary

Successfully completed a 4-phase architectural refactor:
- Eliminated code duplication with shared Visibility module
- Standardized Enable/Disable protocol (fixed TimedEvaluator auto-reset bug)
- Created centralized InputManager for per-player input state
- Built reusable Modal system with proper client-server communication

All identified bugs from PROJECT_JOURNAL.md have been addressed.
