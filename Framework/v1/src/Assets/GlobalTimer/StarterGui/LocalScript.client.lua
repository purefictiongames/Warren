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
local screenGui = playerGui:WaitForChild("GlobalTimer.ScreenGui")
local timerLabel = screenGui:FindFirstChild("TimerLabel", true)

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

-- Initialize display
if timerLabel then
	timerLabel.Text = "--:--"
end

print("GlobalTimer.LocalScript: HUD ready")

print("GlobalTimer.LocalScript loaded")
