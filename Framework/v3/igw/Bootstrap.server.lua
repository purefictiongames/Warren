--[[
    It Gets Worse — Server Bootstrap (Warren v3.0)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Data-driven server entry point. Reads init.cfg + metadata to create
    pipeline nodes and the WorldMapOrchestrator. Skips the old RegionManager /
    System.Player view system — jumps straight to gameplay.

    Node registration, wiring, and instance creation are all metadata-driven.
    The orchestrator's onStart triggers the first dungeon build.

--]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Create loading screen RemoteEvents immediately (ReplicatedFirst needs these ASAP)
local viewReadyEvent = Instance.new("RemoteEvent")
viewReadyEvent.Name = "ViewReady"
viewReadyEvent.Parent = ReplicatedStorage

local loadingDoneEvent = Instance.new("RemoteEvent")
loadingDoneEvent.Name = "LoadingDone"
loadingDoneEvent.Parent = ReplicatedStorage

-- Wait for Warren package and game modules (with timeouts to avoid infinite hang)
print("[Bootstrap] Waiting for modules...")
local Warren = require(ReplicatedStorage:WaitForChild("Warren", 30))
local Components = require(ReplicatedStorage:WaitForChild("Components", 30))

local initCfgModule = ReplicatedStorage:WaitForChild("init.cfg", 10)
if not initCfgModule then
    error("[Bootstrap] FATAL: init.cfg not found in ReplicatedStorage after 10s")
end
local manifest = require(initCfgModule)

local metadataModule = ReplicatedStorage:WaitForChild("metadata", 10)
if not metadataModule then
    error("[Bootstrap] FATAL: metadata not found in ReplicatedStorage after 10s")
end
local metadata = require(metadataModule)
print("[Bootstrap] All modules loaded")

local Node = Warren.Node
local Debug = Warren.System.Debug
local Log = Warren.System.Log
local Asset = Warren.System.Asset
local IPC = Warren.System.IPC
local ClassResolver = Warren.ClassResolver

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

Debug.configure({
    level = manifest.debug and manifest.debug.level or "info",
})

Log.configure({
    backend = manifest.log and manifest.log.backend or "Memory",
})

--------------------------------------------------------------------------------
-- BOOTSTRAP
--------------------------------------------------------------------------------

Debug.info("Bootstrap", Warren._VERSION and ("Warren v" .. Warren._VERSION) or "Warren")
Debug.info("Bootstrap", manifest.name .. " v" .. manifest.version .. " — server starting")

Log.init()

--------------------------------------------------------------------------------
-- STUDIO CLI ACCESS
--------------------------------------------------------------------------------

if RunService:IsStudio() then
    _G.Warren = Warren
    _G.Node = Node
    _G.Debug = Debug
    _G.Log = Log
    _G.IPC = IPC
end

--------------------------------------------------------------------------------
-- NODE REGISTRATION
--------------------------------------------------------------------------------

local orchestratorName = manifest.orchestrator
local allNodes = { orchestratorName }
for _, nodeName in ipairs(metadata.nodes) do
    table.insert(allNodes, nodeName)
end

for _, nodeName in ipairs(allNodes) do
    local definition = Components[nodeName]
    if definition then
        IPC.registerNode(Node.extend(definition))
    else
        warn("[Bootstrap] Node not found in Components: " .. nodeName)
    end
end

Asset.buildInheritanceTree()

--------------------------------------------------------------------------------
-- MODE + WIRING (from metadata)
--------------------------------------------------------------------------------

local orchestratorMeta = metadata[orchestratorName] or {}
local wiring = orchestratorMeta.wiring or {}

IPC.defineMode("Dungeon", {
    nodes = allNodes,
    wiring = wiring,
})

--------------------------------------------------------------------------------
-- CREATE INSTANCES (server-domain only)
--------------------------------------------------------------------------------

local definitions = metadata.definitions or {}
local defaults = metadata.defaults or {}

for _, nodeName in ipairs(metadata.nodes) do
    -- Only create server-domain instances on server
    local comp = Components[nodeName]
    if comp and comp.domain == "client" then
        continue
    end

    local nodeConfig = metadata[nodeName] or {}
    local definition = {}
    for k, v in pairs(defaults) do definition[k] = v end
    for k, v in pairs(nodeConfig) do definition[k] = v end
    definition.type = nodeName

    local resolved = ClassResolver.resolve(definition, definitions, {
        reservedKeys = { type = true, class = true, id = true },
    })

    IPC.createInstance(nodeName, {
        id = nodeName .. "_1",
        attributes = resolved,
    })
end

-- Orchestrator last (its onStart triggers the pipeline)
local orchestratorConfig = {}
for k, v in pairs(orchestratorMeta) do
    if k ~= "wiring" then
        orchestratorConfig[k] = v
    end
end

local orchestrator = IPC.createInstance(orchestratorName, {
    id = orchestratorName .. "_Main",
    attributes = { config = orchestratorConfig },
})

if RunService:IsStudio() then
    _G.Orchestrator = orchestrator
end

--------------------------------------------------------------------------------
-- IPC LIFECYCLE
--------------------------------------------------------------------------------

IPC.init()
IPC.switchMode("Dungeon")
IPC.start()

Debug.info("Bootstrap", "IPC started — " .. orchestratorName .. " will build first region")

--------------------------------------------------------------------------------
-- WARREN v3.0: SDK + OPENCLOUD
--------------------------------------------------------------------------------

if not RunService:IsStudio() then
    -- SDK init — 5s timeout to avoid blocking game if module is missing
    local sdkModule = ServerStorage:FindFirstChild("WarrenSDK")
    if sdkModule then
        local sdkOk, sdkErr = pcall(function()
            local WarrenSDK = require(sdkModule)
            WarrenSDK.init({
                apiKeySecret = "warren_api_key",
                registryUrl = "https://registry.alpharabbitgames.com",
            })
            Debug.info("Bootstrap", "Warren SDK initialized")
        end)
        if not sdkOk then
            warn("[Bootstrap] Warren SDK init failed: " .. tostring(sdkErr))
        end
    else
        warn("[Bootstrap] WarrenSDK not found in ServerStorage — skipping SDK init")
    end

    -- OpenCloud init
    local opencloudOk, opencloudErr = pcall(function()
        local secret = HttpService:GetSecret("warren_opencloud_key")
        Warren.OpenCloud._robloxConfig = {
            universeId = tostring(game.GameId),
            apiKey = secret,
        }
        Debug.info("Bootstrap", "OpenCloud initialized")
    end)
    if not opencloudOk then
        warn("[Bootstrap] OpenCloud init failed: " .. tostring(opencloudErr))
    end
else
    Debug.info("Bootstrap", "Studio mode — local compute + local DataStore")
end

--------------------------------------------------------------------------------
-- LOADING SCREEN PROTOCOL
--------------------------------------------------------------------------------
-- ReplicatedFirst shows a black overlay, waits for ViewReady, preloads, fades.
-- We fire ViewReady once the dungeon is built (shared.dungeonReady set by
-- WorldMapOrchestrator in onDungeonComplete).

Players.PlayerAdded:Connect(function(player)
    task.spawn(function()
        local character = player.Character or player.CharacterAdded:Wait()
        character:WaitForChild("HumanoidRootPart", 10)

        -- Wait for first dungeon to be ready
        while not shared.dungeonReady do
            task.wait(0.1)
        end

        -- Signal loading screen to preload + fade
        local containerName = shared.dungeonReady.containerName
        viewReadyEvent:FireClient(player, { containerName = containerName })
    end)
end)

-- Handle players already in game (Studio fast-start)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        local character = player.Character or player.CharacterAdded:Wait()
        character:WaitForChild("HumanoidRootPart", 10)

        while not shared.dungeonReady do
            task.wait(0.1)
        end

        local containerName = shared.dungeonReady.containerName
        viewReadyEvent:FireClient(player, { containerName = containerName })
    end)
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

game:BindToClose(function()
    Debug.info("Bootstrap", "Server shutting down...")

    if not RunService:IsStudio() then
        local sdkModule = ServerStorage:FindFirstChild("WarrenSDK")
        if sdkModule then
            pcall(function()
                require(sdkModule).shutdown()
            end)
        end
    end

    Warren.System.stopAll()
    Log.shutdown()
    Debug.info("Bootstrap", "Server shutdown complete")
end)

Debug.info("Bootstrap", "Server ready")
