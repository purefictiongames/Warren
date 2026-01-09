--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- CameraConfig.lua (ReplicatedFirst)
-- Camera configuration for different game modes
--
-- Isometric: Fixed overhead view for gameplay (play/practice modes)
--            Dynamically calculated to frame MarshmallowBag and Campfire
-- Free: Default Roblox third-person camera (standby mode)

return {
	-- Isometric camera settings (for play/practice modes)
	-- Camera position is calculated dynamically to frame the play area
	isometric = {
		-- Angle from horizontal (60° = steep top-down view)
		angle = 60,

		-- Buffer space around the play area (studs on each side)
		buffer = 20,

		-- Field of view
		fieldOfView = 70,

		-- Fallback position if assets can't be found
		position = Vector3.new(0, 100, 60),
		lookAt = Vector3.new(0, 0, 0),
	},

	-- Free camera settings (for standby mode)
	-- Uses default Roblox third-person following behavior
	free = {
		fieldOfView = 70,
	},

	-- Mode to camera style mapping
	-- Maps RunModes values to camera styles
	modes = {
		standby = "free",
		practice = "isometric",
		play = "isometric",
	},
}
