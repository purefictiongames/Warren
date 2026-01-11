--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- GlobalTimer.LocalScript (Client)
-- Timer display - supports two modes:
--   "duration": HUD panel for game timer (sidebar)
--   "sequence": Centered countdown with text sequence (ready/set/go)

-- Guard: Only run if this is the deployed version (has dot in name)
if not script.Name:match("%.") then
	return
end

-- Extract asset name from script name (e.g., "GlobalTimer.LocalScript" → "GlobalTimer")
local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[GlobalTimer.client] Could not extract asset name from script.Name:", script.Name)
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Dependencies
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local timerUpdate = ReplicatedStorage:WaitForChild(assetName .. ".TimerUpdate")

-- Get model reference for attributes
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild(assetName)

-- Read timer mode
local timerMode = model:GetAttribute("TimerMode") or "duration"
System.Debug:Message(assetName .. ".client", "Timer mode:", timerMode)

--------------------------------------------------------------------------------
-- CREATE TIMER UI (mode-specific)
--------------------------------------------------------------------------------

local screenGui, content, timerLabel, sequenceLabel

if timerMode == "sequence" then
	--------------------------------------------------------------------------------
	-- SEQUENCE MODE: Centered fullscreen overlay with stacked text/number
	--------------------------------------------------------------------------------

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = assetName .. ".ScreenGui"
	screenGui.DisplayOrder = 500 -- Above game, below transitions
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 1, 0)
	content.BackgroundTransparency = 1
	content.Visible = false
	content.Parent = screenGui

	-- Centered container for countdown
	local container = GUI:Create({
		type = "Frame",
		id = assetName .. "-container",
		class = "transparent",
		size = {0.5, 0, 0.4, 0},
		position = {0.5, 0, 0.5, 0},
		anchorPoint = {0.5, 0.5},
		children = {
			{
				type = "TextLabel",
				id = assetName .. "-sequence-text",
				class = "countdown-text",
				text = "",
				size = {1, 0, 0.4, 0},
				position = {0.5, 0, 0.1, 0},
				anchorPoint = {0.5, 0},
			},
			{
				type = "TextLabel",
				id = assetName .. "-countdown-number",
				class = "countdown-number",
				text = "",
				size = {1, 0, 0.5, 0},
				position = {0.5, 0, 0.5, 0},
				anchorPoint = {0.5, 0},
			},
		},
	})
	container.Parent = content

	sequenceLabel = GUI:GetById(assetName .. "-sequence-text")
	timerLabel = GUI:GetById(assetName .. "-countdown-number")

	screenGui.Parent = playerGui

	System.Debug:Message(assetName .. ".client", "Created sequence mode UI (centered)")

else
	--------------------------------------------------------------------------------
	-- DURATION MODE: HUD panel for sidebar (existing behavior)
	--------------------------------------------------------------------------------

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = assetName .. ".ScreenGui"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false

	content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 1, 0)
	content.BackgroundTransparency = 1
	content.Visible = false
	content.Parent = screenGui

	-- Container with shared HUD panel styling
	local container = GUI:Create({
		type = "Frame",
		id = assetName .. "-container",
		class = "hud-panel",
		children = {
			{
				type = "TextLabel",
				id = assetName .. "-header",
				class = "hud-header",
				text = "TIME:",
				size = {1, 0, 0.35, 0},
				position = {0, 0, 0.05, 0},
			},
			{
				type = "TextLabel",
				id = assetName .. "-timer",
				class = "hud-value",
				text = "00:00",
				size = {1, 0, 0.55, 0},
				position = {0, 0, 0.4, 0},
			},
		},
	})
	container.Parent = content

	timerLabel = GUI:GetById(assetName .. "-timer")

	screenGui.Parent = playerGui

	System.Debug:Message(assetName .. ".client", "Created duration mode UI (HUD panel)")
end

--------------------------------------------------------------------------------
-- VISIBILITY CONTROL
--------------------------------------------------------------------------------

-- Update visibility based on HUDVisible attribute
local function updateVisibility()
	local rawValue = model:GetAttribute("HUDVisible")
	local visible = rawValue
	if visible == nil then visible = false end
	content.Visible = visible
	System.Debug:Message(assetName .. ".client", "updateVisibility:", tostring(visible))
end

-- Listen for attribute changes
model:GetAttributeChangedSignal("HUDVisible"):Connect(function()
	updateVisibility()
end)

-- Set initial visibility
updateVisibility()

--------------------------------------------------------------------------------
-- TIMER LOGIC (mode-specific)
--------------------------------------------------------------------------------

local function updateTimer(data)
	if timerMode == "sequence" then
		-- Sequence mode: update both text and number
		if sequenceLabel then
			sequenceLabel.Text = data.sequenceText or ""
		end
		if timerLabel then
			timerLabel.Text = data.formatted or ""
		end
		-- Auto-hide when stopped and countdown complete
		if not data.isRunning and data.timeRemaining <= 0 then
			content.Visible = false
		end
	else
		-- Duration mode: existing behavior
		if timerLabel then
			if data.isRunning then
				timerLabel.Text = data.formatted
			else
				if data.timeRemaining <= 0 then
					timerLabel.Text = "TIME!"
				else
					timerLabel.Text = data.formatted
				end
			end
		end
	end
end

timerUpdate.OnClientEvent:Connect(updateTimer)

System.Debug:Message(assetName .. ".client", "Script loaded")
