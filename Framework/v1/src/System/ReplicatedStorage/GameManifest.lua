--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- GameManifest.ModuleScript
-- Declarative configuration for asset deployment and wiring
-- Defines which Lib/Game templates to instantiate and how to connect them
--
-- Grammar:
--   configuredTemplates - Pre-merged templates (Lib base + game model/attributes)
--   instances           - Lib-based assets with optional extensions (from src/Lib/)
--   gameAssets          - Game-specific assets without Lib base (from src/Game/)
--   wiring              - Event connections between assets

return {
	--------------------------------------------------------------------------------
	-- Configured Templates
	-- Pre-merge Lib templates with game-specific models/attributes at bootstrap
	-- These become available in ReplicatedStorage.Templates for runtime spawning
	-- Format: { base = "LibName", alias = "TemplateName", model = "...", attributes = {} }
	--------------------------------------------------------------------------------
	configuredTemplates = {
		-- CamperEvaluator: TimedEvaluator with game-specific camper visuals
		{
			base = "TimedEvaluator",
			alias = "CamperEvaluator",
			model = "Game.CamperEvaluator.Model",
			attributes = {
				TimeoutBehavior = "despawn", -- What to do when timer expires
			},
		},
		-- CampDropper: Dropper configured to spawn CamperEvaluators
		{
			base = "Dropper",
			alias = "CampDropper",
			attributes = {
				DropTemplate = "CamperEvaluator",
				SpawnMode = "onDemand", -- WaveController controls spawning
				SpawnOffset = Vector3.new(0, 2, -3), -- Move NPC up 2 and forward 3 (toward campfire, out of tent)
			},
		},
	},

	--------------------------------------------------------------------------------
	-- Lib Instances
	-- Generic library modules with optional game-specific extensions
	-- Format: { lib = "LibName", alias = "InstanceName", extension = "Game.Folder.Extension" }
	--------------------------------------------------------------------------------
	instances = {
		-- Dispenser with MarshmallowBag extension and game-specific model
		{
			lib = "Dispenser",
			alias = "MarshmallowBag",
			extension = "Game.MarshmallowBag.Extension",
			model = "Game.MarshmallowBag.Model",
			attributes = {
				DispenseItem = "Marshmallow",
				Capacity = 10,
			},
		},

		-- Timers (generic, no extension needed)
		{
			lib = "GlobalTimer",
			alias = "PlayTimer",
			attributes = {
				CountdownStart = 3.00,
				TimerMode = "duration",
			},
		},
		{
			lib = "GlobalTimer",
			alias = "CountdownTimer",
			attributes = {
				CountdownStart = 0.03,
				TimerMode = "sequence",
				TextSequence = "ready...,set...,go!",
			},
		},

		-- WaveController with game-specific extension
		{
			lib = "WaveController",
			alias = "WaveController",
			extension = "Game.WaveController.Extension",
			attributes = {
				TentTemplate = "CampDropper", -- Matches ArrayPlacer spawn naming
			},
		},

		-- ArrayPlacer for spawning CampDroppers (pre-configured Dropper+CamperEvaluator)
		{
			lib = "ArrayPlacer",
			alias = "CampPlacer",
			attributes = {
				Spawns = "CampDropper", -- Pre-configured template from configuredTemplates
				Count = 4,
				CenterOn = "Campfire",
				AnchorSizeX = 20,
				AnchorSizeY = 0.5,
				AnchorSizeZ = 40,
			},
		},

		-- Generic UI/display assets (no extension needed)
		{ lib = "LeaderBoard", alias = "LeaderBoard" },
		{ lib = "MessageTicker", alias = "MessageTicker" },

		-- Zone detection
		{ lib = "ZoneController", alias = "Campfire" },
	},

	--------------------------------------------------------------------------------
	-- Game Assets
	-- Game-specific assets that live entirely in the Game folder
	-- Format: { use = "TemplateName", as = "InstanceName" }
	--------------------------------------------------------------------------------
	gameAssets = {
		{ use = "Orchestrator", as = "Orchestrator" },
		{ use = "Scoreboard", as = "Scoreboard" },
		{ use = "Camper", as = "Camper" },
		{ use = "RoastingStick", as = "RoastingStick" },
	},

	--------------------------------------------------------------------------------
	-- Event Wiring
	-- Static routes for non-targeted messages
	-- Targeted messages (with message.target) are routed by System.Router
	--------------------------------------------------------------------------------
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
	},
}
