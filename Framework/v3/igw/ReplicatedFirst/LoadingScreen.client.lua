--[[
    It Gets Worse — Loading Screen (ReplicatedFirst)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    ReplicatedFirst LocalScript — runs before all other framework code.
    Shows an opaque black overlay instantly, then:

    1. Waits for server's ViewReady signal (geometry built, player positioned)
    2. Preloads renderable assets in the view container
    3. Waits for frame time to settle (lighting/shaders finish)
    4. Fades overlay out over 1 second
    5. Signals server via LoadingDone (server unanchors player)
    6. Destroys itself

    This prevents players from seeing unfinished geometry or falling through
    the void while the server builds the world.

--]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local FADE_DURATION = 1.0
local MIN_WAIT_FRAMES = 10
local MARGIN_PERCENT = 0.25        -- 25% above baseline
local MAX_SETTLE_TIME = 5.0        -- Frame settle timeout
local REQUIRED_STABLE_FRAMES = 5
local CONTAINER_WAIT_TIMEOUT = 30  -- Max seconds to wait for container
local BASELINE_SETTLE_TIME = 0.2   -- Seconds before measuring baseline
local BASELINE_FRAMES = 10         -- Frames to measure for baseline

--------------------------------------------------------------------------------
-- CREATE OVERLAY
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
screenGui.DisplayOrder = 1000
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0
overlay.BorderSizePixel = 0
overlay.ZIndex = 1
overlay.Parent = screenGui

local label = Instance.new("TextLabel")
label.Name = "LoadingLabel"
label.Size = UDim2.fromScale(1, 1)
label.Position = UDim2.fromScale(0, 0)
label.BackgroundTransparency = 1
label.Text = "Loading..."
label.TextColor3 = Color3.fromRGB(180, 180, 180)
label.TextSize = 18
label.Font = Enum.Font.GothamMedium
label.ZIndex = 2
label.Parent = screenGui

screenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- WAIT FOR SERVER SIGNAL
--------------------------------------------------------------------------------

local viewReadyEvent = ReplicatedStorage:WaitForChild("ViewReady", 60)
local loadingDoneEvent = ReplicatedStorage:WaitForChild("LoadingDone", 60)

if not viewReadyEvent or not loadingDoneEvent then
    warn("[LoadingScreen] Timed out waiting for RemoteEvents, dismissing")
    screenGui:Destroy()
    return
end

-- Block until server says view is ready
local payload = nil
local received = false
local conn
conn = viewReadyEvent.OnClientEvent:Connect(function(data)
    payload = data or {}
    received = true
    conn:Disconnect()
end)

-- Wait for signal (with safety timeout)
local waitStart = os.clock()
while not received and (os.clock() - waitStart) < 60 do
    task.wait(0.1)
end

if not received then
    warn("[LoadingScreen] Timed out waiting for ViewReady, dismissing")
    screenGui:Destroy()
    return
end

--------------------------------------------------------------------------------
-- PRELOAD CONTAINER ASSETS
--------------------------------------------------------------------------------

local containerName = payload.containerName

if containerName then
    local container = workspace:WaitForChild(containerName, CONTAINER_WAIT_TIMEOUT)

    if container then
        -- Filter renderable assets (same as ScreenTransition.lua)
        local assets = {}
        for _, obj in ipairs(container:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Decal") or obj:IsA("Texture")
               or obj:IsA("MeshPart") or obj:IsA("Light") then
                table.insert(assets, obj)
            end
        end

        if #assets > 0 then
            ContentProvider:PreloadAsync(assets)
        end
    else
        warn("[LoadingScreen] Container '" .. containerName .. "' not found after timeout")
    end
end

--------------------------------------------------------------------------------
-- WAIT FOR FRAME TIME TO SETTLE
--------------------------------------------------------------------------------

-- Let rendering settle before measuring baseline
task.wait(BASELINE_SETTLE_TIME)

-- Measure baseline frame time
local totalDt = 0
for _ = 1, BASELINE_FRAMES do
    local dt = RunService.RenderStepped:Wait()
    totalDt = totalDt + dt
end
local baseline = totalDt / BASELINE_FRAMES

-- Wait minimum frames (give lighting time to start)
for _ = 1, MIN_WAIT_FRAMES do
    RunService.RenderStepped:Wait()
end

-- Wait for consecutive stable frames
local threshold = baseline * (1 + MARGIN_PERCENT)
local settleStart = os.clock()
local stableCount = 0

while os.clock() - settleStart < MAX_SETTLE_TIME do
    local dt = RunService.RenderStepped:Wait()

    if dt <= threshold then
        stableCount = stableCount + 1
        if stableCount >= REQUIRED_STABLE_FRAMES then
            break
        end
    else
        stableCount = 0
    end
end

--------------------------------------------------------------------------------
-- FADE OUT + SIGNAL SERVER
--------------------------------------------------------------------------------

local tweenInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

TweenService:Create(overlay, tweenInfo, { BackgroundTransparency = 1 }):Play()
TweenService:Create(label, tweenInfo, { TextTransparency = 1 }):Play()

task.wait(FADE_DURATION)

-- Tell server we're done (unanchors HRP)
loadingDoneEvent:FireServer()

-- Clean up
screenGui:Destroy()
