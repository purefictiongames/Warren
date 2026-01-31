--[[
    Castle Dracula - Level 3: Inner Keep / Clockwork / Defenses
    BaseShell - Floors and Walls (ceilings omitted for dev visibility)

    4 rooms + 2 corridors. Floor at Y=280 (above L2 ceilings).
    Towers R01/R02 continue vertically from L2.

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
--]]

local FLOOR_Y = 280  -- L3 floor height

return {
    name = "CastleDracula_L3_BaseShell",
    spec = {
        origin = "corner",

        classes = {
            floor = { Material = "Cobblestone", Color = {75, 70, 65} },
            wall = { Material = "Brick", Color = {95, 90, 85} },
        },

        parts = {
            ----------------------------------------------------------------
            -- R01: Spiral Stair Tower Upper (40x40, ceil 100)
            ----------------------------------------------------------------
            { id = "R01_Floor", class = "floor",
              position = {700, FLOOR_Y, 420}, size = {40, 1, 40} },
            { id = "R01_Wall_S", class = "wall",
              position = {700, FLOOR_Y + 1, 420}, size = {40, 100, 1} },
            { id = "R01_Wall_N", class = "wall",
              position = {700, FLOOR_Y + 1, 459}, size = {40, 100, 1} },
            { id = "R01_Wall_W", class = "wall",
              position = {700, FLOOR_Y + 1, 420}, size = {1, 100, 40} },
            { id = "R01_Wall_E", class = "wall",
              position = {739, FLOOR_Y + 1, 420}, size = {1, 100, 40} },

            ----------------------------------------------------------------
            -- R02: Lift Shaft Upper (30x30, ceil 160)
            ----------------------------------------------------------------
            { id = "R02_Floor", class = "floor",
              position = {700, FLOOR_Y, 470}, size = {30, 1, 30} },
            { id = "R02_Wall_S", class = "wall",
              position = {700, FLOOR_Y + 1, 470}, size = {30, 160, 1} },
            { id = "R02_Wall_N", class = "wall",
              position = {700, FLOOR_Y + 1, 499}, size = {30, 160, 1} },
            { id = "R02_Wall_W", class = "wall",
              position = {700, FLOOR_Y + 1, 470}, size = {1, 160, 30} },
            { id = "R02_Wall_E", class = "wall",
              position = {729, FLOOR_Y + 1, 470}, size = {1, 160, 30} },

            ----------------------------------------------------------------
            -- R03: Clockwork Control Hall (340x220, ceil 120) - Main Hub
            ----------------------------------------------------------------
            { id = "R03_Floor", class = "floor",
              position = {520, FLOOR_Y, 360}, size = {340, 1, 220} },
            { id = "R03_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 360}, size = {340, 120, 1} },
            { id = "R03_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 579}, size = {340, 120, 1} },
            { id = "R03_Wall_W", class = "wall",
              position = {520, FLOOR_Y + 1, 360}, size = {1, 120, 220} },
            { id = "R03_Wall_E", class = "wall",
              position = {859, FLOOR_Y + 1, 360}, size = {1, 120, 220} },

            ----------------------------------------------------------------
            -- R04: Turret Power Room (160x120, ceil 80)
            ----------------------------------------------------------------
            { id = "R04_Floor", class = "floor",
              position = {360, FLOOR_Y, 360}, size = {160, 1, 120} },
            { id = "R04_Wall_S", class = "wall",
              position = {360, FLOOR_Y + 1, 360}, size = {160, 80, 1} },
            { id = "R04_Wall_N", class = "wall",
              position = {360, FLOOR_Y + 1, 479}, size = {160, 80, 1} },
            { id = "R04_Wall_W", class = "wall",
              position = {360, FLOOR_Y + 1, 360}, size = {1, 80, 120} },
            { id = "R04_Wall_E", class = "wall",
              position = {519, FLOOR_Y + 1, 360}, size = {1, 80, 120} },

            ----------------------------------------------------------------
            -- CORRIDORS
            ----------------------------------------------------------------

            -- C01: Stair to Control Hall (120x30, ceil 55)
            { id = "C01_Floor", class = "floor",
              position = {740, FLOOR_Y, 430}, size = {120, 1, 30} },
            { id = "C01_Wall_S", class = "wall",
              position = {740, FLOOR_Y + 1, 430}, size = {120, 55, 1} },
            { id = "C01_Wall_N", class = "wall",
              position = {740, FLOOR_Y + 1, 459}, size = {120, 55, 1} },

            -- C03: Control Hall to Turret Power (20x40, ceil 40)
            { id = "C03_Floor", class = "floor",
              position = {500, FLOOR_Y, 420}, size = {20, 1, 40} },
            { id = "C03_Wall_S", class = "wall",
              position = {500, FLOOR_Y + 1, 420}, size = {20, 40, 1} },
            { id = "C03_Wall_N", class = "wall",
              position = {500, FLOOR_Y + 1, 459}, size = {20, 40, 1} },
        },
    },
}
