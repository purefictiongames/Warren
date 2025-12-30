-- DebugConfig.ModuleScript (ReplicatedFirst)
-- Controls debug output filtering across the framework
--
-- Level 1: System only (System, System.Script, System.client)
-- Level 2: System + Subsystems (adds System.Player, System.Backpack)
-- Level 3: Assets only (Dispenser, ZoneController, etc.)
-- Level 4: Everything with filtering (uses Filter table)

return {
	Level = 2,  -- Default: System + Subsystems

	-- Filter table (only used at Level 4)
	-- Rules processed: enabled checked first, then disabled
	-- Glob patterns: "*" matches any sequence
	Filter = {
		-- Enable specific sources (checked first - if match, ALLOW)
		enabled = {
			-- "System.*",        -- All system sources
			-- "Dispenser",       -- Specific asset
		},

		-- Disable specific sources (checked second - if match, BLOCK)
		disabled = {
			-- "TimedEvaluator",  -- Too verbose
			-- "ZoneController",  -- Hide zone messages
		},
	},
}
