--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Camera.module (Client)
-- Controls camera mode switching based on RunModes changes
-- Discovered and loaded by System.client.lua

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for System module
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE STATE
--------------------------------------------------------------------------------

local CameraConfig
local player
local camera
local runtimeAssets
local playerModeChanged
local currentCameraStyle = "free"
local pendingCameraStyle = nil
local savedCameraState = nil
local calculatedIsometricCFrame = nil

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
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

	local marshmallowBag = runtimeAssets:FindFirstChild("MarshmallowBag")
	local campfire = runtimeAssets:FindFirstChild("Campfire")

	if not marshmallowBag or not campfire then
		System.Debug:Warn("Camera.client", "Could not find MarshmallowBag or Campfire for framing")
		return CFrame.new(config.position, config.lookAt)
	end

	local bagPos = getModelBounds(marshmallowBag)
	local firePos = getModelBounds(campfire)

	if not bagPos or not firePos then
		System.Debug:Warn("Camera.client", "Could not get bounds for assets")
		return CFrame.new(config.position, config.lookAt)
	end

	local centerX = (bagPos.X + firePos.X) / 2
	local centerZ = (bagPos.Z + firePos.Z) / 2
	local lookAt = Vector3.new(centerX, 0, centerZ)

	local distanceX = math.abs(bagPos.X - firePos.X)
	local distanceZ = math.abs(bagPos.Z - firePos.Z)
	local maxDistance = math.max(distanceX, distanceZ)

	local buffer = config.buffer or 20
	local totalWidth = maxDistance + (buffer * 2)

	local fov = config.fieldOfView or 70
	local fovRadians = math.rad(fov / 2)

	local viewDistance = (totalWidth / 2) / math.tan(fovRadians)

	local angle = math.rad(config.angle or 60)
	local height = viewDistance * math.sin(angle)
	local offset = viewDistance * math.cos(angle)

	local cameraPos = Vector3.new(centerX, height, centerZ + offset)

	System.Debug:Message("Camera.client", string.format(
		"Calculated camera - center: (%.1f, %.1f), distance: %.1f, height: %.1f, offset: %.1f",
		centerX, centerZ, maxDistance, height, offset
	))

	return CFrame.new(cameraPos, lookAt)
end

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

	camera.CameraType = Enum.CameraType.Scriptable

	if not calculatedIsometricCFrame then
		calculatedIsometricCFrame = calculateIsometricCamera()
	end

	camera.CFrame = calculatedIsometricCFrame

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

	camera.CameraType = Enum.CameraType.Custom

	if humanoid then
		camera.CameraSubject = humanoid
	elseif character then
		camera.CameraSubject = character
	end

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
-- MODULE DEFINITION
--------------------------------------------------------------------------------

return {
	dependencies = { "GUI.Transition" },  -- Depends on Transition for Camera.TransitionCovered event

	init = function(self)
		CameraConfig = require(ReplicatedFirst:WaitForChild("Camera"):WaitForChild("CameraConfig"))
		player = Players.LocalPlayer
		camera = workspace.CurrentCamera
		runtimeAssets = workspace:WaitForChild("RuntimeAssets")
		playerModeChanged = ReplicatedStorage:WaitForChild("RunModes.PlayerModeChanged")
	end,

	start = function(self)
		-- Listen for RunModes changes
		playerModeChanged.OnClientEvent:Connect(function(data)
			local newMode = data.newMode
			local newCameraStyle = CameraConfig.modes[newMode]

			if newCameraStyle and newCameraStyle ~= currentCameraStyle then
				pendingCameraStyle = newCameraStyle
				System.Debug:Message("Camera.client", "Pending camera switch to", newCameraStyle, "for mode", newMode)
			end
		end)

		-- Listen for transition covered event (created by Transition module)
		local transitionCoveredEvent = ReplicatedStorage:FindFirstChild("Camera.TransitionCovered")
		if transitionCoveredEvent then
			transitionCoveredEvent.Event:Connect(function()
				System.Debug:Message("Camera.client", "Transition covered - switching camera")
				applyPendingCamera()
			end)
			System.Debug:Message("Camera.client", "Listening for Camera.TransitionCovered")
		else
			System.Debug:Warn("Camera.client", "Camera.TransitionCovered event not found (Transition module should create it)")
		end

		System.Debug:Message("Camera.client", "Started")
	end,
}
