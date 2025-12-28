-- TimedEvaluator.Script (Server)
-- Timed evaluation system - accepts items and compares against target value

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function setupTimedEvaluator(model)
    local forceItemPickup = ReplicatedStorage:WaitForChild("Backpack.ForceItemPickup")
    -- Config from attributes (with validation)
    local acceptType = model:GetAttribute("AcceptType") or "Marshmallow"
    local evalTarget = model:GetAttribute("EvalTarget") or "ToastLevel"
    local countdown = model:GetAttribute("Countdown") or 30

    -- Validate target range (0 is falsy-ish for game logic, so check explicitly)
    local targetMin = model:GetAttribute("TargetMin")
    local targetMax = model:GetAttribute("TargetMax")
    if targetMin == nil or targetMin <= 0 then targetMin = 10 end
    if targetMax == nil or targetMax <= 0 then targetMax = 100 end
    if targetMin > targetMax then targetMin, targetMax = targetMax, targetMin end

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
    local timerGeneration = 0  -- Invalidates old timer threads
    local isRunning = false
    local hasEvaluated = false

    -- Create TimerTick event for satisfaction updates
    local timerTick = Instance.new("BindableEvent")
    timerTick.Name = "TimerTick"
    timerTick.Parent = model

    -- Update satisfaction based on current state
    local function updateSatisfaction(state)
        local satisfaction = model:GetAttribute("Satisfaction") or 0
        local decay = state.deltaTime * 3 -- Lose 3 satisfaction per second
        satisfaction = math.max(0, satisfaction - decay)
        model:SetAttribute("Satisfaction", satisfaction)
        print("TimedEvaluator: Satisfaction updated to", math.floor(satisfaction))
    end

    -- Listen for timer ticks
    timerTick.Event:Connect(updateSatisfaction)

    -- Evaluate submitted item (or nil if timeout)
    local function evaluate(item, player)
        if hasEvaluated then return end
        hasEvaluated = true
        isRunning = false

        -- Stop timer if running (pcall in case thread already finished)
        if timerThread then
            pcall(function() task.cancel(timerThread) end)
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
        timerGeneration = timerGeneration + 1
        local myGeneration = timerGeneration

        timerThread = task.spawn(function()
            local timeRemaining = countdown
            model:SetAttribute("TimeRemaining", timeRemaining)

            -- Check generation to ensure this timer is still valid
            while timeRemaining > 0 and isRunning and myGeneration == timerGeneration do
                local dt = task.wait(1)
                timeRemaining = timeRemaining - 1
                model:SetAttribute("TimeRemaining", timeRemaining)

                -- Fire tick event with state for satisfaction updates
                timerTick:Fire({
                    deltaTime = dt,
                    timeRemaining = timeRemaining,
                    countdown = countdown,
                })
            end

            -- Time's up - evaluate with nothing (only if still current timer)
            if isRunning and not hasEvaluated and myGeneration == timerGeneration then
                evaluate(nil, nil)
            end
        end)
    end

    -- Reset/init function
    local function reset()
        -- Stop existing timer (pcall in case thread already finished)
        if timerThread then
            pcall(function() task.cancel(timerThread) end)
            timerThread = nil
        end

        -- Reset state
        hasEvaluated = false
        isRunning = true

        -- Set random target value within configured range
        local newTarget = math.random(targetMin, targetMax)
        model:SetAttribute("TargetValue", newTarget)
        model:SetAttribute("TimeRemaining", countdown)
        model:SetAttribute("Satisfaction", 100) -- Start fully satisfied

        print("TimedEvaluator: Reset - TargetValue:", newTarget, "(range:", targetMin, "-", targetMax, ") Countdown:", countdown)

        -- Start timer
        startTimer()
    end

    -- Find marshmallow mounted on RoastingStick
    local function findMountedItem(player)
        local character = player.Character
        if not character then return nil end

        local stick = character:FindFirstChild("RoastingStick")
        if not stick then return nil end

        local mounted = stick:FindFirstChild(acceptType)
        if mounted and mounted:IsA("Tool") then
            return mounted
        end

        return nil
    end

    -- Unmount item from RoastingStick and move to backpack
    local function unmountToBackpack(player, item)
        -- Remove weld if present
        local handle = item:FindFirstChild("Handle")
        if handle then
            local weld = handle:FindFirstChild("WeldConstraint")
            if weld then
                weld:Destroy()
            end
        end

        -- Fire pickup event to move to backpack
        forceItemPickup:Fire({
            player = player,
            item = item,
        })
    end

    -- Find accepted item in player's inventory
    local function findAcceptedItem(player)
        -- Check backpack first
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") and child.Name == acceptType then
                    return child
                end
            end
        end

        -- Check equipped tool
        local character = player.Character
        if character then
            for _, child in ipairs(character:GetChildren()) do
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

        -- Check for mounted item first and unmount to backpack
        local mounted = findMountedItem(player)
        if mounted then
            print("TimedEvaluator: Unmounting", mounted.Name, "from RoastingStick")
            unmountToBackpack(player, mounted)
            task.wait(0.1) -- Let backpack receive it
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
