--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Input.Script (Server)
-- Coordinates input state with RunModes changes
-- Manages per-player allowed prompts and modal state

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Input%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Dependencies
local InputManager = require(ReplicatedStorage:WaitForChild("Input.InputManager"))
local RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))

-- RunModesConfig stays in ServerScriptService.System hierarchy (Rojo syncs src/System there)
local ServerScriptService = game:GetService("ServerScriptService")
local RunModesConfig = require(ServerScriptService:WaitForChild("System"):WaitForChild("RunModes"):WaitForChild("ReplicatedFirst"):WaitForChild("RunModesConfig"))

-- Create events for client communication
local inputStateChanged = Instance.new("RemoteEvent")
inputStateChanged.Name = "Input.StateChanged"
inputStateChanged.Parent = ReplicatedStorage

-- Create RemoteEvents for client modal requests (Modal.lua uses these)
local pushModalRemote = Instance.new("RemoteEvent")
pushModalRemote.Name = "Input.PushModalRemote"
pushModalRemote.Parent = ReplicatedStorage

local popModalRemote = Instance.new("RemoteEvent")
popModalRemote.Name = "Input.PopModalRemote"
popModalRemote.Parent = ReplicatedStorage

-- Helper: Get input config for a mode
local function getInputConfig(mode)
	local modeConfig = RunModesConfig.modes and RunModesConfig.modes[mode]
	if modeConfig and modeConfig.input then
		return modeConfig.input
	end
	-- Default: no prompts allowed, no game controls
	return {
		prompts = {},
		gameControls = false,
	}
end

-- Apply input configuration for a player's mode
local function applyInputConfig(player, mode)
	local inputConfig = getInputConfig(mode)

	-- Update allowed prompts
	InputManager:_setAllowedPrompts(player, inputConfig.prompts or {})

	-- Send state update to client
	local stateData = InputManager:_getStateForReplication(player)
	stateData.gameControls = inputConfig.gameControls
	inputStateChanged:FireClient(player, stateData)

	System.Debug:Message("Input", "Applied input config for", player.Name, "mode:", mode, "prompts:", table.concat(inputConfig.prompts or {}, ", "))
end

-- Handle player joining
local function onPlayerAdded(player)
	InputManager:_initPlayer(player)

	-- Get current mode and apply config
	local mode = RunModes:GetMode(player)
	applyInputConfig(player, mode)

	System.Debug:Message("Input", "Initialized player:", player.Name)
end

-- Handle player leaving
local function onPlayerRemoving(player)
	InputManager:_cleanupPlayer(player)
	System.Debug:Message("Input", "Cleaned up player:", player.Name)
end

-- Listen for RunModes changes
local modeChanged = ReplicatedStorage:WaitForChild("RunModes.ModeChanged")
modeChanged.Event:Connect(function(data)
	local player = data.player
	local newMode = data.newMode

	applyInputConfig(player, newMode)
end)

-- Connect player events
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Initialize existing players (in case script runs after players joined)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-----------------------------------------------------------
-- Public API via BindableFunctions
-----------------------------------------------------------

-- Push modal (callable by Tutorial, etc.)
local pushModalFunc = Instance.new("BindableFunction")
pushModalFunc.Name = "Input.PushModal"
pushModalFunc.OnInvoke = function(player, modalId)
	InputManager:_pushModal(player, modalId)

	-- Notify client
	local stateData = InputManager:_getStateForReplication(player)
	inputStateChanged:FireClient(player, stateData)

	System.Debug:Message("Input", "Pushed modal for", player.Name, ":", modalId)
	return true
end
pushModalFunc.Parent = ReplicatedStorage

-- Pop modal (callable by Tutorial, etc.)
local popModalFunc = Instance.new("BindableFunction")
popModalFunc.Name = "Input.PopModal"
popModalFunc.OnInvoke = function(player, modalId)
	local success = InputManager:_popModal(player, modalId)

	-- Notify client
	local stateData = InputManager:_getStateForReplication(player)
	inputStateChanged:FireClient(player, stateData)

	System.Debug:Message("Input", "Popped modal for", player.Name, ":", modalId)
	return success
end
popModalFunc.Parent = ReplicatedStorage

-- Check if prompt allowed (callable by assets)
local isPromptAllowedFunc = Instance.new("BindableFunction")
isPromptAllowedFunc.Name = "Input.IsPromptAllowed"
isPromptAllowedFunc.OnInvoke = function(player, assetName)
	return InputManager:IsPromptAllowed(player, assetName)
end
isPromptAllowedFunc.Parent = ReplicatedStorage

-----------------------------------------------------------
-- Client RemoteEvent handlers (for Modal.lua)
-----------------------------------------------------------

-- Handle client push modal request
pushModalRemote.OnServerEvent:Connect(function(player, modalId)
	InputManager:_pushModal(player, modalId)

	-- Notify client
	local stateData = InputManager:_getStateForReplication(player)
	inputStateChanged:FireClient(player, stateData)

	System.Debug:Message("Input", "Client pushed modal for", player.Name, ":", modalId)
end)

-- Handle client pop modal request
popModalRemote.OnServerEvent:Connect(function(player, modalId)
	InputManager:_popModal(player, modalId)

	-- Notify client
	local stateData = InputManager:_getStateForReplication(player)
	inputStateChanged:FireClient(player, stateData)

	System.Debug:Message("Input", "Client popped modal for", player.Name, ":", modalId)
end)

System.Debug:Message("Input", "Server script initialized")
