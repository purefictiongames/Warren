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
	local inputEvent = ReplicatedStorage:WaitForChild("Camper.Input")
	local interactEvent = ReplicatedStorage:WaitForChild("Camper.Interact")

	-- Find Anchor (contains ProximityPrompt)
	local anchor = model:FindFirstChild("Anchor")
	if not anchor then
		System.Debug:Warn("Camper", "No Anchor found in", model.Name)
		return
	end

	-- Configure Anchor: invisible, non-collideable, but interactable
	-- Set attributes so Visibility.showModel() knows to keep these values
	anchor.Transparency = 1
	anchor:SetAttribute("VisibleTransparency", 1)
	anchor.CanCollide = false
	anchor:SetAttribute("VisibleCanCollide", false)
	anchor.CanTouch = false
	anchor:SetAttribute("VisibleCanTouch", false)

	-- Ground the model: move it down so its base sits at Y=0
	local minY = math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local bottomY = part.Position.Y - (part.Size.Y / 2)
			if bottomY < minY then
				minY = bottomY
			end
		end
	end
	if minY ~= math.huge and minY > 0 then
		-- Model is floating - drop it to ground
		model:PivotTo(model:GetPivot() - Vector3.new(0, minY, 0))
		System.Debug:Message("Camper", "Grounded model, dropped by", minY, "studs")
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

	-- Command handlers (callable from Input or BindableFunctions)
	local function handleEnable()
		Visibility.showModel(model)
		prompt.Enabled = true
		model:SetAttribute("IsEnabled", true)
		System.Debug:Message("Camper", "Enabled")
		return true
	end

	local function handleDisable()
		Visibility.hideModel(model)
		prompt.Enabled = false
		model:SetAttribute("IsEnabled", false)
		System.Debug:Message("Camper", "Disabled")
		return true
	end

	-- Listen on Input for commands from Orchestrator
	inputEvent.Event:Connect(function(message)
		if not message or type(message) ~= "table" then
			return
		end

		if message.command == "enable" then
			handleEnable()
		elseif message.command == "disable" then
			handleDisable()
		else
			System.Debug:Warn("Camper", "Unknown command:", message.command)
		end
	end)

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

	-- Set initial state
	model:SetAttribute("IsEnabled", true)

	System.Debug:Message("Camper", "Initialized")
end)

System.Debug:Message("Camper", "Script loaded, init registered")
