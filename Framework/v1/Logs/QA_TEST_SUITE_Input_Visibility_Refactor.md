> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# QA Test Suite - Input & Visibility Refactor

**Date:** January 8, 2026
**Version:** 1.0
**Refactor Scope:** Phases 1-4 (Visibility, Enable/Disable, InputManager, Modal)

---

## Prerequisites

1. Run `rojo serve` in `Framework/v1/`
2. Connect Rojo plugin in Studio
3. Set `DebugConfig.lua` Level to 4 for full visibility
4. Have Output window open

---

## Phase 1: Visibility Utility

### Test 1.1: Dispenser Visibility

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Start game, observe Dispenser in standby | Dispenser model should be invisible (hidden) | [ ] |
| 2 | Talk to Camper, start Practice mode | Dispenser model should appear (visible) | [ ] |
| 3 | Let GlobalTimer expire (return to standby) | Dispenser model should hide again | [ ] |
| 4 | Check Output for errors | No errors related to Visibility module | [ ] |

### Test 1.2: TimedEvaluator Visibility

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | In standby mode | TimedEvaluator model invisible | [ ] |
| 2 | Enter Practice mode | TimedEvaluator model appears | [ ] |
| 3 | Return to standby | TimedEvaluator model hides | [ ] |

### Test 1.3: Camper Visibility (Inverse)

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | In standby mode | Camper NPC visible | [ ] |
| 2 | Enter Practice mode | Camper NPC should hide | [ ] |
| 3 | Return to standby | Camper NPC reappears | [ ] |

### Test 1.4: Transparency Preservation

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Enter Practice mode | Assets with semi-transparent parts show correct transparency | [ ] |
| 2 | Return to standby, re-enter Practice | Transparencies still correct (no accumulation bugs) | [ ] |
| 3 | Repeat 3 times | No visual degradation | [ ] |

---

## Phase 2: Enable/Disable Protocol

### Test 2.1: TimedEvaluator Timer Start

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Enter Practice mode | Output shows "TimedEvaluator: Enabled" | [ ] |
| 2 | Check Output | Should see "TimedEvaluator: Reset" AFTER "Enabled" (from Orchestrator) | [ ] |
| 3 | Observe TimedEvaluator countdown | Timer should be running with correct countdown | [ ] |

### Test 2.2: No Duplicate Timers

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Enter Practice mode | Only ONE timer countdown sequence in Output | [ ] |
| 2 | Watch satisfaction decay messages | Should tick at consistent rate, not doubled | [ ] |
| 3 | Submit marshmallow, watch reset | Single reset, single new timer | [ ] |

### Test 2.3: Game Loop Flow

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Enter Practice mode | Game loop starts: Dispenser refilled, TimedEvaluator reset, GlobalTimer starts | [ ] |
| 2 | Get marshmallow, roast, submit | Score appears, TimedEvaluator resets for next round | [ ] |
| 3 | Let GlobalTimer expire | Game ends, all players return to standby | [ ] |

### Test 2.4: Disable Stops Timers

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | In Practice mode, observe TimedEvaluator countdown | Timer ticking | [ ] |
| 2 | Let GlobalTimer expire (forces standby) | TimedEvaluator timer stops immediately | [ ] |
| 3 | Check Output | "TimedEvaluator: Disabled" message, no more timer ticks | [ ] |

---

## Phase 3: InputManager

### Test 3.1: Input State Initialization

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Start game, check Output | "Input: Initialized player: [YourName]" | [ ] |
| 2 | Check for mode application | "Input: Applied input config for [YourName] mode: standby prompts: Camper" | [ ] |

### Test 3.2: Prompt Filtering - Standby Mode

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | In standby mode | Only Camper ProximityPrompt should be visible/usable | [ ] |
| 2 | Walk to Dispenser | Dispenser prompt should NOT appear (asset is disabled) | [ ] |
| 3 | Walk to TimedEvaluator | TimedEvaluator prompt should NOT appear | [ ] |
| 4 | Walk to Camper | Camper "Talk" prompt should appear | [ ] |

### Test 3.3: Prompt Filtering - Practice Mode

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Enter Practice mode | Output shows "prompts: Dispenser, TimedEvaluator" | [ ] |
| 2 | Walk to Dispenser | Dispenser prompt appears | [ ] |
| 3 | Walk to TimedEvaluator | TimedEvaluator prompt appears | [ ] |
| 4 | Walk to Camper location | Camper prompt NOT visible (Camper is disabled) | [ ] |

### Test 3.4: Mode Transition Updates Input

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Start in standby | Camper prompt only | [ ] |
| 2 | Enter Practice | Output: "Applied input config for... practice" | [ ] |
| 3 | Return to standby | Output: "Applied input config for... standby" | [ ] |
| 4 | Prompts update correctly | Back to Camper only | [ ] |

### Test 3.5: Input State Changed Event (Client)

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Check client Output | "Input.client: State updated - allowed prompts: Camper" on spawn | [ ] |
| 2 | Enter Practice | "Input.client: State updated - allowed prompts: Dispenser, TimedEvaluator" | [ ] |

---

## Phase 4: Modal System

