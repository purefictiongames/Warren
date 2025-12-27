-- GlobalTimer.Script (Server)
-- Global round timer - counts down and fires events for HUD and Orchestrator

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Parse CountdownStart attribute (M.SS format where SS must be 00-59)
-- Returns total seconds or nil if invalid
local function parseCountdown(value)
    if type(value) ~= "number" or value < 0 then
        return nil
    end

    local minutes = math.floor(value)
    -- Extract seconds from decimal: 1.30 -> 0.30 -> 30
    local decimalPart = value - minutes
    local seconds = math.floor(decimalPart * 100 + 0.5) -- Round to handle floating point

    if seconds > 59 then
        warn("GlobalTimer: Invalid CountdownStart - seconds must be <= 59 (got", seconds, ")")
        return nil
    end

    return (minutes * 60) + seconds
end

local function setupGlobalTimer(model)
    -- Parse countdown from attribute
    local countdownStart = model:GetAttribute("CountdownStart") or 3.00
    local totalSeconds = parseCountdown(countdownStart)

    if not totalSeconds then
        warn("GlobalTimer: Invalid CountdownStart attribute, defaulting to 3:00")
        totalSeconds = 180 -- 3 minutes default
    end

    print("GlobalTimer: Countdown set to", totalSeconds, "seconds (from", countdownStart, ")")

    -- Find events (created in Studio, extracted by System)
    local timerUpdate = ReplicatedStorage:WaitForChild("GlobalTimer.TimerUpdate")
    local timerExpired = ReplicatedStorage:WaitForChild("GlobalTimer.TimerExpired")

    -- Internal state
    local timerThread = nil
    local timerGeneration = 0
    local isRunning = false
    local timeRemaining = 0

    -- Format seconds as M:SS for display
    local function formatTime(seconds)
        local mins = math.floor(seconds / 60)
        local secs = seconds % 60
        return string.format("%d:%02d", mins, secs)
    end

    -- Broadcast time update to all clients
    local function broadcastUpdate()
        timerUpdate:FireAllClients({
            timeRemaining = timeRemaining,
            formatted = formatTime(timeRemaining),
            isRunning = isRunning,
        })
    end

    -- Start the countdown
    local function start()
        -- Stop existing timer
        if timerThread then
            pcall(function() task.cancel(timerThread) end)
            timerThread = nil
        end

        timerGeneration = timerGeneration + 1
        local myGeneration = timerGeneration

        isRunning = true
        timeRemaining = totalSeconds
        model:SetAttribute("TimeRemaining", timeRemaining)

        print("GlobalTimer: Started -", formatTime(timeRemaining))
        broadcastUpdate()

        timerThread = task.spawn(function()
            while timeRemaining > 0 and isRunning and myGeneration == timerGeneration do
                task.wait(1)
                timeRemaining = timeRemaining - 1
                model:SetAttribute("TimeRemaining", timeRemaining)
                broadcastUpdate()
            end

            -- Timer expired
            if isRunning and myGeneration == timerGeneration then
                isRunning = false
                print("GlobalTimer: Expired!")
                broadcastUpdate()
                timerExpired:Fire()
            end
        end)
    end

    -- Stop the countdown (without firing expired)
    local function stop()
        if timerThread then
            pcall(function() task.cancel(timerThread) end)
            timerThread = nil
        end
        isRunning = false
        model:SetAttribute("TimeRemaining", timeRemaining)
        broadcastUpdate()
        print("GlobalTimer: Stopped at", formatTime(timeRemaining))
    end

    -- Expose Start via BindableFunction (for Orchestrator)
    local startFunction = Instance.new("BindableFunction")
    startFunction.Name = "Start"
    startFunction.OnInvoke = function()
        start()
        return true
    end
    startFunction.Parent = model

    -- Expose Stop via BindableFunction (for Orchestrator)
    local stopFunction = Instance.new("BindableFunction")
    stopFunction.Name = "Stop"
    stopFunction.OnInvoke = function()
        stop()
        return true
    end
    stopFunction.Parent = model

    print("GlobalTimer: Setup complete")
end

-- Wait for model in RuntimeAssets
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("GlobalTimer")
setupGlobalTimer(model)

print("GlobalTimer.Script loaded")
