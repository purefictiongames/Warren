--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Input.Script (Client)
-- Handles client-side input state and ProximityPrompt visibility filtering

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Input%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Dependencies
local InputManager = require(ReplicatedStorage:WaitForChild("Input.InputManager"))

local player = Players.LocalPlayer

-- Current state
local currentState = {
	state = InputManager.States.WORLD,
	allowedPrompts = {},
	gameControls = false,
}

-- Convert allowed prompts array to set for fast lookup
local allowedPromptsSet = {}

-- Helper: Get asset name from a ProximityPrompt
local function getAssetNameFromPrompt(prompt)
	-- Walk up the hierarchy to find the asset model in RuntimeAssets
	local current = prompt.Parent
	while current do
		if current.Parent and current.Parent.Name == "RuntimeAssets" then
			return current.Name
		end
		current = current.Parent
	end
	return nil
end

-- Update allowed prompts set
local function updateAllowedPromptsSet(promptList)
	allowedPromptsSet = {}
	for _, assetName in ipairs(promptList) do
		allowedPromptsSet[assetName] = true
	end
end

-- Handle state updates from server
local function onStateChanged(stateData)
	currentState = stateData
	updateAllowedPromptsSet(stateData.allowedPrompts or {})

	-- Update InputManager local state
	InputManager:_updateFromServer(stateData)

	System.Debug:Message("Input.client", "State updated - allowed prompts:", table.concat(stateData.allowedPrompts or {}, ", "))
end

-- Filter prompt visibility based on current state
-- This intercepts prompt display before it happens
local function shouldShowPrompt(prompt)
	-- If in modal state, hide all world prompts
	if currentState.state == InputManager.States.MODAL then
		return false
	end

	-- Check if the prompt's asset is allowed
	local assetName = getAssetNameFromPrompt(prompt)
	if assetName and allowedPromptsSet[assetName] then
		return true
	end

	-- Default: check if prompt is globally enabled and we have no filter
	-- (backwards compatibility for prompts not in RuntimeAssets)
	if not assetName then
		return true
	end

	return false
end

-- Connect to PromptShown to filter visibility
-- Note: This doesn't prevent the prompt from showing, but we can use it for tracking
ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	-- We can't directly hide the prompt from PromptShown
	-- But we can track which prompts are visible for debugging
	local assetName = getAssetNameFromPrompt(prompt)
	local allowed = shouldShowPrompt(prompt)

	if not allowed and assetName then
		System.Debug:Message("Input.client", "Prompt shown but not allowed:", assetName)
	end
end)

-- The actual filtering happens via prompt.Enabled which is controlled server-side
-- This client script primarily handles:
-- 1. Tracking local input state
-- 2. Future: Additional client-side input blocking for modals

-- Listen for server state updates
local inputStateChanged = ReplicatedStorage:WaitForChild("Input.StateChanged")
inputStateChanged.OnClientEvent:Connect(onStateChanged)

-- Expose local state check for other client scripts
-- They can require InputManager and use its API

System.Debug:Message("Input.client", "Client script initialized")
