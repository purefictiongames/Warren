# Debug Session: Invisible CamperEvaluators After Lib/Game Refactor

**Date:** 2026-01-10
**Issue:** CamperEvaluator NPCs (campers) are not visible after the Lib/Game refactoring
**Status:** In Progress

## Summary

After refactoring the framework from a flat `Assets/` structure to a `Lib/Game` pattern with extension hooks, CamperEvaluator NPCs spawn but are invisible. The tents (CampDroppers) are visible, but the camper NPCs that spawn at them and their billboard GUIs are not appearing visually, despite existing in the Explorer hierarchy with seemingly correct properties.

## Environment

- Framework version: v1 (post Lib/Game refactor)
- Key components involved:
  - `ArrayPlacer` - Spawns CampDroppers in elliptical pattern
  - `Dropper` (as CampDropper) - Spawns CamperEvaluators on demand
  - `TimedEvaluator` (as CamperEvaluator) - The camper NPC with R6 character
  - `WaveController` - Controls spawn timing and sends spawn commands

## Architecture Overview

```
Spawn Chain:
ArrayPlacer (CampPlacer)
  └─> Dropper (CampDropper_1, _2, _3, _4)
        └─> TimedEvaluator (CamperEvaluator) - THE INVISIBLE MODEL

Template Creation (Bootstrap):
1. Clone base TimedEvaluator from Lib/
2. Swap Anchor with Game/CamperEvaluator/Model/Anchor.rbxm
3. Apply attributes from GameManifest
4. Store in _ConfiguredTemplates folder
```

## Model Hierarchy (Confirmed Correct)

```
CampPlacer_CampDropper_1_Drop_1 (Model)
└── Anchor (Part) - Transparency=1 (intentionally invisible)
    └── Walking NPC (Model)
        ├── Humanoid
        ├── Head (BasePart)
        ├── Torso (BasePart)
        ├── Left Arm (BasePart)
        ├── Right Arm (BasePart)
        ├── Left Leg (BasePart)
        ├── Right Leg (BasePart)
        └── Handle (BasePart) - from accessory
```

## Issues Identified and Fixed

### Issue 1: WaveController Targeting Wrong Tent Names

**Symptom:** WaveController was building tent names as `CampPlacer_Dropper_N` instead of `CampPlacer_CampDropper_N`.

**Root Cause:** WaveController had hardcoded `TentTemplate = "Dropper"` but ArrayPlacer spawns templates with their alias name (`CampDropper`).

**Fix:** Added configurable `TentTemplate` attribute to WaveController in GameManifest:
```lua
-- GameManifest.lua
{
    lib = "WaveController",
    alias = "WaveController",
    extension = "Game.WaveController.Extension",
    attributes = {
        TentTemplate = "CampDropper", -- Matches ArrayPlacer spawn naming
    },
},
```

**File Changed:** `src/System/ReplicatedStorage/GameManifest.lua`

---

### Issue 2: VisibleTransparency Attributes Baked Into Template

**Symptom:** Body parts had `Transparency=1` (invisible) after spawning.

**Root Cause:** The `Game/CamperEvaluator/Model/Anchor.rbxm` file was saved while the model was in a hidden state. This baked in:
- `Transparency = 1` on body parts
- `VisibleTransparency = 1` attribute (storing "visible" state as invisible)

When `Visibility.showModel()` runs, it restores parts to their stored `VisibleTransparency` value, which was 1 (invisible).

**Fix (Partial):** Added code to DropperModule to clear visibility attributes when cloning:
```lua
-- DropperModule.lua - spawnInstance()
for _, desc in ipairs(clone:GetDescendants()) do
    if desc:IsA("BasePart") then
        if desc:GetAttribute("VisibleTransparency") then
            desc:SetAttribute("VisibleTransparency", nil)
        end
        -- Also clear VisibleCanCollide, VisibleCanTouch
    end
end
```

**File Changed:** `src/Warren/Dropper/ReplicatedStorage/DropperModule.lua`

---

### Issue 3: Transparency Property Not Reset After Clearing Attributes

**Symptom:** After clearing `VisibleTransparency` attributes, parts still had `Transparency=1` baked in.

**Root Cause:** Clearing the attribute doesn't change the actual `Transparency` property value. The property value of 1 remains until `showModel()` runs and sets it to 0.

**Fix:** Enhanced DropperModule to also directly reset `Transparency=0` for body parts:
```lua
-- DropperModule.lua - spawnInstance()
for _, desc in ipairs(clone:GetDescendants()) do
    if desc:IsA("BasePart") then
        local partName = desc.Name
        if partName ~= "Anchor" and partName ~= "SpawnPoint" then
            if desc:GetAttribute("VisibleTransparency") then
                desc:SetAttribute("VisibleTransparency", nil)
            end
            -- Also reset the actual Transparency property
            if desc.Transparency == 1 then
                desc.Transparency = 0
            end
        end
    end
end
```

**File Changed:** `src/Warren/Dropper/ReplicatedStorage/DropperModule.lua`

---

## Current State (After Fixes)

### Server-Side Debug Output Shows Correct Values:

```
CampPlacer_CampDropper_1: Cleared VisibleTransparency on 0 parts and reset Transparency
CampPlacer_CampDropper_1: After attr clear - parts: Anchor(T:1), Left Leg(T:0), Head(T:0), Torso(T:0), Right Leg(T:0), Left Arm(T:0), Right Arm(T:0), Handle(T:0)

CampPlacer_CampDropper_1_Drop_1: BEFORE showModel - parts: Left Leg(T:0,VA:nil), Head(T:0,VA:nil), Torso(T:0,VA:nil), Right Leg(T:0,VA:nil), Left Arm(T:0,VA:nil), Right Arm(T:0,VA:nil), Handle(T:0,VA:nil)
CampPlacer_CampDropper_1_Drop_1: AFTER showModel - parts: Left Leg(T:0), Head(T:0), Torso(T:0), Right Leg(T:0), Left Arm(T:0), Right Arm(T:0), Handle(T:0)
CampPlacer_CampDropper_1_Drop_1: Enabled

CampPlacer_CampDropper_1_Drop_1: Humanoid stabilized and standing
```

