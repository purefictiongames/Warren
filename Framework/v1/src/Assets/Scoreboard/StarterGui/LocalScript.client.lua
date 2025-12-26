-- Scoreboard.LocalScript (Client)
-- Listens to ScoreUpdate events and updates the HUD

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function setupHUD()
    -- Wait for ScoreUpdate RemoteEvent
    local scoreUpdate = ReplicatedStorage:WaitForChild("Scoreboard.ScoreUpdate")

    -- Wait for ScreenGui (deployed by System bootstrap)
    local screenGui = playerGui:WaitForChild("Scoreboard.ScreenGui")

    -- Find UI elements (adjust names based on your Studio setup)
    local scoreLabel = screenGui:FindFirstChild("ScoreLabel", true)
    local targetLabel = screenGui:FindFirstChild("TargetLabel", true)

    -- Round to nearest 5
    local function roundToNearest5(value)
        return math.floor((value + 2.5) / 5) * 5
    end

    -- Update display
    local function updateDisplay(data)
        if scoreLabel then
            local displayScore = roundToNearest5(math.floor(data.totalScore))
            scoreLabel.Text = "Score: " .. tostring(displayScore)
        end

        if targetLabel then
            if data.submitted then
                targetLabel.Text = "Target: " .. tostring(data.targetValue) .. " | You: " .. tostring(math.floor(data.submittedValue or 0))
            else
                targetLabel.Text = "Time's up! Target was: " .. tostring(data.targetValue)
            end
        end

        print("HUD: Updated - Round:", data.roundScore, "Total:", data.totalScore)
    end

    -- Listen for score updates
    scoreUpdate.OnClientEvent:Connect(updateDisplay)

    -- Initialize display
    if scoreLabel then
        scoreLabel.Text = "Score: 0"
    end
    if targetLabel then
        targetLabel.Text = "Waiting..."
    end

    print("Scoreboard.LocalScript: HUD ready")
end

setupHUD()

print("Scoreboard.LocalScript loaded")
