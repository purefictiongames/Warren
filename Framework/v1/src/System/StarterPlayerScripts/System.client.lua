--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- System.LocalScript (Client)
-- Client-side boot handler with ping-pong protocol

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for System module (deployed by System.Script)
local System = require(ReplicatedStorage:WaitForChild("System.System"))

-- Wait for ClientBoot event
local ClientBoot = ReplicatedStorage:WaitForChild("System.ClientBoot", 30)

if not ClientBoot then
	System.Debug:Warn("System.client", "ClientBoot event not found, assuming server ready")
	System:_updateFromServer(System.Stages.READY)
	return
end

local PING_TIMEOUT = 5
local responded = false

-- Listen for server response
ClientBoot.OnClientEvent:Connect(function(message, stage)
	if message == "PONG" then
		responded = true
		System:_updateFromServer(stage)
	end
end)

-- Send ping to server
ClientBoot:FireServer("PING")

-- Timeout fallback - assume READY if no response
task.delay(PING_TIMEOUT, function()
	if not responded then
		System.Debug:Warn("System.client", "Server ping timeout, assuming READY")
		System:_updateFromServer(System.Stages.READY)
	end
end)

-- Wait until we're at READY stage, then signal back
task.spawn(function()
	System:WaitForStage(System.Stages.READY)
	if ClientBoot then
		ClientBoot:FireServer("READY")
	end
	System.Debug:Message("System.client", "Ready")
end)
