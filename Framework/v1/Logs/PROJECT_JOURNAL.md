> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# LibPureFiction Framework - Project Journal

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

## Statistics

- **Session Logs Written:** 18
- **Commits:** ~30
- **Lua Files:** 40+
- **Assets Built:** 11 (added Camper, Tutorial)
- **Templates Built:** 2
- **System Modules Built:** 4 (added RunModes)
- **Lines of Code:** ~4,500 (estimate)
- **Debug Calls Migrated:** 97
- **Major Pivots:** 4 (added RunModes refactor)
- **Days to Working Game Loop:** 2
