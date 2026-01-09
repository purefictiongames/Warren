--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Transition.LocalScript (Client)
-- Handles client-side screen transitions (fade to black, etc.)
-- Listens for server commands and fires back when transition milestones are reached

-- Guard: Only run if this is the deployed version
if not script.Name:match("^GUI%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Dependencies
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Load styles for transition configuration
local Styles = nil
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

-- Get style properties for a transition class
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

-- Wait for transition event (deployed by bootstrap with GUI. prefix)
local remoteEvent = ReplicatedStorage:WaitForChild("GUI.TransitionEvent", 10)
if not remoteEvent then
	warn("[Transition.client] GUI.TransitionEvent RemoteEvent not found")
	return
end

--------------------------------------------------------------------------------
-- TRANSITION UI
--------------------------------------------------------------------------------

-- Create persistent ScreenGui for transitions
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TransitionOverlay"
screenGui.DisplayOrder = 1000 -- Above everything
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = true
screenGui.Parent = playerGui

-- Create the transition frame (covers entire screen)
local frame = Instance.new("Frame")
frame.Name = "Cover"
frame.Size = UDim2.new(1, 0, 1, 0)
frame.Position = UDim2.new(0, 0, 0, 0)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BackgroundTransparency = 1 -- Start fully transparent
frame.BorderSizePixel = 0
frame.Parent = screenGui

-- Create camera transition event (for Camera system to listen to)
-- Camera switches happen while screen is covered for seamless transition
local cameraTransitionCovered = Instance.new("BindableEvent")
cameraTransitionCovered.Name = "Camera.TransitionCovered"
cameraTransitionCovered.Parent = ReplicatedStorage

-- Current transition state
local currentTween = nil
local pendingConfig = nil

--------------------------------------------------------------------------------
-- TRANSITION HANDLERS
--------------------------------------------------------------------------------

-- Handle "start" action - fade out (cover the screen)
local function handleStart(data)
	-- Cancel any existing transition
	if currentTween then
		currentTween:Cancel()
		currentTween = nil
	end

	-- Get style configuration
	local styleConfig = getStyleConfig(data.class or "transition-fade")
	local duration = data.duration or styleConfig.duration
	local color = styleConfig.backgroundColor

	-- Store config for reveal phase
	pendingConfig = {
		duration = duration,
	}

	-- Set frame color
	frame.BackgroundColor3 = Color3.fromRGB(color[1], color[2], color[3])

	-- Tween transparency from 1 to 0 (fade in the cover)
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	currentTween = TweenService:Create(frame, tweenInfo, {
		BackgroundTransparency = 0
	})

	currentTween:Play()

	-- Wait for completion and notify server
	currentTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			currentTween = nil
			-- Fire camera transition event (camera switches while screen is black)
			cameraTransitionCovered:Fire()
			-- Notify server that screen is covered
			remoteEvent:FireServer({ action = "covered" })
			System.Debug:Message("GUI.Transition.client", "Screen covered, notified server")
		end
	end)

	System.Debug:Message("GUI.Transition.client", "Starting fade out, duration:", duration)
end

-- Handle "reveal" action - fade in (uncover the screen)
local function handleReveal(data)
	-- Cancel any existing transition
	if currentTween then
		currentTween:Cancel()
		currentTween = nil
	end

	-- Use reveal duration from data, pending config, or default
	local duration = data.duration
	if not duration and pendingConfig then
		duration = pendingConfig.duration
	end
	duration = duration or 0.5

	-- Tween transparency from 0 to 1 (fade out the cover)
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)

	currentTween = TweenService:Create(frame, tweenInfo, {
		BackgroundTransparency = 1
	})

	currentTween:Play()

	-- Wait for completion and notify server
	currentTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			currentTween = nil
			pendingConfig = nil
			-- Notify server that transition is complete
			remoteEvent:FireServer({ action = "complete" })
			System.Debug:Message("GUI.Transition.client", "Transition complete, notified server")
		end
	end)

	System.Debug:Message("GUI.Transition.client", "Starting fade in, duration:", duration)
end

--------------------------------------------------------------------------------
-- EVENT LISTENER
--------------------------------------------------------------------------------

remoteEvent.OnClientEvent:Connect(function(data)
	if not data or type(data) ~= "table" then return end

	if data.action == "start" then
		handleStart(data)
	elseif data.action == "reveal" then
		handleReveal(data)
	end
end)

System.Debug:Message("GUI.Transition.client", "Transition system ready")
