-- Scoreboard.Script (Server)
-- Listens to evaluation events from assets, calculates scores, fires to clients

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Scoreboard%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Dependencies (guaranteed to exist after SCRIPTS stage)
local scoreUpdate = ReplicatedStorage:WaitForChild("Scoreboard.ScoreUpdate")
local roundComplete = ReplicatedStorage:WaitForChild("Scoreboard.RoundComplete")
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local timedEvaluator = runtimeAssets:WaitForChild("TimedEvaluator")
local anchor = timedEvaluator:WaitForChild("Anchor")
local evaluationComplete = anchor:WaitForChild("EvaluationComplete")

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

		-- Update player's total score
		playerScores[player] = (playerScores[player] or 0) + score

		System.Debug:Message("Scoreboard", player.Name, "scored", score, "points. Total:", playerScores[player])

		-- Fire to client
		scoreUpdate:FireClient(player, {
			roundScore = score,
			totalScore = playerScores[player],
			submitted = result.submitted,
			submittedValue = result.submittedValue,
			targetValue = result.targetValue,
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

System.Debug:Message("Scoreboard", "Setup complete")

System.Debug:Message("Scoreboard", "Script loaded")
