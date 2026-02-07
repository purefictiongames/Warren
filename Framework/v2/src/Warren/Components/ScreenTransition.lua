--[[
    Warren Framework v2
    ScreenTransition.lua - Screen Fade Transition Component

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    ScreenTransition is a client-side node that handles fade-to-black screen
    transitions during teleportation. It coordinates with the server-side
    RegionManager via IPC signals.

    ============================================================================
    SIGNAL FLOW
    ============================================================================

    1. Server -> Client: transitionStart
       Client disables controls, fades to black, fires fadeOutComplete

    2. Client -> Server: fadeOutComplete
       Server builds/loads map, moves player, fires loadingComplete

    3. Server -> Client: loadingComplete { container }
       Client preloads assets, waits for lighting, fades in, fires transitionComplete

    4. Client -> Server: transitionComplete
       Server fires transitionEnd, unanchors player

    5. Server -> Client: transitionEnd
       Client re-enables controls

--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- SCREENTRANSITION NODE
--------------------------------------------------------------------------------

local ScreenTransition = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE STATE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                fadeFrame = nil,
                isTransitioning = false,
                originalWalkSpeed = nil,
                baselineFrameTime = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state and state.screenGui then
            state.screenGui:Destroy()
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- UI CREATION
    ----------------------------------------------------------------------------

    local function createUI(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        -- Clean up existing
        if state.screenGui then
            state.screenGui:Destroy()
        end
        local existing = playerGui:FindFirstChild("ScreenTransition")
        if existing then
            existing:Destroy()
        end

        -- Create ScreenGui
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "ScreenTransition"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 999
        screenGui.IgnoreGuiInset = true
        screenGui.Parent = playerGui

        -- Create full-screen black frame (starts transparent)
        local fadeFrame = Instance.new("Frame")
        fadeFrame.Name = "FadeFrame"
        fadeFrame.Size = UDim2.new(1, 0, 1, 0)
        fadeFrame.Position = UDim2.new(0, 0, 0, 0)
        fadeFrame.BackgroundColor3 = Color3.new(0, 0, 0)
        fadeFrame.BackgroundTransparency = 1
        fadeFrame.BorderSizePixel = 0
        fadeFrame.ZIndex = 100
        fadeFrame.Parent = screenGui

        state.screenGui = screenGui
        state.fadeFrame = fadeFrame
    end

    ----------------------------------------------------------------------------
    -- FADE ANIMATIONS
    ----------------------------------------------------------------------------

    local FADE_DURATION = 2.0

    local function fadeToBlack(self, callback)
        local state = getState(self)
        if not state.fadeFrame then
            if callback then callback() end
            return
        end

        local tween = TweenService:Create(
            state.fadeFrame,
            TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0 }
        )

        tween.Completed:Connect(function()
            if callback then callback() end
        end)

        tween:Play()
    end

    local function fadeFromBlack(self, callback)
        local state = getState(self)
        if not state.fadeFrame then
            if callback then callback() end
            return
        end

        local tween = TweenService:Create(
            state.fadeFrame,
            TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        )

        tween.Completed:Connect(function()
            if callback then callback() end
        end)

        tween:Play()
    end

    ----------------------------------------------------------------------------
    -- INPUT CONTROL
    ----------------------------------------------------------------------------

    local function disableControls(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:Move(Vector3.zero, false)
                state.originalWalkSpeed = humanoid.WalkSpeed
                humanoid.WalkSpeed = 0
            end
        end

        -- Disable PlayerModule controls
        local playerScripts = player:FindFirstChild("PlayerScripts")
        if playerScripts then
            local playerModule = playerScripts:FindFirstChild("PlayerModule")
            if playerModule then
                local success, controls = pcall(function()
                    return require(playerModule):GetControls()
                end)
                if success and controls then
                    controls:Disable()
                end
            end
        end
    end

    local function enableControls(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        -- Re-enable PlayerModule controls
        local playerScripts = player:FindFirstChild("PlayerScripts")
        if playerScripts then
            local playerModule = playerScripts:FindFirstChild("PlayerModule")
            if playerModule then
                local success, controls = pcall(function()
                    return require(playerModule):GetControls()
                end)
                if success and controls then
                    controls:Enable()
                end
            end
        end

        -- Restore walk speed
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and state.originalWalkSpeed then
                humanoid.WalkSpeed = state.originalWalkSpeed
                state.originalWalkSpeed = nil
            end
        end
    end

    ----------------------------------------------------------------------------
    -- ASSET PRELOADING & LIGHTING WAIT
    ----------------------------------------------------------------------------

    -- Frame time detection settings
    local BASELINE_SETTLE_TIME = 0.2    -- Seconds to wait before measuring baseline
    local BASELINE_SAMPLE_COUNT = 10    -- Frames to average for baseline
    local MARGIN_PERCENT = 0.25         -- 25% margin above baseline
    local MAX_WAIT_TIME = 5.0           -- Timeout after 5 seconds
    local MIN_WAIT_FRAMES = 10          -- Minimum frames to wait during loading

    local function measureBaselineFrameTime(self)
        local state = getState(self)

        -- Wait for frame rates to settle after fade
        task.wait(BASELINE_SETTLE_TIME)

        -- Measure average frame time over several frames
        local total = 0
        for _ = 1, BASELINE_SAMPLE_COUNT do
            total = total + RunService.RenderStepped:Wait()
        end

        state.baselineFrameTime = total / BASELINE_SAMPLE_COUNT
    end

    local function waitForFrameTimeToSettle(self)
        local state = getState(self)
        local baseline = state.baselineFrameTime

        if not baseline then
            -- No baseline, just wait minimum frames
            for _ = 1, MIN_WAIT_FRAMES do
                RunService.RenderStepped:Wait()
            end
            return true
        end

        local threshold = baseline * (1 + MARGIN_PERCENT)
        local startTime = os.clock()
        local stableCount = 0
        local requiredStableFrames = 5

        -- Wait minimum frames first (give lighting time to start)
        for _ = 1, MIN_WAIT_FRAMES do
            RunService.RenderStepped:Wait()
        end

        -- Then wait for frame times to return to near baseline
        while os.clock() - startTime < MAX_WAIT_TIME do
            local dt = RunService.RenderStepped:Wait()

            if dt <= threshold then
                stableCount = stableCount + 1
                if stableCount >= requiredStableFrames then
                    return true
                end
            else
                stableCount = 0  -- Reset if a frame exceeds threshold
            end
        end

        return false  -- Timeout
    end

    local function preloadAndWait(self, container, callback)
        task.spawn(function()
            -- Preload assets
            if container then
                local assets = {}
                for _, obj in ipairs(container:GetDescendants()) do
                    if obj:IsA("BasePart") or obj:IsA("Decal") or obj:IsA("Texture")
                       or obj:IsA("MeshPart") or obj:IsA("Light") then
                        table.insert(assets, obj)
                    end
                end

                pcall(function()
                    ContentProvider:PreloadAsync(assets)
                end)
            end

            -- Wait for frame times to return to baseline
            waitForFrameTimeToSettle(self)

            if callback then callback() end
        end)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "ScreenTransition",
        domain = "client",

        Sys = {
            onInit = function(self)
                createUI(self)
            end,
            onStart = function(self) end,
            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            -- Step 1: Server signals to start transition
            onTransitionStart = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                if data.player and data.player ~= player then return end
                if state.isTransitioning then return end

                state.isTransitioning = true

                -- Disable controls
                disableControls(self)

                -- Fade to black, measure baseline, then signal server
                fadeToBlack(self, function()
                    -- Measure baseline frame time while screen is black and idle
                    measureBaselineFrameTime(self)

                    -- Now signal server to start loading
                    self.Out:Fire("fadeOutComplete", {
                        _targetPlayer = player,
                        player = player,
                    })
                end)
            end,

            -- Step 3: Server signals loading is complete
            onLoadingComplete = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                if data.player and data.player ~= player then return end

                -- Preload and wait for lighting (screen stays black)
                preloadAndWait(self, data.container, function()
                    -- Signal server that preloading is done
                    self.Out:Fire("transitionComplete", {
                        _targetPlayer = player,
                        player = player,
                    })
                end)
            end,

            -- Step 5: Server signals transition is fully done
            onTransitionEnd = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                if data.player and data.player ~= player then return end

                -- Fade in, then re-enable controls
                fadeFromBlack(self, function()
                    enableControls(self)
                    state.isTransitioning = false
                end)
            end,
        },

        Out = {
            fadeOutComplete = {},
            transitionComplete = {},
        },
    }
end)

return ScreenTransition
