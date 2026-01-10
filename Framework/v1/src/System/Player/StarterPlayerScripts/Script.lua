--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Player.module (Client)
-- Client-side player system
-- Discovered and loaded by System.client.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for System module (for Debug logging)
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

return {
	dependencies = {},  -- No dependencies

	init = function(self)
		-- Nothing to initialize currently
	end,

	start = function(self)
		System.Debug:Message("System.Player.client", "Started")
	end,
}
