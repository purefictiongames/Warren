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
	local assetsFolder = ReplicatedStorage:WaitForChild("Assets")
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")

	-- Get configuration from model attributes
	local dropTemplate = model:GetAttribute("DropTemplate") or "TimedEvaluator"
	local spawnOffset = model:GetAttribute("SpawnOffset") or Vector3.new(0, 0, 0)

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
	local template = assetsFolder:FindFirstChild(dropTemplate)
	if not template then
		System.Debug:Alert(assetName, "Drop template not found:", dropTemplate)
		return nil
	end

	-- Load initialization module for the template
	local initModule = nil
	local moduleFolder = template:FindFirstChild("ReplicatedStorage")
	if moduleFolder then
		local modScript = moduleFolder:FindFirstChild(dropTemplate .. "Module")
		if modScript then
			initModule = require(modScript)
		end
	end

	if not initModule then
		-- Try deployed location
		local deployedModule = ReplicatedStorage:FindFirstChild(dropTemplate .. "." .. dropTemplate .. "Module")
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

		-- Position at SpawnPoint
		local targetCFrame = spawnPoint.CFrame * CFrame.new(spawnOffset)
		clone:PivotTo(targetCFrame)
		clone.Parent = runtimeAssets

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

		System.Debug:Message(assetName, "Enabled")
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

	System.Debug:Message(assetName, "Initialized via module")

	return {
		model = model,
		assetName = assetName,
		enable = handleEnable,
		disable = handleDisable,
		reset = handleReset,
		spawnedInstances = spawnedInstances,
	}
end

return DropperModule
