--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- RunModes.lua (ReplicatedStorage)
-- Main API module for the Run Modes system
--
-- Run Modes controls per-player game state (standby, practice, play).
-- Orchestrator and other systems read mode config to determine asset behavior.
--
-- Usage:
--   local RunModes = require(ReplicatedStorage:WaitForChild("RunModes.RunModes"))
--   RunModes:SetMode(player, RunModes.Modes.PRACTICE)
--   if RunModes:IsGameActive(player) then ... end

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RunModes = {}

-- Mode constants
RunModes.Modes = {
	STANDBY = "standby",
	PRACTICE = "practice",
	PLAY = "play",
}

-- Internal state (populated by server script)
local playerModes = {} -- [player] = mode string
local config = nil -- Loaded from RunModesConfig.lua

-- Lazy load config
local function getConfig()
	if config then
		return config
	end

	local success, result = pcall(function()
		-- Config is in ReplicatedFirst/RunModes/RunModesConfig (same pattern as GUI)
		local runModesFolder = ReplicatedFirst:FindFirstChild("RunModes")
		if runModesFolder then
			local configModule = runModesFolder:FindFirstChild("RunModesConfig")
			if configModule then
				return require(configModule)
			end
		end
		return nil
	end)

	if success and result then
		config = result
	else
		warn("[RunModes] Config not found in ReplicatedFirst.RunModes.RunModesConfig, using defaults")
		config = {
			defaultMode = "standby",
			modes = {
				standby = { assets = {}, scoring = { persist = false, badges = false } },
				practice = { assets = {}, scoring = { persist = false, badges = false } },
				play = { assets = {}, scoring = { persist = true, badges = true } },
			},
		}
	end

	return config
end

--[[
    Get the current mode for a player
    @param player Player - The player to check
    @return string - The current mode ("standby", "practice", "play")
--]]
function RunModes:GetMode(player)
	return playerModes[player] or getConfig().defaultMode
end

--[[
    Set the mode for a player (server only)
    @param player Player - The player to set mode for
    @param mode string - The mode to set
    @return boolean - True if mode was changed
--]]
function RunModes:SetMode(player, mode)
	if not RunService:IsServer() then
		warn("[RunModes] SetMode can only be called on server")
		return false
	end

	-- Validate mode exists
	local cfg = getConfig()
	if not cfg.modes[mode] then
		warn("[RunModes] Invalid mode:", mode)
		return false
	end

	-- Check if transition is valid (if transitions are defined)
	local currentMode = self:GetMode(player)
	if cfg.transitions and cfg.transitions[currentMode] then
		local validTransitions = cfg.transitions[currentMode]
		local isValid = false
		for _, validMode in ipairs(validTransitions) do
			if validMode == mode then
				isValid = true
				break
			end
		end
		if not isValid then
			warn("[RunModes] Invalid transition from", currentMode, "to", mode)
			return false
		end
	end

	-- Internal set (called by server script after firing events)
	if self._setModeInternal then
		self._setModeInternal(player, mode)
		return true
	end

	-- Direct set if no server script has registered
	playerModes[player] = mode
	return true
end

--[[
    Get the configuration for a specific mode
    @param mode string - The mode name
    @return table - The mode configuration
--]]
function RunModes:GetConfig(mode)
	local cfg = getConfig()
	return cfg.modes[mode]
end

--[[
    Get the full configuration
    @return table - The complete RunModesConfig
--]]
function RunModes:GetFullConfig()
	return getConfig()
end

--[[
    Check if the game is active for a player (practice or play mode)
    @param player Player - The player to check
    @return boolean - True if in practice or play mode
--]]
function RunModes:IsGameActive(player)
	local mode = self:GetMode(player)
	return mode == self.Modes.PRACTICE or mode == self.Modes.PLAY
end

--[[
    Check if scoring should be persisted for a player
    @param player Player - The player to check
    @return boolean - True if scores should be persisted
--]]
function RunModes:IsScoringEnabled(player)
	local mode = self:GetMode(player)
	local modeConfig = self:GetConfig(mode)
	return modeConfig and modeConfig.scoring and modeConfig.scoring.persist == true
end

--[[
    Check if badges are enabled for a player
    @param player Player - The player to check
    @return boolean - True if badges are enabled
--]]
function RunModes:AreBadgesEnabled(player)
	local mode = self:GetMode(player)
	local modeConfig = self:GetConfig(mode)
	return modeConfig and modeConfig.scoring and modeConfig.scoring.badges == true
end

--[[
    Get all players in a specific mode
    @param mode string - The mode to filter by
    @return table - Array of players in that mode
--]]
function RunModes:GetPlayersInMode(mode)
	local players = {}
	if self._getPlayerModes then
		local modes = self._getPlayerModes()
		for player, playerMode in pairs(modes) do
			if playerMode == mode then
				table.insert(players, player)
			end
		end
	end
	return players
end

--[[
    Get asset settings for a specific asset in a mode
    @param mode string - The mode name
    @param assetName string - The asset name
    @return table|nil - Asset settings or nil if not defined
--]]
function RunModes:GetAssetSettings(mode, assetName)
	local modeConfig = self:GetConfig(mode)
	if modeConfig and modeConfig.assets then
		return modeConfig.assets[assetName]
	end
	return nil
end

-- Internal: Allow server script to register mode tracking
function RunModes:_registerServerHandlers(setModeFunc, getModesFunc)
	self._setModeInternal = setModeFunc
	self._getPlayerModes = getModesFunc
end

-- Internal: Direct mode update (called by server script)
function RunModes:_updatePlayerMode(player, mode)
	playerModes[player] = mode
end

-- Internal: Remove player (called on PlayerRemoving)
function RunModes:_removePlayer(player)
	playerModes[player] = nil
end

return RunModes
