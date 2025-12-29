-- MessageTicker.LocalScript (Client)
-- Displays messages from server with fade-out effect

-- Guard: Only run if this is the deployed version
if not script.Name:match("^MessageTicker%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Dependencies (guaranteed to exist after READY stage)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local messageTicker = ReplicatedStorage:WaitForChild("MessageTicker.MessageTicker")

local FADE_DELAY = 3 -- seconds before fade starts
local FADE_DURATION = 1 -- seconds for fade animation

-- Create ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MessageTicker.ScreenGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

-- Create message label
local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "MessageLabel"
messageLabel.Size = UDim2.new(1, 0, 0, 50)
messageLabel.Position = UDim2.new(0, 0, 1, -120) -- Above backpack/toolbar
messageLabel.AnchorPoint = Vector2.new(0, 1)
messageLabel.BackgroundTransparency = 1
messageLabel.Font = Enum.Font.Bangers
messageLabel.TextSize = 36
messageLabel.TextColor3 = Color3.fromRGB(255, 170, 0)
messageLabel.Text = ""
messageLabel.TextTransparency = 1 -- Start invisible
messageLabel.Parent = screenGui

-- Track current fade tween
local currentTween = nil

local function showMessage(message)
	-- Cancel any existing fade
	if currentTween then
		currentTween:Cancel()
		currentTween = nil
	end

	-- Show message immediately
	messageLabel.Text = message
	messageLabel.TextTransparency = 0

	-- Wait, then fade out
	task.delay(FADE_DELAY, function()
		-- Only fade if this message is still showing
		if messageLabel.Text == message then
			local tweenInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			currentTween = TweenService:Create(messageLabel, tweenInfo, { TextTransparency = 1 })
			currentTween:Play()
		end
	end)
end

messageTicker.OnClientEvent:Connect(showMessage)

print("MessageTicker.LocalScript: HUD ready")

print("MessageTicker.LocalScript loaded")
