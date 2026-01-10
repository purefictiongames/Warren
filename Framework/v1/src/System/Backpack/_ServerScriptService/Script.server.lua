--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Backpack.Script (Server)
-- Handles backpack events: item added, force drop, force pickup
-- Uses two-phase initialization: init() creates state, start() connects events

-- Guard: Only run if this is the deployed version (name starts with "Backpack.")
if not script.Name:match("^Backpack%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Wait for System module
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

local BackpackModule = {}

-- Module state (initialized in init())
local itemAdded
local forceItemDrop
local forceItemPickup
local trackedPlayers = {}

-- Connect ChildAdded on a backpack instance
local function connectBackpackEvents(player, backpack)
	backpack.ChildAdded:Connect(function(item)
		if itemAdded then
			itemAdded:Fire({
				player = player,
				item = item,
			})
		end
	end)
end

-- Watch a player's backpack and fire events when items are added
local function watchBackpack(player)
	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 10)
	if backpack then
		connectBackpackEvents(player, backpack)
	end

	player.CharacterAdded:Connect(function()
		task.wait(0.1)
		local newBackpack = player:FindFirstChild("Backpack")
		if newBackpack then
			connectBackpackEvents(player, newBackpack)
		end
	end)
end

-- Drop an item on the ground near the player
local function dropItem(player, item)
	local character = player.Character
	if not character then
		item:Destroy()
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		item:Destroy()
		return
	end

	local handle = item:FindFirstChild("Handle")
	if handle then
		local dropPos = rootPart.Position + rootPart.CFrame.LookVector * 3
		dropPos = Vector3.new(dropPos.X, rootPart.Position.Y - 2, dropPos.Z)
		handle.CFrame = CFrame.new(dropPos)
	end

	item.Parent = Workspace
end

-- Pick up an item into player's backpack
local function pickupItem(player, item)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return
	end
	item.Parent = backpack
end

--[[
    Phase 1: Initialize
    Get event references - NO connections yet
--]]
function BackpackModule:init()
	itemAdded = ReplicatedStorage:WaitForChild("Backpack.ItemAdded", 10)
	forceItemDrop = ReplicatedStorage:WaitForChild("Backpack.ForceItemDrop", 10)
	forceItemPickup = ReplicatedStorage:WaitForChild("Backpack.ForceItemPickup", 10)

	if not itemAdded then System.Debug:Warn("System.Backpack", "ItemAdded event not found!") end
	if not forceItemDrop then System.Debug:Warn("System.Backpack", "ForceItemDrop event not found!") end
	if not forceItemPickup then System.Debug:Warn("System.Backpack", "ForceItemPickup event not found!") end
end

--[[
    Phase 2: Start
    Connect events, start logic
--]]
function BackpackModule:start()
	-- Connect force drop event
	if forceItemDrop then
		forceItemDrop.Event:Connect(function(data)
			if data.player and data.item then
				dropItem(data.player, data.item)
			end
		end)
	end

	-- Connect force pickup event
	if forceItemPickup then
		forceItemPickup.Event:Connect(function(data)
			if data.player and data.item then
				pickupItem(data.player, data.item)
			end
		end)
	end

	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		trackedPlayers[player] = true
		watchBackpack(player)
	end

	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		if not trackedPlayers[player] then
			trackedPlayers[player] = true
			watchBackpack(player)
		end
	end)

	-- Fallback poll for untracked players
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				if not trackedPlayers[player] then
					trackedPlayers[player] = true
					watchBackpack(player)
				end
			end
		end
	end)

	-- Clean up when players leave
	Players.PlayerRemoving:Connect(function(player)
		trackedPlayers[player] = nil
	end)

	System.Debug:Message("System.Backpack", "Started")
end

-- Register with System
System:RegisterModule("Backpack", BackpackModule, { type = "system" })

return BackpackModule
