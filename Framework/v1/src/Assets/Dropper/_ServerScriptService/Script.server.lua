--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Dropper.Script (Server)
-- Dynamically spawns and controls asset instances (e.g., TimedEvaluator Campers)
-- Clones template at runtime, initializes via shared module, watches via events

-- Guard: Only run if this is the deployed version (has dot in name)
if not script.Name:match("%.") then
	return
end

-- Extract asset name from script name
local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[Dropper.Script] Could not extract asset name from script.Name:", script.Name)
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Load Visibility utility
local Visibility = require(ReplicatedStorage:WaitForChild("System.Visibility"))

-- Register init function (will be called at ASSETS stage)
System:RegisterAsset(assetName, function()
	-- Dependencies
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
	local assetsFolder = ReplicatedStorage:WaitForChild("Assets")
	local model = runtimeAssets:WaitForChild(assetName)

	-- Get standardized events (created by bootstrap)
	local inputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Input")
	local outputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Output")

	-- Get configuration from model attributes
	local dropTemplate = model:GetAttribute("DropTemplate") or "TimedEvaluator"
	local spawnOffset = model:GetAttribute("SpawnOffset") or Vector3.new(0, 0, 0)

	-- Find SpawnPoint in model (fallback to Anchor)
	local spawnPoint = model:FindFirstChild("SpawnPoint")
	if not spawnPoint then
		spawnPoint = model:FindFirstChild("Anchor")
		if spawnPoint then
			System.Debug:Warn(assetName, "No SpawnPoint found, using Anchor as spawn location")
		end
	end

	if not spawnPoint then
		System.Debug:Alert(assetName, "No SpawnPoint or Anchor found in model")
		return
	end

	-- Find template to clone
	local template = assetsFolder:FindFirstChild(dropTemplate)
	if not template then
		System.Debug:Alert(assetName, "Drop template not found:", dropTemplate)
		return
	end

	System.Debug:Message(assetName, "Configured to drop:", dropTemplate)

	-- Track spawned instances
	local spawnedInstances = {} -- { controller, model, inputEvent, connections }
	local spawnCounter = 0

	-- Load the appropriate module for the template type
	local initModule = nil
	local moduleScript = template:FindFirstChild("ReplicatedStorage")
	if moduleScript then
		local modScript = moduleScript:FindFirstChild(dropTemplate .. "Module") or moduleScript:FindFirstChild("ModuleScript")
		if modScript then
			initModule = require(modScript)
		end
	end

	if not initModule then
		-- Try to find in ReplicatedStorage (already deployed)
		local deployedModule = ReplicatedStorage:FindFirstChild(dropTemplate .. "." .. dropTemplate .. "Module")
		if deployedModule then
			initModule = require(deployedModule)
		end
	end

	if not initModule or not initModule.initialize then
		System.Debug:Alert(assetName, "No initialization module found for:", dropTemplate)
		return
	end

	-- Generate unique name for spawned instance
	local function generateSpawnName()
		spawnCounter = spawnCounter + 1
		return assetName .. "_Spawn_" .. spawnCounter
	end

	-- Spawn a new instance
	local function spawnInstance()
		local spawnName = generateSpawnName()

		-- Clone template
		local clone = template:Clone()
		clone.Name = spawnName

		-- Remove any service folders (they won't work at runtime anyway)
		for _, child in ipairs(clone:GetChildren()) do
			if child.Name:match("^_") or child.Name == "ReplicatedStorage" or child.Name == "StarterGui" then
				child:Destroy()
			end
		end

		-- Position at SpawnPoint
		local targetCFrame = spawnPoint.CFrame * CFrame.new(spawnOffset)
		clone:PivotTo(targetCFrame)
		clone.Parent = runtimeAssets

		-- Create Input event for this instance
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
			System.Debug:Warn(assetName, "Failed to initialize spawned instance:", spawnName)
			clone:Destroy()
			instanceInput:Destroy()
			return nil
		end

		-- Track connections for cleanup
		local connections = {}

		-- Listen for EvaluationComplete and forward to Dropper's Output
		if controller.evaluationComplete then
			local conn = controller.evaluationComplete.Event:Connect(function(result)
				-- Forward with origin info
				outputEvent:Fire({
					action = "evaluationComplete",
					origin = spawnName,
					dropperName = assetName,
					result = result,
				})
				System.Debug:Message(assetName, "Forwarded EvaluationComplete from", spawnName)
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
		System.Debug:Message(assetName, "Spawned instance:", spawnName)

		return instance
	end

	-- Despawn an instance
	local function despawnInstance(instance)
		if not instance then return end

		-- Disconnect all connections
		for _, conn in ipairs(instance.connections) do
			conn:Disconnect()
		end

		-- Disable before destroying
		if instance.controller and instance.controller.disable then
			instance.controller.disable()
		end

		-- Clean up
		if instance.model then
			instance.model:Destroy()
		end
		if instance.inputEvent then
			instance.inputEvent:Destroy()
		end

		System.Debug:Message(assetName, "Despawned instance:", instance.name)
	end

	-- Despawn all instances
	local function despawnAll()
		for _, instance in ipairs(spawnedInstances) do
			despawnInstance(instance)
		end
		spawnedInstances = {}
	end

	-- Get current spawned instance (first one, for single-spawn mode)
	local function getCurrentInstance()
		return spawnedInstances[1]
	end

	-- Command handlers
	local function handleEnable()
		Visibility.showModel(model) -- Show dropper (tent)
		model:SetAttribute("IsEnabled", true)

		-- Spawn instance if none exists
		if #spawnedInstances == 0 then
			local instance = spawnInstance()
			if instance and instance.controller then
				instance.controller.enable()
			end
		else
			-- Enable existing instance
			local instance = getCurrentInstance()
			if instance and instance.controller then
				instance.controller.enable()
			end
		end

		System.Debug:Message(assetName, "Enabled")
		return true
	end

	local function handleDisable()
		-- Disable and despawn all instances
		despawnAll()

		Visibility.hideModel(model) -- Hide dropper (tent)
		model:SetAttribute("IsEnabled", false)
		System.Debug:Message(assetName, "Disabled")
		return true
	end

	local function handleReset()
		-- Reset current instance
		local instance = getCurrentInstance()
		if instance and instance.controller then
			instance.controller.reset()
			System.Debug:Message(assetName, "Reset forwarded to", instance.name)
		end
		return true
	end

	local function handleSpawn()
		-- Explicit spawn command (for future multi-spawn support)
		local instance = spawnInstance()
		if instance and instance.controller then
			instance.controller.enable()
			instance.controller.reset()
		end
		return true
	end

	-- Listen on Input for commands from Orchestrator
	inputEvent.Event:Connect(function(message)
		if not message or type(message) ~= "table" then
			return
		end

		if message.command == "enable" then
			handleEnable()
		elseif message.command == "disable" then
			handleDisable()
		elseif message.command == "reset" then
			handleReset()
		elseif message.command == "spawn" then
			handleSpawn()
		else
			System.Debug:Warn(assetName, "Unknown command:", message.command)
		end
	end)

	-- Expose commands via BindableFunctions (backward compatibility)
	local enableFunction = Instance.new("BindableFunction")
	enableFunction.Name = "Enable"
	enableFunction.OnInvoke = handleEnable
	enableFunction.Parent = model

	local disableFunction = Instance.new("BindableFunction")
	disableFunction.Name = "Disable"
	disableFunction.OnInvoke = handleDisable
	disableFunction.Parent = model

	local resetFunction = Instance.new("BindableFunction")
	resetFunction.Name = "Reset"
	resetFunction.OnInvoke = handleReset
	resetFunction.Parent = model

	System.Debug:Message(assetName, "Initialized - DropTemplate:", dropTemplate)
end)

System.Debug:Message(assetName, "Script loaded, init registered")
