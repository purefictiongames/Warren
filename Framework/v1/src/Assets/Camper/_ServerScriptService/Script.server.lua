--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Camper.Script (Server)
-- Talk-to-interact NPC that triggers tutorial/game start
-- Uses deferred initialization pattern - registers init function, called at ASSETS stage

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Camper%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Register init function (will be called at ASSETS stage)
System:RegisterAsset("Camper", function()
	-- Dependencies
	local Visibility = require(ReplicatedStorage:WaitForChild("System.Visibility"))
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
	local model = runtimeAssets:WaitForChild("Camper")
	local interactEvent = ReplicatedStorage:WaitForChild("Camper.Interact")

	-- Find Anchor (contains ProximityPrompt)
	local anchor = model:FindFirstChild("Anchor")
	if not anchor then
		System.Debug:Warn("Camper", "No Anchor found in", model.Name)
		return
	end

	-- Find ProximityPrompt
	local prompt = anchor:FindFirstChild("ProximityPrompt")
	if not prompt then
		-- Create a default ProximityPrompt if none exists
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ProximityPrompt"
		prompt.ActionText = "Talk"
		prompt.ObjectText = "Camper"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.Parent = anchor
		System.Debug:Message("Camper", "Created default ProximityPrompt")
	end

	-- Handle player interaction
	prompt.Triggered:Connect(function(player)
		System.Debug:Message("Camper", player.Name, "interacted")

		-- Fire event for Tutorial system to handle
		interactEvent:Fire({
			player = player,
		})
	end)

	-- Expose Enable via BindableFunction (for RunModes)
	local enableFunction = Instance.new("BindableFunction")
	enableFunction.Name = "Enable"
	enableFunction.OnInvoke = function()
		Visibility.showModel(model)
		prompt.Enabled = true
		model:SetAttribute("IsEnabled", true)
		System.Debug:Message("Camper", "Enabled")
		return true
	end
	enableFunction.Parent = model

	-- Expose Disable via BindableFunction (for RunModes)
	local disableFunction = Instance.new("BindableFunction")
	disableFunction.Name = "Disable"
	disableFunction.OnInvoke = function()
		Visibility.hideModel(model)
		prompt.Enabled = false
		model:SetAttribute("IsEnabled", false)
		System.Debug:Message("Camper", "Disabled")
		return true
	end
	disableFunction.Parent = model

	-- Set initial state
	model:SetAttribute("IsEnabled", true)

	System.Debug:Message("Camper", "Initialized")
end)

System.Debug:Message("Camper", "Script loaded, init registered")
