> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# Warren Framework - Project Journal

**Project:** Roblox Game Framework with Self-Bootstrapping Asset System
**Timeline:** December 25-30, 2025 (6 days)
**Collaborators:** Human (Architecture/Design) + Claude (Implementation)

---

## Executive Summary

Built a modular, self-bootstrapping Roblox game framework from scratch using Rojo. The framework enables portable, self-contained game assets that automatically deploy their server scripts, client scripts, and events during a staged boot sequence. A working "marshmallow roasting" game serves as the proof-of-concept, featuring dispensers, cooking zones, timed scoring, leaderboards, and a complete game loop.

---

## Chronicle

### Day 1 (Dec 25) - Foundation & First Failures

**Sessions 1-3**

**The Goal:** Create a modular framework where assets are self-contained units that can be dropped into any project.

**Major Success: Self-Bootstrapping Architecture**
Established the core pattern that would define the entire project:
- Assets contain their own `ReplicatedStorage/`, `ServerScriptService/`, etc. folders
- `System.Script` extracts these during bootstrap, prefixing with asset names
- Models deploy to `Workspace/RuntimeAssets` as cleaned instances

This single insight enabled everything that followed.

**First Big Pivot: Rojo Over Packages**
Initially planned to distribute System as a Roblox Package and assets via Toolbox. Realized this created a chicken-and-egg problem: assets dropped from Toolbox needed folders that wouldn't exist until the Package ran.

The user's insight: *"Why am I worrying about packages? If we do it this way, anytime we open a new project and connect to Rojo, it does all of this for us anyway."*

This simplified everything. Rojo became the single source of truth.

**Lesson Learned: .rbxm for Physical Components**
Discovered that Rojo nukes non-script content on every sync. Solution: export physical components (Parts, ProximityPrompts, UI) as `.rbxm` files and include them in the filesystem.

**Built:** Dispenser asset (gives items), ZoneController asset (event-driven zone detection with callback invocation)

---

### Day 2 (Dec 26) - Game Loop Completion

**Sessions 4-7**

**Major Success: Complete Game Loop in One Day**
Built the full marshmallow roasting experience:
1. **TimedEvaluator** - Timed submission with accuracy scoring
2. **Scoreboard** - 60/40 accuracy/speed weighted scoring, HUD
3. **Orchestrator** - Event coordinator that resets assets
4. **GlobalTimer** - Round countdown with M:SS display
5. **LeaderBoard** - Persistent top-10 with DataStore

**Architecture Pattern: Event-Driven Communication**
Assets fire BindableEvents, never call each other directly. Orchestrator listens and coordinates:
```
TimedEvaluator -> EvaluationComplete -> Scoreboard -> RoundComplete -> Orchestrator
GlobalTimer -> TimerExpired -> Orchestrator
Dispenser -> Empty -> Orchestrator
```

**Failure: Timeout Reset Bug**
When the timer expired with no submission, `RoundComplete` wasn't firing because Scoreboard returned early (no player). Fixed by making Scoreboard always fire `RoundComplete`, even on timeout.

**Failure: Touch Exit Detection**
Zone detection used `GetTouchingParts()` which is unreliable with `CanCollide=false`. Fixed with touch counting - increment on `Touched`, decrement on `TouchEnded`, entity exits when count reaches zero.

---

### Day 3 (Dec 27) - Tools & UI Polish

**Sessions 8-10**

**Major Success: RoastingStick Auto-Equip System**
Built a tool system that:
- Auto-equips stick on player spawn
- Watches for marshmallows via `Backpack.ChildAdded`
- Mounts marshmallow to stick tip with WeldConstraint
- Enforces one-marshmallow rule (extras dropped)

**Created Backpack Subsystem**
Centralized backpack event handling with:
- `ItemAdded` - Broadcast when items enter backpack
- `ForceItemDrop` - Drop item on ground
- `ForceItemPickup` - Add item to backpack

**Failure: BillboardGui from .rbxm**
Exported BillboardGui from Studio, but it never rendered despite correct properties. Never diagnosed the root cause. Solution: create GUI entirely in code, which worked immediately and enabled faster iteration.

**Success: Code-Based GUI Pattern**
Established pattern of building BillboardGuis in LocalScripts:
- Dispenser shows marshmallow icon + remaining count
- TimedEvaluator shows satisfaction emoji + 3D marshmallow preview (ViewportFrame)

**Visual Cooking Feedback**
Implemented color interpolation for marshmallow cooking:
- 0-25: Raw (off-white) -> Golden
- 25-50: Golden -> Burnt
- 50-75: Burnt -> Blackened
- 75-100: Fully blackened

---

### Day 4 (Dec 28) - The Great Bug Hunt

**Sessions 11-12**

**Critical Bug: Duplicate Script Execution**
Scripts in `System/Backpack/ServerScriptService/` were running twice - once from the original location, once from the deployed copy.

**Root Cause Discovery:**
Scripts auto-run when they're descendants of `ServerScriptService` (the actual service), regardless of folder nesting. A folder *named* "ServerScriptService" is just a regular Folder, but scripts inside it ARE descendants of SSS.

**Solution Attempt 1: Rename Folders (Failed)**
Renamed `ServerScriptService` to `_ServerScriptService`. This didn't work because the scripts were still descendants of the actual ServerScriptService.

**Solution Attempt 2: Name Guards (Success)**
Added guards at the top of affected scripts:
```lua
if not script.Name:match("^Backpack%.") then
    return
end
```
Original scripts exit early; deployed scripts (with prefix) run.

**Failure: Backpack.ChildAdded in Published Games**
ChildAdded wasn't firing after character respawn. Root cause: the Backpack instance becomes stale on respawn - a new one is created. Fixed by re-watching on `CharacterAdded`.

**Built: MessageTicker**
Server-to-client notification system with fade-out animation. Used for gameplay messages like "Roast your marshmallow!" and "You dropped one!"

---

### Day 5 (Dec 29) - Infrastructure Hardening

**Debug System & Stage-Wait Boot**

**Success: Debug Logging System**
Replaced 97 `print()`/`warn()` calls with configurable logging:
- Level 1: System only
- Level 2: System + Subsystems
- Level 3: Assets only
- Level 4: Filtered (iptables-style rules)

**Major Success: Stage-Wait Boot System**
Implemented 5-stage boot to eliminate race conditions:
```lua
Stages = {
    SYNC    = 1,  -- Assets cloned to RuntimeAssets
    EVENTS  = 2,  -- All events created
    MODULES = 3,  -- ModuleScripts deployed
    SCRIPTS = 4,  -- Server scripts can run
    READY   = 5,  -- Clients can interact
}
```

Critical insight: `Players.CharacterAutoLoads = false` at boot start, re-enable after READY. This prevents players from spawning during bootstrap.

**Lesson: Rojo Naming**
`.shared.lua` doesn't work as expected - Rojo creates `System.shared` instead of `System`. Use plain `.lua`.

---

### Day 6 (Dec 30) - GUI System & Modular Layouts

**Modular Layout System**

**Success: Layout-Agnostic Assets**
Assets create standalone ScreenGuis with a `Content` wrapper. The GUI system repositions this content into layout regions via configuration:
```lua
["right-sidebar"] = {
    assets = {
        ["GlobalTimer.ScreenGui"] = "timer",
        ["Scoreboard.ScreenGui"] = "score",
    },
    rows = { ... }
}
```

