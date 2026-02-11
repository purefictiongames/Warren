--[[
    It Gets Worse — Server Bootstrap

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the server entry point. It:
    1. Requires the Warren framework package
    2. Requires game-specific Components
    3. Configures system subsystems
    4. Initializes the framework in the correct order

    Nothing in the framework runs until this script explicitly calls it.

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Warren package and game modules
local Warren = require(ReplicatedStorage:WaitForChild("Warren"))
local Components = require(ReplicatedStorage:WaitForChild("Components"))
local Debug = Warren.System.Debug

--------------------------------------------------------------------------------
-- STUDIO CLI ACCESS
--------------------------------------------------------------------------------
-- Expose globals for command bar testing in Studio
-- These are stripped in production (non-Studio) builds

if RunService:IsStudio() then
    _G.Warren = Warren
    _G.Node = Warren.Node
    _G.Debug = Warren.System.Debug
    _G.Log = Warren.System.Log
    _G.IPC = Warren.System.IPC
    _G.State = Warren.System.State
    _G.Asset = Warren.System.Asset
    _G.Store = Warren.System.Store
    _G.View = Warren.System.View
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Configure debug output (defaults from Config.lua, override here if needed)
Debug.configure({
    level = "info",  -- "error", "warn", "info", "trace"
    -- show = { "@Core" },  -- Use @GroupName to reference groups
    -- hide = { "*.Tick" },
    -- solo = {},  -- If non-empty, ONLY these patterns show
})

-- Configure persistent logging (defaults from Config.lua, override here if needed)
local Log = Warren.System.Log
Log.configure({
    backend = "Memory",  -- "Memory", "DataStore", "None"
    -- capture = { "@Gameplay" },  -- Use @GroupName to capture specific groups
    -- ignore = { "*.Tick" },
})

--------------------------------------------------------------------------------
-- BOOTSTRAP
--------------------------------------------------------------------------------

Debug.info("Bootstrap", "Warren v" .. Warren._VERSION)
Debug.info("Bootstrap", "Server starting...")

-- Initialize Log subsystem (generates session ID, starts auto-flush)
Log.init()

--------------------------------------------------------------------------------
-- ASSET REGISTRATION
--------------------------------------------------------------------------------
-- Register node classes from Warren and Game before IPC initialization.
-- This builds the inheritance tree and validates contracts.

local Asset = Warren.System.Asset
local IPC = Warren.System.IPC

-- Wait for Game module (game-specific node implementations)
local Game = require(ReplicatedStorage:WaitForChild("Game"))

-- Register dungeon nodes with IPC
IPC.registerNode(Components.JumpPad)
IPC.registerNode(Components.RegionManager)
IPC.registerNode(Components.TitleScreen)       -- Client-side, but registered for wiring
IPC.registerNode(Components.ExitScreen)        -- Client-side, but registered for wiring
IPC.registerNode(Components.ScreenTransition)  -- Client-side, but registered for wiring
IPC.registerNode(Components.AreaHUD)           -- Client-side, but registered for wiring
IPC.registerNode(Components.MiniMap)           -- Client-side, but registered for wiring

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

-- Dungeon mode: JumpPad signals route to RegionManager, screen transitions cross client/server
IPC.defineMode("Dungeon", {
    nodes = { "JumpPad", "RegionManager", "TitleScreen", "ExitScreen", "ScreenTransition", "AreaHUD", "MiniMap" },
    wiring = {
        -- Server-side: JumpPad → RegionManager
        JumpPad = { "RegionManager" },
        -- Cross-domain: TitleScreen (client) → RegionManager (server)
        TitleScreen = { "RegionManager" },
        -- Cross-domain: ExitScreen (client) → RegionManager (server)
        ExitScreen = { "RegionManager" },
        -- Cross-domain: RegionManager (server) → TitleScreen, ExitScreen, ScreenTransition, AreaHUD, MiniMap (client)
        RegionManager = { "TitleScreen", "ExitScreen", "ScreenTransition", "AreaHUD", "MiniMap" },
        -- Cross-domain: ScreenTransition (client) → RegionManager (server)
        ScreenTransition = { "RegionManager" },
        -- Cross-domain: MiniMap (client) → RegionManager (server)
        MiniMap = { "RegionManager" },
    },
})

--------------------------------------------------------------------------------
-- IPC INITIALIZATION
--------------------------------------------------------------------------------

-- Initialize IPC (calls onInit on all registered instances)
IPC.init()

-- Switch to Dungeon mode (enables wiring)
IPC.switchMode("Dungeon")

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
-- Warren.System.State.init()
-- Warren.System.Store.init()

--------------------------------------------------------------------------------
-- INFINITE DUNGEON SYSTEM
--------------------------------------------------------------------------------
-- Manages infinite dungeon with region-based generation and teleportation
--
-- TODO: This is a temporary hack. Should be its own script in ServerScriptService.
-- See: src/Game/DungeonServer/_ServerScriptService/DungeonStartup.server.lua
--
-- KNOWN ISSUES:
-- [ ] Lighting is slow to load on first play. Bootstrap should wait for all
--     lighting and shaders to complete before showing environment to player.
--     Consider using a loading screen or ContentProvider:PreloadAsync().
--------------------------------------------------------------------------------

local function startInfiniteDungeon()
    -- Set dark/nighttime lighting
    local Lighting = game:GetService("Lighting")
    Lighting.ClockTime = 0  -- Midnight
    Lighting.Brightness = 0  -- No ambient light
    Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
    Lighting.Ambient = Color3.fromRGB(20, 20, 25)  -- Slight ambient for visibility
    Lighting.FogEnd = 1000
    Lighting.FogColor = Color3.fromRGB(0, 0, 0)
    Lighting.GlobalShadows = false  -- Disable shadows for performance

    -- Create region manager via IPC (handles init/start automatically)
    local regionManager = IPC.createInstance("RegionManager", {
        id = "InfiniteDungeon",
    })

    -- Store globally for debugging (IPC handles lifecycle)
    -- Note: Both _G and shared for command bar compatibility in different Studio contexts
    _G.RegionManager = regionManager
    shared.RegionManager = regionManager

    -- Configure
    -- Note: material/color use serializable formats (string/array) for DataStore compatibility
    regionManager:configure({
        baseUnit = 5,
        wallThickness = 1,
        doorSize = 12,
        floorThreshold = 6.5,  -- Height diff before truss is placed
        mainPathLength = 8,
        spurCount = 4,
        loopCount = 1,
        verticalChance = 30,
        minVerticalRatio = 0.2,
        scaleRange = {
            min = 4,
            max = 12,
            minY = 4,
            maxY = 8,
        },
        material = "Brick",  -- String for serialization
        color = { 140, 110, 90 },  -- RGB array for serialization
        -- Map type distribution (deterministic pattern)
        hubInterval = 4,          -- Guarantee a hub every N regions
        hubPadRange = { min = 3, max = 4 },  -- Pads in hub regions
        origin = { 0, 20, 0 },
    })

    -- Build title diorama (3D scene behind title screen)
    regionManager:buildTitleDiorama()

    -- Dungeon is now started via onStartPressed signal from TitleScreen
    -- (handled in RegionManager.In.onStartPressed)
    local Players = game:GetService("Players")
    local dungeonOwner = nil  -- First player to join owns the dungeon

    local function onPlayerAdded(player)
        -- Dungeon is started via TitleScreen signal, not automatically
        -- Character handling is done after dungeon starts (in RegionManager)

        -- Track the first player as dungeon owner for save purposes
        if not dungeonOwner then
            dungeonOwner = player
        end
    end

    -- Save dungeon data when owner leaves
    Players.PlayerRemoving:Connect(function(player)
        if player == dungeonOwner then
            Debug.info("Bootstrap", "Dungeon owner leaving, saving data...")
            regionManager:saveData(player)
        end
    end)

    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end
end

--------------------------------------------------------------------------------
-- CLEANUP ON SHUTDOWN
--------------------------------------------------------------------------------
-- Ensure all nodes are properly stopped when the game closes.
-- This disconnects all RunService connections and cleans up state.

game:BindToClose(function()
    Debug.info("Bootstrap", "Server shutting down...")

    -- Despawn region manager via IPC (handles all dungeon cleanup)
    IPC.despawn("InfiniteDungeon")

    Warren.System.stopAll()
    Log.shutdown()
    Debug.info("Bootstrap", "Server shutdown complete")
end)

Debug.info("Bootstrap", "Server ready")

-- Start dungeon AFTER bootstrap complete (all systems initialized)
startInfiniteDungeon()
