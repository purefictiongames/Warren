--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Tutorial.Script (Server)
-- State machine for the Tutorial system
-- Listens to game events and transitions players through tutorial states
-- Uses two-phase initialization: init() creates state, start() connects events

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Tutorial%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- Wait for System module
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

local TutorialModule = {}

-- Module state (initialized in init())
local Tutorial
local RunModes
local tutorialCommand
local tutorialStateChanged
local messageTicker
local tutorialStore
local playerStates = {}
local playerTasks = {}

-- Check if player has completed tutorial (from DataStore)
local function isCompleted(player)
	if not tutorialStore then
		return false
	end

	local success, result = pcall(function()
		return tutorialStore:GetAsync("completed_" .. player.UserId)
	end)
	return success and result == true
end

-- Mark tutorial as completed in DataStore
local function markCompleted(player)
	if not tutorialStore then
		return
	end

	pcall(function()
		tutorialStore:SetAsync("completed_" .. player.UserId, true)
	end)
end

-- Set player state and fire events
local function setState(player, state)
	local oldState = playerStates[player] or Tutorial.States.INACTIVE
	playerStates[player] = state
	Tutorial:_updatePlayerState(player, state)

	tutorialStateChanged:Fire({
		player = player,
		oldState = oldState,
		newState = state,
	})

	tutorialCommand:FireClient(player, {
		command = "state_changed",
		oldState = oldState,
		newState = state,
	})

	if state == Tutorial.States.FIND_CAMPER and messageTicker then
		messageTicker:FireClient(player, "Find the camper and talk to them!")
	end

	System.Debug:Message("Tutorial", player.Name, "state:", oldState, "->", state)
end

-- Handle step completion
local function onStepComplete(player, taskId)
	if not playerTasks[player] then
		playerTasks[player] = {}
	end
	playerTasks[player][taskId] = true

	tutorialCommand:FireClient(player, {
		command = "task_complete",
		taskId = taskId,
	})

	System.Debug:Message("Tutorial", player.Name, "completed step:", taskId)
end

-- Handle popup button responses from client
local function handleClientResponse(player, data)
	local state = playerStates[player]
	local buttonId = data.buttonId

	System.Debug:Message("Tutorial", player.Name, "responded:", data.action, buttonId)

	if state == Tutorial.States.WELCOME and buttonId == "ok" then
		setState(player, Tutorial.States.FIND_CAMPER)
	elseif state == Tutorial.States.RULES and buttonId == "next" then
		setState(player, Tutorial.States.MODE_SELECT)
	elseif state == Tutorial.States.MODE_SELECT then
		if buttonId == "practice" then
			setState(player, Tutorial.States.PRACTICE)
			RunModes:SetMode(player, RunModes.Modes.PRACTICE)
		elseif buttonId == "play" then
			setState(player, Tutorial.States.PLAYING)
			RunModes:SetMode(player, RunModes.Modes.PLAY)
			setState(player, Tutorial.States.COMPLETED)
			markCompleted(player)
		end
	end
end

-- Setup player on join
local function setupPlayer(player)
	if isCompleted(player) then
		playerStates[player] = Tutorial.States.COMPLETED
		Tutorial:_updatePlayerState(player, Tutorial.States.COMPLETED)
		System.Debug:Message("Tutorial", player.Name, "already completed tutorial")
	else
		playerStates[player] = Tutorial.States.INACTIVE
		Tutorial:_updatePlayerState(player, Tutorial.States.INACTIVE)

		task.delay(2, function()
			if player.Parent and playerStates[player] == Tutorial.States.INACTIVE then
				setState(player, Tutorial.States.WELCOME)
			end
		end)
	end
end

