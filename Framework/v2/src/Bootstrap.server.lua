--[[
    LibPureFiction Framework v2
    Server Bootstrap

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the server entry point. It:
    1. Requires the Lib module
    2. Configures system subsystems
    3. Initializes the framework in the correct order

    Nothing in the framework runs until this script explicitly calls it.

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Lib to be available (Rojo sync)
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Debug = Lib.System.Debug

--------------------------------------------------------------------------------
-- STUDIO CLI ACCESS
--------------------------------------------------------------------------------
-- Expose globals for command bar testing in Studio
-- These are stripped in production (non-Studio) builds

if RunService:IsStudio() then
    _G.Lib = Lib
    _G.Node = Lib.Node
    _G.Debug = Lib.System.Debug
    _G.Log = Lib.System.Log
    _G.IPC = Lib.System.IPC
    _G.State = Lib.System.State
    _G.Asset = Lib.System.Asset
    _G.Store = Lib.System.Store
    _G.View = Lib.System.View
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Groups are defined in Lib/Config.lua (shared by all contexts).
-- Uncomment below to override at runtime:
-- Lib.System.setGroups({
--     Core = { "System.*", "Bootstrap", "Log" },
--     Gameplay = { "Combat.*", "Economy.*", "Inventory.*" },
-- })

-- Configure debug output (defaults from Config.lua, override here if needed)
Debug.configure({
    level = "info",  -- "error", "warn", "info", "trace"
    -- show = { "@Core" },  -- Use @GroupName to reference groups
    -- hide = { "*.Tick" },
    -- solo = {},  -- If non-empty, ONLY these patterns show
})

-- Configure persistent logging (defaults from Config.lua, override here if needed)
local Log = Lib.System.Log
Log.configure({
    backend = "Memory",  -- "Memory", "DataStore", "None"
    -- capture = { "@Gameplay" },  -- Use @GroupName to capture specific groups
    -- ignore = { "*.Tick" },
})

--------------------------------------------------------------------------------
-- BOOTSTRAP
--------------------------------------------------------------------------------

Debug.info("Bootstrap", "LibPureFiction v" .. Lib._VERSION)
Debug.info("Bootstrap", "Server starting...")

-- Initialize Log subsystem (generates session ID, starts auto-flush)
Log.init()

--------------------------------------------------------------------------------
-- ASSET REGISTRATION
--------------------------------------------------------------------------------
-- Register node classes from Lib and Game before IPC initialization.
-- This builds the inheritance tree and validates contracts.

local Asset = Lib.System.Asset
local IPC = Lib.System.IPC

-- Wait for Game module (game-specific node implementations)
local Game = require(ReplicatedStorage:WaitForChild("Game"))

-- Register Lib-level nodes (base classes)
-- Example:
--   Asset.register(require(Lib.Dispenser))
--   Asset.register(require(Lib.Evaluator))

-- Register Game-level nodes (game-specific implementations)
-- Example:
--   Asset.register(Game.MarshmallowBag)
--   Asset.register(Game.Camper)

-- Verify all expected classes are registered
-- Asset.verify({ "Dispenser", "MarshmallowBag", "Evaluator", "Camper" })

-- Build inheritance tree (for introspection/debugging)
Asset.buildInheritanceTree()

--------------------------------------------------------------------------------
-- MODE DEFINITION
--------------------------------------------------------------------------------
-- Define run modes with wiring configurations.
-- Each mode specifies which nodes are active and how they're connected.

-- Example:
-- IPC.defineMode("Playing", {
--     nodes = { "MarshmallowBag", "Camper" },
--     wiring = {
--         MarshmallowBag = { "Camper" },
--     },
-- })

--------------------------------------------------------------------------------
-- IPC INITIALIZATION
--------------------------------------------------------------------------------

-- Initialize IPC (calls onInit on all registered instances)
IPC.init()

-- Start IPC (enables routing, calls onStart on all instances)
IPC.start()

--------------------------------------------------------------------------------
-- ASSET SPAWNING
--------------------------------------------------------------------------------
-- Spawn node instances for models in Workspace.
-- Models must have a NodeClass attribute specifying which class to use.

-- Example: Spawn all models in RuntimeAssets container
-- local RuntimeAssets = workspace:FindFirstChild("RuntimeAssets")
-- if RuntimeAssets then
--     Asset.spawnAll(RuntimeAssets)
-- end

-- TODO: Initialize other subsystems in order
-- Lib.System.State.init()
-- Lib.System.Store.init()

Debug.info("Bootstrap", "Server ready")
