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
-- Level 1: System only (System, System.Script, System.client)
-- Level 2: System + Subsystems (adds System.Player, System.Backpack)
-- Level 3: Assets only (Dispenser, ZoneController, etc.)
-- Level 4: Everything with filtering (uses Filter table)

return {
	Level = 3,  -- Debug: Assets only (shows all asset debug messages)

	-- Filter table (only used at Level 4)
	Filter = {
		enabled = {},
		disabled = {},
	},
}
