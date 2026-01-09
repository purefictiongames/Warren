--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Transition.lua (ReplicatedStorage)
-- Screen transition system for smooth visual transitions between game states
-- Server-side API with client-coordinated timing via events
--
-- Usage:
--   local Transition = require(ReplicatedStorage:WaitForChild("GUI.Transition"))
--   Transition:Start(player, "fade", { class = "transition-fade" })
--   -- Listen for TransitionCovered to know when screen is black
--   -- Call Transition:Reveal(player) when ready to fade back in

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Transition = {}

-- Events (lazy loaded)
local remoteEvent = nil
local startEvent = nil
local coveredEvent = nil
local completeEvent = nil

-- Pending transitions: player -> { config, state }
local pending = {}

-- Initialize events
local function ensureEvents()
	if remoteEvent then return end

	-- Wait for events (deployed by bootstrap with GUI. prefix)
	remoteEvent = ReplicatedStorage:WaitForChild("GUI.TransitionEvent", 5)
	startEvent = ReplicatedStorage:WaitForChild("GUI.TransitionStart", 5)
	coveredEvent = ReplicatedStorage:WaitForChild("GUI.TransitionCovered", 5)
	completeEvent = ReplicatedStorage:WaitForChild("GUI.TransitionComplete", 5)

	if not remoteEvent then
		warn("[Transition] GUI.TransitionEvent RemoteEvent not found")
		return
	end

	-- Listen for client messages (server only)
	if RunService:IsServer() then
		remoteEvent.OnServerEvent:Connect(function(player, data)
			if not data or type(data) ~= "table" then return end

			if data.action == "covered" then
				if coveredEvent then
					coveredEvent:Fire({ player = player })
				end
			elseif data.action == "complete" then
				pending[player] = nil
				if completeEvent then
					completeEvent:Fire({ player = player })
				end
			end
		end)
	end
end

-----------------------------------------------------------
-- Public API
-----------------------------------------------------------

--- Start a screen transition for a player
---@param player Player The player to transition
---@param transitionType string Type of transition ("fade", future: "wipe", "iris")
---@param config table? Optional configuration
---   config.class: string - Style class from Styles.lua (default: "transition-fade")
---   config.duration: number - Override duration in seconds
function Transition:Start(player, transitionType, config)
	ensureEvents()
	if not remoteEvent then return end

	config = config or {}
	config.type = transitionType or "fade"
	config.class = config.class or "transition-fade"

	-- Store pending transition
	pending[player] = {
		config = config,
		state = "covering",
	}

	-- Fire to client
	remoteEvent:FireClient(player, {
		action = "start",
		type = config.type,
		class = config.class,
		duration = config.duration,
	})

	-- Fire server event
	if startEvent then
		startEvent:Fire({ player = player, config = config })
	end
end

--- Signal client to reveal (fade back in)
--- Call this after doing work while screen is covered
---@param player Player The player to reveal
---@param config table? Optional configuration for reveal
---   config.duration: number - Override reveal duration
function Transition:Reveal(player, config)
	ensureEvents()
	if not remoteEvent then return end

	local pendingData = pending[player]
	if not pendingData then return end

	pendingData.state = "revealing"

	-- Fire to client
	remoteEvent:FireClient(player, {
		action = "reveal",
		duration = config and config.duration,
	})
end

--- Get the transition events for listening
---@return table { Start: BindableEvent, Covered: BindableEvent, Complete: BindableEvent }
function Transition:GetEvents()
	ensureEvents()
	return {
		Start = startEvent,
		Covered = coveredEvent,
		Complete = completeEvent,
	}
end

--- Check if a player has a pending transition
---@param player Player The player to check
---@return boolean
function Transition:IsPending(player)
	return pending[player] ~= nil
end

--- Get the current state of a player's transition
---@param player Player The player to check
---@return string? "covering" | "revealing" | nil
function Transition:GetState(player)
	local data = pending[player]
	return data and data.state
end

return Transition
