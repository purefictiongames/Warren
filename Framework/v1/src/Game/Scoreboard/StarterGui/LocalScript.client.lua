--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Scoreboard.LocalScript (Client)
-- Score display - creates its own standalone GUI

-- Guard: Only run if this is the deployed version (has dot in name)
if not script.Name:match("%.") then
	return
end

-- Extract asset name from script name (e.g., "Scoreboard.LocalScript" → "Scoreboard")
local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[Scoreboard.client] Could not extract asset name from script.Name:", script.Name)
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
local scoreUpdate = ReplicatedStorage:WaitForChild(assetName .. ".ScoreUpdate")

--------------------------------------------------------------------------------
-- CREATE SCORE UI
--------------------------------------------------------------------------------

-- Create ScreenGui manually (layout system will find and reposition if active)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = assetName .. ".ScreenGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false -- Hidden by default until RunModes activates

-- Content frame that layout can move
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.Visible = false -- Hidden by default until RunModes activates
content.Parent = screenGui

-- Container with shared HUD panel styling
local container = GUI:Create({
	type = "Frame",
	id = "score-container",
	class = "hud-panel",
	children = {
		{
			type = "TextLabel",
			id = "score-header",
			class = "hud-header",
			text = "SCORE:",
			size = {1, 0, 0.35, 0},
			position = {0, 0, 0.05, 0},
		},
		{
			type = "TextLabel",
			id = "score-value",
			class = "hud-value",
			text = "0",
			size = {1, 0, 0.55, 0},
			position = {0, 0, 0.4, 0},
		},
	},
})
container.Parent = content

-- Get reference to score value for updates
local scoreValue = GUI:GetById("score-value")

screenGui.Parent = playerGui

--------------------------------------------------------------------------------
-- VISIBILITY CONTROL
--------------------------------------------------------------------------------

-- Get model reference for HUDVisible attribute
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild(assetName)

-- Update visibility based on HUDVisible attribute
-- NOTE: We control the Content frame's Visible property, not ScreenGui.Enabled,
-- because the layout system may reparent Content into HUD.ScreenGui.
-- The Content frame follows our UI whether standalone or in a layout region.
local function updateVisibility()
	local visible = model:GetAttribute("HUDVisible")
	if visible == nil then visible = false end -- Default to hidden until RunModes activates
	content.Visible = visible
end

-- Listen for attribute changes
model:GetAttributeChangedSignal("HUDVisible"):Connect(updateVisibility)

-- Set initial visibility
updateVisibility()

--------------------------------------------------------------------------------
-- SCORE LOGIC
--------------------------------------------------------------------------------

local function roundToNearest5(value)
	return math.floor((value + 2.5) / 5) * 5
end

local function updateScore(data)
	if scoreValue then
		local displayScore = roundToNearest5(math.floor(data.totalScore))
		scoreValue.Text = tostring(displayScore)
	end

	System.Debug:Message(assetName .. ".client", "Score updated - Total:", data.totalScore)
end

scoreUpdate.OnClientEvent:Connect(updateScore)

System.Debug:Message(assetName .. ".client", "Script loaded")
