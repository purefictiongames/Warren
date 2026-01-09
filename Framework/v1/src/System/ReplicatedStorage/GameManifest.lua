--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- GameManifest.ModuleScript
-- Declarative configuration for asset deployment and wiring
-- Defines which asset templates to instantiate and how to connect them

return {
	-- Asset instantiation
	-- Each entry clones a template from Assets/ and deploys it with the given alias
	-- Format: { use = "TemplateName", as = "InstanceName" }
	assets = {
		{ use = "Dispenser", as = "MarshmallowBag" },
		{ use = "Camper", as = "Camper" },
		{ use = "GlobalTimer", as = "GlobalTimer" },
		{ use = "Scoreboard", as = "Scoreboard" },
		{ use = "TimedEvaluator", as = "TimedEvaluator" },
		{ use = "Orchestrator", as = "Orchestrator" },
		{ use = "RoastingStick", as = "RoastingStick" },
		{ use = "LeaderBoard", as = "LeaderBoard" },
		{ use = "MessageTicker", as = "MessageTicker" },
		{ use = "ZoneController", as = "ZoneController" },
	},

	-- Event wiring
	-- Format: { from = "AssetName.EventName", to = "AssetName.EventName" }
	-- Connects Output events to Input events for black box communication
	wiring = {
		-- Asset Outputs → Orchestrator Input
		{ from = "GlobalTimer.Output", to = "Orchestrator.Input" },
		{ from = "MarshmallowBag.Output", to = "Orchestrator.Input" },
		{ from = "Scoreboard.Output", to = "Orchestrator.Input" },

		-- Scoreboard Output → LeaderBoard Input (score updates)
		{ from = "Scoreboard.Output", to = "LeaderBoard.Input" },

		-- RunModes (system event - still custom for now)
		{ from = "RunModes.ModeChanged", to = "Orchestrator.Input" },
	}
}
