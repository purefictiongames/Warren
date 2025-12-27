-- GlobalTimer.LocalScript (Client)
-- Listens to TimerUpdate events and updates the HUD countdown display

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function setupHUD()
    -- Wait for TimerUpdate RemoteEvent
    local timerUpdate = ReplicatedStorage:WaitForChild("GlobalTimer.TimerUpdate")

    -- Wait for ScreenGui (deployed by System bootstrap)
    local screenGui = playerGui:WaitForChild("GlobalTimer.ScreenGui")

    -- Find UI elements
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
end

setupHUD()

print("GlobalTimer.LocalScript loaded")
