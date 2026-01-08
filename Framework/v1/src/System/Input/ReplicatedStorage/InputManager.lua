--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- InputManager.lua (ReplicatedStorage)
-- Centralized input state management coordinated with RunModes
-- Handles per-player input permissions and modal state

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputManager = {}

-- Input states
InputManager.States = {
	WORLD = "world", -- Normal gameplay input
	MODAL = "modal", -- Modal UI has focus, world input disabled
}

-- Per-player state (server tracks all, client tracks local)
local playerInputStates = {} -- player -> { state, allowedPrompts, modalStack }

-- Events (created by server script, used by client)
local inputStateChanged = nil -- RemoteEvent: Server -> Client state updates

-- Initialize player state
local function initPlayerState(player)
	if not playerInputStates[player] then
		playerInputStates[player] = {
			state = InputManager.States.WORLD,
			allowedPrompts = {}, -- Set of asset names whose prompts are allowed
			modalStack = {}, -- Stack of modal IDs
		}
	end
	return playerInputStates[player]
end

-- Clean up player state
local function cleanupPlayerState(player)
	playerInputStates[player] = nil
end

-----------------------------------------------------------
-- Public API
-----------------------------------------------------------

--- Get current input state for a player
---@param player Player
---@return string InputManager.States value
function InputManager:GetState(player)
	local state = playerInputStates[player]
	return state and state.state or InputManager.States.WORLD
end

--- Check if world interaction is allowed for a player
---@param player Player
---@return boolean
function InputManager:IsWorldInputEnabled(player)
	return self:GetState(player) == InputManager.States.WORLD
end

--- Check if a specific prompt/asset is allowed for a player
---@param player Player
---@param assetName string The asset name (e.g., "Dispenser", "Camper")
---@return boolean
function InputManager:IsPromptAllowed(player, assetName)
	local state = playerInputStates[player]
	if not state then return false end

	-- If modal is open, no prompts allowed
	if state.state == InputManager.States.MODAL then
		return false
	end

	-- Check if this asset's prompts are in the allowed set
	return state.allowedPrompts[assetName] == true
end

--- Get list of allowed prompt asset names for a player
---@param player Player
---@return table Array of asset names
function InputManager:GetAllowedPrompts(player)
	local state = playerInputStates[player]
	if not state then return {} end

	local result = {}
	for assetName, allowed in pairs(state.allowedPrompts) do
		if allowed then
			table.insert(result, assetName)
		end
	end
	return result
end

-----------------------------------------------------------
-- Server-only API (called from Input server script)
-----------------------------------------------------------

--- Set allowed prompts for a player (server only)
---@param player Player
---@param promptList table Array of asset names whose prompts should be enabled
function InputManager:_setAllowedPrompts(player, promptList)
	local state = initPlayerState(player)

	-- Clear existing
	state.allowedPrompts = {}

	-- Set new allowed prompts
	for _, assetName in ipairs(promptList) do
		state.allowedPrompts[assetName] = true
	end
end

--- Push a modal onto the stack (server only)
---@param player Player
---@param modalId string Unique identifier for the modal
function InputManager:_pushModal(player, modalId)
	local state = initPlayerState(player)
	table.insert(state.modalStack, modalId)
	state.state = InputManager.States.MODAL
end

--- Pop a modal from the stack (server only)
---@param player Player
---@param modalId string The modal ID to remove (validates it's on top)
---@return boolean Success
function InputManager:_popModal(player, modalId)
	local state = playerInputStates[player]
	if not state then return false end

	-- Find and remove the modal
	for i = #state.modalStack, 1, -1 do
		if state.modalStack[i] == modalId then
			table.remove(state.modalStack, i)
			break
		end
	end

	-- Restore state if stack is empty
	if #state.modalStack == 0 then
		state.state = InputManager.States.WORLD
	end

	return true
end

--- Initialize a player (server only, called when player joins)
---@param player Player
function InputManager:_initPlayer(player)
	initPlayerState(player)
end

--- Clean up a player (server only, called when player leaves)
---@param player Player
function InputManager:_cleanupPlayer(player)
	cleanupPlayerState(player)
end

--- Get the full state for a player (for replication to client)
---@param player Player
---@return table State data
function InputManager:_getStateForReplication(player)
	local state = playerInputStates[player]
	if not state then
		return {
			state = InputManager.States.WORLD,
			allowedPrompts = {},
		}
	end

	return {
		state = state.state,
		allowedPrompts = self:GetAllowedPrompts(player),
	}
end

-----------------------------------------------------------
-- Client-only API (used by Input client script)
-----------------------------------------------------------

--- Update local state from server (client only)
---@param stateData table State data from server
function InputManager:_updateFromServer(stateData)
	-- On client, we only track local player
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if not player then return end

	local state = initPlayerState(player)
	state.state = stateData.state or InputManager.States.WORLD

	-- Convert array back to set
	state.allowedPrompts = {}
	for _, assetName in ipairs(stateData.allowedPrompts or {}) do
		state.allowedPrompts[assetName] = true
	end
end

return InputManager
