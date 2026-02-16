--[[
    It Gets Worse — Server Bootstrap (Warren v3.0)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the Roblox server entry point. It:
    1. Requires the Warren v3.0 framework package
    2. Requires game-specific Components
    3. Configures system subsystems
    4. Connects to Lune authority server via Warren.Transport
    5. Initializes the framework in the correct order

    Warren v3.0 changes:
    - Transport layer connects to Lune VPS for authoritative state
    - State sync as replica (Lune is authority for persistence)
    - DataStore access routed through Lune via Open Cloud
    - Roblox server handles materialization, Lune handles persistence

    Nothing in the framework runs until this script explicitly calls it.

--]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- Create loading screen RemoteEvents immediately (ReplicatedFirst needs these ASAP)
local viewReadyEvent = Instance.new("RemoteEvent")
viewReadyEvent.Name = "ViewReady"
viewReadyEvent.Parent = ReplicatedStorage

local loadingDoneEvent = Instance.new("RemoteEvent")
loadingDoneEvent.Name = "LoadingDone"
loadingDoneEvent.Parent = ReplicatedStorage

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
    _G.Player = Warren.System.Player
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

-- Resolve current Place context via PlaceGraph
local PlaceGraph = Components.PlaceGraph
local placeName, placeConfig = PlaceGraph.resolve(game.PlaceId)

Debug.info("Bootstrap", "Place:", placeName, "→ initialView:", placeConfig.initialView)

-- Register dungeon nodes with IPC
IPC.registerNode(Components.JumpPad)
IPC.registerNode(Components.RegionManager)
IPC.registerNode(Components.TitleScreen)       -- Client-side, but registered for wiring
IPC.registerNode(Components.ExitScreen)        -- Client-side, but registered for wiring
IPC.registerNode(Components.ScreenTransition)  -- Client-side, but registered for wiring
IPC.registerNode(Components.AreaHUD)           -- Client-side, but registered for wiring
IPC.registerNode(Components.MiniMap)           -- Client-side, but registered for wiring
IPC.registerNode(Components.LobbyManager)      -- Server-side lobby pad management
IPC.registerNode(Components.LobbyCountdown)    -- Client-side lobby countdown UI

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
    nodes = { "JumpPad", "RegionManager", "TitleScreen", "ExitScreen", "ScreenTransition", "AreaHUD", "MiniMap", "LobbyManager", "LobbyCountdown" },
    wiring = {
        -- Server-side: JumpPad → RegionManager
        JumpPad = { "RegionManager" },
        -- Cross-domain: TitleScreen (client) → RegionManager (server)
        TitleScreen = { "RegionManager" },
        -- Cross-domain: ExitScreen (client) → RegionManager (server)
        ExitScreen = { "RegionManager" },
        -- Cross-domain: RegionManager (server) → TitleScreen, ExitScreen, ScreenTransition, AreaHUD, MiniMap, LobbyManager, LobbyCountdown (client)
        RegionManager = { "TitleScreen", "ExitScreen", "ScreenTransition", "AreaHUD", "MiniMap", "LobbyManager", "LobbyCountdown" },
        -- Cross-domain: ScreenTransition (client) → RegionManager (server)
        ScreenTransition = { "RegionManager" },
        -- Cross-domain: MiniMap (client) → RegionManager (server)
        MiniMap = { "RegionManager" },
        -- Server-side: LobbyManager → LobbyCountdown (client)
        LobbyManager = { "LobbyCountdown" },
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

--------------------------------------------------------------------------------
-- WARREN v3.0: TRANSPORT + STATE
--------------------------------------------------------------------------------
-- Connect to Lune authority server for state synchronization.
-- Persistence (DataStore) is now routed through Lune via Open Cloud.
-- Roblox server is a replica — it materializes, Lune persists.

local Transport = Warren.Transport
local State = Warren.State

-- Start transport + SDK (connects to Lune VPS + Warren Registry)
-- In Studio, runs in offline mode (falls back to local DataStore)
if not RunService:IsStudio() then
    -- Initialize SDK (auth with Registry for RPC compute calls)
    -- Wrapped in pcall: SDK failure is non-fatal, game falls back to local compute
    local sdkOk, sdkErr = pcall(function()
        local WarrenSDK = require(ServerStorage:WaitForChild("WarrenSDK"))
        WarrenSDK.init({
            apiKeySecret = "warren_api_key",
            registryUrl = "https://registry.alpharabbitgames.com",
        })
        Debug.info("Bootstrap", "Warren SDK initialized (Registry RPC)")
    end)
    if not sdkOk then
        warn("[Bootstrap] Warren SDK init failed: " .. tostring(sdkErr))
        warn("[Bootstrap] Game will use local compute fallback")
    end

    -- Transport stays connected to Lune for state sync (save/load/visits)
    -- Independent of SDK — state sync works even if SDK auth fails
    local transportOk, transportErr = pcall(function()
        Transport.start({
            endpoint = "https://warren.alpharabbitgames.com",  -- Lune VPS
            authToken = HttpService:GetSecret("warren_api_secret"),
            pollInterval = 0.5,
            batchSize = 10,
        })

        -- Start state as replica (receives patches from Lune)
        local gameStore = State.createStore()
        State.Sync.startReplica(gameStore, {
            onResync = function()
                Debug.info("Bootstrap", "State resync from Lune authority")
            end,
        })

        Debug.info("Bootstrap", "Transport + State replica initialized")
    end)
    if not transportOk then
        warn("[Bootstrap] Transport init failed: " .. tostring(transportErr))
        warn("[Bootstrap] Game will run without state sync")
    end
else
    Debug.info("Bootstrap", "Studio mode — SDK/Transport offline, using local DataStore")
end

--------------------------------------------------------------------------------
-- INFINITE DUNGEON SYSTEM
--------------------------------------------------------------------------------
-- Manages infinite dungeon with region-based generation and teleportation
--
-- TODO: This is a temporary hack. Should be its own script in ServerScriptService.
-- See: src/Game/DungeonServer/_ServerScriptService/DungeonStartup.server.lua
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

    -- Create lobby manager (server-side pad detection, countdown, teleport)
    IPC.createInstance("LobbyManager", {
        id = "LobbyManager_Main",
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

    local Players = game:GetService("Players")
    local System = Warren.System
    local dungeonOwner = nil  -- First player to join owns the dungeon

    -- Register view definitions with System.Player
    regionManager:registerViews()

    -- Set default view based on PlaceGraph
    if PlaceGraph.isGameplayServer() then
        System.Player.setDefaultView("gameplay")
    else
        System.Player.setDefaultView("title")
    end
    Debug.info("Bootstrap", "Default view:", System.Player.getDefaultView())

    -- Pre-build default view geometry (ready before first player arrives)
    System.Player.preload(System.Player.getDefaultView())

    -- Register join hook for game-specific logic
    System.Player.onJoin(function(player)
        if not dungeonOwner then
            dungeonOwner = player
        end

        if PlaceGraph.isGameplayServer() then
            -- Gameplay server: anchor player, position, signal loading screen
            task.spawn(function()
                local character = player.Character or player.CharacterAdded:Wait()
                local hrp = character:WaitForChild("HumanoidRootPart")
                hrp.Anchored = true  -- prevent falling while loading

                local activeRegion = regionManager:getActiveRegion()
                if activeRegion and activeRegion.layout then
                    -- Position at dungeon spawn point immediately
                    local spawnData = activeRegion.layout.spawn
                    if spawnData and spawnData.position then
                        hrp.CFrame = CFrame.new(
                            spawnData.position[1],
                            spawnData.position[2] + 3,
                            spawnData.position[3]
                        )
                    end

                    regionManager.Out:Fire("buildMiniMap", {
                        _targetPlayer = player,
                        player = player,
                        layout = activeRegion.layout,
                    })
                    regionManager.Out:Fire("transitionEnd", {
                        _targetPlayer = player,
                        player = player,
                    })
                end

                -- Signal client loading screen to preload container assets
                local containerName = activeRegion and activeRegion.container
                    and activeRegion.container.Name or nil
                viewReadyEvent:FireClient(player, { containerName = containerName })

                -- Wait for client to finish preloading, then unanchor
                local resolved = false
                local conn
                conn = loadingDoneEvent.OnServerEvent:Connect(function(p)
                    if p == player then
                        resolved = true
                        conn:Disconnect()
                        if hrp and hrp.Parent then
                            hrp.Anchored = false
                        end
                    end
                end)
                -- Safety timeout: unanchor after 15s even if client never responds
                task.delay(15, function()
                    if not resolved then
                        if conn then conn:Disconnect() end
                        if hrp and hrp.Parent then
                            hrp.Anchored = false
                        end
                    end
                end)
            end)
        else
            -- Start server: check TeleportData for lobby re-entry, then signal loading screen
            task.spawn(function()
                local joinData = player:GetJoinData()
                local teleportData = joinData and joinData.TeleportData
                if teleportData and teleportData.destination == "lobby" then
                    task.wait(0.5)
                    System.Player.transitionTo(player, "lobby")
                end

                -- Yield so activate()'s transitionTo completes first
                task.wait(0)
                viewReadyEvent:FireClient(player, { containerName = "TitleDiorama" })
            end)
        end
    end)

    -- Activate System.Player (connects PlayerAdded/PlayerRemoving, processes existing players)
    System.Player.activate()

    -- Save dungeon data when owner leaves (only on start server)
    if placeName == "start" then
        Players.PlayerRemoving:Connect(function(player)
            if player == dungeonOwner then
                Debug.info("Bootstrap", "Dungeon owner leaving, saving data...")
                regionManager:saveData(player)
            end
        end)
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

    -- Revoke SDK session with Registry
    if not RunService:IsStudio() then
        local WarrenSDK = require(ServerStorage.WarrenSDK)
        WarrenSDK.shutdown()
        Debug.info("Bootstrap", "Warren SDK session revoked")
    end

    Warren.System.stopAll()
    Log.shutdown()
    Debug.info("Bootstrap", "Server shutdown complete")
end)

Debug.info("Bootstrap", "Server ready")

-- Start dungeon AFTER bootstrap complete (all systems initialized)
startInfiniteDungeon()
