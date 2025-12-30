-- GUI.LocalScript (Client)
-- Initializes the GUI system and handles viewport changes

-- Guard: Only run if this is the deployed version
if not script.Name:match("^GUI%.") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Load GUI module
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Initialize the GUI system
GUI:Initialize()

System.Debug:Message("System.GUI.client", "GUI system initialized")

--------------------------------------------------------------------------------
-- VIEWPORT MONITORING (Phase 5 preparation)
--------------------------------------------------------------------------------

-- This section will be expanded in Phase 5 for responsive breakpoints
-- For now, just log viewport size for debugging

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

System.Debug:Message("System.GUI.client", "Script loaded")

--------------------------------------------------------------------------------
-- PHASE 5-8 TEST: Responsive + Z-Index + Pseudo-classes + Actions (remove after verification)
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Function to create test GUI (called on each breakpoint change)
local currentTestGui = nil

local function createResponsiveTest()
	-- Remove old test GUI
	if currentTestGui then
		currentTestGui:Destroy()
	end

	-- Create new GUI with current breakpoint styles
	currentTestGui = GUI:Create({
		type = "ScreenGui",
		name = "GUI_Phase8_Test",
		resetOnSpawn = false,
		zIndex = 50,  -- Phase 6: maps to DisplayOrder for ScreenGui
		children = {
			{
				type = "Frame",
				size = {0.4, 0, 0, 260},
				position = {0.5, 0, 0.05, 0},
				anchorPoint = {0.5, 0},
				backgroundColor = {40, 40, 50},
				backgroundTransparency = 0.1,
				cornerRadius = 12,
				padding = { all = 15 },
				children = {
					{
						type = "Frame",
						size = {1, 0, 1, 0},
						backgroundTransparency = 1,
						listLayout = { direction = "Vertical", padding = 8 },
						children = {
							{
								type = "TextLabel",
								text = "Phase 5: Responsive (" .. GUI:GetBreakpoint() .. ")",
								class = "responsive-text",
								size = {1, 0, 0, 30},
								backgroundTransparency = 1,
								layoutOrder = 1,
							},
							{
								type = "TextLabel",
								text = "Resize window to change breakpoint",
								textColor = {180, 180, 180},
								textSize = 14,
								size = {1, 0, 0, 20},
								backgroundTransparency = 1,
								layoutOrder = 2,
							},
							{
								type = "TextLabel",
								text = "Desktop=blue, Tablet=orange, Phone=red",
								textColor = {140, 140, 140},
								textSize = 12,
								size = {1, 0, 0, 20},
								backgroundTransparency = 1,
								layoutOrder = 3,
							},
							{
								type = "TextButton",
								text = "Hover/Click Me (Phase 7)",
								class = "btn",
								size = {1, 0, 0, 30},
								cornerRadius = 6,
								layoutOrder = 4,
							},
							{
								type = "TextButton",
								text = "Toggle Panel (Phase 8)",
								class = "btn",
								size = {1, 0, 0, 30},
								cornerRadius = 6,
								layoutOrder = 5,
								actions = {
									onClick = {
										{ action = "toggle", target = "#toggle-panel" }
									}
								}
							},
							{
								type = "Frame",
								id = "toggle-panel",
								size = {1, 0, 0, 40},
								backgroundColor = {60, 100, 60},
								cornerRadius = 6,
								layoutOrder = 6,
								children = {
									{
										type = "TextLabel",
										text = "I can be toggled!",
										textColor = {255, 255, 255},
										textSize = 14,
										size = {1, 0, 1, 0},
										backgroundTransparency = 1,
									}
								}
							},
						}
					}
				}
			}
		}
	})
	currentTestGui.Parent = playerGui
end

-- Create initial test
createResponsiveTest()

-- Recreate on breakpoint change
GUI:OnBreakpointChanged(function(newBreakpoint, oldBreakpoint)
	System.Debug:Message("System.GUI.client", "Recreating test for breakpoint:", newBreakpoint)
	createResponsiveTest()
end)

System.Debug:Message("System.GUI.client", "Phase 8 test created (all features)")
