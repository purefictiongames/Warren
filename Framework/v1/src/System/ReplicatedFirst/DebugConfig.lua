--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- DebugConfig.ModuleScript (ReplicatedFirst)
-- Controls debug output filtering across the framework
--
-- Priority Levels (from highest to lowest):
--   Critical - Always shown (bootstrap, errors, warnings)
--   Info     - Normal messages (default output level)
--   Verbose  - Debug/trace messages (detailed logging)
--
-- Categories:
--   System      - Core framework (System.Script, System.System, etc.)
--   Subsystems  - Framework subsystems (System.Player, System.Backpack, System.GUI, etc.)
--   Assets      - Game assets (MarshmallowBag, Orchestrator, etc.)
--   RunModes    - Run mode system
--   Tutorial    - Tutorial system
--   Input       - Input handling system

return {
	-- Priority threshold: "Critical", "Info", or "Verbose"
	-- Critical: Only bootstrap, errors, warnings
	-- Info: Critical + normal messages
	-- Verbose: Everything
	priorityThreshold = "Info",

	-- Category filtering (true = enabled, false = disabled)
	-- Categories not listed default to true (enabled)
	categories = {
		System = true,      -- Core framework
		Subsystems = true,  -- Framework subsystems
		Assets = true,      -- Game assets
		RunModes = true,    -- Run mode system
		Tutorial = true,    -- Tutorial system
		Input = true,       -- Input handling
	},

	-- Advanced filtering with glob patterns (optional)
	-- These override category filtering
	filter = {
		enabled = {},   -- Always show these patterns (e.g., "System.*", "Orchestrator")
		disabled = {},  -- Never show these patterns (e.g., "*.Tick", "ZoneController")
	},
}
