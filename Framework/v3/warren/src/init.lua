--[[
    Warren Framework v3.0
    Main Entry Point

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Warren is a dual-runtime Luau framework running on both Roblox and Lune.
    It follows an Arduino-like model where games are composed of modular
    components wired together through a unified messaging bus.

    On Roblox: Full stack — DOM, Factory, Renderer, Transport client.
    On Lune:   Headless — Shared logic, Transport server, Open Cloud.

    This module is the public API surface. Runtime detection determines
    which subsystems are loaded.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Roblox
    local Warren = require(game.ReplicatedStorage.Warren)
    local room = Warren.Dom.createElement("Room", { width = 20 })

    -- Lune
    local Warren = require("warren")
    Warren.Transport.start({ port = 8080, authToken = "..." })
    ```

    ============================================================================
    ARCHITECTURE
    ============================================================================

    See docs/ARCHITECTURE.md and docs/ADR-001.md for full documentation.

    Key principles:
    - Single ModuleScript per system with nested submodules
    - No code runs on load - Bootstrap controls execution
    - Declarative manifest defines structure and wiring
    - Closure-protected internals with public API surface
    - Singleton/Factory pattern for each subsystem
    - Runtime-conditional loading (Roblox vs Lune)

--]]

local Warren = {
    _VERSION = "3.0.0",
}

-- Dual-runtime require: Lune uses @warren/ aliases, Roblox uses script tree
local _L = script == nil

-- Runtime detection (must load first)
Warren.Runtime = _L and require("@warren/Runtime") or require(script.Runtime)

local isRoblox = Warren.Runtime.isRoblox

-- =============================================================================
-- SHARED MODULES (both runtimes)
-- =============================================================================

-- Styles: Style definitions and resolution
Warren.Styles = _L and require("@warren/Styles") or require(script.Styles)

-- ClassResolver: DOM class inheritance resolution
Warren.ClassResolver = _L and require("@warren/ClassResolver") or require(script.ClassResolver)

-- Transport: Roblox ↔ Lune communication layer
Warren.Transport = _L and require("@warren/Transport") or require(script.Transport)

-- State: Versioned state store, diff engine, sync, predictions
Warren.State = _L and require("@warren/State") or require(script.State)

-- Wire State ↔ Transport binding
Warren.State.bindTransport(Warren.Transport)

-- =============================================================================
-- LUNE-ONLY MODULES
-- =============================================================================

if not isRoblox then
    -- OpenCloud: DataStore, Messaging HTTP clients (API keys stay on VPS)
    Warren.OpenCloud = require("@warren/OpenCloud")

    -- Boot: Lune-side bootstrap sequence
    Warren.Boot = require("@warren/Boot")
end

-- =============================================================================
-- ROBLOX-ONLY MODULES
-- =============================================================================

if isRoblox then
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

    -- Internal: EntityUtils, SchemaValidator, etc. (for advanced component use)
    Warren.Internal = require(script.Internal)

    -- PixelFont: Bitmap font rendering for UI components
    Warren.PixelFont = require(script.PixelFont)
end

return Warren
