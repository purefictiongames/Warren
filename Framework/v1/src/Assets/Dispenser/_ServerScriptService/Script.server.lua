--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Dispenser.Script (Server)
-- Handles ProximityPrompt interaction and item dispensing

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Dispenser%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Dependencies (guaranteed to exist after SCRIPTS stage)
local Dispenser = require(ReplicatedStorage:WaitForChild("Dispenser.ModuleScript"))
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("Dispenser")

-- MessageTicker loaded lazily (optional dependency)
local messageTicker = nil
task.spawn(function()
	messageTicker = ReplicatedStorage:WaitForChild("MessageTicker.MessageTicker", 10)
end)

-- Create Empty event for Orchestrator to listen to
local emptyEvent = Instance.new("BindableEvent")
emptyEvent.Name = "Dispenser.Empty"
emptyEvent.Parent = ReplicatedStorage

-- Set up a dispenser model
local function setupDispenser(model)
	-- Get config from model attributes
	local itemType = model:GetAttribute("DispenseItem") or "Marshmallow"
	local capacity = model:GetAttribute("Capacity") or 10

	-- Create dispenser instance
	local dispenser = Dispenser.new(itemType, capacity)

	-- Find Anchor
	local anchor = model:FindFirstChild("Anchor")
	if not anchor then
		System.Debug:Warn("Dispenser", "No Anchor found in", model.Name)
		return
	end

	-- Configure mesh from MeshName attribute
	local meshName = model:GetAttribute("MeshName")
	if meshName then
		local mesh = anchor:FindFirstChild(meshName)
		if mesh then
			mesh.Size = anchor.Size
			mesh.CFrame = anchor.CFrame
			mesh.Anchored = true
			-- Hide anchor, mesh is the visual
			anchor.Transparency = 1
		else
			System.Debug:Warn("Dispenser", "Mesh not found:", meshName)
		end
	end

	-- Find ProximityPrompt
	local prompt = anchor:FindFirstChild("ProximityPrompt")
	if not prompt then
		System.Debug:Warn("Dispenser", "No ProximityPrompt found in", model.Name)
		return
	end

	-- Set initial remaining count
	model:SetAttribute("Remaining", dispenser.remaining)

	-- Handle interaction
	prompt.Triggered:Connect(function(player)
		local item = dispenser:dispense()
		if item then
			-- Disable collision BEFORE parenting to prevent collision with player/dispenser
			local handle = item:FindFirstChild("Handle")
			if handle then
				handle.CanCollide = false
			end

			local backpack = player.Backpack
			System.Debug:Message("Dispenser", "Putting", item.Name, "in backpack:", backpack:GetFullName())
			item.Parent = backpack
			model:SetAttribute("Remaining", dispenser.remaining)
			System.Debug:Message("Dispenser", "Gave", item.Name, "to", player.Name)

			-- Notify player
			if messageTicker then
				messageTicker:FireClient(player, "Roast your marshmallow over the campfire!")
			end

			-- Fire empty event if this was the last one
			if dispenser:isEmpty() then
				System.Debug:Message("Dispenser", "Now empty - firing event")
				emptyEvent:Fire()
			end
		else
			System.Debug:Message("Dispenser", "Empty")
			if messageTicker then
				messageTicker:FireClient(player, "The bag is empty!")
			end
		end
	end)

	-- Expose Reset via BindableFunction (for Orchestrator)
	local resetFunction = Instance.new("BindableFunction")
	resetFunction.Name = "Reset"
	resetFunction.OnInvoke = function()
		dispenser:refill()
		model:SetAttribute("Remaining", dispenser.remaining)
		System.Debug:Message("Dispenser", "Refilled to", dispenser.remaining)
		return true
	end
	resetFunction.Parent = model

	System.Debug:Message("Dispenser", "Set up", model.Name, "(DispenseItem:" .. itemType .. ", Capacity:" .. capacity .. ")")
end

setupDispenser(model)

System.Debug:Message("Dispenser", "Script loaded")
