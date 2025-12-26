-- Orchestrator.Script (Server)
-- Coordinates game flow by listening to events and triggering actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function setupOrchestrator()
    -- Wait for RoundComplete event from Scoreboard
    local roundComplete = ReplicatedStorage:WaitForChild("Scoreboard.RoundComplete")

    -- Find TimedEvaluator's Reset function
    local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
    local timedEvaluator = runtimeAssets:WaitForChild("TimedEvaluator")
    local resetFunction = timedEvaluator:WaitForChild("Reset")

    -- Handle round complete
    local function onRoundComplete(result)
        print("Orchestrator: Round complete - resetting TimedEvaluator")

        -- Small delay to let client see the score
        task.wait(2)

        -- Reset TimedEvaluator for next round
        resetFunction:Invoke()

        print("Orchestrator: TimedEvaluator reset - new round started")
    end

    roundComplete.Event:Connect(onRoundComplete)

    print("Orchestrator: Setup complete - listening for RoundComplete")
end

setupOrchestrator()

print("Orchestrator.Script loaded")
