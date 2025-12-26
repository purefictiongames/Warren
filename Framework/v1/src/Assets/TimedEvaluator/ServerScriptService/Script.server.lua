-- TimedEvaluator.Script (Server)
-- Timed evaluation system - accepts items and compares against target value

local Players = game:GetService("Players")

local function setupTimedEvaluator(model)
    -- Config from attributes
    local acceptType = model:GetAttribute("AcceptType") or "Marshmallow"
    local evalTarget = model:GetAttribute("EvalTarget") or "ToastLevel"
    local countdown = model:GetAttribute("Countdown") or 30

    -- Find components
    local anchor = model:FindFirstChild("Anchor")
    if not anchor then
        warn("TimedEvaluator: No Anchor found in", model.Name)
        return
    end

    local prompt = anchor:FindFirstChild("ProximityPrompt")
    if not prompt then
        warn("TimedEvaluator: No ProximityPrompt found in Anchor")
        return
    end

    local evaluationComplete = anchor:FindFirstChild("EvaluationComplete")
    if not evaluationComplete then
        warn("TimedEvaluator: No EvaluationComplete event found in Anchor")
        return
    end

    -- Internal state
    local timerThread = nil
    local isRunning = false
    local hasEvaluated = false

    -- Evaluate submitted item (or nil if timeout)
    local function evaluate(item, player)
        if hasEvaluated then return end
        hasEvaluated = true
        isRunning = false

        -- Stop timer if running
        if timerThread then
            task.cancel(timerThread)
            timerThread = nil
        end

        local targetValue = model:GetAttribute("TargetValue") or 0
        local submittedValue = nil
        local score = nil

        if item then
            submittedValue = item:GetAttribute(evalTarget) or 0
            score = math.abs(targetValue - submittedValue)
            print("TimedEvaluator: Evaluated", item.Name, "- Submitted:", submittedValue, "Target:", targetValue, "Score:", score)
        else
            print("TimedEvaluator: Time ran out! Target was:", targetValue)
        end

        -- Fire event with result
        local timeRemaining = model:GetAttribute("TimeRemaining") or 0
        evaluationComplete:Fire({
            submitted = item ~= nil,
            submittedValue = submittedValue,
            targetValue = targetValue,
            score = score,
            player = player,
            timeRemaining = timeRemaining,
            countdown = countdown,
        })
    end

    -- Start countdown timer
    local function startTimer()
        timerThread = task.spawn(function()
            local timeRemaining = countdown
            model:SetAttribute("TimeRemaining", timeRemaining)

            while timeRemaining > 0 and isRunning do
                task.wait(1)
                timeRemaining = timeRemaining - 1
                model:SetAttribute("TimeRemaining", timeRemaining)
            end

            -- Time's up - evaluate with nothing
            if isRunning and not hasEvaluated then
                evaluate(nil, nil)
            end
        end)
    end

    -- Reset/init function
    local function reset()
        -- Stop existing timer
        if timerThread then
            task.cancel(timerThread)
            timerThread = nil
        end

        -- Reset state
        hasEvaluated = false
        isRunning = true

        -- Set random target value (1-10 for now)
        local newTarget = math.random(1, 10)
        model:SetAttribute("TargetValue", newTarget)
        model:SetAttribute("TimeRemaining", countdown)

        print("TimedEvaluator: Reset - TargetValue:", newTarget, "Countdown:", countdown)

        -- Start timer
        startTimer()
    end

    -- Find accepted item in player's inventory
    local function findAcceptedItem(player)
        -- Check equipped tool first
        local character = player.Character
        if character then
            for _, child in ipairs(character:GetChildren()) do
                if child:IsA("Tool") and child.Name == acceptType then
                    return child
                end
            end
        end

        -- Check backpack
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") and child.Name == acceptType then
                    return child
                end
            end
        end

        return nil
    end

    -- Handle player interaction
    prompt.Triggered:Connect(function(player)
        if not isRunning or hasEvaluated then
            print("TimedEvaluator: Not accepting submissions")
            return
        end

        local item = findAcceptedItem(player)
        if not item then
            print("TimedEvaluator: Player has no", acceptType)
            return
        end

        -- Take the item and evaluate
        local itemToEvaluate = item
        item:Destroy()

        evaluate(itemToEvaluate, player)
    end)

    -- Expose reset via BindableFunction (for orchestrator)
    local resetFunction = Instance.new("BindableFunction")
    resetFunction.Name = "Reset"
    resetFunction.OnInvoke = function()
        reset()
        return true
    end
    resetFunction.Parent = model

    -- Initial reset on load
    reset()

    print("TimedEvaluator: Setup complete - AcceptType:", acceptType, "EvalTarget:", evalTarget)
end

-- Wait for model in RuntimeAssets
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("TimedEvaluator")
setupTimedEvaluator(model)

print("TimedEvaluator.Script loaded")
