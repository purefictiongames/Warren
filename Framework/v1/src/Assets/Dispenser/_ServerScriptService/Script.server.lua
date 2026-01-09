--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Dispenser.Script (Server)
-- Handles ProximityPrompt interaction and item dispensing
-- Uses deferred initialization pattern - registers init function, called at ASSETS stage

-- Guard: Only run if this is the deployed version (has dot in name)
if not script.Name:match("%.") then
	return
end

-- Extract asset name from script name (e.g., "MarshmallowBag.Script" → "MarshmallowBag")
local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[Dispenser.Script] Could not extract asset name from script.Name:", script.Name)
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Register init function (will be called at ASSETS stage)
System:RegisterAsset(assetName, function()
	-- Dependencies
	local DispenserModule = require(ReplicatedStorage:WaitForChild(assetName .. ".ModuleScript"))
	local Visibility = require(ReplicatedStorage:WaitForChild("System.Visibility"))
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
	local model = runtimeAssets:WaitForChild(assetName)

	-- Get standardized events (created by bootstrap)
	local inputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Input")
	local outputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Output")

	-- MessageTicker loaded lazily (optional dependency)
	local messageTicker = nil
	task.spawn(function()
		messageTicker = ReplicatedStorage:WaitForChild("MessageTicker.MessageTicker", 10)
	end)


	-- Get config from model attributes
	local itemType = model:GetAttribute("DispenseItem") or "Marshmallow"
	local capacity = model:GetAttribute("Capacity") or 10

	-- Create dispenser instance
	local dispenser = DispenserModule.new(itemType, capacity)

	-- Find Anchor
	local anchor = model:FindFirstChild("Anchor")
	if not anchor then
		System.Debug:Warn(assetName, "No Anchor found in", model.Name)
		return
	end

	-- Configure Anchor: non-collideable (set attribute so showModel keeps it that way)
	anchor.CanCollide = false
	anchor:SetAttribute("VisibleCanCollide", false)
	anchor.CanTouch = false
	anchor:SetAttribute("VisibleCanTouch", false)

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
			-- Mesh should also be non-collideable to prevent player getting stuck
			mesh.CanCollide = false
			mesh:SetAttribute("VisibleCanCollide", false)
		else
			System.Debug:Warn(assetName, "Mesh not found:", meshName)
		end
	end

	-- Make all parts in the model non-collideable (picnic table, etc.)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part:SetAttribute("VisibleCanCollide", false)
		end
	end

	-- Find ProximityPrompt
	local prompt = anchor:FindFirstChild("ProximityPrompt")
	if not prompt then
		System.Debug:Warn(assetName, "No ProximityPrompt found in", model.Name)
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
			System.Debug:Message(assetName, "Putting", item.Name, "in backpack:", backpack:GetFullName())
			item.Parent = backpack
			model:SetAttribute("Remaining", dispenser.remaining)
			System.Debug:Message(assetName, "Gave", item.Name, "to", player.Name)

			-- Notify player
			if messageTicker then
				messageTicker:FireClient(player, "Roast your marshmallow over the campfire!")
			end

			-- Fire Output event if this was the last one
			if dispenser:isEmpty() then
				System.Debug:Message(assetName, "Now empty - firing Output")
				outputEvent:Fire({ action = "dispenserEmpty" })
			end
		else
			System.Debug:Message(assetName, "Empty")
			if messageTicker then
				messageTicker:FireClient(player, "The bag is empty!")
			end
		end
	end)

	-- Command handlers (callable from Input or BindableFunctions)
	local function handleReset()
		dispenser:refill()
		model:SetAttribute("Remaining", dispenser.remaining)
		System.Debug:Message(assetName, "Refilled to", dispenser.remaining)
		return true
	end

	local function handleEnable()
		Visibility.showModel(model)
		prompt.Enabled = true
		model:SetAttribute("IsEnabled", true)
		model:SetAttribute("HUDVisible", true)
		System.Debug:Message(assetName, "Enabled")
		return true
	end

	local function handleDisable()
		Visibility.hideModel(model)
		prompt.Enabled = false
		model:SetAttribute("IsEnabled", false)
		model:SetAttribute("HUDVisible", false)
		System.Debug:Message(assetName, "Disabled")
		return true
	end

	-- Listen on Input for commands from Orchestrator
	inputEvent.Event:Connect(function(message)
		if not message or type(message) ~= "table" then
			return
		end

		if message.command == "reset" then
			handleReset()
		elseif message.command == "enable" then
			handleEnable()
		elseif message.command == "disable" then
			handleDisable()
		else
			System.Debug:Warn(assetName, "Unknown command:", message.command)
		end
	end)

	-- Expose Reset via BindableFunction (backward compatibility)
	local resetFunction = Instance.new("BindableFunction")
	resetFunction.Name = "Reset"
	resetFunction.OnInvoke = handleReset
	resetFunction.Parent = model

	-- Expose Enable via BindableFunction (backward compatibility)
	local enableFunction = Instance.new("BindableFunction")
	enableFunction.Name = "Enable"
	enableFunction.OnInvoke = handleEnable
	enableFunction.Parent = model

	-- Expose Disable via BindableFunction (backward compatibility)
	local disableFunction = Instance.new("BindableFunction")
	disableFunction.Name = "Disable"
	disableFunction.OnInvoke = handleDisable
	disableFunction.Parent = model

	System.Debug:Message(assetName, "Initialized (DispenseItem:" .. itemType .. ", Capacity:" .. capacity .. ")")
end)

System.Debug:Message(assetName, "Script loaded, init registered")
