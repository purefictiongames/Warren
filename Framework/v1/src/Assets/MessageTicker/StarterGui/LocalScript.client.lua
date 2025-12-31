--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

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
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

local FADE_DELAY = 3 -- seconds before fade starts
local FADE_DURATION = 1 -- seconds for fade animation

-- Create GUI using declarative system
local screenGui = GUI:Create({
	type = "ScreenGui",
	name = "MessageTicker.ScreenGui",
	resetOnSpawn = false,
	zIndex = 10,
	children = {
		{
			type = "TextLabel",
			id = "ticker-message",
			class = "ticker-text",
			text = "",
			size = {1, 0, 0, 50},
			position = {0, 0, 1, -120},
			anchorPoint = {0, 1},
			textTransparency = 1, -- Start invisible
		}
	}
})
screenGui.Parent = playerGui

-- Get reference to message label
local messageLabel = GUI:GetById("ticker-message")

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

System.Debug:Message("MessageTicker.client", "HUD ready")

System.Debug:Message("MessageTicker.client", "Script loaded")
