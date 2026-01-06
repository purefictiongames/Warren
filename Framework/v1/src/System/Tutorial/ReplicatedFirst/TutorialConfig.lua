--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- TutorialConfig.lua (ReplicatedFirst)
-- Declarative configuration for the Tutorial system
-- Defines flow states, popup content, step hints, and task list items

return {
	-- Tutorial states
	states = {
		INACTIVE = "inactive",
		WELCOME = "welcome",
		FIND_CAMPER = "find_camper",
		RULES = "rules",
		MODE_SELECT = "mode_select",
		PRACTICE = "practice",
		PLAYING = "playing",
		COMPLETED = "completed",
	},

	-- Welcome popup content
	welcome = {
		title = "Welcome to Toast a Marshmallow!",
		body = "Roast marshmallows to perfection and serve happy campers. The better your timing, the higher your score!",
		buttons = {
			{ id = "ok", text = "Let's Go!", primary = true },
		},
	},

	-- Rules popup content
	rules = {
		title = "How to Play",
		body = "1. Grab a marshmallow from the dispenser\n2. Roast it over the campfire\n3. Serve it to the camper before time runs out\n\nWatch the toast level - aim for the target!",
		buttons = {
			{ id = "next", text = "Got It!", primary = true },
		},
	},

	-- Mode selection popup
	modeSelect = {
		title = "Ready to Start?",
		body = "Would you like to practice first or jump right in?",
		buttons = {
			{ id = "practice", text = "Practice", primary = false },
			{ id = "play", text = "Play!", primary = true },
		},
	},

	-- In-game step hints (shown via MessageTicker)
	steps = {
		{ id = "grab", message = "Grab a marshmallow from the dispenser!", event = "Backpack.ItemAdded" },
		{ id = "roast", message = "Toast it over the campfire!", event = "zone_enter" },
		{ id = "serve", message = "Give it to the camper!", event = "Scoreboard.RoundComplete" },
	},

	-- Task list items (shown in HUD during tutorial)
	tasks = {
		{ id = "grab", text = "Get a marshmallow", completedOn = "Backpack.ItemAdded" },
		{ id = "roast", text = "Roast at the fire", completedOn = "zone_enter" },
		{ id = "serve", text = "Serve to camper", completedOn = "Scoreboard.RoundComplete" },
	},

	-- Highlight targets (shown during find_camper state)
	highlights = {
		find_camper = "Camper",
	},
}
