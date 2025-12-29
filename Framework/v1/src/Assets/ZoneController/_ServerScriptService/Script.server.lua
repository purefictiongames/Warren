-- ZoneController.Script (Server)
-- Event-driven zone detection with tick-based method invocation
-- Scans entities for a matching callback method and calls it while in zone

-- Guard: Only run if this is the deployed version
if not script.Name:match("^ZoneController%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Dependencies (guaranteed to exist after SCRIPTS stage)
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("ZoneController")

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
		warn("ZoneController: No MatchCallback attribute set on", zoneModel.Name)
		return
	end

	-- Find Zone part
	local zone = zoneModel:FindFirstChild("Zone")
	if not zone then
		warn("ZoneController: No Zone part found in", zoneModel.Name)
		return
	end

	-- Ensure zone is configured correctly
	zone.CanCollide = false
	zone.CanTouch = true

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
		print("ZoneController: Entity entered zone")
	end

	-- Handle entity leaving zone (called when touch count reaches 0)
	local function onEntityExit(entityRoot)
		if attendance[entityRoot] then
			print("ZoneController: Entity left zone")
			attendance[entityRoot] = nil
		end
	end

	-- Zone touch events - use counting for reliable entry/exit detection
	zone.Touched:Connect(function(hit)
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
						warn("ZoneController: Error calling", matchCallback, "on", instance.Name, "-", err)
					end
				end
			end
		end
	end)

	print("ZoneController: Set up", zoneModel.Name, "(MatchCallback:", matchCallback, ", TickRate:", tickRate, ")")
end

setupZoneController(model)

print("ZoneController.Script loaded")