**Full GUI System Built:**
- Declarative element creation (`GUI:Create({ type = "TextLabel", ... })`)
- CSS-like styling with classes and IDs
- Responsive breakpoints (desktop/tablet/phone)
- Layout builder with rows/columns
- Runtime style updates (`GUI:AddClass`, `GUI:RemoveClass`)

---

## Technical Wins

### 1. Self-Bootstrapping Pattern
The core insight that assets can contain their own deployment structure, extracted by System during boot. Makes assets truly portable.

### 2. Event-Driven Architecture
Assets communicate via BindableEvents/RemoteEvents, never directly. Orchestrator coordinates. Clean separation, easy to add new listeners.

### 3. Attribute-Based Configuration
Assets read configuration from Instance Attributes set in Studio. State attributes (like `Remaining`, `TimeRemaining`) auto-replicate to clients.

### 4. Staged Boot
Deterministic deployment order (events before scripts), client ping-pong for late joiners, character spawn control.

### 5. Debug System
Filterable logging that can quiet noisy assets while debugging specific ones.

---

## Technical Failures & Lessons

### 1. The Duplicate Script Saga
**Lesson:** Understand how Roblox determines script execution. Folder names don't matter - ancestry does. Scripts run if they descend from ServerScriptService (the service), not a folder named that.

### 2. BillboardGui from .rbxm
**Lesson:** When something mysteriously doesn't work with .rbxm, try code-based creation. Sometimes faster to implement than debug.

### 3. Stale Instance References
**Lesson:** Roblox recreates certain instances (like Backpack) on respawn. Connections to old instances become stale. Always re-establish connections on CharacterAdded.

### 4. Touch Event Reliability
**Lesson:** `GetTouchingParts()` is unreliable with `CanCollide=false`. Use touch counting instead.

### 5. Rojo Sync Issues
**Lesson:** If changes aren't appearing in-game, disconnect and reconnect the Rojo plugin before deeper debugging.

---

## Architecture Decisions Log

| Decision | Why | Alternative Considered |
|----------|-----|----------------------|
| Rojo as sole distribution | Simpler than Packages + Toolbox | Roblox Packages, Toolbox distribution |
| Underscore prefix for service folders | Prevents auto-run, maintains structure | Storing in ReplicatedStorage |
| Name guards in scripts | Belt-and-suspenders for duplicate prevention | Relying solely on deployment order |
| Code-based BillboardGuis | Reliable, fast iteration | .rbxm export (failed mysteriously) |
| Event-driven asset communication | Loose coupling, easy extension | Direct function calls |
| 5-stage boot | Deterministic ordering, race condition elimination | WaitForChild everywhere |
| CharacterAutoLoads = false | Prevents spawning during boot | Complex player handling |

---

## Emergent Mechanics

Things that fell out naturally from the architecture:

1. **Dispenser Spam Penalty** - One marshmallow at a time; extras drop. Natural consequence of mount system.

2. **Stickless Roasting** - Player can hold marshmallow directly. Works but could enable "damage from heat" mechanic.

3. **Multiple Listeners** - Both LeaderBoard and Orchestrator listen to same events independently. Easy to add more.

---

## What We'd Do Differently

1. **Stage-wait from day one** - Would have avoided many race condition bugs
2. **Debug system from day one** - Console noise was painful early on
3. **Name guards everywhere** - Standard pattern for all scripts in System hierarchy
4. **Code-based GUI from start** - Don't bother with .rbxm for UI elements

---

## Current State (Dec 30)

**Working:**
- Complete game loop (dispense -> cook -> submit -> score -> reset)
- Persistent leaderboard
- Round timer
- Player notifications
- Debug filtering
- Staged boot
- Modular layout system

**Assets:** Dispenser, ZoneController, TimedEvaluator, Scoreboard, GlobalTimer, LeaderBoard, Orchestrator, RoastingStick, MessageTicker

**Templates:** Marshmallow, RoastingStick

**System Modules:** Player, Backpack, GUI

---

## Future Roadmap (Not Started)

1. **Gameplay Features**
   - Stick durability (degrades with use)
   - Player damage for stickless roasting
   - Animal AI (steal dropped marshmallows)
   - Multiple zones/dispensers

2. **Framework**
   - Error handling if stage never fires
   - Stage timeout warnings
   - Remote log streaming for published debugging

3. **Polish**
   - End-of-round summary screen
   - Visual effects (fire particles, cooking smoke)
   - Sound effects
   - Better stick grip positioning

---

---

### Day 7+ (Jan 7, 2026) - RunModes, Tutorial & Input System

**Sessions 17-18**

**Major Success: Per-Player Game States (RunModes)**

Introduced a per-player state machine for game modes:
- **standby** - Player exploring, game loop inactive
- **practice** - Game active with guidance, scores don't persist
- **play** - Full game, scores persist, badges awarded

This required significant architectural changes:
- New boot stages: `SYNC → EVENTS → MODULES → SCRIPTS → ASSETS → ORCHESTRATE → READY`
- Deferred initialization pattern: Assets register init functions via `System:RegisterAsset()`, called at ASSETS stage
- Orchestrator waits for ORCHESTRATE stage, applies mode config to all assets

**Bug Fixes Required by RunModes:**

1. **TimedEvaluator model not appearing** - Transparency-based hide/show was fragile. Created `VisibleTransparency` attribute pattern: store original transparency in attribute, restore from it when showing.

2. **Game loop not ending** - Added `endGame()` to Orchestrator that transitions all active players back to standby when GlobalTimer expires or Dispenser empties.

3. **Tutorial task list persisting** - Tutorial state wasn't reset when returning to standby. Added RunModes.ModeChanged listener to reset tutorial.

4. **RoastingStick equipped on spawn** - Refactored to deferred init pattern, starts disabled, Orchestrator enables when entering practice/play.

5. **Gamepad/Enter support for popups** - Initial approach used ContextActionService with priority hacking to compete with ProximityPrompts. Replaced with `GuiService.SelectedObject` - the native Roblox way to handle modal UI focus.

**New Pattern: GuiService for Modal Input**

```lua
-- When popup opens
GuiService.SelectedObject = primaryButton

-- Use Activated event (fires for mouse, touch, AND gamepad A when selected)
button.Activated:Connect(function()
    -- Handle click/tap/gamepad
end)

-- When popup closes
GuiService.SelectedObject = nil
```

**Architecture Insight: Input Management**

Discovered that input control needs to be coupled with game state (RunModes) at the system level:
- Standby: ProximityPrompts active, game controls disabled
- Practice/Play: Game controls active, certain prompts disabled
- Modal open: All world interaction paused, only modal input active

---

## Planned Refactor: Input & State Management

The RunModes work surfaced architectural gaps. Planned improvements:

### 1. Centralized Input Manager
- Input state tied to RunModes config
- Modal system that captures focus and disables world interaction
- ProximityPrompt enable/disable coordinated with mode changes

```lua
RunModesConfig = {
    standby = {
        assets = { ... },
        input = {
            proximityPrompts = { "Camper" },
            gameControls = false,
        }
    },
    practice = {
        assets = { ... },
        input = {
            proximityPrompts = {},
            gameControls = true,
        }
    }
}
```

### 2. Visibility Pattern Standardization
- All assets use `VisibleTransparency` attribute for hide/show
- Extract into shared utility or System method

