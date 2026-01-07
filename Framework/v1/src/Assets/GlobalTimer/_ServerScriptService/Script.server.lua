--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- GlobalTimer.Script (Server)
-- Global round timer - counts down and fires events for HUD and Orchestrator
-- Uses deferred initialization pattern - registers init function, called at ASSETS stage

-- Guard: Only run if this is the deployed version
if not script.Name:match("^GlobalTimer%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Register init function (will be called at ASSETS stage)
System:RegisterAsset("GlobalTimer", function()
	-- Dependencies
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
	local model = runtimeAssets:WaitForChild("GlobalTimer")
	local timerUpdate = ReplicatedStorage:WaitForChild("GlobalTimer.TimerUpdate")
	local timerExpired = ReplicatedStorage:WaitForChild("GlobalTimer.TimerExpired")

	-- Parse CountdownStart attribute (M.SS format where SS must be 00-59)
	local function parseCountdown(value)
		if type(value) ~= "number" or value < 0 then
			return nil
		end

		local minutes = math.floor(value)
		local decimalPart = value - minutes
		local seconds = math.floor(decimalPart * 100 + 0.5)

		if seconds > 59 then
			System.Debug:Warn("GlobalTimer", "Invalid CountdownStart - seconds must be <= 59 (got", seconds, ")")
			return nil
		end

		return (minutes * 60) + seconds
	end

	-- Parse countdown from attribute
	local countdownStart = model:GetAttribute("CountdownStart") or 1.00
	local totalSeconds = parseCountdown(countdownStart)

	if not totalSeconds then
		System.Debug:Warn("GlobalTimer", "Invalid CountdownStart attribute, defaulting to 3:00")
		totalSeconds = 180
	end

	System.Debug:Message("GlobalTimer", "Countdown set to", totalSeconds, "seconds (from", countdownStart, ")")

	-- Internal state
	local timerThread = nil
	local timerGeneration = 0
	local isRunning = false
	local timeRemaining = 0

	-- Format seconds as M:SS for display
	local function formatTime(seconds)
		local mins = math.floor(seconds / 60)
		local secs = seconds % 60
		return string.format("%d:%02d", mins, secs)
	end

	-- Broadcast time update to all clients
	local function broadcastUpdate()
		timerUpdate:FireAllClients({
			timeRemaining = timeRemaining,
			formatted = formatTime(timeRemaining),
			isRunning = isRunning,
		})
	end

	-- Start the countdown
	local function start()
		if timerThread then
			pcall(function() task.cancel(timerThread) end)
			timerThread = nil
		end

		timerGeneration = timerGeneration + 1
		local myGeneration = timerGeneration

		isRunning = true
		timeRemaining = totalSeconds
		model:SetAttribute("TimeRemaining", timeRemaining)

		System.Debug:Message("GlobalTimer", "Started -", formatTime(timeRemaining))
		broadcastUpdate()

		timerThread = task.spawn(function()
			while timeRemaining > 0 and isRunning and myGeneration == timerGeneration do
				task.wait(1)
				timeRemaining = timeRemaining - 1
				model:SetAttribute("TimeRemaining", timeRemaining)
				broadcastUpdate()
			end

			if isRunning and myGeneration == timerGeneration then
				isRunning = false
				System.Debug:Message("GlobalTimer", "Expired!")
				broadcastUpdate()
				timerExpired:Fire()
			end
		end)
	end

	-- Stop the countdown (without firing expired)
	local function stop()
		if timerThread then
			pcall(function() task.cancel(timerThread) end)
			timerThread = nil
		end
		isRunning = false
		model:SetAttribute("TimeRemaining", timeRemaining)
		broadcastUpdate()
		System.Debug:Message("GlobalTimer", "Stopped at", formatTime(timeRemaining))
	end

	-- Expose Start via BindableFunction (for Orchestrator)
	local startFunction = Instance.new("BindableFunction")
	startFunction.Name = "Start"
	startFunction.OnInvoke = function()
		start()
		return true
	end
	startFunction.Parent = model

	-- Expose Stop via BindableFunction (for Orchestrator)
	local stopFunction = Instance.new("BindableFunction")
	stopFunction.Name = "Stop"
	stopFunction.OnInvoke = function()
		stop()
		return true
	end
	stopFunction.Parent = model

	-- Expose Enable via BindableFunction (for RunModes)
	local enableFunction = Instance.new("BindableFunction")
	enableFunction.Name = "Enable"
	enableFunction.OnInvoke = function()
		model:SetAttribute("IsEnabled", true)
		model:SetAttribute("HUDVisible", true)
		System.Debug:Message("GlobalTimer", "Enabled")
		return true
	end
	enableFunction.Parent = model

	-- Expose Disable via BindableFunction (for RunModes)
	local disableFunction = Instance.new("BindableFunction")
	disableFunction.Name = "Disable"
	disableFunction.OnInvoke = function()
		stop()  -- Stop timer when disabled
		model:SetAttribute("IsEnabled", false)
		model:SetAttribute("HUDVisible", false)
		System.Debug:Message("GlobalTimer", "Disabled")
		return true
	end
	disableFunction.Parent = model

	System.Debug:Message("GlobalTimer", "Initialized")
end)

System.Debug:Message("GlobalTimer", "Script loaded, init registered")
