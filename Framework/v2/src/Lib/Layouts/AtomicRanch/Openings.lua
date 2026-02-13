--[[
    AtomicRanch/Openings

    Global door and window openings defined in world space.
    These automatically cut through any walls they intersect.

    Position is corner-based (same as walls).
    Y=0 is foundation top (same as wall origin).
--]]

local DOOR_H = 7
local WIN_H = 4

return {
    name = "AtomicRanch_Openings",
    spec = {
        origin = "corner",

        openings = {
            ----------------------------------------------------------------
            -- EXTERIOR DOORS
            ----------------------------------------------------------------
            { id = "FrontDoor",
              position = {43, 0, -1},
              size = {4, DOOR_H, 3} },

            { id = "MasterSlider",
              position = {47, 0, 39},
              size = {6, DOOR_H, 3} },

            ----------------------------------------------------------------
            -- EXTERIOR WINDOWS
            ----------------------------------------------------------------
            -- South wall
            { id = "LivingPictureWindow",
              position = {50, 3, -1},
              size = {10, WIN_H, 3} },

            { id = "KitchenWindowS",
              position = {7, 3, -1},
              size = {6, WIN_H, 3} },

            -- East wall
            { id = "LivingWindowE",
              position = {63, 3, 8},
              size = {3, WIN_H, 8} },

            { id = "MasterWindowE",
              position = {63, 3, 29},
              size = {3, WIN_H, 6} },

            -- West wall
            { id = "KitchenWindowW",
              position = {-1, 3, 9},
              size = {3, WIN_H, 6} },

            { id = "Bedroom2Window",
              position = {-1, 3, 29.5},
              size = {3, WIN_H, 5} },

            -- North wall
            { id = "BathroomWindow",
              position = {24.5, 5, 39},
              size = {3, 2, 3} },

            ----------------------------------------------------------------
            -- INTERIOR DOORS
            ----------------------------------------------------------------
            { id = "KitchenLivingArch",
              position = {19, 0, 7},
              size = {3, DOOR_H, 6} },

            { id = "KitchenBedroom2Door",
              position = {6.5, 0, 23},
              size = {3, DOOR_H, 3} },

            { id = "LivingBathroomDoor",
              position = {24.5, 0, 23},
              size = {3, DOOR_H, 3} },

            { id = "LivingMasterDoor",
              position = {43.5, 0, 23},
              size = {3, DOOR_H, 3} },

            { id = "Bedroom2BathroomDoor",
              position = {19, 0, 28.5},
              size = {3, DOOR_H, 3} },

            { id = "BathroomMasterDoor",
              position = {31, 0, 30.5},
              size = {3, DOOR_H, 3} },
        },
    },
}