### Client-Side Shows Billboard Created:

```
CampPlacer.client: Found anchor for CampPlacer_CampDropper_1_Drop_1 at Workspace.RuntimeAssets.CampPlacer_CampDropper_1_Drop_1.Anchor
CampPlacer.client: Initial HUDVisible for CampPlacer_CampDropper_1_Drop_1 = true Billboard enabled: true
CampPlacer.client: Created display for CampPlacer_CampDropper_1_Drop_1
```

### Positions Appear Reasonable:

```
SpawnPoint position: 112.03, 1.48, -42.76
Target CFrame (with SpawnOffset 0,2,-3): 109.06, 3.52, -42.69
Character torso after spawn: 109.04, 3.52, -43.23
Grounded by: -1.02 studs (final torso Y ≈ 2.5)
```

## Remaining Mystery

Despite all server-side indicators showing correct values:
- Transparency = 0 on all body parts
- Billboard enabled = true
- HUDVisible = true
- Humanoid stabilized and standing
- Positions appear reasonable

**The campers are still not visually appearing to the user.**

## Observations That May Be Clues

### 1. "camperSpawned" Messages Routing to Wrong Components

```
Scoreboard: Unknown message: camperSpawned
WaveController: Unknown action/command: camperSpawned
```

**Analysis:** These warnings are benign. Both components just log the warning and ignore unknown messages. The wiring is correct:
- `CampPlacer.Output -> WaveController.Input` (for camper status)
- `CampPlacer.Output -> Scoreboard.Input` (for evaluation results)

Dropper fires `camperSpawned` on its output, which gets forwarded through ArrayPlacer to both WaveController and Scoreboard. WaveController handles `camperDespawned` and `evaluationComplete` but not `camperSpawned`. This is expected - WaveController tracks slots by pre-marking them occupied when sending spawn commands.

### 2. Camera Position vs Camper Position

```
Camera center: (45.2, -69.9)
Camper position: (~109, ~2.5, ~-43)
Distance in XZ: ~69 studs
Camera distance setting: 53.5
```

The camper is quite far from the camera center. While tents at similar positions are visible, this might affect visibility.

### 3. SpawnOffset Direction

SpawnOffset is `Vector3.new(0, 2, -3)` applied in SpawnPoint's local coordinates. The camper spawns approximately 3 studs in the -X world direction from the SpawnPoint, suggesting SpawnPoint's local -Z aligns with world -X. This should place the camper outside the tent, but geometry occlusion is possible.

## Debug Logging Added

### Server-Side (DropperModule.lua):
- Logs how many VisibleTransparency attributes were cleared
- Logs part transparency values after clearing
- Logs SpawnPoint and target positions

### Server-Side (TimedEvaluatorModule.lua):
- Logs part transparency + VisibleTransparency BEFORE showModel
- Logs part transparency AFTER showModel

### Client-Side (ArrayPlacer client script):
- Logs client-side part transparency and Y positions
- Logs anchor position and billboard studsOffset

## Next Steps to Investigate

1. **Verify client-side state**: Run game and check new client-side logging to see if client has correct transparency values.

2. **Check for rendering issues**:
   - Are parts being rendered behind tent geometry?
   - Is the camera able to see the camper position?
   - Are there any material or color issues making parts hard to see?

3. **Test with debug marker**: Spawn a bright-colored part at camper position to verify rendering.

4. **Check camera view**: Walk closer to camper spawn positions to verify they're not just out of view.

5. **Verify the .rbxm file**: Re-export `Game/CamperEvaluator/Model/Anchor.rbxm` with parts visible to ensure no baked-in invisible state.

## Files Modified During This Session

| File | Changes |
|------|---------|
| `src/System/ReplicatedStorage/GameManifest.lua` | Added TentTemplate attribute to WaveController, SpawnOffset to CampDropper |
| `src/Warren/Dropper/ReplicatedStorage/DropperModule.lua` | Clear VisibleTransparency attributes, reset Transparency=0, debug logging |
| `src/Warren/TimedEvaluator/ReplicatedStorage/TimedEvaluatorModule.lua` | Debug logging for showModel before/after |
| `src/Warren/ArrayPlacer/StarterPlayerScripts/Script.client.lua` | Client-side debug logging for parts and billboard |

## Related Commits

- `5433260` - Add central Router and configurable anchor system for Humanoid NPCs
- `bcafb92` - Add WaveController for wave-based spawning and difficulty control
- `1431d7e` - Fix invisible Walking NPCs by grounding dynamically spawned TimedEvaluators

## Session Notes

This issue emerged after the Lib/Game refactoring. The key architectural change was:
- Before: Templates used directly from `Assets/` folder
- After: Templates created at bootstrap by merging Lib base with Game-specific model/attributes

The `swapModelParts` function in bootstrap replaces the base TimedEvaluator's Anchor with the game-specific Anchor from `Game/CamperEvaluator/Model/Anchor.rbxm`. This file appears to have been saved with invisible parts, causing the visibility issue.

Even after fixing the transparency values (confirmed via debug logging), the visual issue persists. This suggests the root cause may be something other than transparency - possibly camera, occlusion, streaming, or a client-specific rendering issue.
