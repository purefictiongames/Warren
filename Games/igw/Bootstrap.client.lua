--[[
    It Gets Worse — Client Bootstrap (Warren v3.0)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Data-driven client entry point. Reads init.cfg + metadata, registers
    all nodes for cross-domain wiring resolution, creates client-domain
    instances only.

    Currently the only client node is PortalCountdown (countdown UI +
    screen fade for portal transitions).

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Wait for Warren package and game modules
local Warren = require(ReplicatedStorage:WaitForChild("Warren"))
local Components = require(ReplicatedStorage:WaitForChild("Components"))
local manifest = require(ReplicatedStorage:WaitForChild("init.cfg"))
local metadata = require(ReplicatedStorage:WaitForChild("metadata"))

local Node = Warren.Node
local Debug = Warren.System.Debug
local Log = Warren.System.Log
local IPC = Warren.System.IPC

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

Debug.configure({
    level = manifest.debug and manifest.debug.level or "info",
})

Log.configure({ backend = "Memory" })

--------------------------------------------------------------------------------
-- BOOTSTRAP
--------------------------------------------------------------------------------

Debug.info("Bootstrap", manifest.name .. " v" .. manifest.version .. " — client starting")
Log.init()

if RunService:IsStudio() then
    _G.Warren = Warren
    _G.Debug = Debug
    _G.IPC = IPC
end

--------------------------------------------------------------------------------
-- NODE REGISTRATION (must match server for cross-domain wiring)
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
    end
end

local orchestratorMeta = metadata[orchestratorName] or {}
local wiring = orchestratorMeta.wiring or {}

IPC.defineMode("Dungeon", {
    nodes = allNodes,
    wiring = wiring,
})

--------------------------------------------------------------------------------
-- CREATE CLIENT INSTANCES
--------------------------------------------------------------------------------

-- Only create client-domain node instances
for _, nodeName in ipairs(metadata.nodes) do
    local comp = Components[nodeName]
    if comp and comp.domain == "client" then
        IPC.createInstance(nodeName, { id = nodeName .. "_1" })
    end
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

local LocalPlayer = Players.LocalPlayer
if LocalPlayer then
    LocalPlayer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            Debug.info("Bootstrap", "Client shutting down...")
            Warren.System.stopAll()
        end
    end)
end

Debug.info("Bootstrap", "Client ready")
