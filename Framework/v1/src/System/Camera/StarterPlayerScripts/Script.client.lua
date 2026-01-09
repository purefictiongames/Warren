--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Camera.Script (Client)
-- Controls camera mode switching based on RunModes changes
-- Switches between isometric (fixed overhead) and free (third-person) camera
-- Camera switch happens during transition while screen is black

-- Guard: Only run if this is the deployed version (has dot in name)
if not script.Name:match("^Camera%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Load configuration
local CameraConfig = require(ReplicatedFirst:WaitForChild("Camera"):WaitForChild("CameraConfig"))

-- Dependencies
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local runtimeAssets = workspace:WaitForChild("RuntimeAssets")

-- Listen for mode changes from RunModes
local playerModeChanged = ReplicatedStorage:WaitForChild("RunModes.PlayerModeChanged")

-- State tracking
local currentCameraStyle = "free"
local pendingCameraStyle = nil
local savedCameraState = nil
local calculatedIsometricCFrame = nil

--------------------------------------------------------------------------------
-- CAMERA POSITION CALCULATION
--------------------------------------------------------------------------------

-- Get the bounding box center and size of a model
local function getModelBounds(model)
	if not model then return nil, nil end

	local cf, size = model:GetBoundingBox()
	return cf.Position, size
end

-- Calculate optimal isometric camera position to frame the play area
local function calculateIsometricCamera()
	local config = CameraConfig.isometric

	-- Find the key assets to frame
	local marshmallowBag = runtimeAssets:FindFirstChild("MarshmallowBag")
	local campfire = runtimeAssets:FindFirstChild("Campfire")

	if not marshmallowBag or not campfire then
		System.Debug:Warn("Camera.client", "Could not find MarshmallowBag or Campfire for framing")
		-- Fall back to config values
		return CFrame.new(config.position, config.lookAt)
	end

	-- Get positions of both assets
	local bagPos = getModelBounds(marshmallowBag)
	local firePos = getModelBounds(campfire)

	if not bagPos or not firePos then
		System.Debug:Warn("Camera.client", "Could not get bounds for assets")
		return CFrame.new(config.position, config.lookAt)
	end

	-- Calculate center point between fire and marshmallow bag
	local centerX = (bagPos.X + firePos.X) / 2
	local centerZ = (bagPos.Z + firePos.Z) / 2
	local lookAt = Vector3.new(centerX, 0, centerZ)

	-- Calculate the distance between assets (horizontal)
	local distanceX = math.abs(bagPos.X - firePos.X)
	local distanceZ = math.abs(bagPos.Z - firePos.Z)
	local maxDistance = math.max(distanceX, distanceZ)

	-- Add buffer on each side (20 studs per side = 40 total)
	local buffer = config.buffer or 20
	local totalWidth = maxDistance + (buffer * 2)

	-- Calculate height needed for 60° angle to see the entire area
	-- At 60° down from horizontal, height = distance * tan(60°) ≈ distance * 1.73
	-- But we also need to account for FOV
	local fov = config.fieldOfView or 70
	local fovRadians = math.rad(fov / 2)

	-- Height calculation: to see totalWidth at FOV, we need height
	-- Using similar triangles: height = (totalWidth / 2) / tan(fov/2) for horizontal
	-- For 60° angle, camera is offset back as well as up
	local viewDistance = (totalWidth / 2) / math.tan(fovRadians)

	-- 60° angle means: height = viewDistance * sin(60°), offset = viewDistance * cos(60°)
	local angle = math.rad(config.angle or 60)
	local height = viewDistance * math.sin(angle)
	local offset = viewDistance * math.cos(angle)

	-- Position camera behind (positive Z) and above the center
	local cameraPos = Vector3.new(centerX, height, centerZ + offset)

	System.Debug:Message("Camera.client", string.format(
		"Calculated camera - center: (%.1f, %.1f), distance: %.1f, height: %.1f, offset: %.1f",
		centerX, centerZ, maxDistance, height, offset
	))

	return CFrame.new(cameraPos, lookAt)
end

--------------------------------------------------------------------------------
-- CAMERA FUNCTIONS
--------------------------------------------------------------------------------

-- Save current free camera state before switching to isometric
local function saveFreeCamera()
	savedCameraState = {
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		fieldOfView = camera.FieldOfView,
	}
	System.Debug:Message("Camera.client", "Saved free camera state")
end

-- Apply isometric camera (fixed overhead view)
local function applyIsometric()
	local config = CameraConfig.isometric

	-- Set to scriptable so we have full control
	camera.CameraType = Enum.CameraType.Scriptable

	-- Calculate optimal camera position if not already done
	if not calculatedIsometricCFrame then
		calculatedIsometricCFrame = calculateIsometricCamera()
	end

	camera.CFrame = calculatedIsometricCFrame

	-- Set field of view
	if config.fieldOfView then
		camera.FieldOfView = config.fieldOfView
	end

	currentCameraStyle = "isometric"
	System.Debug:Message("Camera.client", "Applied isometric camera")
end

-- Restore free camera (default Roblox third-person)
local function restoreFreeCamera()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- Restore to custom (third-person following) mode
	camera.CameraType = Enum.CameraType.Custom

	-- Set camera subject back to humanoid
	if humanoid then
		camera.CameraSubject = humanoid
	elseif character then
		camera.CameraSubject = character
	end

	-- Restore field of view
	if savedCameraState and savedCameraState.fieldOfView then
		camera.FieldOfView = savedCameraState.fieldOfView
	else
		camera.FieldOfView = CameraConfig.free.fieldOfView or 70
	end

	savedCameraState = nil
	currentCameraStyle = "free"
	System.Debug:Message("Camera.client", "Restored free camera")
end

-- Apply pending camera style (called when transition screen is covered)
local function applyPendingCamera()
	if not pendingCameraStyle then
		return
	end

	System.Debug:Message("Camera.client", "Applying pending camera style:", pendingCameraStyle)

	if pendingCameraStyle == "isometric" then
		saveFreeCamera()
		applyIsometric()
	elseif pendingCameraStyle == "free" then
		restoreFreeCamera()
	end

	pendingCameraStyle = nil
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

-- When RunModes changes, store the pending camera style
-- (actual switch happens when transition screen is covered)
playerModeChanged.OnClientEvent:Connect(function(data)
	local newMode = data.newMode
	local newCameraStyle = CameraConfig.modes[newMode]

	if newCameraStyle and newCameraStyle ~= currentCameraStyle then
		pendingCameraStyle = newCameraStyle
		System.Debug:Message("Camera.client", "Pending camera switch to", newCameraStyle, "for mode", newMode)
	end
end)

-- Listen for transition covered event (fired by Transition.client when screen is black)
-- This is when we actually switch the camera
-- Use WaitForChild since Transition.client creates this event
local transitionCoveredEvent = ReplicatedStorage:WaitForChild("Camera.TransitionCovered", 10)
if transitionCoveredEvent then
	transitionCoveredEvent.Event:Connect(function()
		System.Debug:Message("Camera.client", "Transition covered - switching camera")
		applyPendingCamera()
	end)
	System.Debug:Message("Camera.client", "Listening for Camera.TransitionCovered")
else
	System.Debug:Warn("Camera.client", "Camera.TransitionCovered event not found after 10s timeout")
end

System.Debug:Message("Camera.client", "Script loaded")
