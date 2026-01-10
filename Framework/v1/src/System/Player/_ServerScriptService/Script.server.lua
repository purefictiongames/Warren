--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Player.Script (Server)
-- Handles player-level system concerns
-- Uses two-phase initialization: init() creates state, start() connects events

-- Guard: Only run if this is the deployed version (name starts with "Player.")
if not script.Name:match("^Player%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for System module
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

local PlayerModule = {}

-- Setup player (called on join and for existing players)
local function setupPlayer(player)
	-- Player-specific setup goes here
	System.Debug:Verbose("System.Player", "Setup player:", player.Name)
end

--[[
    Phase 1: Initialize
    Create state, events - NO connections to other modules
--]]
function PlayerModule:init()
	-- Nothing to create in this module currently
end

--[[
    Phase 2: Start
    Connect events, start logic - safe to call other modules
--]]
function PlayerModule:start()
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end

	-- Handle new players
	Players.PlayerAdded:Connect(setupPlayer)

	System.Debug:Message("System.Player", "Started")
end

-- Register with System
System:RegisterModule("Player", PlayerModule, { type = "system" })

return PlayerModule
