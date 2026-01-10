--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- System.LocalScript (Client)
-- Client-side boot orchestrator with deterministic module loading
-- Manages client boot stages: WAIT -> DISCOVER -> INIT -> START -> READY
-- Uses explicit module discovery and topological sorting (no timing hacks)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- EARLY BOOTSTRAP: Debug system initialized first
--------------------------------------------------------------------------------

-- Initialize Debug before anything else - it's infrastructure for all modules
local Debug = require(ReplicatedStorage:WaitForChild("System.Debug"))
Debug:Initialize()

-- Now require System (which re-exports Debug as System.Debug)
local System = require(ReplicatedStorage:WaitForChild("System.System"))

-- Create client stage event for other client scripts to wait on
local clientStageEvent = Instance.new("BindableEvent")
clientStageEvent.Name = "System.ClientStage"
clientStageEvent.Parent = ReplicatedStorage
System._clientStageEvent = clientStageEvent

-- Wait for ClientBoot event (server communication)
local ClientBoot = ReplicatedStorage:WaitForChild("System.ClientBoot", 30)

--------------------------------------------------------------------------------
-- SERVER SYNCHRONIZATION (Ping-Pong Protocol)
--------------------------------------------------------------------------------

local PING_TIMEOUT = 5
local responded = false

if ClientBoot then
	System.Debug:Message("System.client", "ClientBoot found, setting up ping-pong")

	-- Listen for server response
	ClientBoot.OnClientEvent:Connect(function(message, stage)
		System.Debug:Message("System.client", "Received from server:", message, stage)
		if message == "PONG" then
			responded = true
			System:_updateFromServer(stage)
		end
	end)

	-- Send ping to server
	System.Debug:Message("System.client", "Sending PING to server")
	ClientBoot:FireServer("PING")

	-- Timeout fallback - assume READY if no response
	task.delay(PING_TIMEOUT, function()
		if not responded then
			System.Debug:Warn("System.client", "Server ping timeout, assuming READY")
			System:_updateFromServer(System.Stages.READY)
		end
	end)
else
	System.Debug:Warn("System.client", "ClientBoot event not found, assuming server ready")
	System:_updateFromServer(System.Stages.READY)
end

--------------------------------------------------------------------------------
-- CLIENT BOOT SEQUENCE
--------------------------------------------------------------------------------

-- Stage 1: WAIT - Wait for server to be READY
System:_setClientStage(System.ClientStages.WAIT)
System.Debug:Message("System.client", "Waiting for server READY, current stage:", System:GetCurrentStage())
System:WaitForStage(System.Stages.READY)
System.Debug:Message("System.client", "Server is READY")

-- Notify server that we received READY
if ClientBoot then
	ClientBoot:FireServer("READY")
end

-- Stage 2: DISCOVER - Find all client modules and build dependency graph
-- System explicitly discovers and requires modules (no self-registration)
System:_setClientStage(System.ClientStages.DISCOVER)
System:_discoverClientModules()

-- Stage 3: INIT - All client module:init() called in dependency order
-- Modules create events/state but do NOT connect to other modules yet
System:_setClientStage(System.ClientStages.INIT)
System:_initAllClientModules()

-- Stage 4: START - All client module:start() called in dependency order
-- Modules can now safely connect events and call other modules
System:_setClientStage(System.ClientStages.START)
System:_startAllClientModules()

-- Stage 5: READY - Client fully ready
System:_setClientStage(System.ClientStages.READY)

System.Debug:Message("System.client", "Client boot complete -", #System:GetClientModuleOrder(), "modules initialized")
