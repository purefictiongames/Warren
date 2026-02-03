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
    _VERSION = "2.0.0-dev",
}

-- Core system module (Debug, IPC, State, Asset, Store, View)
Lib.System = require(script.System)

-- Node base class for game components
Lib.Node = require(script.Node)

-- Reusable component library (PathFollower, etc.)
Lib.Components = require(script.Components)

-- Factory: Declarative instance builder (geometry, gui)
Lib.Factory = require(script.Factory)

-- GeometrySpec: Backwards compatibility wrapper (prefer Lib.Factory)
Lib.GeometrySpec = require(script.GeometrySpec)

-- Standalone map layouts (used with Factory.geometry)
Lib.Layouts = require(script.Layouts)

-- Admin utilities (SaveData management, etc.)
-- Can be required directly in edit mode: require(game.ReplicatedStorage.Lib.Admin.SaveDataAdmin)
Lib.Admin = require(script.Admin)

-- Test suite is NOT auto-loaded to avoid circular dependency
-- Access via: require(game.ReplicatedStorage.Lib.Tests)

-- Visual demos are NOT auto-loaded to avoid circular dependency
-- Access via: require(game.ReplicatedStorage.Lib.Demos)

return Lib
