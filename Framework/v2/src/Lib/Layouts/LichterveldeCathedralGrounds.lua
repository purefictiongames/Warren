--[[
    LichterveldeCathedralGrounds
    Raised lawn with retaining wall around cathedral entrance

    Simple design:
    - 1 cylinder (curved corner)
    - 2 wedges (angled sides)
    - 3 rotated blocks (retaining wall)
--]]

-- Base elevation (matches cathedral)
local Y_BASE = 83

-- Lawn dimensions
local LAWN_HEIGHT = 5
local LAWN_Y = Y_BASE + LAWN_HEIGHT/2

-- Retaining wall
local WALL_HEIGHT = 5
local WALL_THICKNESS = 3
local WALL_Y = Y_BASE + WALL_HEIGHT/2

-- Colors
local COLOR_GRASS = {85, 130, 75}
local COLOR_WALL = {150, 100, 75}  -- Match cathedral brick trim

return {
    name = "LichterveldeCathedralGrounds",
    spec = {
        origin = "corner",
        bounds = {200, 100, 200},

        classes = {
            grass = { Color = COLOR_GRASS, Material = "Grass", CanCollide = true },
            wall = { Color = COLOR_WALL, Material = "Brick", CanCollide = true },
        },

        parts = {
            -- ================================================================
            -- GRASS - Raised lawn platform
            -- ================================================================

            -- Main grass cylinder (curved corner near entrance)
            { id = "Grass_Curve", class = "grass", shape = "cylinder",
              position = {100, LAWN_Y, 60},
              height = LAWN_HEIGHT,
              radius = 50,
              rotation = {0, 0, 0} },

            -- Left wedge (angled edge)
            { id = "Grass_Wedge_Left", class = "grass", shape = "wedge",
              position = {60, LAWN_Y, 100},
              size = {40, LAWN_HEIGHT, 60},
              rotation = {0, 180, 0} },

            -- Right wedge (angled edge)
            { id = "Grass_Wedge_Right", class = "grass", shape = "wedge",
              position = {140, LAWN_Y, 100},
              size = {40, LAWN_HEIGHT, 60},
              rotation = {0, 0, 0} },

            -- ================================================================
            -- RETAINING WALL - Follows lawn edge
            -- ================================================================

            -- Left wall segment (angled)
            { id = "Wall_Left", class = "wall",
              position = {45, WALL_Y, 85},
              size = {WALL_THICKNESS, WALL_HEIGHT, 70},
              rotation = {0, 30, 0} },

            -- Center wall segment (front)
            { id = "Wall_Center", class = "wall",
              position = {100, WALL_Y, 15},
              size = {WALL_THICKNESS, WALL_HEIGHT, 80},
              rotation = {0, 90, 0} },

            -- Right wall segment (angled)
            { id = "Wall_Right", class = "wall",
              position = {155, WALL_Y, 85},
              size = {WALL_THICKNESS, WALL_HEIGHT, 70},
              rotation = {0, -30, 0} },
        },
    },
}
