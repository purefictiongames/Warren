-- ServerStorage.LibPureFiction.Utils.Import.ReplicatedStorage.Import
-- Simple Import helper rooted at ServerStorage.LibPureFiction.

local ServerStorage = game:GetService("ServerStorage")
local LibRoot = ServerStorage:WaitForChild("LibPureFiction")

local Import = {}
Import.__index = Import

--[[
    Usage:

    local Import = require(ServerStorage.LibPureFiction.Utils.Import.ReplicatedStorage.Import)

    -- Load ServerStorage.LibPureFiction.EventBus.ReplicatedStorage.EventBus
    local EventBus = Import("EventBus.ReplicatedStorage.EventBus")

    -- Load ServerStorage.LibPureFiction.Spawner.ReplicatedStorage.Spawner
    local Spawner = Import("Spawner.ReplicatedStorage.Spawner")
]]

function Import.__call(_, path)
	assert(type(path) == "string", "Import(path) expects a string")

	local current = LibRoot

	for segment in string.gmatch(path, "[^%.]+") do
		current = current:WaitForChild(segment)
	end

	assert(current, ("Import failed: '%s' not found under LibPureFiction"):format(path))
	assert(current:IsA("ModuleScript"), ("Import target '%s' is not a ModuleScript"):format(current.Name))

	return require(current)
end

setmetatable(Import, Import)

return Import
