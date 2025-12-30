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

System.Debug:Message("System.GUI.client", "Script loaded")
