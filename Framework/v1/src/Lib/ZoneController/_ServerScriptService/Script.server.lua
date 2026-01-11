--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- ZoneController.Script (Server)
-- Event-driven zone detection with tick-based method invocation
-- Scans entities for a matching callback method and calls it while in zone

-- Guard: Only run if this is the deployed version (has dot in name)
if not script.Name:match("%.") then
	return
end

-- Extract asset name from script name (e.g., "Campfire.Script" → "Campfire")
local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[ZoneController.Script] Could not extract asset name from script.Name:", script.Name)
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Dependencies (guaranteed to exist after SCRIPTS stage)
local Visibility = require(ReplicatedStorage:WaitForChild("System.Visibility"))
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild(assetName)
local inputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Input")

-- Active state - when false, zone detection is disabled
local isActive = false

-- Deep search for instances that have a BindableFunction child with the method name
local function findMethodInTree(root, methodName, isPlayer)
	local results = {}

	local function search(instance)
		-- Check if this instance has a BindableFunction child with the method name
		local callback = instance:FindFirstChild(methodName)
		if callback and callback:IsA("BindableFunction") then
			table.insert(results, instance)
		end

		for _, child in ipairs(instance:GetChildren()) do
			search(child)
		end
	end

	-- For players, search Character (in Workspace) and Backpack separately
	if isPlayer then
		local character = root.Character
		if character then
			search(character)
		end
		local backpack = root:FindFirstChild("Backpack")
		if backpack then
			search(backpack)
		end
	else
		search(root)
	end

	return results
end

-- Get the entity root (Player or Model) from a hit part
-- For players, returns the Player object (so we can search Backpack too)
local function getEntityRoot(hit)
	-- Walk up to find Character
	local current = hit
	while current and current ~= workspace do
		local player = Players:GetPlayerFromCharacter(current)
		if player then
			return player, "player"  -- Return Player, not Character
		end
		current = current.Parent
	end

	-- Not a player - look for a Model with PrimaryPart or Humanoid
	current = hit.Parent
	while current and current ~= workspace do
		if current:IsA("Model") then
			if current:FindFirstChild("Humanoid") or current.PrimaryPart then
				return current, "model"
			end
		end
		current = current.Parent
	end

	return nil, nil
end

