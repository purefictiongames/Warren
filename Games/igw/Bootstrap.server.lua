--[[
    It Gets Worse v2 — Server Bootstrap (Warren v3.1)

    Generic Warren server bootstrap. Reads manifest, configures subsystems,
    hands off to orchestrator. No game-specific code.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Warren package, Components registry, and manifest
local Warren = require(ReplicatedStorage:WaitForChild("Warren"))
local Components = require(ReplicatedStorage:WaitForChild("Components"))
local manifest = require(ReplicatedStorage:WaitForChild("init.cfg"))

local Debug = Warren.System.Debug
local Log = Warren.System.Log
local Asset = Warren.System.Asset
local IPC = Warren.System.IPC

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

for _, nodeName in ipairs(manifest.mode.nodes) do
    local nodeClass = Components[nodeName]
    if nodeClass then
        IPC.registerNode(nodeClass)
    else
        warn("[Bootstrap] Node class not found in Components: " .. nodeName)
    end
end

Asset.buildInheritanceTree()

--------------------------------------------------------------------------------
-- MODE + IPC INIT
--------------------------------------------------------------------------------

IPC.defineMode(manifest.mode.name, {
    nodes = manifest.mode.nodes,
    wiring = manifest.mode.wiring,
})

--------------------------------------------------------------------------------
-- CREATE INSTANCES (before init so all get normal lifecycle)
--------------------------------------------------------------------------------
-- Pipeline nodes first (so they exist when orchestrator fires buildPass)

for _, nodeName in ipairs(manifest.preload or {}) do
    IPC.createInstance(nodeName, { id = nodeName .. "_1" })
end

-- Orchestrator last (its onStart triggers the pipeline)
local orchestrator = IPC.createInstance(manifest.orchestrator, {
    id = manifest.orchestrator .. "_Main",
    attributes = { config = manifest.config },
})

if RunService:IsStudio() then
    _G.Orchestrator = orchestrator
end

--------------------------------------------------------------------------------
-- IPC LIFECYCLE
--------------------------------------------------------------------------------

IPC.init()
IPC.switchMode(manifest.mode.name)
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
