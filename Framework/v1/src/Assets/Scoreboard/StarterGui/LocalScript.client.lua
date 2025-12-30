-- Scoreboard.LocalScript (Client)
-- Listens to ScoreUpdate events and updates the HUD

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Scoreboard%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Dependencies (guaranteed to exist after READY stage)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local scoreUpdate = ReplicatedStorage:WaitForChild("Scoreboard.ScoreUpdate")
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Create scoreboard GUI
local screenGui = GUI:Create({
	type = "ScreenGui",
	name = "Scoreboard.ScreenGui",
	resetOnSpawn = false,
	zIndex = 5,
	children = {
		{
			type = "Frame",
			size = {0, 150, 0, 70},
			position = {1, -10, 0, 10},
			anchorPoint = {1, 0},
			backgroundTransparency = 1,
			children = {
				{
					type = "TextLabel",
					id = "score-value",
					class = "score-value",
					text = "0",
					size = {1, 0, 0, 40},
					position = {0.5, 0, 0, 0},
					anchorPoint = {0.5, 0},
					textXAlignment = Enum.TextXAlignment.Center,
				},
				{
					type = "TextLabel",
					id = "target-label",
					class = "score-label",
					text = "Waiting...",
					size = {1, 0, 0, 24},
					position = {0.5, 0, 1, 0},
					anchorPoint = {0.5, 1},
					textXAlignment = Enum.TextXAlignment.Center,
				},
			}
		}
	}
})
screenGui.Parent = playerGui

local scoreValue = GUI:GetById("score-value")
local targetLabel = GUI:GetById("target-label")

-- Round to nearest 5
local function roundToNearest5(value)
	return math.floor((value + 2.5) / 5) * 5
end

-- Update display
local function updateDisplay(data)
	if scoreValue then
		local displayScore = roundToNearest5(math.floor(data.totalScore))
		scoreValue.Text = tostring(displayScore)
	end

	if targetLabel then
		if data.submitted then
			targetLabel.Text = "Target: " .. tostring(data.targetValue) .. " | You: " .. tostring(math.floor(data.submittedValue or 0))
		else
			targetLabel.Text = "Time's up! Target was: " .. tostring(data.targetValue)
		end
	end

	System.Debug:Message("Scoreboard.client", "Updated - Round:", data.roundScore, "Total:", data.totalScore)
end

-- Listen for score updates
scoreUpdate.OnClientEvent:Connect(updateDisplay)

System.Debug:Message("Scoreboard.client", "HUD ready")

System.Debug:Message("Scoreboard.client", "Script loaded")
