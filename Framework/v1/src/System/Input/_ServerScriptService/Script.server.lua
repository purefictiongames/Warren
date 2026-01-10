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
-- Uses two-phase initialization: init() creates state, start() connects events

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Input%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Wait for System module
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

local InputModule = {}

-- Module state (initialized in init())
local InputManager
local RunModes
local RunModesConfig
local inputStateChanged
local pushModalRemote
local popModalRemote
local pushModalFunc
local popModalFunc
local isPromptAllowedFunc
local modeChanged

-- Helper: Get input config for a mode
local function getInputConfig(mode)
	local modeConfig = RunModesConfig.modes and RunModesConfig.modes[mode]
	if modeConfig and modeConfig.input then
		return modeConfig.input
	end
	return {
		prompts = {},
		gameControls = false,
	}
end

-- Apply input configuration for a player's mode
local function applyInputConfig(player, mode)
	local inputConfig = getInputConfig(mode)
	InputManager:_setAllowedPrompts(player, inputConfig.prompts or {})

	local stateData = InputManager:_getStateForReplication(player)
	stateData.gameControls = inputConfig.gameControls
	inputStateChanged:FireClient(player, stateData)

	System.Debug:Message("Input", "Applied input config for", player.Name, "mode:", mode, "prompts:", table.concat(inputConfig.prompts or {}, ", "))
end

-- Handle player joining
local function onPlayerAdded(player)
	InputManager:_initPlayer(player)
	local mode = RunModes:GetMode(player)
	applyInputConfig(player, mode)
	System.Debug:Message("Input", "Initialized player:", player.Name)
end

-- Handle player leaving
local function onPlayerRemoving(player)
	InputManager:_cleanupPlayer(player)
	System.Debug:Message("Input", "Cleaned up player:", player.Name)
end

--[[
    Phase 1: Initialize
    Load dependencies, create events - NO connections yet
--]]
function InputModule:init()
	-- Load dependencies
	InputManager = require(ReplicatedStorage:WaitForChild("Input.InputManager"))
	RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))
	RunModesConfig = require(ServerScriptService:WaitForChild("System"):WaitForChild("RunModes"):WaitForChild("ReplicatedFirst"):WaitForChild("RunModesConfig"))

	-- Get mode changed event reference
	modeChanged = ReplicatedStorage:WaitForChild("RunModes.ModeChanged")

	-- Create events for client communication
	inputStateChanged = Instance.new("RemoteEvent")
	inputStateChanged.Name = "Input.StateChanged"
	inputStateChanged.Parent = ReplicatedStorage

	pushModalRemote = Instance.new("RemoteEvent")
	pushModalRemote.Name = "Input.PushModalRemote"
	pushModalRemote.Parent = ReplicatedStorage

	popModalRemote = Instance.new("RemoteEvent")
	popModalRemote.Name = "Input.PopModalRemote"
	popModalRemote.Parent = ReplicatedStorage

	-- Create BindableFunctions for public API
	pushModalFunc = Instance.new("BindableFunction")
	pushModalFunc.Name = "Input.PushModal"
	pushModalFunc.Parent = ReplicatedStorage

	popModalFunc = Instance.new("BindableFunction")
	popModalFunc.Name = "Input.PopModal"
	popModalFunc.Parent = ReplicatedStorage

	isPromptAllowedFunc = Instance.new("BindableFunction")
	isPromptAllowedFunc.Name = "Input.IsPromptAllowed"
	isPromptAllowedFunc.Parent = ReplicatedStorage
end

--[[
    Phase 2: Start
    Connect events, setup handlers, initialize players
--]]
function InputModule:start()
	-- Setup BindableFunction handlers
	pushModalFunc.OnInvoke = function(player, modalId)
		InputManager:_pushModal(player, modalId)
		local stateData = InputManager:_getStateForReplication(player)
		inputStateChanged:FireClient(player, stateData)
		System.Debug:Message("Input", "Pushed modal for", player.Name, ":", modalId)
		return true
	end

	popModalFunc.OnInvoke = function(player, modalId)
		local success = InputManager:_popModal(player, modalId)
		local stateData = InputManager:_getStateForReplication(player)
		inputStateChanged:FireClient(player, stateData)
		System.Debug:Message("Input", "Popped modal for", player.Name, ":", modalId)
		return success
	end

	isPromptAllowedFunc.OnInvoke = function(player, assetName)
		return InputManager:IsPromptAllowed(player, assetName)
	end

	-- Listen for RunModes changes
	modeChanged.Event:Connect(function(data)
		applyInputConfig(data.player, data.newMode)
	end)

	-- Handle client modal requests
	pushModalRemote.OnServerEvent:Connect(function(player, modalId)
		InputManager:_pushModal(player, modalId)
		local stateData = InputManager:_getStateForReplication(player)
		inputStateChanged:FireClient(player, stateData)
		System.Debug:Message("Input", "Client pushed modal for", player.Name, ":", modalId)
	end)

	popModalRemote.OnServerEvent:Connect(function(player, modalId)
		InputManager:_popModal(player, modalId)
		local stateData = InputManager:_getStateForReplication(player)
		inputStateChanged:FireClient(player, stateData)
		System.Debug:Message("Input", "Client popped modal for", player.Name, ":", modalId)
	end)

	-- Connect player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Initialize existing players
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	System.Debug:Message("Input", "Started")
end

-- Register with System
System:RegisterModule("Input", InputModule, { type = "system" })

return InputModule
