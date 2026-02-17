--[[
    Warren SDK — Server Bootstrap

    Generic server bootstrap. Reads boot manifest + game metadata from
    ReplicatedStorage, configures subsystems, registers nodes, resolves
    attributes via ClassResolver cascade, and starts IPC lifecycle.

    Usage:
        -- ServerScriptService/Warren.server.lua (1 line)
        require(game:GetService("ReplicatedStorage"):WaitForChild("Warren").Bootstrap.Server)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Warren lives at Bootstrap's grandparent (Warren/Bootstrap/Server → Warren)
local Warren = require(script.Parent.Parent)

-- Game files live as siblings of Warren in ReplicatedStorage
local Components = require(ReplicatedStorage:WaitForChild("Components"))
local manifest = require(ReplicatedStorage:WaitForChild("init.cfg"))
local metadata = require(ReplicatedStorage:WaitForChild("metadata"))

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
    _G.Debug = Debug
    _G.Log = Log
    _G.IPC = IPC
end

--------------------------------------------------------------------------------
-- NODE REGISTRATION
--------------------------------------------------------------------------------

-- Full node list: orchestrator + pipeline nodes
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
        warn("[Bootstrap] Node definition not found in Components: " .. nodeName)
    end
end

Asset.buildInheritanceTree()

--------------------------------------------------------------------------------
-- MODE + IPC INIT
--------------------------------------------------------------------------------

-- Wiring lives under orchestrator key in metadata
local orchestratorMeta = metadata[orchestratorName] or {}
local wiring = orchestratorMeta.wiring or {}

IPC.defineMode("Dungeon", {
    nodes = allNodes,
    wiring = wiring,
})

--------------------------------------------------------------------------------
-- CREATE INSTANCES (before init so all get normal lifecycle)
--------------------------------------------------------------------------------
-- Pipeline nodes first (so they exist when orchestrator fires buildPass)
-- Each node gets config resolved via ClassResolver (FBP IIP via JavaFX CSS cascade)

local definitions = metadata.definitions or {}
local defaults = metadata.defaults or {}

for _, nodeName in ipairs(metadata.nodes) do
    -- Merge: defaults → per-node metadata
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

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

game:BindToClose(function()
    Debug.info("Bootstrap", "Server shutting down...")
    Warren.System.stopAll()
    Log.shutdown()
    Debug.info("Bootstrap", "Server shutdown complete")
end)

Debug.info("Bootstrap", "Server ready")

return true
