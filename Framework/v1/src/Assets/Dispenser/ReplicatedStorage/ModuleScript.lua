-- Dispenser.ModuleScript (Shared)
-- Generic dispenser class - clones items from Templates folder
-- Synced

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
		warn("Dispenser: Templates folder not found")
		return nil
	end

	local template = templates:FindFirstChild(self.itemType)
	if not template then
		warn("Dispenser: Template not found:", self.itemType)
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
