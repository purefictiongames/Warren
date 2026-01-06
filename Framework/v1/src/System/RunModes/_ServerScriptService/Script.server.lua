--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- RunModes.Script (Server)
-- Tracks per-player run mode and fires events on mode changes
--
-- Events fired:
--   RunModes.ModeChanged (BindableEvent) - For server listeners (Orchestrator)
--   RunModes.PlayerModeChanged (RemoteEvent) - For client notification

-- Guard: Only run if this is the deployed version
if not script.Name:match("^RunModes%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Load RunModes API module
local RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))

-- Get events
local modeChangedEvent = ReplicatedStorage:WaitForChild("RunModes.ModeChanged")
local playerModeChangedRemote = ReplicatedStorage:WaitForChild("RunModes.PlayerModeChanged")

-- Per-player mode state
local playerModes = {} -- [player] = mode string

-- Get default mode from config
local config = RunModes:GetFullConfig()
local defaultMode = config.defaultMode or "standby"

--[[
    Set mode for a player and fire events
    @param player Player - The player
    @param newMode string - The new mode
--]]
local function setMode(player, newMode)
	local oldMode = playerModes[player] or defaultMode

	-- Skip if no change
	if oldMode == newMode then
		return
	end

	-- Update internal state
	playerModes[player] = newMode

	-- Update API module's internal state
	RunModes:_updatePlayerMode(player, newMode)

	System.Debug:Message("RunModes", player.Name, "mode:", oldMode, "→", newMode)

	-- Fire server event (for Orchestrator and other server listeners)
	modeChangedEvent:Fire({
		player = player,
		oldMode = oldMode,
		newMode = newMode,
	})

	-- Fire client event (notify the player)
	playerModeChangedRemote:FireClient(player, {
		oldMode = oldMode,
		newMode = newMode,
	})
end

--[[
    Get the current modes table
    @return table - Player to mode mapping
--]]
local function getPlayerModes()
	return playerModes
end

-- Register handlers with API module
RunModes:_registerServerHandlers(setMode, getPlayerModes)

-- Initialize player in default mode when they join
Players.PlayerAdded:Connect(function(player)
	playerModes[player] = defaultMode
	RunModes:_updatePlayerMode(player, defaultMode)
	System.Debug:Message("RunModes", player.Name, "joined in", defaultMode, "mode")

	-- Fire initial mode event so listeners can react
	-- Use task.defer to ensure all systems are ready
	task.defer(function()
		modeChangedEvent:Fire({
			player = player,
			oldMode = nil,
			newMode = defaultMode,
		})
		playerModeChangedRemote:FireClient(player, {
			oldMode = nil,
			newMode = defaultMode,
		})
	end)
end)

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player)
	local mode = playerModes[player]
	if mode then
		System.Debug:Message("RunModes", player.Name, "left from", mode, "mode")
	end
	playerModes[player] = nil
	RunModes:_removePlayer(player)
end)

-- Initialize any players already in game (for late script load)
for _, player in ipairs(Players:GetPlayers()) do
	if not playerModes[player] then
		playerModes[player] = defaultMode
		RunModes:_updatePlayerMode(player, defaultMode)
		System.Debug:Message("RunModes", player.Name, "initialized in", defaultMode, "mode")
	end
end

System.Debug:Message("RunModes", "Setup complete - default mode:", defaultMode)
