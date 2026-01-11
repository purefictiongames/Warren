--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- ArrayPlacer.Script (Server)
-- Spawns multiple instances of a template in an elliptical pattern around its own Anchor
-- Configured via manifest: { spawns = "Template", count = N }
-- Ellipse size determined by Anchor part's Size.X and Size.Z (radii = Size/2)

-- Guard: Only run if this is the deployed version
if not script.Name:match("%.") then
	return
end

local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[ArrayPlacer.Script] Could not extract asset name")
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Load Visibility utility
local Visibility = require(ReplicatedStorage:WaitForChild("System.Visibility"))

System:RegisterAsset(assetName, function()
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
	local libFolder = ReplicatedStorage:WaitForChild("Lib")
	local model = runtimeAssets:WaitForChild(assetName)

	-- Get standardized events
	local inputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Input")
	local outputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Output")

	-- Get configuration from attributes (set by System.Script from manifest)
	local spawnsTemplate = model:GetAttribute("Spawns")
	local count = model:GetAttribute("Count") or 4

	if not spawnsTemplate then
		System.Debug:Alert(assetName, "No 'Spawns' attribute - nothing to spawn")
		return
	end

	-- Find own Anchor part (defines ellipse center and size)
	local anchor = model:FindFirstChild("Anchor")
	if not anchor then
		System.Debug:Alert(assetName, "No Anchor part found - cannot determine placement area")
		return
	end

	-- Find template
	-- Check order: _ConfiguredTemplates (bootstrap), Templates (Rojo), Lib (raw)
	local configuredTemplates = ReplicatedStorage:FindFirstChild("_ConfiguredTemplates")
	local staticTemplates = ReplicatedStorage:FindFirstChild("Templates")

	-- Debug: List what's in template folders
	if configuredTemplates then
		local templateNames = {}
		for _, child in ipairs(configuredTemplates:GetChildren()) do
			table.insert(templateNames, child.Name)
		end
		System.Debug:Message(assetName, "_ConfiguredTemplates contains:", table.concat(templateNames, ", "))
	end

	local template = configuredTemplates and configuredTemplates:FindFirstChild(spawnsTemplate)
	local templateSource = "_ConfiguredTemplates"

	if not template and staticTemplates then
		template = staticTemplates:FindFirstChild(spawnsTemplate)
		templateSource = "Templates"
	end

	if not template then
		template = libFolder:FindFirstChild(spawnsTemplate)
		templateSource = "Lib"
	end

	if not template then
		System.Debug:Alert(assetName, "Template not found:", spawnsTemplate)
		return
	end

	System.Debug:Message(assetName, "Found template", spawnsTemplate, "in", templateSource)

	-- Optional: Center anchor on another asset (for initial positioning)
	local centerOn = model:GetAttribute("CenterOn")
	if centerOn then
		local centerAsset = runtimeAssets:FindFirstChild(centerOn)
		if centerAsset then
			local centerAnchor = centerAsset:FindFirstChild("Anchor")
			local centerPos = centerAnchor and centerAnchor.Position or centerAsset:GetPivot().Position
			-- Move anchor to center on that asset's XZ, keep configured Y
			anchor.Position = Vector3.new(centerPos.X, anchor.Position.Y, centerPos.Z)
			System.Debug:Message(assetName, "Centered anchor on", centerOn)
		else
			System.Debug:Warn(assetName, "CenterOn asset not found:", centerOn)
		end
	end

	-- Configure anchor size for ellipse (can be overridden by attributes)
	local anchorSizeX = model:GetAttribute("AnchorSizeX")
	local anchorSizeZ = model:GetAttribute("AnchorSizeZ")
	local anchorSizeY = model:GetAttribute("AnchorSizeY")
	if anchorSizeX or anchorSizeZ or anchorSizeY then
		anchor.Size = Vector3.new(
			anchorSizeX or anchor.Size.X,
			anchorSizeY or anchor.Size.Y,
			anchorSizeZ or anchor.Size.Z
		)
	end

	-- Ellipse radii from anchor size
	local radiusX = anchor.Size.X / 2
	local radiusZ = anchor.Size.Z / 2
	local originPosition = anchor.Position

	System.Debug:Message(assetName, "Spawns:", spawnsTemplate, "Count:", count, "RadiusX:", radiusX, "RadiusZ:", radiusZ)

	-- Determine the base template name for module lookup
	-- For configured templates, the base name might differ from the alias
	local baseTemplateName = template:GetAttribute("_BaseTemplate") or spawnsTemplate

	-- Load initialization module for the template
	local initModule = nil
	local moduleFolder = template:FindFirstChild("ReplicatedStorage")
	if moduleFolder then
		-- Try alias name first, then base name
		local modScript = moduleFolder:FindFirstChild(spawnsTemplate .. "Module")
			or moduleFolder:FindFirstChild(baseTemplateName .. "Module")
		if modScript then
			initModule = require(modScript)
		end
	end

	if not initModule then
		-- Try deployed location (alias name first, then base name)
		local deployedModule = ReplicatedStorage:FindFirstChild(spawnsTemplate .. "." .. spawnsTemplate .. "Module")
			or ReplicatedStorage:FindFirstChild(baseTemplateName .. "." .. baseTemplateName .. "Module")
		if deployedModule then
			initModule = require(deployedModule)
		end
	end

	if not initModule or not initModule.initialize then
		System.Debug:Alert(assetName, "No init module for:", spawnsTemplate, "(base:", baseTemplateName, ")")
		return
	end

	System.Debug:Message(assetName, "Using init module for base:", baseTemplateName)

	-- Track spawned instances
	local spawnedInstances = {}

	-- Ground level (use 0 or configurable)
	local groundY = model:GetAttribute("GroundY") or 0

	-- Rotation offset for spawned models (in degrees, applied after facing origin)
	-- 0 = model's local -Z faces the origin (CFrame.lookAt default)
	-- 180 = model's local +Z faces the origin (common for models that "face" +Z)
	local faceOffset = model:GetAttribute("FaceOffset") or 0

	-- Calculate position for index in ellipse
	local function getPositionForIndex(index, total)
		local angle = (index - 1) * (2 * math.pi / total)
		local x = originPosition.X + radiusX * math.cos(angle)
		local z = originPosition.Z + radiusZ * math.sin(angle)

		-- Face toward origin (at ground level)
		local position = Vector3.new(x, groundY, z)
		local lookAt = Vector3.new(originPosition.X, groundY, originPosition.Z)

		return CFrame.lookAt(position, lookAt)
	end

	-- Rotate a model around its bounding box center (not its pivot)
	local function rotateModelAroundCenter(mdl, degrees)
		if degrees == 0 then return end

		-- Find bounding box center
		local minPos = Vector3.new(math.huge, math.huge, math.huge)
		local maxPos = Vector3.new(-math.huge, -math.huge, -math.huge)

		for _, part in ipairs(mdl:GetDescendants()) do
			if part:IsA("BasePart") then
				local halfSize = part.Size / 2
				local partMin = part.Position - halfSize
				local partMax = part.Position + halfSize
				minPos = Vector3.new(math.min(minPos.X, partMin.X), math.min(minPos.Y, partMin.Y), math.min(minPos.Z, partMin.Z))
				maxPos = Vector3.new(math.max(maxPos.X, partMax.X), math.max(maxPos.Y, partMax.Y), math.max(maxPos.Z, partMax.Z))
			end
		end

		local center = (minPos + maxPos) / 2

		-- Rotate around center
		local rotationCFrame = CFrame.new(center) * CFrame.Angles(0, math.rad(degrees), 0) * CFrame.new(-center)

		for _, part in ipairs(mdl:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CFrame = rotationCFrame * part.CFrame
			end
		end
	end

	-- Ground a model so its bottom sits at Y=groundY
	local function groundModel(mdl)
		local minY = math.huge
		for _, part in ipairs(mdl:GetDescendants()) do
			if part:IsA("BasePart") then
				local bottomY = part.Position.Y - (part.Size.Y / 2)
				if bottomY < minY then
					minY = bottomY
				end
			end
		end
		if minY ~= math.huge then
			local offset = groundY - minY
			if math.abs(offset) > 0.01 then
				mdl:PivotTo(mdl:GetPivot() + Vector3.new(0, offset, 0))
				System.Debug:Message(assetName, "Grounded", mdl.Name, "by", offset)
			end
		end
	end

	-- Spawn all instances
	local function spawnAll()
		for i = 1, count do
			local spawnName = assetName .. "_" .. spawnsTemplate .. "_" .. i

			-- Clone template
			local clone = template:Clone()
			clone.Name = spawnName

			-- Remove service folders
			for _, child in ipairs(clone:GetChildren()) do
				if child.Name:match("^_") or child.Name == "ReplicatedStorage" or child.Name == "StarterGui" or child.Name == "StarterPlayerScripts" then
					child:Destroy()
				end
			end

			-- Note: Template is already pre-configured with all attributes at bootstrap
			-- No runtime propagation needed - the template in Templates folder is ready to use

			-- Debug: Log what parts exist in the cloned template
			local partNames = {}
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") or desc:IsA("MeshPart") then
					table.insert(partNames, desc.Name .. "(" .. desc.ClassName .. ")")
				end
			end
			System.Debug:Message(assetName, "Clone", spawnName, "has parts:", table.concat(partNames, ", "))

			-- Position in circle facing origin
			local targetCFrame = getPositionForIndex(i, count)
			clone:PivotTo(targetCFrame)
			clone.Parent = runtimeAssets

			-- Ground the model so bottom sits at ground level
			groundModel(clone)

			-- Apply rotation offset (rotates around model's visual center, not pivot)
			if faceOffset ~= 0 then
				rotateModelAroundCenter(clone, faceOffset)
			end

			-- Create events for this instance
			local instanceInput = Instance.new("BindableEvent")
			instanceInput.Name = spawnName .. ".Input"
			instanceInput.Parent = ReplicatedStorage

			local instanceOutput = Instance.new("BindableEvent")
			instanceOutput.Name = spawnName .. ".Output"
			instanceOutput.Parent = ReplicatedStorage

			-- Initialize via module
			local controller = initModule.initialize({
				model = clone,
				assetName = spawnName,
				inputEvent = instanceInput,
				outputEvent = instanceOutput,
				System = System,
			})

			if not controller then
				System.Debug:Warn(assetName, "Failed to init:", spawnName)
				clone:Destroy()
				instanceInput:Destroy()
				instanceOutput:Destroy()
			else
				-- Track connections
				local connections = {}

				-- Forward output events to ArrayPlacer's output
				local conn = instanceOutput.Event:Connect(function(message)
					-- Add source info and forward
					message.arrayPlacerOrigin = assetName
					message.instanceName = spawnName
					outputEvent:Fire(message)
				end)
				table.insert(connections, conn)

				local instance = {
					index = i,
					name = spawnName,
					model = clone,
					controller = controller,
					inputEvent = instanceInput,
					outputEvent = instanceOutput,
					connections = connections,
				}

				table.insert(spawnedInstances, instance)
				System.Debug:Message(assetName, "Spawned:", spawnName, "at index", i)
			end
		end
	end

	-- Despawn all instances
	local function despawnAll()
		for _, instance in ipairs(spawnedInstances) do
			for _, conn in ipairs(instance.connections) do
				conn:Disconnect()
			end

			if instance.controller and instance.controller.disable then
				instance.controller.disable()
			end

			if instance.model then
				instance.model:Destroy()
			end
			if instance.inputEvent then
				instance.inputEvent:Destroy()
			end
			if instance.outputEvent then
				instance.outputEvent:Destroy()
			end

			System.Debug:Message(assetName, "Despawned:", instance.name)
		end
		spawnedInstances = {}
	end

	-- Command handlers
	local function handleEnable()
		model:SetAttribute("IsEnabled", true)

		if #spawnedInstances == 0 then
			spawnAll()
		end

		-- Enable all spawned instances
		for _, instance in ipairs(spawnedInstances) do
			if instance.controller and instance.controller.enable then
				instance.controller.enable()
			end
		end

		System.Debug:Message(assetName, "Enabled -", #spawnedInstances, "instances")
		return true
	end

	local function handleDisable()
		-- Disable and despawn all
		despawnAll()
		model:SetAttribute("IsEnabled", false)
		System.Debug:Message(assetName, "Disabled")
		return true
	end

	local function handleReset()
		-- Reset all spawned instances
		for _, instance in ipairs(spawnedInstances) do
			if instance.controller and instance.controller.reset then
				instance.controller.reset()
			end
		end
		System.Debug:Message(assetName, "Reset all instances")
		return true
	end

	-- Route command to specific spawned instance
	local function routeToInstance(targetName, message)
		for _, instance in ipairs(spawnedInstances) do
			if instance.name == targetName then
				-- Forward command to instance's input event
				if instance.inputEvent then
					instance.inputEvent:Fire(message)
					System.Debug:Message(assetName, "Routed", message.command, "to", targetName)
					return true
				end
				-- Or call controller method directly
				if instance.controller then
					if message.command == "spawn" and instance.controller.spawn then
						instance.controller.spawn()
						return true
					elseif message.command == "despawn" and instance.controller.despawn then
						instance.controller.despawn()
						return true
					elseif message.command == "reset" and instance.controller.reset then
						instance.controller.reset()
						return true
					elseif message.command == "enable" and instance.controller.enable then
						instance.controller.enable()
						return true
					elseif message.command == "disable" and instance.controller.disable then
						instance.controller.disable()
						return true
					end
				end
			end
		end
		System.Debug:Warn(assetName, "Instance not found for routing:", targetName)
		return false
	end

	-- Listen for commands
	inputEvent.Event:Connect(function(message)
		if not message or type(message) ~= "table" then return end

		-- Check if this is a routed command for a specific instance
		if message.target and message.target:match("^" .. assetName .. "_") then
			routeToInstance(message.target, message)
			return
		end

		-- Otherwise handle as ArrayPlacer-level command
		if message.command == "enable" then
			handleEnable()
		elseif message.command == "disable" then
			handleDisable()
		elseif message.command == "reset" then
			handleReset()
		else
			System.Debug:Warn(assetName, "Unknown command:", message.command)
		end
	end)

	-- BindableFunctions
	local enableFn = Instance.new("BindableFunction")
	enableFn.Name = "Enable"
	enableFn.OnInvoke = handleEnable
	enableFn.Parent = model

	local disableFn = Instance.new("BindableFunction")
	disableFn.Name = "Disable"
	disableFn.OnInvoke = handleDisable
	disableFn.Parent = model

	local resetFn = Instance.new("BindableFunction")
	resetFn.Name = "Reset"
	resetFn.OnInvoke = handleReset
	resetFn.Parent = model

	System.Debug:Message(assetName, "Initialized")
end)

System.Debug:Message(assetName, "Script loaded")
