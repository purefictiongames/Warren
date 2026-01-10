--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Input.module (Client)
-- Handles client-side input state and ProximityPrompt visibility filtering
-- Discovered and loaded by System.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- Wait for System module
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE STATE
--------------------------------------------------------------------------------

local InputManager
local inputStateChanged
local currentState
local allowedPromptsSet = {}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Get asset name from a ProximityPrompt
local function getAssetNameFromPrompt(prompt)
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
	InputManager:_updateFromServer(stateData)
	System.Debug:Message("Input.client", "State updated - allowed prompts:", table.concat(stateData.allowedPrompts or {}, ", "))
end

-- Filter prompt visibility based on current state
local function shouldShowPrompt(prompt)
	if currentState.state == InputManager.States.MODAL then
		return false
	end

	local assetName = getAssetNameFromPrompt(prompt)
	if assetName and allowedPromptsSet[assetName] then
		return true
	end

	if not assetName then
		return true
	end

	return false
end

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

return {
	dependencies = {},  -- No dependencies

	init = function(self)
		InputManager = require(ReplicatedStorage:WaitForChild("Input.InputManager"))

		currentState = {
			state = InputManager.States.WORLD,
			allowedPrompts = {},
			gameControls = false,
		}

		inputStateChanged = ReplicatedStorage:WaitForChild("Input.StateChanged")
	end,

	start = function(self)
		-- Connect to PromptShown for tracking
		ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
			local assetName = getAssetNameFromPrompt(prompt)
			local allowed = shouldShowPrompt(prompt)

			if not allowed and assetName then
				System.Debug:Message("Input.client", "Prompt shown but not allowed:", assetName)
			end
		end)

		-- Listen for server state updates
		inputStateChanged.OnClientEvent:Connect(onStateChanged)

		System.Debug:Message("Input.client", "Started")
	end,
}
