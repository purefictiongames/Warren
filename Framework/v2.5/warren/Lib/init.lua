--[[
    LibPureFiction Framework v2
    Main Entry Point

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LibPureFiction is a Roblox game framework designed for developer ergonomics.
    It follows an Arduino-like model where games are composed of modular
    components wired together through a unified messaging bus.

    This module (Lib) is the main entry point. It exposes:
        - System: Core framework subsystems (Debug, IPC, State, Asset, Store, View)
        - Future: Asset modules, utilities, etc.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Lib = require(game.ReplicatedStorage.Lib)

    -- Access system subsystems
    local Debug = Lib.System.Debug
    local IPC = Lib.System.IPC

    -- Configure debug
    Debug.configure({ level = "trace" })

    -- Log messages
    Debug.info("MyModule", "Framework loaded")
    ```

    ============================================================================
    ARCHITECTURE
    ============================================================================

    See docs/ARCHITECTURE.md for full documentation.

    Key principles:
    - Single ModuleScript per system with nested submodules
    - No code runs on load - Bootstrap controls execution
    - Declarative manifest defines structure and wiring
    - Closure-protected internals with public API surface
    - Singleton/Factory pattern for each subsystem

--]]

local Lib = {
    _VERSION = "2.5.2",
}

-- Core system module (Debug, IPC, State, Asset, Store, View)
Lib.System = require(script.System)

-- Node base class for game components
Lib.Node = require(script.Node)

-- Factory: Declarative instance builder (geometry, gui)
Lib.Factory = require(script.Factory)

-- GeometrySpec: Backwards compatibility wrapper (prefer Lib.Factory)
Lib.GeometrySpec = require(script.GeometrySpec)

-- Dom: DOM tree API (getElementById, appendChild, setAttribute, etc.)
Lib.Dom = require(script.Dom)

-- Content modules (Components, Admin, Layouts, etc.) are injected by the
-- game's Rojo project file. They appear as children of this script at runtime
-- but live in separate directories on disk.
local function optionalRequire(name)
    local child = script:FindFirstChild(name)
    return child and require(child) or nil
end

Lib.Components = optionalRequire("Components")
Lib.Admin = optionalRequire("Admin")
Lib.Layouts = optionalRequire("Layouts")

return Lib
