-- Orchestrator.Script (Server)
-- Coordinates game flow - listens to events and triggers appropriate resets

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function setupOrchestrator()
    local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")

    -- Get GlobalTimer controls
    local globalTimer = runtimeAssets:WaitForChild("GlobalTimer")
    local globalTimerStart = globalTimer:WaitForChild("Start")

    -- Get asset Reset functions
    local dispenser = runtimeAssets:WaitForChild("Dispenser")
    local dispenserReset = dispenser:WaitForChild("Reset")

    local timedEvaluator = runtimeAssets:WaitForChild("TimedEvaluator")
    local timedEvaluatorReset = timedEvaluator:WaitForChild("Reset")

    -- Listen for per-submission reset (RoundComplete from Scoreboard)
    local roundComplete = ReplicatedStorage:WaitForChild("Scoreboard.RoundComplete")

    local function onRoundComplete(result)
        print("Orchestrator: Submission received - resetting TimedEvaluator")
        task.wait(1)
        timedEvaluatorReset:Invoke()
    end

    roundComplete.Event:Connect(onRoundComplete)

    -- Full reset function (shared by multiple triggers)
    local function fullReset(reason)
        print("Orchestrator:", reason, "- resetting all assets")

        -- Delay to let players see result
        task.wait(3)

        -- Reset all assets and restart timer
        dispenserReset:Invoke()
        timedEvaluatorReset:Invoke()
        globalTimerStart:Invoke()

        print("Orchestrator: New round started")
    end

    -- Listen for GlobalTimer expiration
    local timerExpired = ReplicatedStorage:WaitForChild("GlobalTimer.TimerExpired")
    timerExpired.Event:Connect(function()
        fullReset("GlobalTimer expired")
    end)

    -- Listen for Dispenser empty
    local dispenserEmpty = ReplicatedStorage:WaitForChild("Dispenser.Empty")
    dispenserEmpty.Event:Connect(function()
        fullReset("Dispenser empty")
    end)

    -- Start GlobalTimer on game load
    globalTimerStart:Invoke()

    print("Orchestrator: Setup complete")
end

setupOrchestrator()

print("Orchestrator.Script loaded")