### 3. Asset Enable/Disable Protocol
- Standardize `Enable()` / `Disable()` BindableFunctions
- Clear contract for what each does (visibility, state, input)

### 4. Modal System
- Dedicated modal layer above game UI
- Automatically disables world input when modal active
- GuiService selection management built-in

---

---

### Day 8 (Jan 8, 2026) - Input & Visibility System Refactor

**Session 19**

**Major Success: Centralized Input Management**

Completed comprehensive 4-phase architectural refactor addressing gaps identified in RunModes work:

**Phase 1: Visibility Utility Module**
- Extracted duplicated visibility code from Dispenser, TimedEvaluator, and Camper
- Created `System/ReplicatedStorage/Visibility.lua` with `hideModel()`/`showModel()`
- Uses `VisibleTransparency` attribute pattern for state preservation

**Phase 2: Enable/Disable Protocol Standardization**
- Fixed critical bug in TimedEvaluator: `Enable()` was calling `reset()`, causing duplicate timers
- Standardized Enable/Disable semantics across all assets
- Clear separation: Enable/Disable controls visibility, RunModes controls behavior

**Phase 3: InputManager Subsystem**
- Created `System/Input` subsystem with per-player state tracking
- Integrated with RunModes configuration:
```lua
standby = {
    input = { prompts = { "Camper" }, gameControls = false }
}
```
- Server-to-server BindableFunctions for internal coordination
- Client-to-server RemoteEvents for UI interactions
- Pattern: Assets query `InputManager:IsPromptAllowed(player, assetName)` to check state

**Phase 4: Reusable Modal System**
- Built `System/GUI/ReplicatedStorage/Modal.lua` for all dialog UI
- Quick helpers: `Modal.Alert()`, `Modal.Confirm()`
- Automatic gamepad navigation via `GuiService.SelectedObject`
- Integrated with InputManager for prompt blocking during modals
- Refactored Tutorial popups to use Modal system (deleted 100+ lines of duplicate UI code)

**Critical Bug Fixes:**

