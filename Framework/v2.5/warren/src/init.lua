--[[
    Warren Framework v2.5
    Main Entry Point

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Warren is a Roblox game framework designed for developer ergonomics.
    It follows an Arduino-like model where games are composed of modular
    components wired together through a unified messaging bus.

    This module is the public API surface. Games consume Warren as a package
    and build their own Components, Admin, and Game modules separately.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Warren = require(game.ReplicatedStorage.Warren)

    -- Access system subsystems
    local Debug = Warren.System.Debug
    local IPC = Warren.System.IPC

    -- Configure debug
    Debug.configure({ level = "trace" })

    -- Log messages
    Debug.info("MyModule", "Framework loaded")

    -- Create DOM elements
    local room = Warren.Dom.createElement("Room", { width = 20 })
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

local Warren = {
    _VERSION = "2.5.3",
}

-- Core system module (Debug, IPC, State, Asset, Store, View)
Warren.System = require(script.System)

-- Node base class for game components
Warren.Node = require(script.Node)

-- Factory: Declarative instance builder (geometry, gui)
Warren.Factory = require(script.Factory)

-- GeometrySpec: Backwards compatibility wrapper (prefer Warren.Factory)
Warren.GeometrySpec = require(script.GeometrySpec)

-- Dom: DOM tree API (getElementById, appendChild, setAttribute, etc.)
Warren.Dom = require(script.Dom)

-- Styles: Style definitions and resolution
Warren.Styles = require(script.Styles)

-- ClassResolver: DOM class inheritance resolution
Warren.ClassResolver = require(script.ClassResolver)

-- Internal: EntityUtils, SchemaValidator, etc. (for advanced component use)
Warren.Internal = require(script.Internal)

-- PixelFont: Bitmap font rendering for UI components
Warren.PixelFont = require(script.PixelFont)

return Warren
