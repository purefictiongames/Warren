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
-- Dispatches commands to client for HUD rendering

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Tutorial%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Load Tutorial API
local Tutorial = require(ReplicatedStorage:WaitForChild("Tutorial.Tutorial"))
local tutorialCommand = ReplicatedStorage:WaitForChild("Tutorial.TutorialCommand")
local tutorialStateChanged = ReplicatedStorage:WaitForChild("Tutorial.TutorialStateChanged")

-- Load RunModes API (Tutorial transitions RunModes, not Orchestrator)
local RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))

-- MessageTicker loaded lazily (optional dependency)
local messageTicker = nil
task.spawn(function()
	messageTicker = ReplicatedStorage:WaitForChild("MessageTicker.MessageTicker", 10)
end)

-- DataStore for persistence (optional - may fail in Studio)
local tutorialStore = nil
pcall(function()
	tutorialStore = DataStoreService:GetDataStore("TutorialProgress")
end)

-- Internal state
local playerStates = {} -- [player] = state string
local playerTasks = {} -- [player] = { [taskId] = completed }

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

	-- Fire state changed event
	tutorialStateChanged:Fire({
		player = player,
		oldState = oldState,
		newState = state,
	})

	-- Notify client
	tutorialCommand:FireClient(player, {
		command = "state_changed",
		oldState = oldState,
		newState = state,
	})

	-- Send MessageTicker hints for certain states
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

	-- Notify client to update task list
	tutorialCommand:FireClient(player, {
		command = "task_complete",
		taskId = taskId,
	})

	System.Debug:Message("Tutorial", player.Name, "completed step:", taskId)
end

-- Register handlers with Tutorial API
Tutorial:_registerServerHandlers(setState, onStepComplete)

-- Handle popup button responses from client
local function handleClientResponse(player, data)
	local state = playerStates[player]
	local action = data.action
	local buttonId = data.buttonId

	System.Debug:Message("Tutorial", player.Name, "responded:", action, buttonId)

	if state == Tutorial.States.WELCOME and buttonId == "ok" then
		setState(player, Tutorial.States.FIND_CAMPER)
	elseif state == Tutorial.States.RULES and buttonId == "next" then
		setState(player, Tutorial.States.MODE_SELECT)
	elseif state == Tutorial.States.MODE_SELECT then
		if buttonId == "practice" then
			setState(player, Tutorial.States.PRACTICE)
			-- Transition RunModes to PRACTICE
			RunModes:SetMode(player, RunModes.Modes.PRACTICE)
		elseif buttonId == "play" then
			setState(player, Tutorial.States.PLAYING)
			-- Transition RunModes to PLAY
			RunModes:SetMode(player, RunModes.Modes.PLAY)
			-- Mark tutorial as completed
			setState(player, Tutorial.States.COMPLETED)
			markCompleted(player)
		end
	end
end

-- Listen for client responses
tutorialCommand.OnServerEvent:Connect(handleClientResponse)

-- Listen for Camper interaction (when Camper asset exists)
task.spawn(function()
	local camperInteract = ReplicatedStorage:WaitForChild("Camper.Interact", 30)
	if camperInteract then
		camperInteract.Event:Connect(function(data)
			local player = data.player
			local state = playerStates[player] or Tutorial.States.INACTIVE

			if state == Tutorial.States.FIND_CAMPER then
				setState(player, Tutorial.States.RULES)
			elseif state == Tutorial.States.INACTIVE then
				-- Start tutorial when talking to camper
				setState(player, Tutorial.States.WELCOME)
			elseif state == Tutorial.States.COMPLETED then
				-- Allow replay by talking to camper again
				setState(player, Tutorial.States.RULES)
			end
		end)
		System.Debug:Message("Tutorial", "Connected to Camper.Interact")
	else
		System.Debug:Warn("Tutorial", "Camper.Interact not found - camper integration disabled")
	end
end)

-- Listen for game events to complete tutorial steps
task.spawn(function()
	-- Item added to backpack (grab marshmallow)
	local itemAdded = ReplicatedStorage:WaitForChild("Backpack.ItemAdded", 10)
	if itemAdded then
		itemAdded.Event:Connect(function(data)
			local player = data.player
			if Tutorial:IsActive(player) and not Tutorial:IsStepCompleted(player, "grab") then
				Tutorial:CompleteStep(player, "grab")
			end
		end)
	end

	-- Round complete (serve to camper)
	local roundComplete = ReplicatedStorage:WaitForChild("Scoreboard.RoundComplete", 10)
	if roundComplete then
		roundComplete.Event:Connect(function(result)
			local player = result.player
			if player and Tutorial:IsActive(player) and not Tutorial:IsStepCompleted(player, "serve") then
				Tutorial:CompleteStep(player, "serve")

				-- If in practice mode and all steps complete, offer to continue
				local state = playerStates[player]
				if state == Tutorial.States.PRACTICE then
					-- Could transition to PLAYING or stay in PRACTICE
					System.Debug:Message("Tutorial", player.Name, "completed practice round")
				end
			end
		end)
	end
end)

-- Setup player on join
local function setupPlayer(player)
	-- Check if already completed
	if isCompleted(player) then
		playerStates[player] = Tutorial.States.COMPLETED
		Tutorial:_updatePlayerState(player, Tutorial.States.COMPLETED)
		System.Debug:Message("Tutorial", player.Name, "already completed tutorial")
	else
		-- Start in inactive - player talks to camper to begin
		playerStates[player] = Tutorial.States.INACTIVE
		Tutorial:_updatePlayerState(player, Tutorial.States.INACTIVE)

		-- Auto-start welcome for new players (can be changed to require camper interaction)
		task.delay(2, function()
			if player.Parent and playerStates[player] == Tutorial.States.INACTIVE then
				setState(player, Tutorial.States.WELCOME)
			end
		end)
	end
end

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

System.Debug:Message("Tutorial", "Script loaded")
