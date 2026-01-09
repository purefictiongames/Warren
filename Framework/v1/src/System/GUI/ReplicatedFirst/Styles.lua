--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Styles.ModuleScript (ReplicatedFirst)
-- Stylesheet definitions for the GUI system
-- Loaded earliest for fastest access
--
-- Cascade order: base → class (in attribute order) → id → inline
--
-- Shorthand syntax:
--   size = {0.5, 0, 100, 0}     → UDim2.new(0.5, 0, 100, 0)
--   textColor = {255, 170, 0}  → Color3.fromRGB(255, 170, 0)
--   font = "Bangers"           → Enum.Font.Bangers

return {
	-- Base styles applied to all elements of a type
	base = {
		-- GUI Base Styles
		TextLabel = {
			backgroundTransparency = 1,
			font = "SourceSans",
			textColor = {255, 255, 255},
		},
		TextButton = {
			backgroundTransparency = 0.2,
			backgroundColor = {60, 60, 60},
			font = "SourceSans",
			textColor = {255, 255, 255},
		},
		Frame = {
			backgroundTransparency = 0.1,
			backgroundColor = {30, 30, 30},
		},
		ImageLabel = {
			backgroundTransparency = 1,
		},
		ImageButton = {
			backgroundTransparency = 1,
		},

		-- Asset Base Styles (3D objects)
		Model = {
			-- Default styles for all models (if any)
		},
		BasePart = {
			-- Default styles for all parts (if any)
		},
	},

	-- Class styles (applied by class="..." attribute)
	-- Multiple classes applied in order: class="first second third"
	classes = {
		-- Typography
		["hud-text"] = {
			textSize = 24,
			font = "GothamBold",
		},
		["hud-large"] = {
			textSize = 36,
		},
		["hud-small"] = {
			textSize = 16,
		},

		-- Colors
		["gold"] = {
			textColor = {255, 170, 0},
		},
		["white"] = {
			textColor = {255, 255, 255},
		},
		["red"] = {
			textColor = {255, 80, 80},
		},
		["green"] = {
			textColor = {80, 255, 80},
		},

		-- Layout
		["centered"] = {
			anchorPoint = {0.5, 0.5},
		},
		["centered-x"] = {
			anchorPoint = {0.5, 0},
		},
		["centered-y"] = {
			anchorPoint = {0, 0.5},
		},

		-- Visibility
		["hidden"] = {
			visible = false,
		},

		-- Transparency
		["transparent"] = {
			backgroundTransparency = 1,
		},
		["semi-transparent"] = {
			backgroundTransparency = 0.5,
		},

		-- Responsive text styles
		["responsive-text"] = {
			textSize = 24,
			textColor = {100, 200, 255},  -- Blue for desktop
		},
		["responsive-text@tablet"] = {
			textSize = 20,
			textColor = {255, 200, 100},  -- Orange for tablet
		},
		["responsive-text@phone"] = {
			textSize = 16,
			textColor = {255, 100, 100},  -- Red for phone
		},

		-- Button with pseudo-classes (Phase 7)
		["btn"] = {
			backgroundColor = {80, 80, 100},
			textColor = {255, 255, 255},
			textSize = 16,
			backgroundTransparency = 0,
		},
		["btn:hover"] = {
			backgroundColor = {100, 100, 140},
		},
		["btn:active"] = {
			backgroundColor = {60, 60, 80},
		},
		["btn:disabled"] = {
			backgroundColor = {50, 50, 50},
			textColor = {120, 120, 120},
		},

		-- Dynamic class for Phase 9 testing
		["highlight"] = {
			backgroundColor = {100, 150, 100},
		},

		-- MessageTicker styles
		["ticker-text"] = {
			font = "Bangers",
			textSize = 36,
			textColor = {255, 170, 0},
			backgroundTransparency = 1,
		},

		-- Countdown timer styles (ready/set/go sequence)
		["countdown-text"] = {
			font = "Bangers",
			textSize = 72,
			textColor = {255, 170, 0},
			backgroundTransparency = 1,
		},
		["countdown-number"] = {
			font = "Bangers",
			textSize = 120,
			textColor = {255, 170, 0},
			backgroundTransparency = 1,
		},

		-- Dispenser styles
		["dispenser-frame"] = {
			backgroundColor = {255, 255, 255},
			backgroundTransparency = 0.8,
		},
		["dispenser-text"] = {
			font = "GothamBold",
			textSize = 28,
			textColor = {255, 170, 0},
			backgroundTransparency = 1,
		},

		-- Shared HUD panel styles (used by GlobalTimer, Scoreboard, etc.)
		["hud-panel"] = {
			size = {0.9, -10, 0.7, 0},
			backgroundColor = {0, 0, 80},
			backgroundTransparency = 0.8,
			cornerRadius = 12,
			stroke = { color = {255, 255, 255}, thickness = 1 },
		},
		["hud-header"] = {
			font = "Bangers",
			textSize = 36,
			textColor = {255, 170, 0},
			backgroundTransparency = 1,
		},
		["hud-value"] = {
			font = "GothamBlack",
			textSize = 44,
			textColor = {255, 255, 255},
			backgroundTransparency = 1,
		},

		-- Screen transitions
		["transition-fade"] = {
			backgroundColor = {0, 0, 0},
			duration = 0.5,
		},
		["transition-fade-slow"] = {
			backgroundColor = {0, 0, 0},
			duration = 1.0,
		},
		["transition-white"] = {
			backgroundColor = {255, 255, 255},
			duration = 0.5,
		},

		-- Z-index layering (zIndex maps to DisplayOrder for ScreenGui, ZIndex for elements)
		["overlay"] = {
			zIndex = 100,
		},
		["modal"] = {
			zIndex = 200,
		},
		["tooltip"] = {
			zIndex = 300,
		},

		-- Tutorial Popup styles
		["popup-overlay"] = {
			backgroundColor = {0, 0, 0},
			backgroundTransparency = 0.5,
			zIndex = 200,
		},
		["popup-window"] = {
			backgroundColor = {40, 40, 60},
			backgroundTransparency = 0.1,
			cornerRadius = 16,
			stroke = { color = {100, 100, 150}, thickness = 2 },
		},
		["popup-title"] = {
			font = "Bangers",
			textSize = 32,
			textColor = {255, 200, 100},
			backgroundTransparency = 1,
		},
		["popup-body"] = {
			font = "Gotham",
			textSize = 18,
			textColor = {220, 220, 220},
			backgroundTransparency = 1,
		},
		["popup-btn"] = {
			font = "GothamBold",
			textSize = 18,
			backgroundColor = {60, 60, 100},
			textColor = {255, 255, 255},
			cornerRadius = 8,
			backgroundTransparency = 0,
		},
		["popup-btn-primary"] = {
			backgroundColor = {80, 120, 200},
		},
		["popup-btn:hover"] = {
			backgroundColor = {80, 80, 130},
		},
		["popup-btn-primary:hover"] = {
			backgroundColor = {100, 140, 220},
		},

		-- Tutorial Task list styles
		["task-panel"] = {
			backgroundColor = {30, 30, 50},
			backgroundTransparency = 0.3,
			cornerRadius = 12,
			stroke = { color = {80, 80, 120}, thickness = 1 },
		},
		["task-header"] = {
			font = "Bangers",
			textSize = 24,
			textColor = {255, 200, 100},
			backgroundTransparency = 1,
		},
		["task-item"] = {
			font = "Gotham",
			textSize = 16,
			textColor = {200, 200, 200},
			backgroundTransparency = 1,
		},
		["task-item-complete"] = {
			textColor = {100, 200, 100},
		},
		["task-checkbox"] = {
			font = "GothamBold",
			textSize = 16,
			textColor = {150, 150, 150},
			backgroundTransparency = 1,
		},
		["task-checkbox-complete"] = {
			textColor = {100, 200, 100},
		},

		-- Tutorial Highlight styles
		["highlight-arrow"] = {
			textColor = {255, 200, 100},
			textSize = 48,
			backgroundTransparency = 1,
		},

		--------------------------------------------------------------------------------
		-- ASSET STYLING (3D Objects)
		-- Transform properties: position {x,y,z}, rotation {x,y,z} degrees, scale
		--------------------------------------------------------------------------------

		-- Example: Position assets above baseplate
		["SpawnPoint"] = {
			position = {0, 12, 0},  -- Y=12 studs above origin
			rotation = {0, 90, 0},  -- Face east (90 degrees)
		},

		-- Example: Camper positioning (circular arrangement around fire)
		["Camper"] = {
			position = {0, 0, 0},  -- Grounded on baseplate
		},
		["Camper1"] = {
			rotation = {0, 0, 0},     -- North
		},
		["Camper2"] = {
			rotation = {0, 90, 0},    -- East
		},
		["Camper3"] = {
			rotation = {0, 180, 0},   -- South
		},
		["Camper4"] = {
			rotation = {0, 270, 0},   -- West
		},

		-- Example: Dispenser positioning
		["Dispenser"] = {
			position = {0, 1, 0},     -- 1 stud above ground
			rotation = {0, 0, 0},     -- Face forward
		},

		-- Example: TimedEvaluator positioning
		["TimedEvaluator"] = {
			position = {0, 0, 0},     -- Grounded on baseplate
			rotation = {0, 45, 0},    -- Angled for visibility
		},

		-- Example: Scalable crate (requires AllowScale attribute on parts)
		["Crate"] = {
			scale = {1.2, 1.2, 1.2},  -- 120% size (uniform)
		},
		["CrateLarge"] = {
			scale = {1.5, 1.5, 1.5},  -- 150% size
		},
		["CrateSmall"] = {
			scale = {0.75, 0.75, 0.75},  -- 75% size
		},

		-- Example: Non-uniform scaling
		["FlatPlatform"] = {
			scale = {2, 0.5, 2},      -- Wide and flat (requires AllowScale)
		},
	},

	-- ID styles (applied by id="..." attribute)
	-- Higher specificity than classes
	ids = {
		-- Test ID for cascade verification
		["cascade-test"] = {
			textColor = {0, 255, 0},  -- Green overrides class gold
		},
	},
}
