--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Layouts.ModuleScript (ReplicatedFirst)
-- Layout definitions for the GUI system
-- Defines named screen regions using a row/column grid
--
-- Percentage values: "50%" → 0.5 scale
-- Pixel values: 100 → 100 offset

return {
	-- Breakpoint thresholds
	-- Simple format: breakpoint = minWidth (pixels)
	-- Table format: breakpoint = { minWidth, maxWidth, minAspect, maxAspect }
	--   minAspect/maxAspect = width/height ratio (e.g., 1.5 = landscape, 0.7 = portrait)
	--
	-- Examples:
	--   desktop = 1200                    -- width >= 1200px
	--   tablet = { minWidth = 768 }       -- width >= 768px
	--   landscape = { minAspect = 1.3 }   -- width/height >= 1.3
	--   portrait = { maxAspect = 0.8 }    -- width/height <= 0.8
	--
	breakpoints = {
		desktop = 1200,  -- >= 1200px width
		tablet = 768,    -- >= 768px width
		phone = 0,       -- < 768px width (fallback)
	},

	-- Right sidebar layout for timer, score, and task list
	-- Positions itself in the top-right corner
	["right-sidebar"] = {
		-- Sidebar sizing/position (applied to ScreenGui container)
		position = {0.85, 0, 0, 0},  -- Right 15% of screen
		size = {0.15, 0, 0.55, 0},   -- 15% width, 55% height (increased for tasks)

		-- Asset-to-region mapping
		-- Maps ScreenGui names to region IDs
		-- The layout will find these ScreenGuis and move their content into regions
		assets = {
			["PlayTimer.ScreenGui"] = "timer",
			["Scoreboard.ScreenGui"] = "score",
			["Tutorial.TaskList"] = "tasks",
		},

		rows = {
			-- Timer zone (top 30% of sidebar)
			{
				height = "30%",
				columns = {
					{ id = "timer", width = "100%", xalign = "center", yalign = "center" },
				},
			},
			-- Score zone (middle 30% of sidebar)
			{
				height = "30%",
				columns = {
					{ id = "score", width = "100%", xalign = "center", yalign = "top" },
				},
			},
			-- Task list zone (bottom 40% of sidebar)
			{
				height = "40%",
				columns = {
					{ id = "tasks", width = "100%", xalign = "center", yalign = "top" },
				},
			},
		},
	},

	-- Tutorial popup layout (centered overlay)
	["tutorial-popup"] = {
		position = {0.5, 0, 0.5, 0},
		size = {0.5, 0, 0.4, 0},
		anchorPoint = {0.5, 0.5},

		assets = {
			["Tutorial.Popup"] = "popup",
		},

		rows = {
			-- Title zone
			{
				height = "20%",
				columns = {
					{ id = "title", width = "100%", xalign = "center", yalign = "center" },
				},
			},
			-- Body zone
			{
				height = "55%",
				columns = {
					{ id = "body", width = "100%", xalign = "center", yalign = "top" },
				},
			},
			-- Buttons zone
			{
				height = "25%",
				columns = {
					{ id = "buttons", width = "100%", xalign = "center", yalign = "center" },
				},
			},
		},
	},
}
