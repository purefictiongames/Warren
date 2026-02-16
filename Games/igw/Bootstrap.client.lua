--[[
    It Gets Worse v2 — Client Bootstrap (Warren v3.1)

    Generic Warren client bootstrap. Sets up IPC substrate.
    Server is authoritative for all instance creation.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Wait for Warren package, Components, and manifest
local Warren = require(ReplicatedStorage:WaitForChild("Warren"))
local Components = require(ReplicatedStorage:WaitForChild("Components"))
local manifest = require(ReplicatedStorage:WaitForChild("init.cfg"))

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

for _, nodeName in ipairs(manifest.mode.nodes) do
    local nodeClass = Components[nodeName]
    if nodeClass then
        IPC.registerNode(nodeClass)
    end
end

IPC.defineMode(manifest.mode.name, {
    nodes = manifest.mode.nodes,
    wiring = manifest.mode.wiring,
})

IPC.init()
IPC.switchMode(manifest.mode.name)
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
