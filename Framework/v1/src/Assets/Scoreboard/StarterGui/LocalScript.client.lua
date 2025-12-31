-- Scoreboard.LocalScript (Client)
-- Score display - creates its own standalone GUI

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Scoreboard%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Dependencies
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local scoreUpdate = ReplicatedStorage:WaitForChild("Scoreboard.ScoreUpdate")

--------------------------------------------------------------------------------
-- CREATE SCORE UI
--------------------------------------------------------------------------------

-- Create ScreenGui manually (layout system will find and reposition if active)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Scoreboard.ScreenGui"
screenGui.ResetOnSpawn = false

-- Content frame that layout can move
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.Parent = screenGui

-- Score elements using GUI system for styling
local scoreValue = GUI:Create({
	type = "TextLabel",
	id = "score-value",
	class = "score-value",
	text = "0",
	size = {1, 0, 0.6, 0},
	position = {0.5, 0, 0, 0},
	anchorPoint = {0.5, 0},
})
scoreValue.Parent = content

local scoreLabel = GUI:Create({
	type = "TextLabel",
	id = "score-label",
	class = "score-label",
	text = "Waiting...",
	size = {1, 0, 0.4, 0},
	position = {0.5, 0, 1, 0},
	anchorPoint = {0.5, 1},
	textWrapped = true,
})
scoreLabel.Parent = content

screenGui.Parent = playerGui

--------------------------------------------------------------------------------
-- SCORE LOGIC
--------------------------------------------------------------------------------

local function roundToNearest5(value)
	return math.floor((value + 2.5) / 5) * 5
end

local function updateScore(data)
	if scoreValue then
		local displayScore = roundToNearest5(math.floor(data.totalScore))
		scoreValue.Text = tostring(displayScore)
	end

	if scoreLabel then
		if data.submitted then
			scoreLabel.Text = "Target: " .. tostring(data.targetValue) .. " | You: " .. tostring(math.floor(data.submittedValue or 0))
		else
			scoreLabel.Text = "Time's up! Target was: " .. tostring(data.targetValue)
		end
	end

	System.Debug:Message("Scoreboard.client", "Score updated - Total:", data.totalScore)
end

scoreUpdate.OnClientEvent:Connect(updateScore)

System.Debug:Message("Scoreboard.client", "Script loaded")
