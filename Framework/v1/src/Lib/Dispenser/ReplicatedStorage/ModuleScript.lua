--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Dispenser.ModuleScript (Shared)
-- Generic dispenser class - clones items from Templates folder
-- Synced

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local System = require(ReplicatedStorage:WaitForChild("System.System"))

local Dispenser = {}
Dispenser.__index = Dispenser

function Dispenser.new(itemType, capacity)
	local self = setmetatable({}, Dispenser)
	self.itemType = itemType
	self.capacity = capacity
	self.remaining = capacity
	return self
end

function Dispenser:dispense()
	if self.remaining <= 0 then
		return nil
	end

	local templates = ReplicatedStorage:FindFirstChild("Templates")
	if not templates then
		System.Debug:Warn("Dispenser", "Templates folder not found")
		return nil
	end

	local template = templates:FindFirstChild(self.itemType)
	if not template then
		System.Debug:Warn("Dispenser", "Template not found:", self.itemType)
		return nil
	end

	self.remaining = self.remaining - 1
	return template:Clone()
end

function Dispenser:isEmpty()
	return self.remaining <= 0
end

function Dispenser:refill()
	self.remaining = self.capacity
end

return Dispenser
