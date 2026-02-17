--[[
    Warren SDK — Client Bootstrap

    Generic client bootstrap. Reads boot manifest + game metadata,
    sets up IPC substrate with matching node list and wiring.
    Server is authoritative for all instance creation.

    Usage:
        -- StarterPlayerScripts/Warren.client.lua (1 line)
        require(game:GetService("ReplicatedStorage"):WaitForChild("Warren").Bootstrap.Client)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Warren lives at Bootstrap's grandparent (Warren/Bootstrap/Client → Warren)
local Warren = require(script.Parent.Parent)

-- Game files live as siblings of Warren in ReplicatedStorage
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

--------------------------------------------------------------------------------
-- NODE REGISTRATION + MODE (must match server for cross-domain wiring)
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
