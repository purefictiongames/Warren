--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Scoreboard.Script (Server)
-- Listens to evaluation events from assets, calculates scores, fires to clients
-- Uses deferred initialization pattern - registers init function, called at ASSETS stage

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Scoreboard%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Register init function (will be called at ASSETS stage)
System:RegisterAsset("Scoreboard", function()
	-- Dependencies
	local scoreUpdate = ReplicatedStorage:WaitForChild("Scoreboard.ScoreUpdate")
	local roundComplete = ReplicatedStorage:WaitForChild("Scoreboard.RoundComplete")
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
	local timedEvaluator = runtimeAssets:WaitForChild("TimedEvaluator")
	local anchor = timedEvaluator:WaitForChild("Anchor")
	local evaluationComplete = anchor:WaitForChild("EvaluationComplete")
	local model = runtimeAssets:WaitForChild("Scoreboard")

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

		System.Debug:Message("Scoreboard", "Accuracy:", accuracyScore, "Speed:", speedScore, "Total:", score)

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
				System.Debug:Message("Scoreboard", "Practice mode - score not persisted for", player.Name)
			end

			if shouldPersist then
				-- Update player's total score
				playerScores[player] = (playerScores[player] or 0) + score
				System.Debug:Message("Scoreboard", player.Name, "scored", score, "points. Total:", playerScores[player])
			else
				-- In practice mode, show score but don't persist
				System.Debug:Message("Scoreboard", player.Name, "scored", score, "points (practice - not saved)")
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
			System.Debug:Message("Scoreboard", "Timeout - no submission")
		end

		-- Signal round complete (for Orchestrator) - always fire to reset
		roundComplete:Fire({
			player = player,
			roundScore = score,
			totalScore = player and playerScores[player] or 0,
			timeout = not result.submitted,
		})
		System.Debug:Message("Scoreboard", "Round complete signaled")
	end

	-- Connect to TimedEvaluator
	evaluationComplete.Event:Connect(onEvaluationComplete)
	System.Debug:Message("Scoreboard", "Connected to TimedEvaluator.EvaluationComplete")

	-- Clean up when player leaves
	Players.PlayerRemoving:Connect(function(player)
		playerScores[player] = nil
	end)

	-- Expose Enable via BindableFunction (for RunModes)
	local enableFunction = Instance.new("BindableFunction")
	enableFunction.Name = "Enable"
	enableFunction.OnInvoke = function()
		model:SetAttribute("IsEnabled", true)
		model:SetAttribute("HUDVisible", true)
		System.Debug:Message("Scoreboard", "Enabled")
		return true
	end
	enableFunction.Parent = model

	-- Expose Disable via BindableFunction (for RunModes)
	local disableFunction = Instance.new("BindableFunction")
	disableFunction.Name = "Disable"
	disableFunction.OnInvoke = function()
		model:SetAttribute("IsEnabled", false)
		model:SetAttribute("HUDVisible", false)
		System.Debug:Message("Scoreboard", "Disabled")
		return true
	end
	disableFunction.Parent = model

	System.Debug:Message("Scoreboard", "Initialized")
end)

System.Debug:Message("Scoreboard", "Script loaded, init registered")
