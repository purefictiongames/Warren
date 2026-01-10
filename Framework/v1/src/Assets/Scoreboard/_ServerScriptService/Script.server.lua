--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- assetName.Script (Server)
-- Listens to evaluation events from assets, calculates scores, fires to clients
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
local Players = game:GetService("Players")

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

	-- ScoreUpdate is still a custom RemoteEvent for client updates (keep for now)
	local scoreUpdate = ReplicatedStorage:WaitForChild(assetName .. ".ScoreUpdate")

	-- Load RunModes API (lazy - may not exist during initial development)
	local RunModes = nil
	task.spawn(function()
		local runModesModule = ReplicatedStorage:WaitForChild("RunModes.RunModes", 10)
		if runModesModule then
			RunModes = require(runModesModule)
		end
	end)

	-- Track player scores
	local playerScores = {}

	-- Calculate score from evaluation result (Option C: 60/40 weighted balance)
	local function calculateScore(result)
		if not result.submitted then
			return 0
		end

		local diff = result.score or math.abs(result.targetValue - result.submittedValue)
		local timeRemaining = result.timeRemaining or 0
		local countdown = result.countdown or 30

		-- Accuracy component (60% weight, max 60 points)
		local accuracyScore = math.max(0, 60 - (diff * 6))

		-- Speed component (40% weight, max 40 points)
		local speedScore = math.floor((timeRemaining / countdown) * 40)

		local score = accuracyScore + speedScore

		System.Debug:Message("assetName", "Accuracy:", accuracyScore, "Speed:", speedScore, "Total:", score)

		return score
	end

	-- Handle evaluation complete from TimedEvaluator
	local function onEvaluationComplete(result)
		local player = result.player
		local score = 0

		if player then
			score = calculateScore(result)

			-- Check if scoring should be persisted (RunModes integration)
			local shouldPersist = true
			if RunModes and not RunModes:IsScoringEnabled(player) then
				shouldPersist = false
				System.Debug:Message("assetName", "Practice mode - score not persisted for", player.Name)
			end

			if shouldPersist then
				-- Update player's total score
				playerScores[player] = (playerScores[player] or 0) + score
				System.Debug:Message("assetName", player.Name, "scored", score, "points. Total:", playerScores[player])
			else
				-- In practice mode, show score but don't persist
				System.Debug:Message("assetName", player.Name, "scored", score, "points (practice - not saved)")
			end

			-- Fire to client (always show the score)
			scoreUpdate:FireClient(player, {
				roundScore = score,
				totalScore = shouldPersist and playerScores[player] or score,
				submitted = result.submitted,
				submittedValue = result.submittedValue,
				targetValue = result.targetValue,
				isPractice = not shouldPersist,
			})
		else
			System.Debug:Message("assetName", "Timeout - no submission")
		end

		-- Signal round complete via Output - fires to both Orchestrator and LeaderBoard
		outputEvent:Fire({
			action = "roundComplete",
			player = player,
			score = player and playerScores[player] or 0,
			result = {
				player = player,
				roundScore = score,
				totalScore = player and playerScores[player] or 0,
				timeout = not result.submitted,
			}
		})
		System.Debug:Message(assetName, "Round complete signaled via Output")
	end

	-- Clean up when player leaves
	Players.PlayerRemoving:Connect(function(player)
		playerScores[player] = nil
	end)

	-- Command handlers (callable from Input or BindableFunctions)
	local function handleEnable()
		model:SetAttribute("IsEnabled", true)
		model:SetAttribute("HUDVisible", true)
		System.Debug:Message(assetName, "Enabled")
		return true
	end

	local function handleDisable()
		model:SetAttribute("IsEnabled", false)
		model:SetAttribute("HUDVisible", false)
		System.Debug:Message(assetName, "Disabled")
		return true
	end

	-- Listen on Input for commands and forwarded events
	inputEvent.Event:Connect(function(message)
		if not message or type(message) ~= "table" then
			return
		end

		-- Handle forwarded evaluation events from Dropper
		if message.action == "evaluationComplete" then
			System.Debug:Message(assetName, "Received forwarded evaluation from", message.origin or "unknown")
			onEvaluationComplete(message.result)
			return
		end

		-- Handle commands from Orchestrator
		if message.command == "enable" then
			handleEnable()
		elseif message.command == "disable" then
			handleDisable()
		else
			System.Debug:Warn(assetName, "Unknown message:", message.command or message.action)
		end
	end)

	System.Debug:Message(assetName, "Listening for evaluation events via Input")

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
