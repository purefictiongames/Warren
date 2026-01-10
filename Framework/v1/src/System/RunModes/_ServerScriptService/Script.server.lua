--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- RunModes.Script (Server)
-- Tracks per-player run mode and fires events on mode changes
-- Uses two-phase initialization: init() creates state, start() connects events
--
-- Events fired:
--   RunModes.ModeChanged (BindableEvent) - For server listeners (Orchestrator)
--   RunModes.PlayerModeChanged (RemoteEvent) - For client notification

-- Guard: Only run if this is the deployed version
if not script.Name:match("^RunModes%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for System module
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

local RunModesModule = {}

-- Module state (initialized in init())
local RunModes
local modeChangedEvent
local playerModeChangedRemote
local playerModes = {}
local defaultMode

--[[
    Set mode for a player and fire events
--]]
local function setMode(player, newMode)
	local oldMode = playerModes[player] or defaultMode

	if oldMode == newMode then
		return
	end

	playerModes[player] = newMode
	RunModes:_updatePlayerMode(player, newMode)

	System.Debug:Message("RunModes", player.Name, "mode:", oldMode, "→", newMode)

	modeChangedEvent:Fire({
		player = player,
		oldMode = oldMode,
		newMode = newMode,
	})

	playerModeChangedRemote:FireClient(player, {
		oldMode = oldMode,
		newMode = newMode,
	})
end

--[[
    Get the current modes table
--]]
local function getPlayerModes()
	return playerModes
end

--[[
    Phase 1: Initialize
    Load dependencies, get event references - NO connections yet
--]]
function RunModesModule:init()
	-- Load RunModes API module
	RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))

	-- Get events
	modeChangedEvent = ReplicatedStorage:WaitForChild("RunModes.ModeChanged")
	playerModeChangedRemote = ReplicatedStorage:WaitForChild("RunModes.PlayerModeChanged")

	-- Get default mode from config
	local config = RunModes:GetFullConfig()
	defaultMode = config.defaultMode or "standby"

	-- Register handlers with API module (this is setup, not connection)
	RunModes:_registerServerHandlers(setMode, getPlayerModes)
end

--[[
    Phase 2: Start
    Connect events, initialize players
--]]
function RunModesModule:start()
	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		playerModes[player] = defaultMode
		RunModes:_updatePlayerMode(player, defaultMode)
		System.Debug:Message("RunModes", player.Name, "joined in", defaultMode, "mode")

		-- Fire initial mode event (defer to ensure all systems ready)
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

	-- Initialize existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if not playerModes[player] then
			playerModes[player] = defaultMode
			RunModes:_updatePlayerMode(player, defaultMode)
			System.Debug:Message("RunModes", player.Name, "initialized in", defaultMode, "mode")
		end
	end

	System.Debug:Message("RunModes", "Started - default mode:", defaultMode)
end

-- Register with System
System:RegisterModule("RunModes", RunModesModule, { type = "system" })

return RunModesModule
