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
	-- Format: { use = "TemplateName", as = "InstanceName", drops = "Template" (for Droppers) }
	assets = {
		{ use = "Dispenser", as = "MarshmallowBag" },
		{ use = "Camper", as = "Camper" },
		{ use = "GlobalTimer", as = "PlayTimer" },
		{ use = "GlobalTimer", as = "CountdownTimer" },
		{ use = "Scoreboard", as = "Scoreboard" },
		{ use = "WaveController", as = "WaveController" },
		{ use = "ArrayPlacer", as = "CampPlacer", spawns = "Dropper", count = 4, centerOn = "Campfire", anchorSizeX = 20, anchorSizeY = 0.5, anchorSizeZ = 40 },
		{ use = "Orchestrator", as = "Orchestrator" },
		{ use = "RoastingStick", as = "RoastingStick" },
		{ use = "LeaderBoard", as = "LeaderBoard" },
		{ use = "MessageTicker", as = "MessageTicker" },
		{ use = "ZoneController", as = "Campfire" },
	},

	-- Event wiring (static routes for non-targeted messages)
	-- Format: { from = "AssetName.EventName", to = "AssetName.EventName" }
	--
	-- Note: Targeted messages (with message.target) are routed by System.Router
	-- This wiring is for non-targeted action-based events that use static routing
	wiring = {
		-- Asset Outputs → Orchestrator Input (game flow events)
		{ from = "PlayTimer.Output", to = "Orchestrator.Input" },
		{ from = "CountdownTimer.Output", to = "Orchestrator.Input" },
		{ from = "MarshmallowBag.Output", to = "Orchestrator.Input" },
		{ from = "Scoreboard.Output", to = "Orchestrator.Input" },

		-- Orchestrator → WaveController (game signals: gameStarted, wavePaused, etc.)
		{ from = "Orchestrator.Output", to = "WaveController.Input" },

		-- CampPlacer → WaveController (camper status: spawned/despawned/fed)
		{ from = "CampPlacer.Output", to = "WaveController.Input" },

		-- CampPlacer → Scoreboard (evaluation results for scoring)
		{ from = "CampPlacer.Output", to = "Scoreboard.Input" },

		-- Scoreboard Output → LeaderBoard Input (score updates)
		{ from = "Scoreboard.Output", to = "LeaderBoard.Input" },

		-- RunModes (system event)
		{ from = "RunModes.ModeChanged", to = "Orchestrator.Input" },
	}
}
