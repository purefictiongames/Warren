--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Orchestrator.Script (Server)
-- Coordinates game flow - listens to events and triggers appropriate resets
-- Applies RunModes configuration to assets based on player mode changes

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Orchestrator%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Load RunModes API
local RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))

-- Dependencies (guaranteed to exist after SCRIPTS stage)
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")

-- Get GlobalTimer controls
local globalTimer = runtimeAssets:WaitForChild("GlobalTimer")
local globalTimerStart = globalTimer:WaitForChild("Start")

-- Get asset Reset functions
local dispenser = runtimeAssets:WaitForChild("Dispenser")
local dispenserReset = dispenser:WaitForChild("Reset")

local timedEvaluator = runtimeAssets:WaitForChild("TimedEvaluator")
local timedEvaluatorReset = timedEvaluator:WaitForChild("Reset")

-- Track if game loop is running
local gameRunning = false

-- Events
local roundComplete = ReplicatedStorage:WaitForChild("Scoreboard.RoundComplete")
local timerExpired = ReplicatedStorage:WaitForChild("GlobalTimer.TimerExpired")
local dispenserEmpty = ReplicatedStorage:WaitForChild("Dispenser.Empty")
local modeChanged = ReplicatedStorage:WaitForChild("RunModes.ModeChanged")

-- Asset control references
local scoreboard = runtimeAssets:WaitForChild("Scoreboard")
local roastingStick = runtimeAssets:WaitForChild("RoastingStick")

-- Apply mode configuration to all assets
local function applyModeToAssets(mode)
	local config = RunModes:GetConfig(mode)
	if not config or not config.assets then
		System.Debug:Warn("Orchestrator", "No asset config for mode:", mode)
		return
	end

	for assetName, settings in pairs(config.assets) do
		local asset = runtimeAssets:FindFirstChild(assetName)
		if asset then
			-- Apply active state
			if settings.active ~= nil then
				local func = asset:FindFirstChild(settings.active and "Enable" or "Disable")
				if func then
					func:Invoke()
				end
			end
		end
	end

	System.Debug:Message("Orchestrator", "Applied mode config:", mode)
end

-- Start the game loop (call once when first player enters active mode)
local function startGameLoop()
	if gameRunning then return end
	gameRunning = true

	System.Debug:Message("Orchestrator", "Starting game loop")

	-- Reset all assets and start timer
	dispenserReset:Invoke()
	timedEvaluatorReset:Invoke()
	globalTimerStart:Invoke()
end

-- Stop the game loop
local function stopGameLoop()
	if not gameRunning then return end
	gameRunning = false

	-- Stop GlobalTimer
	local stopFunc = globalTimer:FindFirstChild("Stop")
	if stopFunc then
		stopFunc:Invoke()
	end

	System.Debug:Message("Orchestrator", "Stopped game loop")
end

-- Per-submission reset (RoundComplete from Scoreboard)
local function onRoundComplete(result)
	-- Only reset if game is running
	if not gameRunning then return end

	System.Debug:Message("Orchestrator", "Submission received - resetting TimedEvaluator")
	task.wait(1)

	-- Check again after delay
	if not gameRunning then return end

	timedEvaluatorReset:Invoke()
end

roundComplete.Event:Connect(onRoundComplete)

-- Full reset function (shared by multiple triggers)
local function fullReset(reason)
	-- Only reset if game is running
	if not gameRunning then return end

	System.Debug:Message("Orchestrator", reason, "- resetting all assets")

	-- Delay to let players see result
	task.wait(3)

	-- Check again after delay (game might have stopped)
	if not gameRunning then return end

	-- Reset all assets and restart timer
	dispenserReset:Invoke()
	timedEvaluatorReset:Invoke()
	globalTimerStart:Invoke()

	System.Debug:Message("Orchestrator", "New round started")
end

-- Listen for GlobalTimer expiration
timerExpired.Event:Connect(function()
	fullReset("GlobalTimer expired")
end)

-- Listen for Dispenser empty
dispenserEmpty.Event:Connect(function()
	fullReset("Dispenser empty")
end)

-- Listen for RunModes changes
modeChanged.Event:Connect(function(data)
	local player = data.player
	local newMode = data.newMode
	local oldMode = data.oldMode

	System.Debug:Message("Orchestrator", "Mode changed for", player.Name, ":", oldMode, "->", newMode)

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
end)

-- Apply initial standby mode to all assets (game doesn't auto-start)
applyModeToAssets(RunModes.Modes.STANDBY)

System.Debug:Message("Orchestrator", "Setup complete - waiting for RunModes")

System.Debug:Message("Orchestrator", "Script loaded")