--[[
    Phase 1: Initialize
    Load dependencies, get event references - NO connections yet
--]]
function TutorialModule:init()
	-- Load dependencies
	Tutorial = require(ReplicatedStorage:WaitForChild("Tutorial.Tutorial"))
	RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))

	-- Get event references
	tutorialCommand = ReplicatedStorage:WaitForChild("Tutorial.TutorialCommand")
	tutorialStateChanged = ReplicatedStorage:WaitForChild("Tutorial.TutorialStateChanged")

	-- Optional: MessageTicker (loaded lazily)
	task.spawn(function()
		messageTicker = ReplicatedStorage:WaitForChild("MessageTicker.MessageTicker", 10)
	end)

	-- Optional: DataStore for persistence
	pcall(function()
		tutorialStore = DataStoreService:GetDataStore("TutorialProgress")
	end)

	-- Register handlers with Tutorial API (setup, not connection)
	Tutorial:_registerServerHandlers(setState, onStepComplete)
end

--[[
    Phase 2: Start
    Connect events, initialize players
--]]
function TutorialModule:start()
	-- Listen for client responses
	tutorialCommand.OnServerEvent:Connect(handleClientResponse)

	-- Connect Camper interaction
	task.spawn(function()
		local camperInteract = ReplicatedStorage:WaitForChild("Camper.Interact", 30)
		if camperInteract then
			camperInteract.Event:Connect(function(data)
				local player = data.player
				local state = playerStates[player] or Tutorial.States.INACTIVE

				if state == Tutorial.States.FIND_CAMPER then
					setState(player, Tutorial.States.RULES)
				elseif state == Tutorial.States.INACTIVE then
					setState(player, Tutorial.States.WELCOME)
				elseif state == Tutorial.States.COMPLETED then
					setState(player, Tutorial.States.RULES)
				end
			end)
			System.Debug:Message("Tutorial", "Connected to Camper.Interact")
		else
			System.Debug:Warn("Tutorial", "Camper.Interact not found - camper integration disabled")
		end
	end)

	-- Connect game events for tutorial step completion
	task.spawn(function()
		local itemAdded = ReplicatedStorage:WaitForChild("Backpack.ItemAdded", 10)
		if itemAdded then
			itemAdded.Event:Connect(function(data)
				local player = data.player
				if Tutorial:IsActive(player) and not Tutorial:IsStepCompleted(player, "grab") then
					Tutorial:CompleteStep(player, "grab")
				end
			end)
		end

		local roundComplete = ReplicatedStorage:WaitForChild("Scoreboard.RoundComplete", 10)
		if roundComplete then
			roundComplete.Event:Connect(function(result)
				local player = result.player
				if player and Tutorial:IsActive(player) and not Tutorial:IsStepCompleted(player, "serve") then
					Tutorial:CompleteStep(player, "serve")
					local state = playerStates[player]
					if state == Tutorial.States.PRACTICE then
						System.Debug:Message("Tutorial", player.Name, "completed practice round")
					end
				end
			end)
		end
	end)

	-- Connect RunModes changes (reset on standby)
	task.spawn(function()
		local modeChanged = ReplicatedStorage:WaitForChild("RunModes.ModeChanged", 10)
		if modeChanged then
			modeChanged.Event:Connect(function(data)
				local player = data.player
				local newMode = data.newMode

				if newMode == RunModes.Modes.STANDBY then
					local currentState = playerStates[player]
					if currentState == Tutorial.States.PRACTICE or currentState == Tutorial.States.PLAYING then
						setState(player, Tutorial.States.INACTIVE)
						playerTasks[player] = {}
						System.Debug:Message("Tutorial", player.Name, "returned to standby - tutorial reset")
					end
				end
			end)
			System.Debug:Message("Tutorial", "Connected to RunModes.ModeChanged")
		end
	end)

	-- Setup existing players
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end

	-- Setup new players
	Players.PlayerAdded:Connect(setupPlayer)

	-- Cleanup on player leave
	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
		playerTasks[player] = nil
		Tutorial:_removePlayer(player)
	end)

	System.Debug:Message("Tutorial", "Started")
end

-- Register with System
System:RegisterModule("Tutorial", TutorialModule, { type = "system" })

return TutorialModule
