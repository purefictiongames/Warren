--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Player.Script (Server)
-- Handles player-level system concerns

-- Guard: Only run if this is the deployed version (name starts with "Player.")
if not script.Name:match("^Player%.") then
	return
end

-- Wait for boot system to be ready
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

local Players = game:GetService("Players")

-- Setup player
local function setupPlayer(player)
    -- Player-specific setup goes here
end

-- Handle existing and new players
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)

System.Debug:Message("System.Player", "Script loaded")