1. **BindableFunction vs RemoteEvent Confusion**
   - Initial implementation tried to invoke server BindableFunctions from client (doesn't work)
   - Solution: Separate communication channels
     - BindableFunctions: Server-to-server only
     - RemoteEvents: Client-to-server messaging
   - This distinction is now documented in PROCEDURES.md

2. **RunModesConfig Path Resolution**
   - `ReplicatedFirst:WaitForChild("RunModesConfig")` infinite yielded
   - Root cause: Config isn't extracted during boot, lives in ServerScriptService.System hierarchy
   - Fixed with correct path traversal

**Architecture Win: Separation of Concerns**
- Modal system owns UI lifecycle, delegates input state to InputManager
- InputManager doesn't know about UI, only tracks state
- Both systems work independently and gracefully degrade if the other is missing

---

### Day 9 (Jan 8, 2026) - Unified Styling System

**Session 20**

**Major Success: Single Declarative Language for GUI + 3D Assets**

Extended the CSS-like GUI styling system to also handle 3D asset positioning and transforms. This eliminated all hardcoded `CFrame` and `PivotTo` calls in favor of declarative styles in Styles.lua.

**System Architecture: Domain Adapters**

Created adapter pattern to unify styling across domains:
- **DomainAdapter.lua** - Interface definition
- **GuiAdapter.lua** - Handles GUI properties (TextSize, BackgroundColor, etc.)
- **AssetAdapter.lua** - Handles 3D transforms (position, rotation, scale, etc.)
- **StyleEngine.lua** - Unified resolution engine works for both domains

**Transform Properties (Arrays Auto-Convert):**
```lua
["Camper1"] = {
    position = {10, 0.5, -5},     -- Vector3
    rotation = {0, 45, 0},         -- Degrees (converted to radians internally)
    pivot = {0, 0, 0},             -- Pivot offset
    offset = {0, 2, 0},            -- Position offset
    scale = {1.2, 1.2, 1.2},       -- Requires AllowScale attribute
}
```

**Key Design Decisions:**

1. **Rotation in Degrees (Not Radians)**
   - More intuitive for designers: `{0, 90, 0}` instead of `{0, 1.5708, 0}`
   - Converted to radians internally by ValueConverter

2. **Opt-In Scaling with Idempotency**
   - Scale requires `AllowScale` attribute on BaseParts (prevents accidental geometry destruction)
   - Stores baseline size in `__StyleBaseSize` attribute
   - Always scales from baseline to prevent drift on repeated applications

3. **Transform Composition Order**
   - Deterministic: base position → rotation → offset → scale
   - Pivot point controls rotation center
   - Consistent behavior across Models, BaseParts, and Attachments

4. **Same Cascade Rules as GUI**
   - base → class → id → inline
   - Responsive breakpoints work (`@tablet`, `@phone`)
   - Runtime updates supported

**New Public APIs:**
```lua
GUI:StyleAsset(asset, inlineStyles)      -- Style single asset
GUI:StyleAssetTree(rootAsset, inlineStyles)  -- Style asset + descendants
```

**Implementation Phases:**

**Phase 1: Domain Abstraction**
- Created DomainAdapter interface
- Extracted GUI logic into GuiAdapter
- Built AssetAdapter with transform handling
- Extended ValueConverter with asset-specific conversions

**Phase 2: Unified Resolution**
- Created StyleEngine with domain-agnostic resolution
- Modified GUI.lua to expose asset styling APIs
- Extended Styles.lua with asset styling examples

**Technical Wins:**

1. **No Breaking Changes** - GUI system continues to work exactly as before
2. **Clean Separation** - Domain adapters isolate property handling logic
3. **Single Source of Truth** - All positioning in Styles.lua, not scattered in scripts
4. **Testable** - Styling is data, not imperative code

**Testing:**
- System booted cleanly on first attempt
- No errors in game logs
- All existing game mechanics continued to function
- Asset styling examples validated

**Documentation Updated:**
- SYSTEM_REFERENCE.md → v2.0 (1860 lines) with complete asset styling documentation
- PROCEDURES.md → Added Section 10.7 "Asset Positioning and Styling" + 4 new pitfalls
- STYLING_SYSTEM.md → New comprehensive guide (2500+ lines) covering both domains

**What This Enables:**

Before:
```lua
-- Hardcoded in script
camper1.PivotTo(CFrame.new(10, 0.5, -5) * CFrame.Angles(0, math.rad(45), 0))
```

After:
```lua
-- In Styles.lua
["Camper1"] = {
    position = {10, 0.5, -5},
    rotation = {0, 45, 0},
}

-- In script (no positioning logic)
GUI:StyleAsset(camper1)
```

This pattern extends to all game assets: Dispensers, TimedEvaluators, spawn points, props, etc.

---

## Future Refactor Considerations

### Alternative Asset Visibility Approach: Reparenting

Currently, asset visibility is managed by `Visibility.hideModel()` which sets `Transparency = 1`, `CanCollide = false`, and `CanTouch = false` on all BaseParts, storing original values in attributes for restoration.

**Alternative approach:** Move inactive assets out of Workspace entirely (to ServerStorage or a hidden container).

**Pros:**
- Simpler - no attribute tracking for multiple properties
- Zero rendering cost (geometry not even culled)
- Zero physics cost (completely out of simulation)
- Clean mental model: in Workspace = active, out = inactive

**Cons:**
- Script references using `workspace.RuntimeAssets:FindFirstChild()` would fail when asset is inactive
- Need to decide storage location (ServerStorage hides from clients, breaking client scripts)
- Moving large models has network/replication cost
- Event listeners (Touched, etc.) need cleanup/restore logic

**Hybrid option:** Keep model structure in Workspace, but reparent physical `Anchor` parts in/out of a hidden container. References to the model stay valid, but physical presence is toggled entirely.

**Current decision:** Keep visibility-based approach for now. Revisit if property tracking becomes unwieldy or if performance profiling shows invisible geometry causing issues.

### Known Bug: Camper/TimedEvaluator Floating Above Baseplate

**Status:** Deferred - low priority

**Symptom:** Camper and TimedEvaluator models float slightly above the baseplate instead of sitting flush on Y=0.

**Attempted fixes:**
- Set Anchor CanCollide=false (in case collision was pushing them up)
- Set position Y=0 in Styles.lua (was 0.5)
- Added grounding code to calculate model bounds and drop to Y=0

**Possible causes:**
- Model pivot point not at base
- .rbxm export has models at non-zero Y
- Styling system applying transforms after grounding code runs
- Anchor part size/position affecting model pivot

**Workaround:** Manually adjust model positions in Roblox Studio and re-export .rbxm files with correct base positioning.

### Known Bug: ZoneController (Campfire) Sound Still Plays When Hidden

**Status:** Deferred - low priority

**Symptom:** The campfire crackling sound continues to play even when the ZoneController is hidden in standby mode.

**Attempted fixes:**
- Stop sound with `:Stop()`
- Set `Volume = 0`
- Set `PlaybackSpeed = 0`
- Set `Playing = false`
- Call `handleDisable()` at init to hide immediately

**Possible causes:**
- Sound may not be a descendant of the model (external to Zone.rbxm)
- Sound may be triggered by a separate script or SoundService
- Sound may be set to auto-play in .rbxm before scripts run
- Roblox replication/timing issue with sound properties

**Workaround:** Manually disable or remove the sound from the Zone.rbxm in Roblox Studio, or move sound control to a separate script that explicitly manages campfire audio.

### Future Refactor: Unified Asset State System with Pseudo-Class Styles

**Status:** Planned - medium priority

**Problem:** Currently handling asset active/inactive visibility with ad-hoc fixes across multiple assets:
- Visibility.hideModel/showModel manages Transparency, CanCollide, CanTouch, particles, lights, sounds
- Each asset manually sets `VisibleCanCollide = false` attributes to prevent collision restore
- Some assets need brute-force overrides after showModel (e.g., Campfire forcing CanCollide = false)
- Dispenser, Camper, TimedEvaluator, ZoneController all have slightly different approaches

**Proposed Solution:** Integrate asset state into the styling system with pseudo-class-like syntax:

```lua
-- In Styles.lua
["Campfire"] = {
    position = {0, 0, 0},
    rotation = {0, 0, 0},
},
["Campfire:inactive"] = {
    visible = false,
    collideable = false,
    touchable = false,
    particles = false,
    sounds = false,
    lights = false,
},
["Campfire:active"] = {
    visible = true,
    collideable = false,  -- Always non-collideable, even when active
    touchable = true,     -- Zone needs touch detection
    particles = true,
    sounds = true,
    lights = true,
},
```

**Benefits:**
- Declarative configuration per asset
- No more ad-hoc attribute setting in asset scripts
- Consistent behavior across all assets
- Easy to see/modify asset states in one place
- Could extend to other states (`:hover`, `:selected`, etc.)

**Implementation considerations:**
- StyleEngine needs state-aware selector matching
- Assets need to declare their current state
- Orchestrator or RunModes triggers state changes
- AssetAdapter applies state-specific styles

---

---

### Day 10 (Jan 9, 2026) - Transitions, Countdown & Isometric Camera

**Sessions 21-22**

**Major Success: Screen Transition System**

Implemented fade-to-black screen transitions for mode changes, creating a polished experience when entering/exiting gameplay:

- **Server Module:** `GUI/ReplicatedStorage/Transition.lua` - API with `Start()`, `Reveal()`, `GetEvents()`
- **Client Script:** `GUI/StarterPlayerScripts/Transition.client.lua` - Handles fade tweens, fires milestone events
- **Event Flow:** Start → fade to black → Covered (server notified) → mode changes applied → Reveal → fade in → Complete

**Integration with Orchestrator:**
- Mode changes trigger transition before applying new mode config
- Assets enable/disable while screen is black (invisible to player)
- Smooth visual flow: fade out → switch scene → fade in

**Technical Challenge: Naming Conflicts**
Initial attempt created both `Transition.lua` (ModuleScript) and `Transition/` (folder for events) - same name conflict. Resolved by:
- Module stays as `GUI.Transition`
- Events use `GUI.TransitionEvent`, `GUI.TransitionCovered`, etc.
- Bootstrap dot-notation handles deployment correctly

---

**Major Success: CountdownTimer via Template Reuse**

Extended GlobalTimer template to support two deployment modes:
- **PlayTimer** (existing): HUD sidebar, M:SS format, game duration
- **CountdownTimer** (new): Centered fullscreen, "ready.../set.../go!" with 3/2/1

**Attribute-Based Configuration:**
```lua
-- Auto-detected from asset name containing "Countdown"
TimerMode = "sequence"     -- vs "duration"
TextSequence = "ready...,set...,go!"
CountdownStart = 0.03      -- 3 seconds (M.SS format)
```

**Server Changes (GlobalTimer):**
- Auto-detect mode from asset name
- Parse comma-separated TextSequence
- Broadcast includes `sequenceText` field for sequence mode

**Client Changes (GlobalTimer):**
- Create different UI based on mode
- Sequence mode: centered container with stacked text/number labels
- Duration mode: existing HUD panel (unchanged)

**New Styles Added:**
```lua
["countdown-text"] = { font = "Bangers", textSize = 72, textColor = {255, 170, 0} },
["countdown-number"] = { font = "Bangers", textSize = 120, textColor = {255, 170, 0} },
```

---

**Player Freeze During Countdown**

Added racing-game style freeze: player cannot move or interact until countdown completes.

**Orchestrator Changes:**
- `freezePlayer(player)`: Save WalkSpeed/JumpPower, set both to 0
- `unfreezePlayer(player)`: Restore saved values
- `pushModal:Invoke(player, "countdown")`: Lock prompts during countdown
- Flow: TransitionComplete → freeze + lock → CountdownTimer starts → timerExpired → unfreeze + unlock → game begins

---

**Major Success: Isometric Camera System**

Added fixed overhead camera for gameplay that switches during transitions:

**New System Module: `System/Camera/`**
- `ReplicatedFirst/CameraConfig.lua` - Camera angles, buffer, mode mapping
- `StarterPlayerScripts/Script.client.lua` - Camera controller

**Dynamic Positioning:**
Camera automatically frames the play area:
1. Find MarshmallowBag and Campfire models
2. Calculate center point between them
3. Add buffer (20 studs each side)
4. Position camera at 60° down angle, high enough to see everything

**Integration with Transition System:**
- Transition.client creates `Camera.TransitionCovered` BindableEvent
- Fires when screen is fully black
- Camera.client listens, switches camera while hidden
- Screen reveals with new camera already in place

**Camera Modes:**
- `standby`: Free camera (CameraType.Custom, third-person following)
- `practice`/`play`: Isometric (CameraType.Scriptable, fixed overhead)

---

**Identified: Race Condition Issues**

Discovered intermittent bugs where systems don't work until restart:
- Roasting sometimes doesn't work on first load
- ZoneController may not detect player already in zone when enabled
- Event connections may not be ready when events fire

**Root Cause Analysis:**
- Scripts run when loaded, not in guaranteed order
- No verification that initialization completed
- Client scripts especially problematic (no RegisterAsset equivalent)
- Within a boot stage, order is non-deterministic

**Documented Refactor Plan:** Module Initialization System
- Two-phase lifecycle: `init()` (create resources) → `start()` (connect events)
- All modules registered, System orchestrates initialization
- Verification that all modules completed each phase
- Client-side boot system with explicit stages
- ~28 scripts to migrate, 4-6 hours estimated

Plan saved to: `.claude/plans/quiet-hopping-hammock.md`

---

## Technical Wins This Session

1. **Template Reuse Pattern** - Single GlobalTimer template serves two use cases via attributes
2. **Transition Event Flow** - Clean handoff: client → server → client with milestone events
3. **Dynamic Camera Framing** - Auto-calculate position from asset locations
4. **Player Freeze Pattern** - Save/restore Humanoid movement properties

---

## Files Changed

**New Files:**
- `src/System/Camera/ReplicatedFirst/CameraConfig.lua`
- `src/System/Camera/StarterPlayerScripts/Script.client.lua`
- `src/System/GUI/ReplicatedStorage/Transition.lua`
- `src/System/GUI/StarterPlayerScripts/Transition.client.lua`
- `src/System/GUI/ReplicatedStorage/TransitionEvent/` (RemoteEvent)
- `src/System/GUI/ReplicatedStorage/TransitionStart/` (BindableEvent)
- `src/System/GUI/ReplicatedStorage/TransitionCovered/` (BindableEvent)
- `src/System/GUI/ReplicatedStorage/TransitionComplete/` (BindableEvent)

**Modified Files:**
- `default.project.json` - Added Camera module mapping
- `src/Assets/GlobalTimer/_ServerScriptService/Script.server.lua` - Dual-mode support
- `src/Assets/GlobalTimer/StarterGui/LocalScript.client.lua` - Dual-mode UI
- `src/Assets/Orchestrator/_ServerScriptService/Script.server.lua` - Transition, countdown, freeze
- `src/System/GUI/ReplicatedFirst/Styles.lua` - Countdown styles
- `src/System/ReplicatedStorage/GameManifest.lua` - CountdownTimer wiring
- `src/System/RunModes/ReplicatedFirst/RunModesConfig.lua` - CountdownTimer in modes

---

---

### Day 11 (Jan 9, 2026) - ArrayPlacer/Dropper Spawning Bug Fixes

**Session 23**

**Bug: Dynamically Spawned Walking NPCs Invisible**

The ArrayPlacer → Dropper → TimedEvaluator spawn chain was working (HUDs visible with emoji), but the Walking NPC humanoid models inside the TimedEvaluators were not appearing.

**Investigation Path:**
1. Initial hypothesis: Visibility system issue - Walking NPC parts set to Transparency=1
2. Checked Visibility.showModel() logic - appeared correct
3. User confirmed Transparency=0 at runtime - visibility not the problem
4. User suggested: parts might be falling through the world
5. Confirmed: Walking NPC humanoid parts were **not anchored**
6. Parts spawned below ground level and fell out of the map immediately

**Root Cause:**
The TimedEvaluator template contains a Walking NPC (R6 Humanoid with body parts + clothing). These parts are intentionally unanchored for future pathfinding. However, when spawned by DropperModule, the model's pivot placed the NPC at/below ground level, causing unanchored parts to fall through the baseplate.

**Solution: Grounding Logic in TimedEvaluatorModule**

Added grounding code to `TimedEvaluatorModule.initialize()` that:
1. Finds the lowest point of all BaseParts in the model
2. Calculates offset needed to place feet at ground level (GroundY attribute, defaults to 0)
3. Pivots the entire model up by that offset before physics takes over

```lua
-- Ground the model so its bottom sits at ground level
local groundY = model:GetAttribute("GroundY") or 0
local minY = math.huge
for _, part in ipairs(model:GetDescendants()) do
    if part:IsA("BasePart") then
        local bottomY = part.Position.Y - (part.Size.Y / 2)
        if bottomY < minY then
            minY = bottomY
        end
    end
end
if minY ~= math.huge then
    local offset = groundY - minY
    if math.abs(offset) > 0.01 then
        model:PivotTo(model:GetPivot() + Vector3.new(0, offset, 0))
    end
end
```

**Result:** 4 camper NPCs now spawn correctly around the campfire, each with visible Walking NPC models and working HUDs.

**Known Issue (Deferred):** Walking NPCs sometimes fall over due to incomplete Humanoid physics setup (no HumanoidRootPart or proper Motor6D joints). Will address when implementing pathfinding.

---

**Lesson Learned: Unanchored Part Spawning**

When dynamically spawning models with unanchored parts:
- Parts fall immediately when parented to Workspace
- Model pivot position is critical - must account for part heights
- Grounding logic should run BEFORE the model is parented, or immediately after
- For humanoids: ensure feet are at ground level, not center of model

---

---

### Day 12 (Jan 10, 2026) - Central Router & Configurable Anchor System

**Session 24**

**Major Success: Central Message Router (System.Router)**

Replaced ad-hoc event wiring with a centralized message routing system, similar to a network router/firewall.

**Problem Identified:**
- Orchestrator.Output was only wired to WaveController.Input
- Targeted commands (with `target` field) never reached their destinations
- Asset enable/disable commands went to WaveController instead of actual assets

**Solution: System.Router**

Created `System/ReplicatedStorage/Router.lua` with dual routing modes:

1. **Targeted Routing:** Messages with `target` field go directly to `target.Input`
```lua
System.Router:Send(assetName, {
    target = "MarshmallowBag",
    command = "reset",
})
-- Routes to: MarshmallowBag.Input
```

2. **Static Wiring Fallback:** Messages without `target` use GameManifest wiring
```lua
System.Router:Send(assetName, {
    action = "gameStarted",
})
-- Routes to all destinations wired from assetName.Output
```

**Context-Based Filtering:**
```lua
System.Router:SetContext("gameActive", true)
System.Router:AddRule({
    action = "camperFed",
    condition = function(ctx) return ctx.gameActive end,
})
```

**Files Updated:**
- Created `System/ReplicatedStorage/Router.lua`
- Updated `System/ReplicatedStorage/System.lua` to export Router
- Updated `System/Script.server.lua` to initialize Router with wiring config
- Updated `Orchestrator` to use `System.Router:Send()` instead of direct fires
- Updated `WaveController` to use Router for spawn commands
- Cleaned up `GameManifest.lua` wiring (removed redundant routes)

---

**Major Success: Configurable Anchor System**

Refactored the anchor concept to support both dedicated anchor parts AND body parts (like Head for Humanoids).

**Problem:**
- Static assets use dedicated invisible Anchor part for HUD/prompts
- Humanoid NPCs need HUD to follow body parts naturally
- Previous: HUD attached to Anchor which detached from NPC during physics

**Solution: Visibility.resolveAnchor()**

Created utility function with resolution priority:
1. `AnchorPart` attribute (explicit body part name)
2. Literal "Anchor" child part (dedicated anchor)
3. Auto-detect for Humanoids (prefers Head, falls back to HumanoidRootPart)

```lua
local anchor, isBodyPart = Visibility.resolveAnchor(model)

if isBodyPart then
    -- Body part anchor (Head): keep visible, allow touch
    anchor.CanTouch = true
else
    -- Dedicated Anchor: make invisible, anchored
    anchor.Anchored = true
    anchor.Transparency = 1
    anchor.CanCollide = false
end
```

**Updated Assets:**
- `TimedEvaluatorModule.lua` - Uses resolveAnchor, handles body parts vs dedicated anchors
- `TimedEvaluator/LocalScript.client.lua` - Uses resolveAnchor for BillboardGui adornee
- `Visibility.lua` - Added resolveAnchor(), updated bindToAnchor() to skip Humanoids

---

**Bug Fixes: Humanoid Physics**

**Issue 1: Campers having seizures**
- Cause: AlignPosition/AlignOrientation constraints fighting with Humanoid physics
- Fix: `bindToAnchor()` returns early for Humanoids (they handle their own physics)

**Issue 2: Campers falling over on spawn**
- Cause: Humanoid physics not initialized, parts falling through ground
- Fix: Temporary anchoring + velocity zeroing + forced state changes (GettingUp → Running)

```lua
if humanoid then
    rootPart.Anchored = true
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero

    task.delay(0.1, function()
        rootPart.Anchored = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        task.delay(0.1, function()
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end)
end
```

---

**Architecture Insights**

1. **Router vs Direct Wiring:** Central routing provides:
   - Single point of message flow control
   - Easy debugging (log all messages in one place)
   - Context-based filtering for game state
   - Cleaner GameManifest (declarative routes)

2. **Anchor as Primary Part:** Making anchor configurable enables:
   - Same code works for static assets and Humanoids
   - HUD follows NPC naturally when anchor IS the Head
   - No BillboardGui reparenting needed
   - ProximityPrompts work on body parts

3. **Humanoid Physics Separation:** Don't fight Roblox physics:
   - Skip constraint binding for Humanoids
   - Use temporary anchoring for spawn stability
   - Force state changes to ensure standing position

---

**Files Changed This Session:**

**New:**
- `src/System/ReplicatedStorage/Router.lua`

**Modified:**
- `src/System/ReplicatedStorage/System.lua` (added Router export)
- `src/System/ReplicatedStorage/Visibility.lua` (added resolveAnchor, updated bindToAnchor)
- `src/System/Script.server.lua` (Router initialization)
- `src/System/ReplicatedStorage/GameManifest.lua` (updated wiring)
- `src/Assets/Orchestrator/_ServerScriptService/Script.server.lua` (use Router:Send)
- `src/Assets/WaveController/_ServerScriptService/Script.server.lua` (use Router:Send, wave handlers)
- `src/Assets/WaveController/init.meta.json` (className: Model)
- `src/Assets/TimedEvaluator/ReplicatedStorage/TimedEvaluatorModule.lua` (use resolveAnchor)
- `src/Assets/TimedEvaluator/StarterGui/LocalScript.client.lua` (use resolveAnchor)

---

---

### Day 13 (Jan 11, 2026) - v2 Architecture Design: Nodes & IPC

**Session 25**

**Context: Framework v2 Design Phase**

After completing the Debug/Log subsystem simplification (centralized groups, context detection, shared Config in ReplicatedFirst), began designing the IPC subsystem. This led to a fundamental architectural discussion about how v2 should structure component communication.

---

**Major Design Decision: The Node Concept**

Introduced a system-level abstraction called a **Node**. Nodes formalize what v1's assets were doing implicitly:

```
┌─────────────────────────────────────────────────────────────────┐
│                         NODE (Generic)                          │
├─────────────────────────────────────────────────────────────────┤
│  PINOUTS (Standard I/O)                                         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                         │
│  │   In    │  │   Out   │  │   Dbg   │                         │
│  └─────────┘  └─────────┘  └─────────┘                         │
├─────────────────────────────────────────────────────────────────┤
│  LIFECYCLE HOOKS (triggered via events, not direct calls)       │
│  • init()   - called on "init" broadcast                        │
│  • start()  - called on "start" broadcast                       │
│  • stop()   - called on "stop" broadcast                        │
├─────────────────────────────────────────────────────────────────┤
│  CUSTOM HANDLERS (defined by implementation)                    │
│  • onSpawn(), onDrop(), onCollect(), etc.                       │
└─────────────────────────────────────────────────────────────────┘
```

**Inheritance Model (Lua Prototypes):**
```
Node (prototype)           <- Defines pinouts, lifecycle hooks
    │
    ▼ extends (metatables)
DispenserBase (Lib)        <- Interface + default behavior
    │
    ▼ extends
MarshmallowBag (Game)      <- Game-specific implementation
    │
    ▼ instantiate
Runtime Instance           <- Active in workspace
```

**Key Insight: Event-Driven Lifecycle**

Lifecycle methods are NOT called directly. Instead:
```lua
-- Instead of:
for _, node in nodes do node:init() end

-- We broadcast:
IPC.broadcast("lifecycle:init", { context = "server" })

-- Each node's In channel receives it and triggers internal init()
```

This enables coordinated initialization across the system with context-aware filtering.

---

**The Breadboard Analogy**

User provided a hardware electronics analogy that crystallized the architecture:

| Electronics | System |
|-------------|--------|
| ICU (Integrated Circuit) | Node |
| Breadboard | Run Mode wiring config |
| Traces/wires | Message routes |
| Voltage input | Active mode |
| Switching boards | Mode transition |

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SYSTEM (Power Supply)                            │
│                              │                                          │
│                         ┌────▼────┐                                     │
│                         │  SWITCH │  ← Active Run Mode                  │
│                         └────┬────┘                                     │
│              ┌───────────────┼───────────────┐                          │
│              ▼               ▼               ▼                          │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                 │
│   │  TUTORIAL    │  │   PLAYING    │  │   RESULTS    │                 │
│   │  (Breadboard)│  │  (Breadboard)│  │  (Breadboard)│                 │
│   │              │  │              │  │              │                 │
│   │ [Dropper]────│  │ [Dropper]────│  │              │                 │
│   │      │       │  │      │       │  │ [Scoreboard] │                 │
│   │      ▼       │  │      ▼       │  │      │       │                 │
│   │ [SimpleUI]   │  │ [Evaluator]──│  │      ▼       │                 │
│   │              │  │      │       │  │ [Leaderboard]│                 │
│   │              │  │      ▼       │  │              │                 │
│   │              │  │ [Scoreboard] │  │              │                 │
│   └──────────────┘  └──────────────┘  └──────────────┘                 │
│                                                                         │
│   Same ICUs (Nodes), different wiring per mode                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Implications:**
1. **Nodes are mode-agnostic** - They just respond to signals on their pins
2. **Wiring is declarative** - Each run mode has a manifest defining connections
3. **Mode switch = rewire** - IPC swaps active wiring config, nodes don't change
4. **Broadcasts follow wires** - Signals only reach nodes in the active config

---

**Critical Analysis: Is This Architecture Sound?**

Before committing to implementation, conducted critical analysis against stated goals:
- Reusability
- Portability
- Ease of use
- Component independence with zero hard dependencies

**Strengths:**

1. **True Decoupling** ✓
   - Nodes have no `require()` calls to other nodes
   - Dependencies are explicit in wiring config, not hidden in code
   - This is how hardware actually works - chips don't import each other

2. **Reusability** ✓
   - A Dropper node works in any game that needs dropping
   - No code changes needed - just different wiring
   - Lib vs Game split is clean

3. **Testability** ✓
   - Test nodes in isolation: send signal to In, assert on Out
   - Mock IPC trivially
   - No need to bootstrap entire game to test one component

4. **Proven Patterns** ✓
   - Actor model (Erlang, Akka) - battle-tested at scale
   - Hardware description (Verilog) - literal billion-dollar industry
   - Visual programming (Unreal Blueprints, Node-RED)

**Concerns:**

1. **Debugging Indirection**
   - Signal goes Node A → IPC → Node B → IPC → Node C
   - Stack trace shows IPC internals, not logical flow
   - *Mitigation: Debug subsystem needs signal tracing*

2. **Performance Overhead**
   - Every interaction routes through IPC
   - Message lookup, filtering, dispatch costs
   - *Assessment: Acceptable for Roblox scale*

3. **Learning Curve**
   - Developers expect `require()` and direct calls
   - "Where's the code that connects these?" → "It's in the wiring config"
   - *Mitigation: Good documentation, clear examples*

4. **Contract Enforcement**
   - Lua has no interfaces - can't enforce that a node implements `init()`
   - Runtime errors if signal format is wrong
   - *Mitigation: Validation in IPC, clear error messages*

5. **Wiring Complexity at Scale**
   - 5 nodes: trivial
   - 50 nodes: config gets large
   - *Mitigation: Composable wiring configs, good tooling*

**Comparison to Alternatives:**

| Approach | Decoupling | Reusability | Simplicity |
|----------|------------|-------------|------------|
| Direct requires | Poor | Poor | High |
| Simple event bus | Medium | Medium | Medium |
| ECS | High | High | Low |
| **Node/Wiring** | **High** | **High** | **Medium** |

---

**Decision: Proceed with Safeguards**

The unconventional nature is protective - it *forces* clean separation and makes dependencies visible.

**Required Safeguards:**
1. Strong validation in IPC (catch bad wiring at registration, not runtime)
2. Signal tracing in Debug (see message flow)
3. Start with minimal lifecycle hooks (init, start, stop) - add more only when needed
4. Document the mental model before the API

---

**IPC Subsystem Requirements (Derived)**

```lua
IPC.registerNode(node)           -- Add node to the system
IPC.setWiring("Playing", {...})  -- Define mode wiring config
IPC.switchMode("Playing")        -- Activate a wiring config
IPC.send(signal)                 -- Signal flows through active wiring
IPC.broadcast("init")            -- Lifecycle signal to all active nodes
```

**Open Questions for Implementation:**
1. Registration: Do nodes self-register or does IPC discover them?
2. Lifecycle phases: What's the full sequence? (register → init → start → ready → stop → cleanup?)
3. Context filtering: What determines which nodes receive a broadcast?
4. Barrier sync: Can lifecycle broadcasts wait for all nodes to complete?

---

**Files Changed This Session:**

**Debug/Log Simplification (Prior to Design Discussion):**
- `src/Warren/System.lua` - Added context detection, centralized groups, Utils.mergeConfig()
- `src/Warren/Config.lua` → moved to `src/ReplicatedFirst/Config.lua`
- `src/Bootstrap.server.lua` - Updated to use shared Config
- `default.project.json` - Added ReplicatedFirst mapping

**Documentation:**
- `Logs/PROJECT_JOURNAL.md` - This entry

---

---

### Day 14 (Jan 11, 2026) - IPC & Node System Implementation

**Session 26**

**Major Success: Complete IPC & Node System Implementation**

Implemented the full IPC (Inter-Process Communication) and Node architecture based on the spec designed in Session 25. This is the core infrastructure that enables the "breadboard model" for v2.

---

**Node Base Class (`src/Warren/Node.lua`)**

Created the foundational Node class with:

**Core Methods:**
- `Node.extend(definition)` - Prototype inheritance with metatable chaining
- `Node:new(config)` - Instance creation with ID, model, pins
- `Node:getInheritanceChain()` - Walk ancestor chain for contract validation
- `Node:hasHandler(pin, name)` - Check handler existence
- `Node:resolvePin(mode, pinType)` - Mode-specific pin resolution with fallback

**Attribute System:**
- `Node:getAttribute(name)` - Get from model or internal store
- `Node:setAttribute(name, value)` - Set on model and internal store
- `Node:getAttributes()` - Get all attributes

**Pin Channels:**
- `Out` channel - Fire signals via IPC routing
- `Err` channel - Propagate errors to IPC.handleError

**Contract System:**
```lua
Node.defaults = {
    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
        onModeChange = function(self, oldMode, newMode) end,
        onSpawned = function(self) end,
        onDespawning = function(self) end,
    }
}

Node.required = {
    Sys = { "onInit", "onStart", "onStop" }
}
```

**Inheritance Example:**
```lua
-- Lib layer: Define interface with requirements
local Dispenser = Node.extend({
    name = "Dispenser",
    required = { In = { "onDispense" } },  -- MUST implement
    defaults = {
        In = { onRefill = function(self) ... end },  -- Optional override
    },
})

-- Game layer: Implement requirements
local MarshmallowBag = Dispenser.extend({
    name = "MarshmallowBag",
    In = {
        onDispense = function(self) ... end,  -- Required - implemented
        -- onRefill uses Dispenser default
    },
})
```

---

**IPC Subsystem (`src/Warren/System.lua`)**

Added comprehensive IPC subsystem (~800 lines) following the IIFE closure pattern:

**Private State:**
```lua
local nodeDefinitions = {}   -- { className → NodeClass }
local instances = {}         -- { instanceId → instance }
local nodesByClass = {}      -- { className → [instanceId, ...] }
local modeConfigs = {}       -- { modeName → config }
local currentMode = nil
local messageCounter = 0
local seenMessages = {}      -- { msgId → { nodeId → true } }
local isInitialized = false
local isStarted = false
```

**Node Registration API:**
- `IPC.registerNode(NodeClass)` - Validate contract, store definition
- `IPC.createInstance(className, config)` - Create instance with domain check
- `IPC.getInstance(id)` - Get by ID
- `IPC.getInstancesByClass(className)` - Get all of class
- `IPC.spawn(className, config)` - Create + lifecycle hooks
- `IPC.despawn(instanceId)` - Cleanup + destroy

**Mode Management API:**
- `IPC.defineMode(name, config)` - Store wiring config
- `IPC.switchMode(name)` - Broadcast onModeChange, apply attributes
- `IPC.getMode()` - Get current mode name
- `IPC.getModeConfig(name)` - Get mode definition

**Messaging API:**
- `IPC.getMessageId()` - Blocking, returns linear integer
- `IPC.send(sourceId, signal, data)` - Route through active wiring
- `IPC.sendTo(targetId, signal, data)` - Direct to instance
- `IPC.broadcast(signal, data)` - To all Sys.In

**Key Internal Functions:**
- `validateContract(NodeClass)` - Check required handlers exist
- `wireInstance(instance)` - Connect Out/Err to IPC routing
- `resolveWiring(modeName)` - Merge with base mode
- `resolveTargets(sourceId, signal, targetSpec)` - Wiring lookup
- `dispatchToTarget(targetId, signal, data, msgId)` - Execute handler
- `executeHandler(instance, pin, handlerName, data)` - pcall wrapper

**Lifecycle API:**
- `IPC.init()` - Call onInit on all instances
- `IPC.start()` - Call onStart, enable routing
- `IPC.stop()` - Call onStop, cleanup

---

**Bootstrap Updates**

**Server (`src/Bootstrap.server.lua`):**
- Exposed `_G.Node` for Studio command bar testing
- Initialize and start IPC after Log.init()
- Added usage example comments

**Client (`src/Bootstrap.client.lua`) - NEW:**
- Mirror of server bootstrap for client context
- Memory-only Log backend (DataStore is server-only)
- Domain-aware IPC (client nodes only)

**Project Config (`default.project.json`):**
- Added StarterPlayer > StarterPlayerScripts mapping for client bootstrap

---

**Wiring Configuration Example**

```lua
-- Define modes with wiring
IPC.defineMode("Playing", {
    nodes = { "Dropper", "Evaluator", "Scoreboard" },
    wiring = {
        Dropper = { "Evaluator" },
        Evaluator = { "Scoreboard" },
    },
})

IPC.defineMode("Tutorial", {
    base = "Playing",  -- Inherits Playing wiring
    nodes = { "Dropper", "Evaluator", "Scoreboard", "HintUI" },
    wiring = {
        Dropper = { "Evaluator", "HintUI" },
        Evaluator = { "Scoreboard", "HintUI" },
    },
    attributes = {
        Dropper = { DropSpeed = 0.5 },  -- Mode-specific config
    },
})
```

---

**Testing in Studio Command Bar**

```lua
-- Test Node.extend
local TestNode = _G.Node.extend({
    name = "TestNode",
    Sys = {
        onInit = function(self) print("Init:", self.id) end,
        onStart = function(self) print("Start:", self.id) end,
        onStop = function(self) print("Stop:", self.id) end,
    },
    In = {
        onPing = function(self, data)
            print("Ping received:", data.msg)
            self.Out:Fire("pong", { reply = "hello" })
        end
    },
})

-- Register and test
_G.IPC.reset()
_G.IPC.registerNode(TestNode)
local inst = _G.IPC.createInstance("TestNode", { id = "test1" })

-- Define mode
_G.IPC.defineMode("Test", {
    nodes = { "TestNode" },
    wiring = { TestNode = { "TestNode" } }
})

-- Lifecycle
_G.IPC.init()
_G.IPC.switchMode("Test")
_G.IPC.start()

-- Send message
_G.IPC.sendTo("test1", "ping", { msg = "hello" })
```

---

**Key Design Decisions**

1. **IIFE Closure Pattern** - Matches Debug/Log structure for consistency
2. **Contract Validation at Registration** - Fail fast, clear error messages
3. **Domain-Aware Instances** - Server nodes skip on client, vice versa
4. **Cycle Detection via Message ID** - Each message can only visit a node once
5. **Mode Inheritance** - Tutorial extends Playing, adds/overrides wiring
6. **pcall Protection** - All handlers wrapped, errors routed to Err channel

---

**Files Created/Modified**

| File | Action | Lines |
|------|--------|-------|
| `src/Warren/Node.lua` | CREATE | ~400 |
| `src/Warren/System.lua` | MODIFY | +800 |
| `src/Warren/init.lua` | MODIFY | +3 |
| `src/Bootstrap.server.lua` | MODIFY | +15 |
| `src/Bootstrap.client.lua` | CREATE | ~85 |
| `default.project.json` | MODIFY | +10 |
| `docs/IPC_NODE_SPEC.md` | CREATE | ~1200 |

---

**Architecture Milestone**

This implementation completes the core infrastructure for v2:

```
System.Debug  ✓  Console logging with filtering
System.Log    ✓  Persistent telemetry
System.IPC    ✓  Node registration, routing, lifecycle
Lib.Node      ✓  Base class with pins, contracts, inheritance

Remaining placeholders:
System.State  □  Shared state management
System.Asset  □  Template registry and spawning
System.Store  □  Persistent storage
System.View   □  Presentation layer
```

The breadboard model is now operational. Nodes can be defined, registered, wired, and communicate through the IPC system without knowing about each other.

---

## Statistics

- **Session Logs Written:** 26
- **Commits:** ~38
- **Lua Files:** 56+
- **Assets Built:** 11
- **Templates Built:** 2
- **System Modules Built:** 8 (added Node)
- **Lines of Code:** ~7,800 (estimate, +1,400 this session)
- **Debug Calls Migrated:** 97
- **Major Pivots:** 8
- **Days to Working Game Loop:** 2
- **Documentation Pages:** 4 (added IPC_NODE_SPEC)

---

---

### Feb 7, 2026 - Rename: LibPureFiction → Warren

**Context: Alpha Rabbit Branding**

Renamed the entire project from LibPureFiction to **Warren** as part of branding under the Alpha Rabbit identity. Clean break — no backwards compatibility shims, no aliases.

---

**Scope of Changes**

| Area | What Changed |
|------|-------------|
| GitHub repos | `purefictiongames/LibPureFiction` → `purefictiongames/Warren`, `LibPureFiction-Core` → `Warren-Core` |
| Rojo project files | `"name"` field in both `default.project.json` files |
| Rojo tree path | `"Lib"` key → `"Warren"` + directory rename `src/Lib` → `src/Warren` |
| Lua require paths | `game.ReplicatedStorage.Lib` → `game.ReplicatedStorage.Warren` (~75 in game repo, ~7 in Core) |
| Lua WaitForChild | `WaitForChild("Lib")` → `WaitForChild("Warren")` (~36 occurrences) |
| Lua globals | `_G.Lib` → `_G.Warren` |
| Lua file headers | `LibPureFiction Framework v2` → `Warren Framework v2` (100+ files) |
| DataStore name | `"LibPureFiction_Logs"` → `"Warren_Logs"` in System.lua |
| Documentation | All `.md` files across both repos (30+ files) |
| Website | `/var/www/itgetsworse/libpurefiction/` → `/warren/`, display text + internal links in 21 HTML files |
| AlphaRabbit | 3 files (summaries + blog manifest) |
| Wally package | `libpurefiction/system` → `warren/system`, author updated |
| IP statement files | Filenames renamed to include "Warren" |
| Git remotes | Both repos updated to new GitHub URLs |
| Local directories | `~/LibPureFiction` → `~/Warren`, `~/LibPureFiction-Core` → `~/Warren-Core` |

**Execution Order:** GitHub renames first (so redirects catch any in-flight references), then Core repo, game repo, website, AlphaRabbit, local directory renames last.

**Gotcha Found During Execution:** Some Lua files used `ReplicatedStorage.Lib` without the `game.` prefix (common in test files and demos). The initial `sed` pass targeting `game.ReplicatedStorage.Lib` missed ~20 occurrences. Caught during post-replacement grep and fixed with a second pass.

**Commits:**
- Warren-Core: `b6c0cde` — 48 files changed
- Warren: `3e79c22` — 181 files changed
- AlphaRabbit: `2f54290` — 3 files changed

**Verification:** `grep -ri "LibPureFiction"` across all locations returns zero results. GitHub repos accessible at new URLs. Git remotes updated.
