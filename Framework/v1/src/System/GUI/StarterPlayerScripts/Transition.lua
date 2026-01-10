--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Transition.module (Client)
-- Handles client-side screen transitions (fade to black, etc.)
-- Discovered and loaded by System.client.lua

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Wait for System module
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE STATE
--------------------------------------------------------------------------------

local player
local playerGui
local screenGui
local frame
local cameraTransitionCovered
local remoteEvent
local currentTween = nil
local pendingConfig = nil
local Styles = nil

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function getStyles()
	if Styles then return Styles end
	local guiFolder = ReplicatedFirst:FindFirstChild("GUI")
	if guiFolder then
		local stylesModule = guiFolder:FindFirstChild("Styles")
		if stylesModule then
			Styles = require(stylesModule)
		end
	end
	return Styles or { classes = {} }
end

local function getStyleConfig(className)
	local styles = getStyles()
	local config = {
		backgroundColor = {0, 0, 0},
		duration = 0.5,
	}

	if styles.classes and styles.classes[className] then
		local classStyle = styles.classes[className]
		if classStyle.backgroundColor then
			config.backgroundColor = classStyle.backgroundColor
		end
		if classStyle.duration then
			config.duration = classStyle.duration
		end
	end

	return config
end

local function handleStart(data)
	if currentTween then
		currentTween:Cancel()
		currentTween = nil
	end

	local styleConfig = getStyleConfig(data.class or "transition-fade")
	local duration = data.duration or styleConfig.duration
	local color = styleConfig.backgroundColor

	pendingConfig = { duration = duration }
	frame.BackgroundColor3 = Color3.fromRGB(color[1], color[2], color[3])

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	currentTween = TweenService:Create(frame, tweenInfo, { BackgroundTransparency = 0 })
	currentTween:Play()

	currentTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			currentTween = nil
			cameraTransitionCovered:Fire()
			remoteEvent:FireServer({ action = "covered" })
			System.Debug:Message("GUI.Transition.client", "Screen covered, notified server")
		end
	end)

	System.Debug:Message("GUI.Transition.client", "Starting fade out, duration:", duration)
end

local function handleReveal(data)
	if currentTween then
		currentTween:Cancel()
		currentTween = nil
	end

	local duration = data.duration
	if not duration and pendingConfig then
		duration = pendingConfig.duration
	end
	duration = duration or 0.5

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	currentTween = TweenService:Create(frame, tweenInfo, { BackgroundTransparency = 1 })
	currentTween:Play()

	currentTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			currentTween = nil
			pendingConfig = nil
			remoteEvent:FireServer({ action = "complete" })
			System.Debug:Message("GUI.Transition.client", "Transition complete, notified server")
		end
	end)

	System.Debug:Message("GUI.Transition.client", "Starting fade in, duration:", duration)
end

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

return {
	dependencies = { "GUI.Script" },  -- Depends on GUI.Script for styles

	init = function(self)
		player = Players.LocalPlayer
		playerGui = player:WaitForChild("PlayerGui")

		-- Get remote event reference
		remoteEvent = ReplicatedStorage:WaitForChild("GUI.TransitionEvent", 10)
		if not remoteEvent then
			System.Debug:Warn("GUI.Transition.client", "GUI.TransitionEvent RemoteEvent not found")
			return
		end

		-- Create ScreenGui
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "TransitionOverlay"
		screenGui.DisplayOrder = 1000
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.Enabled = true
		screenGui.Parent = playerGui

		-- Create transition frame
		frame = Instance.new("Frame")
		frame.Name = "Cover"
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.Position = UDim2.new(0, 0, 0, 0)
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = screenGui

		-- Create camera transition event
		cameraTransitionCovered = Instance.new("BindableEvent")
		cameraTransitionCovered.Name = "Camera.TransitionCovered"
		cameraTransitionCovered.Parent = ReplicatedStorage
	end,

	start = function(self)
		if not remoteEvent then
			return
		end

		remoteEvent.OnClientEvent:Connect(function(data)
			if not data or type(data) ~= "table" then return end

			if data.action == "start" then
				handleStart(data)
			elseif data.action == "reveal" then
				handleReveal(data)
			end
		end)

		System.Debug:Message("GUI.Transition.client", "Started")
	end,
}
