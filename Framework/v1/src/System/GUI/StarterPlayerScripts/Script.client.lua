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

-- Log initial viewport
System.Debug:Message("System.GUI.client", "Viewport:", getViewportInfo())

-- Monitor viewport changes (Phase 5 will add breakpoint switching)
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	System.Debug:Message("System.GUI.client", "Viewport changed:", getViewportInfo())
	-- Phase 5: Check breakpoint and trigger layout swap if needed
end)

System.Debug:Message("System.GUI.client", "Script loaded")
