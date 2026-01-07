--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- RunModesConfig.lua (ReplicatedFirst)
-- Declarative configuration defining how assets behave in each run mode
--
-- Modes:
--   standby  - Player spawned, exploring, game not active
--   practice - Game active with guidance, no score persistence
--   play     - Full game, scoring persists

return {
	-- Default mode when player spawns
	defaultMode = "standby",

	-- Mode definitions
	modes = {
		--[[
            STANDBY MODE
            Player has spawned but game loop is not active.
            Assets are disabled, HUD is hidden, Camper triggers tutorial.
        --]]
		standby = {
			assets = {
				Dispenser = { active = false, visible = false },
				RoastingStick = { active = false },
				GlobalTimer = { active = false, visible = false },
				Scoreboard = { active = false, visible = false },
				TimedEvaluator = { active = false, visible = false },
				Camper = { active = true, behavior = "tutorial" },
			},
			scoring = {
				persist = false,
				badges = false,
			},
		},

		--[[
            PRACTICE MODE
            Game loop is active with tutorial guidance.
            All assets enabled, but scores are not persisted.
            Camper hidden - TimedEvaluator takes its place.
        --]]
		practice = {
			assets = {
				Dispenser = { active = true, visible = true },
				RoastingStick = { active = true },
				GlobalTimer = { active = true, visible = true },
				Scoreboard = { active = true, visible = true },
				TimedEvaluator = { active = true, visible = true },
				Camper = { active = false },
			},
			scoring = {
				persist = false,
				badges = false,
			},
		},

		--[[
            PLAY MODE
            Full game experience with score persistence and badges.
            Camper hidden - TimedEvaluator takes its place.
        --]]
		play = {
			assets = {
				Dispenser = { active = true, visible = true },
				RoastingStick = { active = true },
				GlobalTimer = { active = true, visible = true },
				Scoreboard = { active = true, visible = true },
				TimedEvaluator = { active = true, visible = true },
				Camper = { active = false },
			},
			scoring = {
				persist = true,
				badges = true,
			},
		},
	},

	-- Valid mode transitions (optional - for validation)
	-- If defined, only these transitions are allowed
	transitions = {
		standby = { "practice", "play" },
		practice = { "standby", "play" },
		play = { "standby" },
	},
}
