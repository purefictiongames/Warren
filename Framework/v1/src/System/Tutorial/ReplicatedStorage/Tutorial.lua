--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Tutorial.lua (ReplicatedStorage)
-- Main API module for the Tutorial system
--
-- The Tutorial system provides behavior-driven guidance that transitions
-- players between RunModes. It observes game events and provides hints
-- without modifying game rules.
--
-- Usage:
--   local Tutorial = require(ReplicatedStorage:WaitForChild("Tutorial.Tutorial"))
--   Tutorial:Start(player)
--   if Tutorial:IsActive(player) then ... end

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tutorial = {}

-- Internal state (populated by server script)
local playerStates = {} -- [player] = state string
local playerTasks = {} -- [player] = { [taskId] = completed boolean }
local config = nil

-- Lazy load config
local function getConfig()
	if config then
		return config
	end

	local success, result = pcall(function()
		-- Config is in ReplicatedFirst/Tutorial/TutorialConfig (same pattern as GUI)
		local tutorialFolder = ReplicatedFirst:FindFirstChild("Tutorial")
		if tutorialFolder then
			local configModule = tutorialFolder:FindFirstChild("TutorialConfig")
			if configModule then
				return require(configModule)
			end
		end
		return nil
	end)

	if success and result then
		config = result
	else
		warn("[Tutorial] Config not found in ReplicatedFirst.Tutorial.TutorialConfig, using defaults")
		config = {
			states = {
				INACTIVE = "inactive",
				WELCOME = "welcome",
				COMPLETED = "completed",
			},
			welcome = { title = "Welcome!", body = "Let's get started.", buttons = {} },
			steps = {},
			tasks = {},
		}
	end

	return config
end

-- Expose states as constants
Tutorial.States = {
	INACTIVE = "inactive",
	WELCOME = "welcome",
	FIND_CAMPER = "find_camper",
	RULES = "rules",
	MODE_SELECT = "mode_select",
	PRACTICE = "practice",
	PLAYING = "playing",
	COMPLETED = "completed",
}

--[[
    Get the current tutorial state for a player
    @param player Player - The player to check
    @return string - The current state
--]]
function Tutorial:GetState(player)
	return playerStates[player] or self.States.INACTIVE
end

--[[
    Set the tutorial state for a player (server only)
    @param player Player - The player to set state for
    @param state string - The state to set
    @return boolean - True if state was changed
--]]
function Tutorial:SetState(player, state)
	if not RunService:IsServer() then
		warn("[Tutorial] SetState can only be called on server")
		return false
	end

	-- Internal set (called by server script after firing events)
	if self._setStateInternal then
		self._setStateInternal(player, state)
		return true
	end

	-- Direct set if no server script has registered
	playerStates[player] = state
	return true
end

--[[
    Check if tutorial is active for a player
    @param player Player - The player to check
    @return boolean - True if in an active tutorial state
--]]
function Tutorial:IsActive(player)
	local state = self:GetState(player)
	return state ~= self.States.INACTIVE and state ~= self.States.COMPLETED
end

--[[
    Check if tutorial is completed for a player
    @param player Player - The player to check
    @return boolean - True if tutorial was completed
--]]
function Tutorial:IsCompleted(player)
	return self:GetState(player) == self.States.COMPLETED
end

--[[
    Start the tutorial for a player
    @param player Player - The player to start tutorial for
--]]
function Tutorial:Start(player)
	if not RunService:IsServer() then
		warn("[Tutorial] Start can only be called on server")
		return
	end

	self:SetState(player, self.States.WELCOME)
end

--[[
    Skip the tutorial and mark as completed
    @param player Player - The player to skip for
--]]
function Tutorial:Skip(player)
	if not RunService:IsServer() then
		warn("[Tutorial] Skip can only be called on server")
		return
	end

	self:SetState(player, self.States.COMPLETED)
end

--[[
    Reset tutorial to allow replay
    @param player Player - The player to reset for
--]]
function Tutorial:Reset(player)
	if not RunService:IsServer() then
		warn("[Tutorial] Reset can only be called on server")
		return
	end

	playerTasks[player] = {}
	self:SetState(player, self.States.INACTIVE)
end

--[[
    Complete a task step for a player
    @param player Player - The player
    @param taskId string - The task ID to complete
--]]
function Tutorial:CompleteStep(player, taskId)
	if not RunService:IsServer() then
		warn("[Tutorial] CompleteStep can only be called on server")
		return
	end

	if not playerTasks[player] then
		playerTasks[player] = {}
	end
	playerTasks[player][taskId] = true

	-- Notify via internal handler if registered
	if self._onStepComplete then
		self._onStepComplete(player, taskId)
	end
end

--[[
    Check if a task is completed for a player
    @param player Player - The player
    @param taskId string - The task ID to check
    @return boolean - True if completed
--]]
function Tutorial:IsStepCompleted(player, taskId)
	return playerTasks[player] and playerTasks[player][taskId] == true
end

--[[
    Get all task completion states for a player
    @param player Player - The player
    @return table - Map of taskId to completed boolean
--]]
function Tutorial:GetTaskStates(player)
	return playerTasks[player] or {}
end

--[[
    Get the tutorial configuration
    @return table - The TutorialConfig table
--]]
function Tutorial:GetConfig()
	return getConfig()
end

-- Internal: Allow server script to register handlers
function Tutorial:_registerServerHandlers(setStateFunc, onStepCompleteFunc)
	self._setStateInternal = setStateFunc
	self._onStepComplete = onStepCompleteFunc
end

-- Internal: Direct state update (called by server script)
function Tutorial:_updatePlayerState(player, state)
	playerStates[player] = state
end

-- Internal: Remove player (called on PlayerRemoving)
function Tutorial:_removePlayer(player)
	playerStates[player] = nil
	playerTasks[player] = nil
end

return Tutorial
