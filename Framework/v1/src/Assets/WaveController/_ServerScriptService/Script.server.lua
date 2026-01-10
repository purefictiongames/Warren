--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- WaveController.Script (Server)
-- Signal processor for game difficulty - controls spawn timing, concurrency, wave progression
-- Sits between Orchestrator (game flow) and Droppers (spawn instances)
--
-- Inputs:
--   { action = "gameStarted" } - Begin spawning
--   { action = "gameStopped" } - Stop spawning, clear queue
--   { action = "camperDespawned", origin = "..." } - Slot freed up
--   { action = "camperFed", origin = "..." } - Successful submission
--
-- Outputs:
--   { target = "CampPlacer_Dropper_N", command = "spawn" } - Spawn at specific tent
--   { target = "CampPlacer_Dropper_N", command = "despawn" } - Force despawn
--   { action = "waveComplete", wave = N } - Wave finished
--   { action = "allWavesComplete" } - Game complete

-- Guard: Only run if this is the deployed version
if not script.Name:match("%.") then
	return
end

local assetName = script.Name:match("^(.+)%.")
if not assetName then
	warn("[WaveController.Script] Could not extract asset name")
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

System:RegisterAsset(assetName, function()
	local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
	local model = runtimeAssets:WaitForChild(assetName)

	-- Get standardized events
	local inputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Input")
	local outputEvent = ReplicatedStorage:WaitForChild(assetName .. ".Output")

	-- Configuration (from attributes, can be modified at runtime)
	local function getConfig()
		return {
			maxConcurrent = model:GetAttribute("MaxConcurrent") or 1,
			spawnInterval = model:GetAttribute("SpawnInterval") or 5,
			activeTents = model:GetAttribute("ActiveTents") or 4,
			waveNumber = model:GetAttribute("WaveNumber") or 1,
			campersPerWave = model:GetAttribute("CampersPerWave") or 10,
			targetArrayPlacer = model:GetAttribute("TargetArrayPlacer") or "CampPlacer",
		}
	end

	-- State
	local isRunning = false
	local spawnThread = nil
	local activeCampers = {} -- { [instanceName] = true }
	local availableTents = {} -- { "CampPlacer_Dropper_1", ... }
	local campersSpawnedThisWave = 0
	local campersFedThisWave = 0

	-- Build list of available tent names
	local function refreshTentList()
		availableTents = {}
		local config = getConfig()
		for i = 1, config.activeTents do
			local tentName = config.targetArrayPlacer .. "_Dropper_" .. i
			table.insert(availableTents, tentName)
		end
		System.Debug:Message(assetName, "Tent list:", table.concat(availableTents, ", "))
	end

	-- Find a tent that doesn't have an active camper
	local function findFreeTent()
		for _, tentName in ipairs(availableTents) do
			-- Check if this tent's camper slot is free
			local camperName = tentName .. "_Drop_1" -- Dropper naming convention
			if not activeCampers[camperName] then
				return tentName
			end
		end
		return nil
	end

	-- Count active campers
	local function countActiveCampers()
		local count = 0
		for _ in pairs(activeCampers) do
			count = count + 1
		end
		return count
	end

	-- Spawn a camper at a specific tent
	local function spawnAt(tentName)
		local config = getConfig()
		local camperName = tentName .. "_Drop_1"

		System.Debug:Message(assetName, "Spawning camper at", tentName)

		-- Mark slot as occupied
		activeCampers[camperName] = true

		-- Send spawn command to the tent (via ArrayPlacer routing)
		outputEvent:Fire({
			target = tentName,
			command = "spawn",
		})

		campersSpawnedThisWave = campersSpawnedThisWave + 1
		model:SetAttribute("CampersSpawnedThisWave", campersSpawnedThisWave)

		System.Debug:Message(assetName, "Active campers:", countActiveCampers(), "/", config.maxConcurrent)
	end

	-- Try to spawn if conditions allow
	local function trySpawn()
		local config = getConfig()

		-- Check if we've spawned enough for this wave
		if campersSpawnedThisWave >= config.campersPerWave then
			System.Debug:Message(assetName, "Wave", config.waveNumber, "spawn limit reached")
			return false
		end

		-- Check if we're at max concurrent
		if countActiveCampers() >= config.maxConcurrent then
			return false
		end

		-- Find a free tent
		local tent = findFreeTent()
		if not tent then
			System.Debug:Message(assetName, "No free tents available")
			return false
		end

		spawnAt(tent)
		return true
	end

	-- Main spawn loop
	local function startSpawnLoop()
		if spawnThread then return end

		spawnThread = task.spawn(function()
			System.Debug:Message(assetName, "Spawn loop started")

			while isRunning do
				local config = getConfig()

				-- Try to spawn up to maxConcurrent
				trySpawn()

				-- Wait for next spawn interval
				task.wait(config.spawnInterval)
			end

			System.Debug:Message(assetName, "Spawn loop ended")
		end)
	end

	local function stopSpawnLoop()
		isRunning = false
		if spawnThread then
			pcall(function() task.cancel(spawnThread) end)
			spawnThread = nil
		end
	end

	-- Check if wave is complete
	local function checkWaveComplete()
		local config = getConfig()

		-- Wave complete when all campers spawned and none active
		if campersSpawnedThisWave >= config.campersPerWave and countActiveCampers() == 0 then
			System.Debug:Message(assetName, "Wave", config.waveNumber, "complete!")

			outputEvent:Fire({
				action = "waveComplete",
				wave = config.waveNumber,
				campersFed = campersFedThisWave,
				campersSpawned = campersSpawnedThisWave,
			})

			-- Could auto-advance to next wave here, or wait for Orchestrator
			return true
		end
		return false
	end

	-- Handle camper despawned (timeout or manual)
	local function onCamperDespawned(origin)
		if activeCampers[origin] then
			activeCampers[origin] = nil
			System.Debug:Message(assetName, "Camper despawned:", origin, "- Active:", countActiveCampers())

			-- Check if wave complete
			checkWaveComplete()

			-- Try to spawn replacement if still running
			if isRunning then
				task.delay(0.5, trySpawn) -- Small delay before spawning next
			end
		end
	end

	-- Handle camper fed (successful submission)
	local function onCamperFed(origin)
		campersFedThisWave = campersFedThisWave + 1
		model:SetAttribute("CampersFedThisWave", campersFedThisWave)

		if activeCampers[origin] then
			activeCampers[origin] = nil
			System.Debug:Message(assetName, "Camper fed:", origin, "- Fed this wave:", campersFedThisWave)

			-- Check if wave complete
			checkWaveComplete()

			-- Try to spawn replacement if still running
			if isRunning then
				task.delay(0.5, trySpawn)
			end
		end
	end

	-- Start the wave controller
	local function handleStart()
		if isRunning then return end

		System.Debug:Message(assetName, "Starting wave controller")

		isRunning = true
		activeCampers = {}
		campersSpawnedThisWave = 0
		campersFedThisWave = 0

		model:SetAttribute("CampersSpawnedThisWave", 0)
		model:SetAttribute("CampersFedThisWave", 0)

		refreshTentList()
		startSpawnLoop()
	end

	-- Stop the wave controller
	local function handleStop()
		System.Debug:Message(assetName, "Stopping wave controller")

		stopSpawnLoop()
		activeCampers = {}
	end

	-- Reset for new wave
	local function handleReset()
		campersSpawnedThisWave = 0
		campersFedThisWave = 0
		model:SetAttribute("CampersSpawnedThisWave", 0)
		model:SetAttribute("CampersFedThisWave", 0)
		System.Debug:Message(assetName, "Reset wave counters")
	end

	-- Set wave number (difficulty adjustment)
	local function handleSetWave(wave)
		model:SetAttribute("WaveNumber", wave)
		System.Debug:Message(assetName, "Wave set to", wave)
	end

	-- Listen for input events
	inputEvent.Event:Connect(function(message)
		if not message or type(message) ~= "table" then return end

		local action = message.action

		if action == "gameStarted" then
			handleStart()
		elseif action == "gameStopped" then
			handleStop()
		elseif action == "camperDespawned" then
			onCamperDespawned(message.origin)
		elseif action == "camperFed" or action == "evaluationComplete" then
			onCamperFed(message.origin or message.instanceName)
		elseif action == "setWave" then
			handleSetWave(message.wave)
		elseif message.command == "start" then
			handleStart()
		elseif message.command == "stop" then
			handleStop()
		elseif message.command == "reset" then
			handleReset()
		else
			System.Debug:Warn(assetName, "Unknown action/command:", action or message.command)
		end
	end)

	-- Set initial config defaults
	if not model:GetAttribute("MaxConcurrent") then
		model:SetAttribute("MaxConcurrent", 1)
	end
	if not model:GetAttribute("SpawnInterval") then
		model:SetAttribute("SpawnInterval", 5)
	end
	if not model:GetAttribute("ActiveTents") then
		model:SetAttribute("ActiveTents", 4)
	end
	if not model:GetAttribute("WaveNumber") then
		model:SetAttribute("WaveNumber", 1)
	end
	if not model:GetAttribute("CampersPerWave") then
		model:SetAttribute("CampersPerWave", 10)
	end

	System.Debug:Message(assetName, "Initialized")
end)

System.Debug:Message(assetName, "Script loaded")
