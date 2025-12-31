--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Dispenser.LocalScript (Client)
-- Updates BillboardGui to show remaining count

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Dispenser%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Dependencies (guaranteed to exist after READY stage)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local runtimeAssets = workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("Dispenser")
local anchor = model:WaitForChild("Anchor")

local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Create BillboardGui using declarative system
local billboardGui = GUI:Create({
	type = "BillboardGui",
	name = "DispenserDisplay",
	size = {0, 96, 0, 32},
	studsOffset = Vector3.new(0, 4.2, 0),
	alwaysOnTop = true,
	children = {
		{
			type = "Frame",
			class = "dispenser-frame",
			size = {1, 0, 1, 0},
			cornerRadius = 10,
			listLayout = {
				direction = "Horizontal",
				hAlign = "Center",
				vAlign = "Center",
				padding = 5,
				sortOrder = "LayoutOrder",
			},
			children = {
				{
					type = "ImageLabel",
					name = "Icon",
					size = {0, 32, 0, 32},
					backgroundTransparency = 1,
					image = "rbxassetid://97382091340704",
					layoutOrder = 0,
				},
				{
					type = "TextLabel",
					class = "dispenser-text",
					size = {0, 20, 1, 0},
					text = "x",
					layoutOrder = 1,
				},
				{
					type = "TextLabel",
					id = "dispenser-count",
					class = "dispenser-text",
					size = {0, 40, 1, 0},
					text = "0",
					layoutOrder = 2,
				},
			}
		}
	}
})

-- Set adornee (can't be done in declarative table - needs reference)
billboardGui.Adornee = anchor
billboardGui.Parent = playerGui

-- Get reference to count label
local countLabel = GUI:GetById("dispenser-count")

local function updateDisplay()
	local remaining = model:GetAttribute("Remaining") or 0
	countLabel.Text = tostring(remaining)
end

-- Initial update
updateDisplay()

-- Listen for changes
model:GetAttributeChangedSignal("Remaining"):Connect(updateDisplay)

System.Debug:Message("Dispenser.client", "Display ready")
