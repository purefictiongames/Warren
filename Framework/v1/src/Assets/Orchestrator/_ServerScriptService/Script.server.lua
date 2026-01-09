--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Orchestrator.Script (Server)
-- Coordinates game flow - receives events via Input, sends commands via Output
-- Applies RunModes configuration to assets based on player mode changes
-- Black box implementation - no direct asset references

-- Guard: Only run if this is the deployed version (has dot in name)
if not script.Name:match("%.") then
	return
end

-- Extract asset name from script name
local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[Orchestrator.Script] Could not extract asset name from script.Name:", script.Name)
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system - ORCHESTRATE stage means all assets are initialized
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.ORCHESTRATE)

-- Load RunModes API
local RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))

-- Get standardized events (created by bootstrap)
local inputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Input")
local outputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Output")

-- Track if game loop is running
local gameRunning = false

-- Apply mode configuration to all assets
-- Reads config and sends enable/disable commands via Output
local function applyModeToAssets(mode)
	local config = RunModes:GetConfig(mode)
	if not config or not config.assets then
		System.Debug:Warn(assetName, "No asset config for mode:", mode)
		return
	end

	System.Debug:Message(assetName, "Applying mode config:", mode)

	for targetAssetName, settings in pairs(config.assets) do
		-- Apply active state
		if settings.active ~= nil then
			local command = settings.active and "enable" or "disable"
			System.Debug:Message(assetName, "Sending", command, "to", targetAssetName)
			outputEvent:Fire({
				target = targetAssetName,
				command = command
			})
		end
	end

	System.Debug:Message(assetName, "Finished applying mode config:", mode)
end

-- Start the game loop
local function startGameLoop()
	if gameRunning then return end
	gameRunning = true

	System.Debug:Message(assetName, "Starting game loop")

	-- Send reset commands to assets
	outputEvent:Fire({ target = "MarshmallowBag", command = "reset" })
	outputEvent:Fire({ target = "TimedEvaluator", command = "reset" })
	outputEvent:Fire({ target = "GlobalTimer", command = "start" })
end

-- Stop the game loop
local function stopGameLoop()
	if not gameRunning then return end
	gameRunning = false

	-- Send stop command to GlobalTimer
	outputEvent:Fire({ target = "GlobalTimer", command = "stop" })

	System.Debug:Message(assetName, "Stopped game loop")
end

-- Per-submission reset (RoundComplete from Scoreboard)
local function onRoundComplete(result)
	-- Only reset if game is running
	if not gameRunning then return end

	System.Debug:Message(assetName, "Submission received - resetting TimedEvaluator")
	task.wait(1)

	-- Check again after delay
	if not gameRunning then return end

	outputEvent:Fire({ target = "TimedEvaluator", command = "reset" })
end

-- End game and return all active players to standby
local function endGame(reason)
	if not gameRunning then return end

	System.Debug:Message(assetName, "Game ending:", reason)

	-- Stop the game loop first
	stopGameLoop()

	-- Brief delay to let players see final state
	task.wait(2)

	-- Transition all active players back to standby
	for _, player in ipairs(game.Players:GetPlayers()) do
		if RunModes:IsGameActive(player) then
			System.Debug:Message(assetName, "Returning", player.Name, "to standby")
			RunModes:SetMode(player, RunModes.Modes.STANDBY)
		end
	end

	System.Debug:Message(assetName, "Game ended - players returned to standby")
end

-- Handle input messages
inputEvent.Event:Connect(function(message)
	if not message or type(message) ~= "table" then
		System.Debug:Warn(assetName, "Invalid input message:", message)
		return
	end

	local action = message.action

	-- Handle RunModes.ModeChanged (doesn't have action field, has player/newMode/oldMode)
	if not action and message.player and message.newMode then
		action = "modeChanged"
	end

	if action == "timerExpired" then
		-- GlobalTimer expired - end the game
		endGame("GlobalTimer expired")

	elseif action == "dispenserEmpty" then
		-- Dispenser (MarshmallowBag) is empty - end the game
		endGame("Dispenser empty")

	elseif action == "roundComplete" then
		-- Scoreboard round complete - reset evaluator
		onRoundComplete(message.result)

	elseif action == "modeChanged" then
		-- RunModes changed for a player
		local player = message.player
		local newMode = message.newMode
		local oldMode = message.oldMode

		System.Debug:Message(assetName, "Mode changed for", player.Name, ":", oldMode, "->", newMode)

		-- Apply mode config to assets
		applyModeToAssets(newMode)

		-- Start game loop if entering active mode
		if RunModes:IsGameActive(player) and not gameRunning then
			startGameLoop()
		end

		-- Check if anyone is still in active mode
		if not RunModes:IsGameActive(player) then
			local anyActive = false
			for _, p in ipairs(game.Players:GetPlayers()) do
				if RunModes:IsGameActive(p) then
					anyActive = true
					break
				end
			end

			if not anyActive and gameRunning then
				stopGameLoop()
				-- Apply standby config since no one is playing
				applyModeToAssets(RunModes.Modes.STANDBY)
			end
		end

	else
		System.Debug:Warn(assetName, "Unknown action:", action)
	end
end)

-- Apply initial standby mode to all assets (game doesn't auto-start)
applyModeToAssets(RunModes.Modes.STANDBY)

System.Debug:Message(assetName, "Setup complete - listening on", assetName .. ".Input")

System.Debug:Message(assetName, "Script loaded")
