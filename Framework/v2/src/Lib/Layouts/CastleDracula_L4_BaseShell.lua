--[[
    Castle Dracula - Level 4: Outer Walls / Battlements / Sentry Loop
    BaseShell - Floors and Walls (ceilings omitted for dev visibility)

    9 rooms + 8 corridors. Floor at Y=400 (above L3 ceilings).
    Towers R01/R02 continue vertically. Four sentry towers at corners.
    Battlement corridors form a wall-walk loop around the castle.

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
--]]

local FLOOR_Y = 400  -- L4 floor height

return {
    name = "CastleDracula_L4_BaseShell",
    spec = {
        origin = "corner",

        classes = {
            floor = { Material = "Cobblestone", Color = {80, 75, 70} },
            wall = { Material = "Brick", Color = {100, 95, 90} },
        },

        parts = {
            ----------------------------------------------------------------
            -- R01: Spiral Stair Tower Rampart (40x40, ceil 110)
            ----------------------------------------------------------------
            { id = "R01_Floor", class = "floor",
              position = {700, FLOOR_Y, 420}, size = {40, 1, 40} },
            { id = "R01_Wall_S", class = "wall",
              position = {700, FLOOR_Y + 1, 420}, size = {40, 110, 1} },
            { id = "R01_Wall_N", class = "wall",
              position = {700, FLOOR_Y + 1, 459}, size = {40, 110, 1} },
            { id = "R01_Wall_W", class = "wall",
              position = {700, FLOOR_Y + 1, 420}, size = {1, 110, 40} },
            { id = "R01_Wall_E", class = "wall",
              position = {739, FLOOR_Y + 1, 420}, size = {1, 110, 40} },

            ----------------------------------------------------------------
            -- R02: Lift Shaft Rampart (30x30, ceil 180)
            ----------------------------------------------------------------
            { id = "R02_Floor", class = "floor",
              position = {700, FLOOR_Y, 470}, size = {30, 1, 30} },
            { id = "R02_Wall_S", class = "wall",
              position = {700, FLOOR_Y + 1, 470}, size = {30, 180, 1} },
            { id = "R02_Wall_N", class = "wall",
              position = {700, FLOOR_Y + 1, 499}, size = {30, 180, 1} },
            { id = "R02_Wall_W", class = "wall",
              position = {700, FLOOR_Y + 1, 470}, size = {1, 180, 30} },
            { id = "R02_Wall_E", class = "wall",
              position = {729, FLOOR_Y + 1, 470}, size = {1, 180, 30} },

            ----------------------------------------------------------------
            -- R03: Rampart Access Gallery (220x60, ceil 85)
            ----------------------------------------------------------------
            { id = "R03_Floor", class = "floor",
              position = {640, FLOOR_Y, 360}, size = {220, 1, 60} },
            { id = "R03_Wall_S", class = "wall",
              position = {640, FLOOR_Y + 1, 360}, size = {220, 85, 1} },
            { id = "R03_Wall_N", class = "wall",
              position = {640, FLOOR_Y + 1, 419}, size = {220, 85, 1} },
            { id = "R03_Wall_W", class = "wall",
              position = {640, FLOOR_Y + 1, 360}, size = {1, 85, 60} },
            { id = "R03_Wall_E", class = "wall",
              position = {859, FLOOR_Y + 1, 360}, size = {1, 85, 60} },

            ----------------------------------------------------------------
            -- R04: NW Sentry Tower (80x80, ceil 100)
            ----------------------------------------------------------------
            { id = "R04_Floor", class = "floor",
              position = {520, FLOOR_Y, 240}, size = {80, 1, 80} },
            { id = "R04_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 240}, size = {80, 100, 1} },
            { id = "R04_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 319}, size = {80, 100, 1} },
            { id = "R04_Wall_W", class = "wall",
              position = {520, FLOOR_Y + 1, 240}, size = {1, 100, 80} },
            { id = "R04_Wall_E", class = "wall",
              position = {599, FLOOR_Y + 1, 240}, size = {1, 100, 80} },

            ----------------------------------------------------------------
            -- R05: NE Sentry Tower (80x80, ceil 100)
            ----------------------------------------------------------------
            { id = "R05_Floor", class = "floor",
              position = {1080, FLOOR_Y, 240}, size = {80, 1, 80} },
            { id = "R05_Wall_S", class = "wall",
              position = {1080, FLOOR_Y + 1, 240}, size = {80, 100, 1} },
            { id = "R05_Wall_N", class = "wall",
              position = {1080, FLOOR_Y + 1, 319}, size = {80, 100, 1} },
            { id = "R05_Wall_W", class = "wall",
              position = {1080, FLOOR_Y + 1, 240}, size = {1, 100, 80} },
            { id = "R05_Wall_E", class = "wall",
              position = {1159, FLOOR_Y + 1, 240}, size = {1, 100, 80} },

            ----------------------------------------------------------------
            -- R06: SE Sentry Tower (80x80, ceil 100)
            ----------------------------------------------------------------
            { id = "R06_Floor", class = "floor",
              position = {1080, FLOOR_Y, 680}, size = {80, 1, 80} },
            { id = "R06_Wall_S", class = "wall",
              position = {1080, FLOOR_Y + 1, 680}, size = {80, 100, 1} },
            { id = "R06_Wall_N", class = "wall",
              position = {1080, FLOOR_Y + 1, 759}, size = {80, 100, 1} },
            { id = "R06_Wall_W", class = "wall",
              position = {1080, FLOOR_Y + 1, 680}, size = {1, 100, 80} },
            { id = "R06_Wall_E", class = "wall",
              position = {1159, FLOOR_Y + 1, 680}, size = {1, 100, 80} },

            ----------------------------------------------------------------
            -- R07: SW Sentry Tower (80x80, ceil 100)
            ----------------------------------------------------------------
            { id = "R07_Floor", class = "floor",
              position = {520, FLOOR_Y, 680}, size = {80, 1, 80} },
            { id = "R07_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 680}, size = {80, 100, 1} },
            { id = "R07_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 759}, size = {80, 100, 1} },
            { id = "R07_Wall_W", class = "wall",
              position = {520, FLOOR_Y + 1, 680}, size = {1, 100, 80} },
            { id = "R07_Wall_E", class = "wall",
              position = {599, FLOOR_Y + 1, 680}, size = {1, 100, 80} },

            ----------------------------------------------------------------
            -- R08: Graveyard Overlook Walk (80x180, ceil 120, open sky)
            ----------------------------------------------------------------
            { id = "R08_Floor", class = "floor",
              position = {900, FLOOR_Y, 300}, size = {80, 1, 180} },
            { id = "R08_Wall_S", class = "wall",
              position = {900, FLOOR_Y + 1, 300}, size = {80, 120, 1} },
            { id = "R08_Wall_N", class = "wall",
              position = {900, FLOOR_Y + 1, 479}, size = {80, 120, 1} },
            { id = "R08_Wall_W", class = "wall",
              position = {900, FLOOR_Y + 1, 300}, size = {1, 120, 180} },
            { id = "R08_Wall_E", class = "wall",
              position = {979, FLOOR_Y + 1, 300}, size = {1, 120, 180} },

            ----------------------------------------------------------------
            -- R09: Crumbled Parapet Drop (80x60, ceil 200, one-way)
            ----------------------------------------------------------------
            { id = "R09_Floor", class = "floor",
              position = {900, FLOOR_Y, 700}, size = {80, 1, 60} },
            { id = "R09_Wall_S", class = "wall",
              position = {900, FLOOR_Y + 1, 700}, size = {80, 200, 1} },
            { id = "R09_Wall_N", class = "wall",
              position = {900, FLOOR_Y + 1, 759}, size = {80, 200, 1} },
            { id = "R09_Wall_W", class = "wall",
              position = {900, FLOOR_Y + 1, 700}, size = {1, 200, 60} },
            { id = "R09_Wall_E", class = "wall",
              position = {979, FLOOR_Y + 1, 700}, size = {1, 200, 60} },

            ----------------------------------------------------------------
            -- BATTLEMENT CORRIDORS (wall-walk loop)
            ----------------------------------------------------------------

            -- C01: North Battlement (640x60, ceil 60, open sky)
            { id = "C01_Floor", class = "floor",
              position = {520, FLOOR_Y, 240}, size = {640, 1, 60} },
            { id = "C01_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 240}, size = {640, 60, 1} },
            { id = "C01_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 299}, size = {640, 60, 1} },

            -- C02: East Battlement (60x460, ceil 60, open sky)
            { id = "C02_Floor", class = "floor",
              position = {1100, FLOOR_Y, 300}, size = {60, 1, 460} },
            { id = "C02_Wall_W", class = "wall",
              position = {1100, FLOOR_Y + 1, 300}, size = {1, 60, 460} },
            { id = "C02_Wall_E", class = "wall",
              position = {1159, FLOOR_Y + 1, 300}, size = {1, 60, 460} },

            -- C03: South Battlement (580x60, ceil 60, open sky)
            { id = "C03_Floor", class = "floor",
              position = {520, FLOOR_Y, 700}, size = {580, 1, 60} },
            { id = "C03_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 700}, size = {580, 60, 1} },
            { id = "C03_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 759}, size = {580, 60, 1} },

            -- C04: West Battlement (60x400, ceil 60, open sky)
            { id = "C04_Floor", class = "floor",
              position = {520, FLOOR_Y, 300}, size = {60, 1, 400} },
            { id = "C04_Wall_W", class = "wall",
              position = {520, FLOOR_Y + 1, 300}, size = {1, 60, 400} },
            { id = "C04_Wall_E", class = "wall",
              position = {579, FLOOR_Y + 1, 300}, size = {1, 60, 400} },

            ----------------------------------------------------------------
            -- CONNECTOR CORRIDORS
            ----------------------------------------------------------------

            -- C05: Stair to Access (20x20, ceil 50)
            { id = "C05_Floor", class = "floor",
              position = {740, FLOOR_Y, 420}, size = {20, 1, 20} },
            { id = "C05_Wall_S", class = "wall",
              position = {740, FLOOR_Y + 1, 420}, size = {20, 50, 1} },
            { id = "C05_Wall_N", class = "wall",
              position = {740, FLOOR_Y + 1, 439}, size = {20, 50, 1} },

            -- C06: Access to West Battlement (40x30, ceil 55)
            { id = "C06_Floor", class = "floor",
              position = {600, FLOOR_Y, 390}, size = {40, 1, 30} },
            { id = "C06_Wall_S", class = "wall",
              position = {600, FLOOR_Y + 1, 390}, size = {40, 55, 1} },
            { id = "C06_Wall_N", class = "wall",
              position = {600, FLOOR_Y + 1, 419}, size = {40, 55, 1} },

            -- C07: Battlement to Overlook (60x40, ceil 60)
            { id = "C07_Floor", class = "floor",
              position = {1040, FLOOR_Y, 380}, size = {60, 1, 40} },
            { id = "C07_Wall_S", class = "wall",
              position = {1040, FLOOR_Y + 1, 380}, size = {60, 60, 1} },
            { id = "C07_Wall_N", class = "wall",
              position = {1040, FLOOR_Y + 1, 419}, size = {60, 60, 1} },

            -- C08: South to Drop (40x40, ceil 60)
            { id = "C08_Floor", class = "floor",
              position = {860, FLOOR_Y, 700}, size = {40, 1, 40} },
            { id = "C08_Wall_S", class = "wall",
              position = {860, FLOOR_Y + 1, 700}, size = {40, 60, 1} },
            { id = "C08_Wall_N", class = "wall",
              position = {860, FLOOR_Y + 1, 739}, size = {40, 60, 1} },
        },
    },
}