### Test 4.1: Tutorial Welcome Popup

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Talk to Camper (first time) | Welcome popup appears | [ ] |
| 2 | Observe popup styling | Dark overlay, centered modal, title, body, buttons | [ ] |
| 3 | Check Output | "Tutorial Client: Created popup with Modal system" | [ ] |

### Test 4.2: Gamepad Navigation

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Open any Tutorial popup | Primary button should be highlighted/selected | [ ] |
| 2 | Press A/Enter | Button activates, advances to next state | [ ] |
| 3 | If multiple buttons, use D-pad | Can navigate between buttons | [ ] |

### Test 4.3: Mouse/Touch Input

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Open Tutorial popup | Popup displays correctly | [ ] |
| 2 | Click primary button | Button activates, state changes | [ ] |
| 3 | Click secondary button (if any) | Correct action occurs | [ ] |

### Test 4.4: Modal Cleanup

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Open popup, click button | Popup closes (after server confirms state change) | [ ] |
| 2 | Check PlayerGui | "Modal.tutorial-popup" ScreenGui should be gone or disabled | [ ] |
| 3 | No orphaned UI | No leftover overlay or modal frames | [ ] |

### Test 4.5: Modal State in InputManager

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Open Tutorial popup | Check if Input.PushModal was called (if wired) | [ ] |
| 2 | Close popup | Input.PopModal called | [ ] |
| 3 | (Optional) While popup open | World prompts should be blocked if modal state active | [ ] |

---

## Integration Tests

### Test I.1: Full Game Loop

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Spawn (standby) | Camper visible, game assets hidden | [ ] |
| 2 | Talk to Camper | Welcome popup (Modal) | [ ] |
| 3 | Complete Tutorial flow | Mode select popup | [ ] |
| 4 | Choose Practice | Assets appear, game starts | [ ] |
| 5 | Get marshmallow | Dispenser works | [ ] |
| 6 | Roast on campfire | Color changes | [ ] |
| 7 | Submit to TimedEvaluator | Score appears, resets for next round | [ ] |
| 8 | Let GlobalTimer expire | Returns to standby, assets hide | [ ] |

### Test I.2: Multiple Mode Transitions

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | standby → practice → standby | All works | [ ] |
| 2 | standby → play → standby | All works | [ ] |
| 3 | Repeat 3 times | No memory leaks, no orphaned connections | [ ] |

### Test I.3: Console Error Check

| Step | Action | Expected Result | Pass |
|------|--------|-----------------|------|
| 1 | Play through full game loop | No red errors in Output | [ ] |
| 2 | Check for warnings | No unexpected warnings | [ ] |
| 3 | Look for specific errors | No "attempt to index nil", no "Visibility" errors | [ ] |

---

## Error Scenarios

### Test E.1: Missing Visibility Module

| Scenario | Expected Behavior | Pass |
|----------|-------------------|------|
| If Visibility.lua fails to load | Assets should error with clear message about missing module | [ ] |

### Test E.2: RunModesConfig Missing Input

| Scenario | Expected Behavior | Pass |
|----------|-------------------|------|
| If input config missing from a mode | InputManager should use empty defaults (no prompts) | [ ] |

### Test E.3: Modal Without InputManager

| Scenario | Expected Behavior | Pass |
|----------|-------------------|------|
| If Input subsystem not loaded | Modal should still work (PushModal/PopModal calls fail silently) | [ ] |

---

## Quick Smoke Test (5 minutes)

| Step | Check | Pass |
|------|-------|------|
| 1 | **Boot** → Game loads without errors | [ ] |
| 2 | **Camper visible** → Talk prompt works | [ ] |
| 3 | **Popup appears** → Uses Modal styling (dark overlay, rounded corners) | [ ] |
| 4 | **Enter Practice** → Assets appear, Dispenser prompt works | [ ] |
| 5 | **Get & roast marshmallow** → Submit works | [ ] |
| 6 | **Timer expires** → Return to standby, Camper reappears | [ ] |

---

## Debug Messages Reference

Check these in Output during testing:

```
-- Phase 1 (Visibility)
"Dispenser: Enabled" / "Dispenser: Disabled"
"TimedEvaluator: Enabled" / "TimedEvaluator: Disabled"
"Camper: Enabled" / "Camper: Disabled"

-- Phase 2 (Enable/Disable Protocol)
"TimedEvaluator: Reset - TargetValue: XX"
"Orchestrator: Starting game loop"

-- Phase 3 (InputManager)
"Input: Initialized player:"
"Input: Applied input config for"
"Input.client: State updated"

-- Phase 4 (Modal)
"Tutorial Client: Created popup with Modal system"
"Tutorial Client: Button activated:"
```

---

## Test Results Summary

| Phase | Tests Passed | Tests Failed | Notes |
|-------|--------------|--------------|-------|
| Phase 1: Visibility | /4 | | |
| Phase 2: Enable/Disable | /4 | | |
| Phase 3: InputManager | /5 | | |
| Phase 4: Modal | /5 | | |
| Integration | /3 | | |
| Error Scenarios | /3 | | |
| **Total** | **/24** | | |

---

## Sign-Off

- [ ] All tests passed
- [ ] Ready for commit

**Tester:** _______________
**Date:** _______________
