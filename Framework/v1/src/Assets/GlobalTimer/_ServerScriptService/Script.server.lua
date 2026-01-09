--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- assetName.Script (Server)
-- Global round timer - counts down and fires events for HUD and Orchestrator
-- Uses deferred initialization pattern - registers init function, called at ASSETS stage

-- Guard: Only run if this is the deployed version (has dot in name)
if not script.Name:match("%.") then
	return
end

-- Extract asset name from script name
local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[assetName.Script] Could not extract asset name from script.Name:", script.Name)
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Register init function (will be called at ASSETS stage)
System:RegisterAsset(assetName, function()
	-- Dependencies
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
	local model = runtimeAssets:WaitForChild(assetName)

	-- Get standardized events (created by bootstrap)
	local inputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Input")
	local outputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Output")

	-- TimerUpdate is still a custom RemoteEvent for client updates (keep for now)
	local timerUpdate = ReplicatedStorage:WaitForChild(assetName .. ".TimerUpdate")

	-- Parse CountdownStart attribute (M.SS format where SS must be 00-59)
	local function parseCountdown(value)
		if type(value) ~= "number" or value < 0 then
			return nil
		end

		local minutes = math.floor(value)
		local decimalPart = value - minutes
		local seconds = math.floor(decimalPart * 100 + 0.5)

		if seconds > 59 then
			System.Debug:Warn("assetName", "Invalid CountdownStart - seconds must be <= 59 (got", seconds, ")")
			return nil
		end

		return (minutes * 60) + seconds
	end

	-- Parse countdown from attribute
	local countdownStart = model:GetAttribute("CountdownStart") or 1.00
	local totalSeconds = parseCountdown(countdownStart)

	if not totalSeconds then
		System.Debug:Warn("assetName", "Invalid CountdownStart attribute, defaulting to 3:00")
		totalSeconds = 180
	end

	System.Debug:Message("assetName", "Countdown set to", totalSeconds, "seconds (from", countdownStart, ")")

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

		System.Debug:Message("assetName", "Started -", formatTime(timeRemaining))
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
				System.Debug:Message(assetName, "Expired!")
				broadcastUpdate()
				outputEvent:Fire({ action = "timerExpired" })
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
		System.Debug:Message("assetName", "Stopped at", formatTime(timeRemaining))
	end

	-- Command handlers (callable from Input or BindableFunctions)
	local function handleStart()
		start()
		return true
	end

	local function handleStop()
		stop()
		return true
	end

	local function handleEnable()
		model:SetAttribute("IsEnabled", true)
		model:SetAttribute("HUDVisible", true)
		System.Debug:Message("assetName", "Enabled")
		return true
	end

	local function handleDisable()
		stop()  -- Stop timer when disabled
		model:SetAttribute("IsEnabled", false)
		model:SetAttribute("HUDVisible", false)
		System.Debug:Message("assetName", "Disabled")
		return true
	end

	-- Listen on Input for commands from Orchestrator
	inputEvent.Event:Connect(function(message)
		if not message or type(message) ~= "table" then
			return
		end

		if message.command == "start" then
			handleStart()
		elseif message.command == "stop" then
			handleStop()
		elseif message.command == "enable" then
			handleEnable()
		elseif message.command == "disable" then
			handleDisable()
		else
			System.Debug:Warn(assetName, "Unknown command:", message.command)
		end
	end)

	-- Expose Start via BindableFunction (backward compatibility)
	local startFunction = Instance.new("BindableFunction")
	startFunction.Name = "Start"
	startFunction.OnInvoke = handleStart
	startFunction.Parent = model

	-- Expose Stop via BindableFunction (backward compatibility)
	local stopFunction = Instance.new("BindableFunction")
	stopFunction.Name = "Stop"
	stopFunction.OnInvoke = handleStop
	stopFunction.Parent = model

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

	System.Debug:Message("assetName", "Initialized")
end)

System.Debug:Message("assetName", "Script loaded, init registered")
