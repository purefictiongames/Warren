--[[
    LibPureFiction Framework v2
    Components/init.lua - Component Library Index

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This module exports all reusable game components. Components are pre-built
    Node extensions that implement common game mechanics.

    Components are designed to be:
    - Standalone: Work independently with minimal dependencies
    - Composable: Can be combined to create complex behaviors
    - Signal-driven: All control via In/Out pins per v2 architecture

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Lib = require(game.ReplicatedStorage.Lib)
    local PathFollower = Lib.Components.PathFollower

    -- Register with IPC
    System.Asset.register(PathFollower)
    ```

--]]

local Components = {}

-- Navigation
Components.PathFollower = require(script.PathFollower)

return Components
