-- GlobalTimer.LocalScript (Client)
-- Listens to TimerUpdate events and updates the HUD countdown display

-- Guard: Only run if this is the deployed version
if not script.Name:match("^GlobalTimer%.") then
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
local timerUpdate = ReplicatedStorage:WaitForChild("GlobalTimer.TimerUpdate")
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Create timer GUI
local screenGui = GUI:Create({
	type = "ScreenGui",
	name = "GlobalTimer.ScreenGui",
	resetOnSpawn = false,
	zIndex = 5,
	children = {
		{
			type = "TextLabel",
			id = "timer-label",
			class = "timer-text",
			text = "--:--",
			size = {0, 120, 0, 60},
			position = {0.5, 0, 0, 10},
			anchorPoint = {0.5, 0},
		}
	}
})
screenGui.Parent = playerGui

local timerLabel = GUI:GetById("timer-label")

-- Update display
local function updateDisplay(data)
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

-- Listen for timer updates
timerUpdate.OnClientEvent:Connect(updateDisplay)

System.Debug:Message("GlobalTimer.client", "HUD ready")

System.Debug:Message("GlobalTimer.client", "Script loaded")
