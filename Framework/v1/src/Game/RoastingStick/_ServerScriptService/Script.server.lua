--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- RoastingStick.Script (Server)
-- Auto-equips roasting stick when enabled, mounts marshmallows when received
-- Uses deferred initialization pattern - registers init function, called at ASSETS stage

-- Guard: Only run if this is the deployed version
if not script.Name:match("^RoastingStick%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Register init function (will be called at ASSETS stage)
System:RegisterAsset("RoastingStick", function()
	-- Dependencies
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
	local templates = ReplicatedStorage:WaitForChild("Templates")
	local stickTemplate = templates:WaitForChild("RoastingStick")
	local forceItemDrop = ReplicatedStorage:WaitForChild("Backpack.ForceItemDrop")
	local itemAdded = ReplicatedStorage:WaitForChild("Backpack.ItemAdded")

	-- Get standardized events (created by bootstrap)
	local inputEvent = ReplicatedStorage:WaitForChild("RoastingStick.Input")

	-- MessageTicker loaded lazily (optional dependency)
	local messageTicker = nil
	task.spawn(function()
		messageTicker = ReplicatedStorage:WaitForChild("MessageTicker.MessageTicker", 10)
	end)

	-- Track if sticks should be equipped (for RunModes)
	-- Start DISABLED - Orchestrator will enable when entering practice/play
	local sticksEnabled = false

	-- Mount marshmallow onto player's equipped stick
	local function mountMarshmallow(player, marshmallow)
		local character = player.Character
		if not character then
			return false, "no_character"
		end

		local stick = character:FindFirstChild("RoastingStick")
		if not stick then
			return false, "stick_not_equipped"
		end

		-- One marshmallow at a time rule
		local existingMarshmallow = stick:FindFirstChild("Marshmallow")
		if existingMarshmallow then
			return false, "already_mounted"
		end

		local stickHandle = stick:FindFirstChild("Handle")
		if not stickHandle then
			return false, "no_stick_handle"
		end

		local marshmallowHandle = marshmallow:FindFirstChild("Handle")
		if not marshmallowHandle then
			return false, "no_marshmallow_handle"
		end

		-- Position at tip of stick (cylinder length is along X axis)
		local tipOffset = stickHandle.Size.X / 2 + marshmallowHandle.Size.Y / 2
		marshmallowHandle.CFrame = stickHandle.CFrame * CFrame.new(tipOffset, 0, 0)

		-- Weld marshmallow to stick
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = stickHandle
		weld.Part1 = marshmallowHandle
		weld.Parent = marshmallowHandle

		-- Parent marshmallow to stick (removes from backpack)
		marshmallow.Parent = stick

		-- Keep CanCollide off to avoid player collision (welded to stick now)
		marshmallowHandle.CanCollide = false

		System.Debug:Message("RoastingStick", "Mounted marshmallow for", player.Name)
		return true, "mounted"
	end

	-- Give player a roasting stick and equip it
	local function giveStick(player)
		local character = player.Character
		local backpack = player:FindFirstChild("Backpack")

		-- Check if player already has one
		local hasStick = false
		if character then
			hasStick = character:FindFirstChild("RoastingStick") ~= nil
		end
		if not hasStick and backpack then
			hasStick = backpack:FindFirstChild("RoastingStick") ~= nil
		end

		if hasStick then return end

		-- Clone and give to player
		local stick = stickTemplate:Clone()

		-- Set grip so cylinder points forward (length is along X axis)
		stick.GripForward = Vector3.new(1, 0, 0)
		stick.GripUp = Vector3.new(0, 1, 0)

		stick.Parent = backpack

		-- Auto-equip
		if character then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid:EquipTool(stick)
			end
		end

		System.Debug:Message("RoastingStick", "Gave stick to", player.Name)
	end

	-- Remove stick from a player
	local function removeStick(player)
		local character = player.Character
		local backpack = player:FindFirstChild("Backpack")

		-- Check character
		if character then
			local stick = character:FindFirstChild("RoastingStick")
			if stick then
				stick:Destroy()
				System.Debug:Message("RoastingStick", "Removed stick from", player.Name, "(character)")
			end
		end

		-- Check backpack
		if backpack then
			local stick = backpack:FindFirstChild("RoastingStick")
			if stick then
				stick:Destroy()
				System.Debug:Message("RoastingStick", "Removed stick from", player.Name, "(backpack)")
			end
		end
	end

	-- Setup player - only give stick if enabled
	local function setupPlayer(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			if sticksEnabled then
				giveStick(player)
			end
		end)

		-- Don't give stick immediately - wait for Enable to be called
	end

	-- Listen for items added to player backpacks
	itemAdded.Event:Connect(function(data)
		local player = data.player
		local item = data.item

		-- Only handle marshmallows
		if item.Name ~= "Marshmallow" then return end

		-- IMMEDIATELY disable collision to prevent collision issues in test mode
		local handle = item:FindFirstChild("Handle")
		if handle then
			handle.CanCollide = false
		end

		task.wait(0.1) -- Let item fully load

		-- Check if item still exists (might have been destroyed by TimedEvaluator)
		if not item:IsDescendantOf(game) then
			return
		end

		local success, reason = mountMarshmallow(player, item)

		-- If mount failed, force drop the item
		if not success then
			-- Re-enable collision before dropping
			if handle then
				handle.CanCollide = true
			end

			forceItemDrop:Fire({
				player = player,
				item = item,
			})

			-- Notify player why it was dropped
			if reason == "already_mounted" and messageTicker then
				messageTicker:FireClient(player, "You dropped a marshmallow! (You can only carry one at a time)")
			end
		end
	end)

	-- Track which players we've set up
	local trackedPlayers = {}

	-- Setup existing and new players
	for _, player in ipairs(Players:GetPlayers()) do
		trackedPlayers[player] = true
		setupPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		if not trackedPlayers[player] then
			trackedPlayers[player] = true
			setupPlayer(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		trackedPlayers[player] = nil
	end)

	-- Get model reference for attributes
	local model = runtimeAssets:WaitForChild("RoastingStick")

	-- Command handlers (callable from Input or BindableFunctions)
	local function handleEnable()
		sticksEnabled = true
		model:SetAttribute("IsEnabled", true)
		-- Give sticks to all current players
		for _, player in ipairs(Players:GetPlayers()) do
			giveStick(player)
		end
		System.Debug:Message("RoastingStick", "Enabled - giving sticks to all players")
		return true
	end

	local function handleDisable()
		sticksEnabled = false
		model:SetAttribute("IsEnabled", false)
		-- Remove sticks from all current players
		for _, player in ipairs(Players:GetPlayers()) do
			removeStick(player)
		end
		System.Debug:Message("RoastingStick", "Disabled - removing sticks from all players")
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
			System.Debug:Warn("RoastingStick", "Unknown command:", message.command)
		end
	end)

	-- Expose Enable via BindableFunction (backward compatibility)
	-- Gives sticks to all players
	local enableFunction = Instance.new("BindableFunction")
	enableFunction.Name = "Enable"
	enableFunction.OnInvoke = handleEnable
	enableFunction.Parent = model

	-- Expose Disable via BindableFunction (backward compatibility)
	-- Removes sticks from all players
	local disableFunction = Instance.new("BindableFunction")
	disableFunction.Name = "Disable"
	disableFunction.OnInvoke = handleDisable
	disableFunction.Parent = model

	System.Debug:Message("RoastingStick", "Initialized")
end)

System.Debug:Message("RoastingStick", "Script loaded, init registered")
