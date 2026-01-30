--[[
    AtomicRanch/InteriorWalls

    Interior room walls (solid - openings handled globally).
    Each room has its own complete wall set.

    Interior walls are INSET from exterior walls by WALL_T to avoid overlap.

    Floor Plan (64 x 40):
    +--------------------+-------------+-------------------------+
    |    BEDROOM 2       |  BATHROOM   |    MASTER BEDROOM       |
    |    (20 x 16)       |  (12 x 16)  |    (32 x 16)            |
    +--------------------+-------------+-------------------------+ Z=24
    |                    |                                       |
    |    KITCHEN         |         LIVING / DINING               |
    |    (20 x 24)       |         (44 x 24)                     |
    |                    |                                       |
    +--------------------+---------------------------------------+ Z=0
    X=0                 X=20        X=32                       X=64
--]]

local WALL_H = 10
local WALL_T = 0.5

-- Building dimensions (must match ExteriorWalls)
local MAIN_W = 64
local MAIN_D = 40

-- Inset values for interior walls adjacent to exterior walls
local INSET = WALL_T  -- Interior walls start after exterior wall thickness

return {
    name = "AtomicRanch_InteriorWalls",
    spec = {
        origin = "corner",

        classes = {
            interior = {
                Material = "SmoothPlastic",
                Color = {255, 250, 245},
            },
        },

        parts = {
            ----------------------------------------------------------------
            -- KITCHEN (origin {0,0}, size {20,24})
            -- Borders: South exterior, West exterior, East interior, North interior
            ----------------------------------------------------------------
            { id = "Kitchen_WallSouth", class = "interior",
              position = {INSET, 0, INSET},
              size = {20 - INSET, WALL_H, WALL_T} },

            { id = "Kitchen_WallNorth", class = "interior",
              position = {INSET, 0, 24 - WALL_T},
              size = {20 - INSET, WALL_H, WALL_T} },

            { id = "Kitchen_WallWest", class = "interior",
              position = {INSET, 0, INSET},
              size = {WALL_T, WALL_H, 24 - INSET} },

            { id = "Kitchen_WallEast", class = "interior",
              position = {20 - WALL_T, 0, INSET},
              size = {WALL_T, WALL_H, 24 - INSET} },

            ----------------------------------------------------------------
            -- LIVING ROOM (origin {20,0}, size {44,24})
            -- Borders: South exterior, East exterior, West interior, North interior
            ----------------------------------------------------------------
            { id = "LivingRoom_WallSouth", class = "interior",
              position = {20, 0, INSET},
              size = {44 - INSET, WALL_H, WALL_T} },

            { id = "LivingRoom_WallNorth", class = "interior",
              position = {20, 0, 24 - WALL_T},
              size = {44 - INSET, WALL_H, WALL_T} },

            { id = "LivingRoom_WallWest", class = "interior",
              position = {20, 0, INSET},
              size = {WALL_T, WALL_H, 24 - INSET} },

            { id = "LivingRoom_WallEast", class = "interior",
              position = {MAIN_W - 2*WALL_T, 0, INSET},
              size = {WALL_T, WALL_H, 24 - INSET} },

            ----------------------------------------------------------------
            -- BEDROOM 2 (origin {0,24}, size {20,16})
            -- Borders: North exterior, West exterior, East interior, South interior
            ----------------------------------------------------------------
            { id = "Bedroom2_WallSouth", class = "interior",
              position = {INSET, 0, 24},
              size = {20 - INSET, WALL_H, WALL_T} },

            { id = "Bedroom2_WallNorth", class = "interior",
              position = {INSET, 0, MAIN_D - 2*WALL_T},
              size = {20 - INSET, WALL_H, WALL_T} },

            { id = "Bedroom2_WallWest", class = "interior",
              position = {INSET, 0, 24},
              size = {WALL_T, WALL_H, 16 - INSET} },

            { id = "Bedroom2_WallEast", class = "interior",
              position = {20 - WALL_T, 0, 24},
              size = {WALL_T, WALL_H, 16 - INSET} },

            ----------------------------------------------------------------
            -- BATHROOM (origin {20,24}, size {12,16})
            -- Borders: North exterior, all others interior
            ----------------------------------------------------------------
            { id = "Bathroom_WallSouth", class = "interior",
              position = {20, 0, 24},
              size = {12, WALL_H, WALL_T} },

            { id = "Bathroom_WallNorth", class = "interior",
              position = {20, 0, MAIN_D - 2*WALL_T},
              size = {12, WALL_H, WALL_T} },

            { id = "Bathroom_WallWest", class = "interior",
              position = {20, 0, 24},
              size = {WALL_T, WALL_H, 16 - INSET} },

            { id = "Bathroom_WallEast", class = "interior",
              position = {32 - WALL_T, 0, 24},
              size = {WALL_T, WALL_H, 16 - INSET} },

            ----------------------------------------------------------------
            -- MASTER BEDROOM (origin {32,24}, size {32,16})
            -- Borders: North exterior, East exterior, West interior, South interior
            ----------------------------------------------------------------
            { id = "MasterBedroom_WallSouth", class = "interior",
              position = {32, 0, 24},
              size = {32 - INSET, WALL_H, WALL_T} },

            { id = "MasterBedroom_WallNorth", class = "interior",
              position = {32, 0, MAIN_D - 2*WALL_T},
              size = {32 - INSET, WALL_H, WALL_T} },

            { id = "MasterBedroom_WallWest", class = "interior",
              position = {32, 0, 24},
              size = {WALL_T, WALL_H, 16 - INSET} },

            { id = "MasterBedroom_WallEast", class = "interior",
              position = {MAIN_W - 2*WALL_T, 0, 24},
              size = {WALL_T, WALL_H, 16 - INSET} },
        },
    },
}
