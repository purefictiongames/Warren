--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- GlobalTimer.LocalScript (Client)
-- Timer display - creates its own standalone GUI

-- Guard: Only run if this is the deployed version
if not script.Name:match("^GlobalTimer%.") then
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
local timerUpdate = ReplicatedStorage:WaitForChild("GlobalTimer.TimerUpdate")

--------------------------------------------------------------------------------
-- CREATE TIMER UI
--------------------------------------------------------------------------------

-- Create ScreenGui manually (layout system will find and reposition if active)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GlobalTimer.ScreenGui"
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
	id = "timer-container",
	class = "hud-panel",
	children = {
		{
			type = "TextLabel",
			id = "timer-header",
			class = "hud-header",
			text = "TIME:",
			size = {1, 0, 0.35, 0},
			position = {0, 0, 0.05, 0},
		},
		{
			type = "TextLabel",
			id = "global-timer",
			class = "hud-value",
			text = "00:00",
			size = {1, 0, 0.55, 0},
			position = {0, 0, 0.4, 0},
		},
	},
})
container.Parent = content

-- Get reference to timer label for updates
local timerLabel = GUI:GetById("global-timer")

screenGui.Parent = playerGui

--------------------------------------------------------------------------------
-- VISIBILITY CONTROL
--------------------------------------------------------------------------------

-- Get model reference for HUDVisible attribute
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("GlobalTimer")

-- Update visibility based on HUDVisible attribute
-- NOTE: We control the Content frame's Visible property, not ScreenGui.Enabled,
-- because the layout system may reparent Content into HUD.ScreenGui.
-- The Content frame follows our UI whether standalone or in a layout region.
local function updateVisibility()
	local rawValue = model:GetAttribute("HUDVisible")
	local visible = rawValue
	if visible == nil then visible = false end -- Default to hidden until RunModes activates
	content.Visible = visible
	System.Debug:Message("GlobalTimer.client", "updateVisibility: raw=", tostring(rawValue), "-> visible=", tostring(visible), "content.Visible=", tostring(content.Visible))
end

-- Listen for attribute changes
model:GetAttributeChangedSignal("HUDVisible"):Connect(function()
	System.Debug:Message("GlobalTimer.client", "HUDVisible attribute changed!")
	updateVisibility()
end)

-- Set initial visibility
System.Debug:Message("GlobalTimer.client", "Setting initial visibility, content.Parent=", content.Parent and content.Parent.Name or "nil")
updateVisibility()

--------------------------------------------------------------------------------
-- TIMER LOGIC
--------------------------------------------------------------------------------

local function updateTimer(data)
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

timerUpdate.OnClientEvent:Connect(updateTimer)

System.Debug:Message("GlobalTimer.client", "Script loaded")
