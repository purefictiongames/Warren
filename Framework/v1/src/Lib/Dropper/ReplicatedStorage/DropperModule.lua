--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- DropperModule
-- Shared logic for initializing Dropper instances
-- Can be used at boot time or runtime for dynamic spawning

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropperModule = {}

--[[
    Initialize a Dropper instance

    @param config {
        model: Model - The Dropper model
        assetName: string - Unique name for this instance
        inputEvent: BindableEvent - Event to receive commands
        outputEvent: BindableEvent - Event to send notifications
        System: table - Reference to System module
    }

    @return table - Controller with enable/disable/reset methods
]]
function DropperModule.initialize(config)
	local model = config.model
	local assetName = config.assetName
	local inputEvent = config.inputEvent
	local outputEvent = config.outputEvent
	local System = config.System

	-- Dependencies
	local Visibility = require(ReplicatedStorage:WaitForChild("System.Visibility"))
	local libFolder = ReplicatedStorage:WaitForChild("Warren")
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")

	-- Get configuration from model attributes
	local dropTemplate = model:GetAttribute("DropTemplate") or "TimedEvaluator"
	local spawnOffset = model:GetAttribute("SpawnOffset") or Vector3.new(0, 0, 0)
	local spawnMode = model:GetAttribute("SpawnMode") or "auto" -- "auto" or "onDemand"

	-- Find and configure Anchor
	local anchor = model:FindFirstChild("Anchor")
	if anchor then
		-- Check if Anchor is a BasePart (can set transparency) or a container
		if anchor:IsA("BasePart") then
			-- Make anchor part invisible and non-collideable
			anchor.Transparency = 1
			anchor:SetAttribute("VisibleTransparency", 1)
			anchor.CanCollide = false
			anchor:SetAttribute("VisibleCanCollide", false)
			anchor.CanTouch = false
			anchor:SetAttribute("VisibleCanTouch", false)
		end

		-- Configure visibility for all parts under/in the model
		-- Anchor and SpawnPoint should be invisible; everything else visible
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				if part.Name == "Anchor" or part.Name == "SpawnPoint" then
					-- Utility parts: invisible
					part.Transparency = 1
					part:SetAttribute("VisibleTransparency", 1)
					part.CanCollide = false
					part:SetAttribute("VisibleCanCollide", false)
					part.CanTouch = false
					part:SetAttribute("VisibleCanTouch", false)
				else
					-- Visual parts (tent, etc.): ensure they're visible
					if part:GetAttribute("VisibleTransparency") == nil then
						part:SetAttribute("VisibleTransparency", part.Transparency)
					end
					if part:GetAttribute("VisibleCanCollide") == nil then
						part:SetAttribute("VisibleCanCollide", part.CanCollide)
					end
					if part:GetAttribute("VisibleCanTouch") == nil then
						part:SetAttribute("VisibleCanTouch", part.CanTouch)
					end
				end
			end
		end
	end

	-- Find SpawnPoint (check direct child first, then descendants, fallback to Anchor)
	local spawnPoint = model:FindFirstChild("SpawnPoint")
	if not spawnPoint and anchor then
		-- Check if SpawnPoint is nested under Anchor
		spawnPoint = anchor:FindFirstChild("SpawnPoint")
	end
	if not spawnPoint then
		-- Search all descendants as last resort
		for _, desc in ipairs(model:GetDescendants()) do
			if desc.Name == "SpawnPoint" and desc:IsA("BasePart") then
				spawnPoint = desc
				break
			end
		end
	end
	if not spawnPoint then
		if anchor and anchor:IsA("BasePart") then
			spawnPoint = anchor
			System.Debug:Warn(assetName, "No SpawnPoint found, using Anchor")
		end
	end

	if not spawnPoint then
		System.Debug:Alert(assetName, "No SpawnPoint or Anchor found")
		return nil
	end

	-- Debug: Log model structure
	local partCount = 0
	local visualParts = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			partCount = partCount + 1
			if part.Name ~= "Anchor" and part.Name ~= "SpawnPoint" then
				table.insert(visualParts, part.Name)
			end
		end
	end
	System.Debug:Message(assetName, "Model has", partCount, "parts. Visual parts:", table.concat(visualParts, ", "))

	-- Find template to clone
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
	System.Debug:Message(assetName, "Looking for dropTemplate:", dropTemplate)

	local template = configuredTemplates and configuredTemplates:FindFirstChild(dropTemplate)
	local templateSource = "_ConfiguredTemplates"

	if not template and staticTemplates then
		template = staticTemplates:FindFirstChild(dropTemplate)
		templateSource = "Templates"
	end

	if not template then
		template = libFolder:FindFirstChild(dropTemplate)
		templateSource = "Lib"
	end

	if not template then
		System.Debug:Alert(assetName, "Drop template not found:", dropTemplate)
		return nil
	end

	System.Debug:Message(assetName, "Found template", dropTemplate, "in", templateSource)

	-- Determine the base template name for module lookup
	-- For configured templates, the base name might differ from the alias
	local baseTemplateName = template:GetAttribute("_BaseTemplate") or dropTemplate

	-- Load initialization module for the template
	local initModule = nil
	local moduleFolder = template:FindFirstChild("ReplicatedStorage")
	if moduleFolder then
		-- Try alias name first, then base name
		local modScript = moduleFolder:FindFirstChild(dropTemplate .. "Module")
			or moduleFolder:FindFirstChild(baseTemplateName .. "Module")
		if modScript then
			initModule = require(modScript)
		end
	end

	if not initModule then
		-- Try deployed location (alias name first, then base name)
		local deployedModule = ReplicatedStorage:FindFirstChild(dropTemplate .. "." .. dropTemplate .. "Module")
			or ReplicatedStorage:FindFirstChild(baseTemplateName .. "." .. baseTemplateName .. "Module")
		if deployedModule then
			initModule = require(deployedModule)
		end
	end

	if not initModule or not initModule.initialize then
		System.Debug:Alert(assetName, "No init module for:", dropTemplate)
		return nil
	end

	System.Debug:Message(assetName, "Configured to drop:", dropTemplate)

	-- Track spawned instances
	local spawnedInstances = {}
	local spawnCounter = 0

	-- Generate unique name
	local function generateSpawnName()
		spawnCounter = spawnCounter + 1
		return assetName .. "_Drop_" .. spawnCounter
	end

	-- Spawn a new instance
	local function spawnInstance()
		local spawnName = generateSpawnName()

		-- Clone template
		local clone = template:Clone()
		clone.Name = spawnName

		-- Remove service folders
		for _, child in ipairs(clone:GetChildren()) do
			if child.Name:match("^_") or child.Name == "ReplicatedStorage" or child.Name == "StarterGui" or child.Name == "StarterPlayerScripts" then
				child:Destroy()
			end
		end

		-- Note: Template is already pre-configured with model and attributes at bootstrap
		-- No runtime propagation needed - the template in Templates folder is ready to use

		-- Clear VisibleTransparency attributes AND reset Transparency to visible state
		-- Templates may have both attributes and properties baked in from being saved while hidden
		local clearedCount = 0
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				local partName = desc.Name
				-- Skip utility parts that should remain invisible
				if partName ~= "Anchor" and partName ~= "SpawnPoint" then
					-- Clear visibility attributes
					if desc:GetAttribute("VisibleTransparency") then
						desc:SetAttribute("VisibleTransparency", nil)
						clearedCount = clearedCount + 1
					end
					-- Also reset the actual Transparency property to visible
					-- (Don't rely on showModel to do this - it might run later)
					if desc.Transparency == 1 then
						desc.Transparency = 0
					end
				end
				-- Always clear collision attributes
				if desc:GetAttribute("VisibleCanCollide") then
					desc:SetAttribute("VisibleCanCollide", nil)
				end
				if desc:GetAttribute("VisibleCanTouch") then
					desc:SetAttribute("VisibleCanTouch", nil)
				end
			end
		end
		System.Debug:Message(assetName, "Cleared VisibleTransparency on", clearedCount, "parts and reset Transparency")

		-- Debug: Log current transparency values AFTER clearing attributes
		local partStates = {}
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(partStates, desc.Name .. "(T:" .. desc.Transparency .. ")")
			end
		end
		System.Debug:Message(assetName, "After attr clear - parts:", table.concat(partStates, ", "))

		-- Position at SpawnPoint
		local targetCFrame = spawnPoint.CFrame * CFrame.new(spawnOffset)
		System.Debug:Message(assetName, "SpawnPoint position:", spawnPoint.Position, "Target CFrame:", targetCFrame.Position)
		clone:PivotTo(targetCFrame)
		clone.Parent = runtimeAssets

		-- Debug: Log actual part positions after placement
		local torso = clone:FindFirstChild("Torso", true) or clone:FindFirstChild("HumanoidRootPart", true)
		if torso then
			System.Debug:Message(assetName, "Character torso position after spawn:", torso.Position)
		end

		-- Create Input event
		local instanceInput = Instance.new("BindableEvent")
		instanceInput.Name = spawnName .. ".Input"
		instanceInput.Parent = ReplicatedStorage

		-- Initialize via module
		local controller = initModule.initialize({
			model = clone,
			assetName = spawnName,
			inputEvent = instanceInput,
			System = System,
		})

		if not controller then
			System.Debug:Warn(assetName, "Failed to init:", spawnName)
			clone:Destroy()
			instanceInput:Destroy()
			return nil
		end

		-- Track connections
		local connections = {}

		-- Forward events to Dropper's output
		if controller.evaluationComplete and outputEvent then
			local conn = controller.evaluationComplete.Event:Connect(function(result)
				outputEvent:Fire({
					action = "evaluationComplete",
					origin = spawnName,
					dropperName = assetName,
					result = result,
				})
			end)
			table.insert(connections, conn)
		end

		local instance = {
			name = spawnName,
			model = clone,
			controller = controller,
			inputEvent = instanceInput,
			connections = connections,
		}

		table.insert(spawnedInstances, instance)
		System.Debug:Message(assetName, "Spawned:", spawnName)

		return instance
	end

	-- Despawn instance
	local function despawnInstance(instance)
		if not instance then return end

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

		System.Debug:Message(assetName, "Despawned:", instance.name)
	end

	-- Despawn all
	local function despawnAll()
		for _, instance in ipairs(spawnedInstances) do
			despawnInstance(instance)
		end
		spawnedInstances = {}
	end

	-- Get current instance
	local function getCurrentInstance()
		return spawnedInstances[1]
	end

	-- Command handlers
	local function handleEnable()
		Visibility.showModel(model)
		model:SetAttribute("IsEnabled", true)

		-- In "auto" mode, spawn immediately; in "onDemand" mode, wait for spawn command
		if spawnMode == "auto" then
			if #spawnedInstances == 0 then
				local instance = spawnInstance()
				if instance and instance.controller then
					instance.controller.enable()
				end
			else
				local instance = getCurrentInstance()
				if instance and instance.controller then
					instance.controller.enable()
				end
			end
		end

		System.Debug:Message(assetName, "Enabled (spawnMode:", spawnMode, ")")
		return true
	end

	-- Explicit spawn command (for onDemand mode)
	local function handleSpawn()
		if not model:GetAttribute("IsEnabled") then
			System.Debug:Warn(assetName, "Cannot spawn - not enabled")
			return false
		end

		-- Despawn existing if any
		despawnAll()

		-- Spawn new
		local instance = spawnInstance()
		if instance and instance.controller then
			instance.controller.enable()
			instance.controller.reset()
			System.Debug:Message(assetName, "Spawned camper:", instance.name)

			-- Fire spawned event
			if outputEvent then
				outputEvent:Fire({
					action = "camperSpawned",
					origin = instance.name,
					dropperName = assetName,
				})
			end
			return true
		end
		return false
	end

	-- Explicit despawn command
	local function handleDespawn()
		local instance = getCurrentInstance()
		local instanceName = instance and instance.name or nil

		despawnAll()

		-- Fire despawned event
		if instanceName and outputEvent then
			outputEvent:Fire({
				action = "camperDespawned",
				origin = instanceName,
				dropperName = assetName,
			})
		end

		System.Debug:Message(assetName, "Despawned")
		return true
	end

	local function handleDisable()
		despawnAll()
		Visibility.hideModel(model)
		model:SetAttribute("IsEnabled", false)
		System.Debug:Message(assetName, "Disabled")
		return true
	end

	local function handleReset()
		local instance = getCurrentInstance()
		if instance and instance.controller then
			instance.controller.reset()
		end
		return true
	end

	-- Listen for commands
	if inputEvent then
		inputEvent.Event:Connect(function(message)
			if not message or type(message) ~= "table" then return end

			if message.command == "enable" then
				handleEnable()
			elseif message.command == "disable" then
				handleDisable()
			elseif message.command == "reset" then
				handleReset()
			elseif message.command == "spawn" then
				handleSpawn()
			elseif message.command == "despawn" then
				handleDespawn()
			end
		end)
	end

	-- Create BindableFunctions
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

	local spawnFn = Instance.new("BindableFunction")
	spawnFn.Name = "Spawn"
	spawnFn.OnInvoke = handleSpawn
	spawnFn.Parent = model

	local despawnFn = Instance.new("BindableFunction")
	despawnFn.Name = "Despawn"
	despawnFn.OnInvoke = handleDespawn
	despawnFn.Parent = model

	System.Debug:Message(assetName, "Initialized via module (spawnMode:", spawnMode, ")")

	return {
		model = model,
		assetName = assetName,
		enable = handleEnable,
		disable = handleDisable,
		reset = handleReset,
		spawn = handleSpawn,
		despawn = handleDespawn,
		spawnedInstances = spawnedInstances,
	}
end

return DropperModule