local function setupZoneController(zoneModel)
	-- Get config from attributes
	local matchCallback = zoneModel:GetAttribute("MatchCallback")
	local tickRate = zoneModel:GetAttribute("TickRate") or 0.5

	if not matchCallback then
		System.Debug:Warn(assetName, "No MatchCallback attribute set on", zoneModel.Name)
		return
	end

	-- Find Zone part
	local zone = zoneModel:FindFirstChild("Zone")
	if not zone then
		System.Debug:Warn(assetName, "No Zone part found in", zoneModel.Name)
		return
	end

	-- Ensure zone is configured correctly
	-- Set attributes so showModel() keeps these values
	zone.CanCollide = false
	zone:SetAttribute("VisibleCanCollide", false)
	zone.CanTouch = true
	zone:SetAttribute("VisibleCanTouch", true)

	-- Make all parts in the model non-collideable (campfire visuals, etc.)
	for _, part in ipairs(zoneModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part:SetAttribute("VisibleCanCollide", false)
		end
	end

	-- Attendance table: entityRoot -> { instances = {instance -> true}, callbacks = {instance -> callback} }
	local attendance = {}

	-- Track touch counts per entity (for reliable exit detection)
	local touchCounts = {}

	-- Handle entity entering zone (called on first touch)
	local function onEntityEnter(entityRoot, entityType)
		-- Just mark entity as in zone - we'll search on each tick
		attendance[entityRoot] = {
			entityType = entityType
		}
		System.Debug:Message(assetName, "Entity entered zone")
	end

	-- Handle entity leaving zone (called when touch count reaches 0)
	local function onEntityExit(entityRoot)
		if attendance[entityRoot] then
			System.Debug:Message(assetName, "Entity left zone")
			attendance[entityRoot] = nil
		end
	end

	-- Zone touch events - use counting for reliable entry/exit detection
	zone.Touched:Connect(function(hit)
		if not isActive then return end
		local entityRoot, entityType = getEntityRoot(hit)
		if entityRoot then
			touchCounts[entityRoot] = (touchCounts[entityRoot] or 0) + 1

			-- First touch - entity just entered
			if touchCounts[entityRoot] == 1 then
				onEntityEnter(entityRoot, entityType)
			end
		end
	end)

	zone.TouchEnded:Connect(function(hit)
		if not isActive then return end
		local entityRoot, entityType = getEntityRoot(hit)
		if entityRoot and touchCounts[entityRoot] then
			touchCounts[entityRoot] = touchCounts[entityRoot] - 1

			-- Last touch ended - entity fully left
			if touchCounts[entityRoot] <= 0 then
				touchCounts[entityRoot] = nil
				onEntityExit(entityRoot)
			end
		end
	end)

	-- Tick loop - call methods on all attended instances
	local lastTick = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		if not isActive then return end
		lastTick = lastTick + deltaTime

		if lastTick < tickRate then
			return
		end

		local dt = lastTick
		lastTick = 0

		-- Build state table to pass to callbacks
		local state = {
			deltaTime = dt,
			tickRate = tickRate,
			zoneCenter = zone.Position,
			zoneSize = zone.Size,
		}

		-- Search and call method on all entities in zone
		for entityRoot, data in pairs(attendance) do
			-- Deep search on each tick to find new instances (e.g., mounted marshmallows)
			local isPlayer = data.entityType == "player"
			local matches = findMethodInTree(entityRoot, matchCallback, isPlayer)

			for _, instance in ipairs(matches) do
				-- Invoke the BindableFunction
				local callback = instance:FindFirstChild(matchCallback)
				if callback then
					local success, err = pcall(function()
						callback:Invoke(state)
					end)
					if not success then
						System.Debug:Alert(assetName, "Error calling", matchCallback, "on", instance.Name, "-", err)
					end
				end
			end
		end
	end)

	System.Debug:Message(assetName, "Set up", zoneModel.Name, "(MatchCallback:", matchCallback, ", TickRate:", tickRate, ")")

	-- Return zone and attendance for enable/disable to clear state
	return zone, attendance, touchCounts
end

local zone, attendance, touchCounts = setupZoneController(model)

-- Command handlers
local function handleEnable()
	Visibility.showModel(model)
	-- Force all parts to be non-collideable (override showModel's restore)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end
	isActive = true
	model:SetAttribute("IsEnabled", true)
	System.Debug:Message(assetName, "Enabled")
	return true
end

local function handleDisable()
	Visibility.hideModel(model)
	isActive = false
	-- Clear any entities currently in zone
	if attendance then
		for k in pairs(attendance) do
			attendance[k] = nil
		end
	end
	if touchCounts then
		for k in pairs(touchCounts) do
			touchCounts[k] = nil
		end
	end
	model:SetAttribute("IsEnabled", false)
	System.Debug:Message(assetName, "Disabled")
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
	else
		System.Debug:Warn(assetName, "Unknown command:", message.command)
	end
end)

-- Expose Enable/Disable via BindableFunction (backward compatibility)
local enableFunction = Instance.new("BindableFunction")
enableFunction.Name = "Enable"
enableFunction.OnInvoke = handleEnable
enableFunction.Parent = model

local disableFunction = Instance.new("BindableFunction")
disableFunction.Name = "Disable"
disableFunction.OnInvoke = handleDisable
disableFunction.Parent = model

-- Set initial state (starts disabled, Orchestrator will enable when game starts)
-- Call handleDisable to actually hide the model and stop sounds
handleDisable()

System.Debug:Message(assetName, "Script loaded")
