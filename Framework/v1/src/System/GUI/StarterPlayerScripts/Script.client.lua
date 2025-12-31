--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- GUI.LocalScript (Client)
-- Initializes the GUI system, handles viewport changes, and manages HUD layouts

-- Guard: Only run if this is the deployed version
if not script.Name:match("^GUI%.") then
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

-- Initialize the GUI system
GUI:Initialize()

System.Debug:Message("System.GUI.client", "GUI system initialized")

--------------------------------------------------------------------------------
-- VIEWPORT MONITORING
--------------------------------------------------------------------------------

local Camera = workspace.CurrentCamera

local function getViewportInfo()
	local size = Camera.ViewportSize
	return string.format("%.0fx%.0f", size.X, size.Y)
end

-- Initialize breakpoint based on current viewport
local initialSize = Camera.ViewportSize
GUI:_updateBreakpoint(initialSize.X, initialSize.Y)
System.Debug:Message("System.GUI.client", "Viewport:", getViewportInfo(), "Breakpoint:", GUI:GetBreakpoint())

-- Monitor viewport changes and update breakpoint
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	local size = Camera.ViewportSize
	local changed = GUI:_updateBreakpoint(size.X, size.Y)
	if changed then
		System.Debug:Message("System.GUI.client", "Breakpoint changed to:", GUI:GetBreakpoint(), "(" .. getViewportInfo() .. ")")
	end
end)

--------------------------------------------------------------------------------
-- HUD LAYOUT SYSTEM
--------------------------------------------------------------------------------

-- Get layouts and check for active HUD layout
local layouts = GUI:GetLayouts()
local hudLayoutName = "right-sidebar"  -- Could be configurable
local layoutDef = layouts[hudLayoutName]

if layoutDef and layoutDef.assets then
	System.Debug:Message("System.GUI.client", "Creating HUD layout:", hudLayoutName)

	local screenGui, regions = GUI:CreateLayout(hudLayoutName)
	if screenGui then
		screenGui.Name = "HUD.ScreenGui"
		screenGui.Parent = playerGui

		local assetMapping = layoutDef.assets

		-- Log regions
		local regionNames = {}
		for id in pairs(regions) do
			table.insert(regionNames, id)
		end
		System.Debug:Message("System.GUI.client", "HUD regions:", table.concat(regionNames, ", "))

		-- Move an asset's content into a layout region
		local function positionAsset(assetScreenGui, regionId)
			local region = regions[regionId]
			if not region then
				System.Debug:Warn("System.GUI.client", "Region not found:", regionId)
				return false
			end

			local content = assetScreenGui:FindFirstChild("Content")
			if not content then
				System.Debug:Warn("System.GUI.client", "No Content frame in:", assetScreenGui.Name)
				return false
			end

			-- Move content to the layout region
			content.AnchorPoint = Vector2.new(0, 0)
			content.Position = UDim2.new(0, 0, 0, 0)
			content.Size = UDim2.new(1, 0, 1, 0)
			content.Parent = region

			-- Hide the original ScreenGui
			assetScreenGui.Enabled = false

			System.Debug:Message("System.GUI.client", "Positioned", assetScreenGui.Name, "->", regionId)
			return true
		end

		-- Track positioned assets
		local positionedAssets = {}

		local function tryPositionAsset(child)
			if not child:IsA("ScreenGui") then return end
			if positionedAssets[child.Name] then return end

			local regionId = assetMapping[child.Name]
			if regionId then
				if positionAsset(child, regionId) then
					positionedAssets[child.Name] = true
				end
			end
		end

		-- Set up listener for new assets
		playerGui.ChildAdded:Connect(function(child)
			task.defer(function()
				tryPositionAsset(child)
			end)
		end)

		-- Check existing children after a frame (let other READY scripts run first)
		task.defer(function()
			for _, child in ipairs(playerGui:GetChildren()) do
				tryPositionAsset(child)
			end
		end)
	end
end

System.Debug:Message("System.GUI.client", "Script loaded")
