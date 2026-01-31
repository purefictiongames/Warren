--[[
    Castle Dracula - Level 4: Outer Walls / Battlements / Sentry Loop
    Door Openings - Cut holes between rooms and corridors

    Parts with geometry = "negate" are CSG subtracted from intersecting walls.

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
--]]

local FLOOR_Y = 400  -- L4 floor height

return {
    name = "CastleDracula_L4_Openings",
    spec = {
        origin = "corner",

        parts = {
            ----------------------------------------------------------------
            -- C05: Stair Tower to Access Gallery
            ----------------------------------------------------------------
            { id = "D_R01_C05", geometry = "negate",
              position = {738, FLOOR_Y + 1, 421}, size = {3, 14, 18} },

            ----------------------------------------------------------------
            -- C06: Access Gallery to West Battlement
            ----------------------------------------------------------------
            { id = "D_R03_C06", geometry = "negate",
              position = {638, FLOOR_Y + 1, 391}, size = {3, 12, 28} },
            { id = "D_C06_C04", geometry = "negate",
              position = {598, FLOOR_Y + 1, 391}, size = {3, 12, 28} },

            ----------------------------------------------------------------
            -- Battlement corners to Sentry Towers
            ----------------------------------------------------------------
            -- NW Tower (R04) to North/West Battlements
            { id = "D_R04_C01", geometry = "negate",
              position = {521, FLOOR_Y + 1, 298}, size = {78, 12, 3} },
            { id = "D_R04_C04", geometry = "negate",
              position = {598, FLOOR_Y + 1, 301}, size = {3, 12, 18} },

            -- NE Tower (R05) to North/East Battlements
            { id = "D_R05_C01", geometry = "negate",
              position = {1081, FLOOR_Y + 1, 298}, size = {78, 12, 3} },
            { id = "D_R05_C02", geometry = "negate",
              position = {1098, FLOOR_Y + 1, 301}, size = {3, 12, 18} },

            -- SE Tower (R06) to South/East Battlements
            { id = "D_R06_C03", geometry = "negate",
              position = {1081, FLOOR_Y + 1, 698}, size = {18, 12, 3} },
            { id = "D_R06_C02", geometry = "negate",
              position = {1098, FLOOR_Y + 1, 681}, size = {3, 12, 78} },

            -- SW Tower (R07) to South/West Battlements
            { id = "D_R07_C03", geometry = "negate",
              position = {521, FLOOR_Y + 1, 698}, size = {78, 12, 3} },
            { id = "D_R07_C04", geometry = "negate",
              position = {578, FLOOR_Y + 1, 681}, size = {3, 12, 18} },

            ----------------------------------------------------------------
            -- C07: East Battlement to Overlook Walk
            ----------------------------------------------------------------
            { id = "D_C02_C07", geometry = "negate",
              position = {1098, FLOOR_Y + 1, 381}, size = {3, 12, 38} },
            { id = "D_C07_R08", geometry = "negate",
              position = {978, FLOOR_Y + 1, 381}, size = {3, 12, 38} },

            ----------------------------------------------------------------
            -- C08: South Battlement to Parapet Drop
            ----------------------------------------------------------------
            { id = "D_C03_C08", geometry = "negate",
              position = {861, FLOOR_Y + 1, 698}, size = {38, 12, 3} },
            { id = "D_C08_R09", geometry = "negate",
              position = {898, FLOOR_Y + 1, 701}, size = {3, 12, 38} },
        },
    },
}
