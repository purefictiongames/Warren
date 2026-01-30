--[[
    AtomicRanch/ExteriorWalls

    Exterior walls (solid - openings handled globally).
    10 studs high, sits on foundation (Y = 0.5).
--]]

-- Dimensions
local WALL_H = 10
local WALL_T = 0.5

-- Main house
local MAIN_W = 64
local MAIN_D = 40

-- Carport
local CARPORT_W = 20

return {
    name = "AtomicRanch_ExteriorWalls",
    spec = {
        origin = "corner",

        classes = {
            wall = { Material = "SmoothPlastic", Color = {240, 235, 225} },
        },

        parts = {
            -- SOUTH WALL: full width
            { id = "WallSouth", class = "wall",
              position = {0, 0, 0},
              size = {MAIN_W, WALL_H, WALL_T} },

            -- EAST WALL: main house only
            { id = "WallEast", class = "wall",
              position = {MAIN_W - WALL_T, 0, 0},
              size = {WALL_T, WALL_H, MAIN_D} },

            -- NORTH WALL: from carport edge to east
            { id = "WallNorthMain", class = "wall",
              position = {CARPORT_W, 0, MAIN_D - WALL_T},
              size = {MAIN_W - CARPORT_W, WALL_H, WALL_T} },

            -- WEST WALL: main house only (carport is open)
            { id = "WallWest", class = "wall",
              position = {0, 0, 0},
              size = {WALL_T, WALL_H, MAIN_D} },
        },
    },
}
