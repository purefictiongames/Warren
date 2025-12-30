-- Layouts.ModuleScript (ReplicatedFirst)
-- Layout definitions for the GUI system
-- Defines named screen regions using a row/column grid
--
-- Percentage values: "50%" → 0.5 scale
-- Pixel values: 100 → 100 offset

return {
	-- Breakpoint thresholds (viewport width in pixels)
	breakpoints = {
		desktop = 1200,  -- >= 1200px
		tablet = 768,    -- >= 768px
		phone = 0,       -- < 768px (fallback)
	},

	-- Example HUD layout
	hud = {
		rows = {
			-- Top bar (10% height)
			{
				height = "10%",
				columns = {
					{ id = "top-left", width = "30%", xalign = "left", yalign = "center" },
					{ id = "top-center", width = "40%", xalign = "center", yalign = "center" },
					{ id = "top-right", width = "30%", xalign = "right", yalign = "center" },
				},
			},
			-- Main area (80% height)
			{
				height = "80%",
				columns = {
					{ id = "main", width = "100%" },
				},
			},
			-- Bottom bar (10% height)
			{
				height = "10%",
				columns = {
					{ id = "bottom-left", width = "30%", xalign = "left", yalign = "center" },
					{ id = "bottom-center", width = "40%", xalign = "center", yalign = "center" },
					{ id = "bottom-right", width = "30%", xalign = "right", yalign = "center" },
				},
			},
		},
	},

	-- Tablet variant (optional - Phase 5)
	-- ["hud@tablet"] = { ... },

	-- Phone variant (optional - Phase 5)
	-- ["hud@phone"] = { ... },
}
