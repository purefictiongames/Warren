-- GlobalTimer.LocalScript (Client)
-- Timer display - creates its own standalone GUI

-- Guard: Only run if this is the deployed version
if not script.Name:match("^GlobalTimer%.") then
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
local timerUpdate = ReplicatedStorage:WaitForChild("GlobalTimer.TimerUpdate")

--------------------------------------------------------------------------------
-- CREATE TIMER UI
--------------------------------------------------------------------------------

-- Create ScreenGui manually (layout system will find and reposition if active)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GlobalTimer.ScreenGui"
screenGui.ResetOnSpawn = false

-- Content frame that layout can move
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.Parent = screenGui

-- Timer label using GUI system for styling
local timerLabel = GUI:Create({
	type = "TextLabel",
	id = "global-timer",
	class = "timer-text",
	text = "--:--",
	size = {1, 0, 1, 0},
})
timerLabel.Parent = content

screenGui.Parent = playerGui

--------------------------------------------------------------------------------
-- TIMER LOGIC
--------------------------------------------------------------------------------

local function updateTimer(data)
	if timerLabel then
		if data.isRunning then
			timerLabel.Text = data.formatted
		else
			if data.timeRemaining <= 0 then
				timerLabel.Text = "TIME!"
			else
				timerLabel.Text = data.formatted
			end
		end
	end
end

timerUpdate.OnClientEvent:Connect(updateTimer)

System.Debug:Message("GlobalTimer.client", "Script loaded")
