--[[
    Castle Dracula - Level 1: Lower Castle / Guard Quarters
    BaseShell - Floors and Walls (ceilings omitted for dev visibility)

    12 rooms + 9 corridors. Floor at Y=70 (above L0 ceilings).
    Towers R01/R02 continue vertically from L0.

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
        Positions from SVG map (1 unit = 1 stud)
--]]

local FLOOR_Y = 70  -- L1 floor height

return {
    name = "CastleDracula_L1_BaseShell",
    spec = {
        origin = "corner",

        classes = {
            floor = { Material = "Cobblestone", Color = {70, 65, 60} },
            wall = { Material = "Brick", Color = {90, 85, 80} },
        },

        parts = {
            ----------------------------------------------------------------
            -- R01: Spiral Stair Tower Mid (40x40, ceil 90)
            -- Continues from L0 R11
            ----------------------------------------------------------------
            { id = "R01_Floor", class = "floor",
              position = {700, FLOOR_Y, 420}, size = {40, 1, 40} },
            { id = "R01_Wall_S", class = "wall",
              position = {700, FLOOR_Y + 1, 420}, size = {40, 90, 1} },
            { id = "R01_Wall_N", class = "wall",
              position = {700, FLOOR_Y + 1, 459}, size = {40, 90, 1} },
            { id = "R01_Wall_W", class = "wall",
              position = {700, FLOOR_Y + 1, 420}, size = {1, 90, 40} },
            { id = "R01_Wall_E", class = "wall",
              position = {739, FLOOR_Y + 1, 420}, size = {1, 90, 40} },

            ----------------------------------------------------------------
            -- R02: Lift Shaft Mid (30x30, ceil 120)
            -- Continues from L0 R12
            ----------------------------------------------------------------
            { id = "R02_Floor", class = "floor",
              position = {700, FLOOR_Y, 470}, size = {30, 1, 30} },
            { id = "R02_Wall_S", class = "wall",
              position = {700, FLOOR_Y + 1, 470}, size = {30, 120, 1} },
            { id = "R02_Wall_N", class = "wall",
              position = {700, FLOOR_Y + 1, 499}, size = {30, 120, 1} },
            { id = "R02_Wall_W", class = "wall",
              position = {700, FLOOR_Y + 1, 470}, size = {1, 120, 30} },
            { id = "R02_Wall_E", class = "wall",
              position = {729, FLOOR_Y + 1, 470}, size = {1, 120, 30} },

            ----------------------------------------------------------------
            -- R03: Guard Hall (160x160, ceil 80) - Main Hub
            ----------------------------------------------------------------
            { id = "R03_Floor", class = "floor",
              position = {520, FLOOR_Y, 360}, size = {160, 1, 160} },
            { id = "R03_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 360}, size = {160, 80, 1} },
            { id = "R03_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 519}, size = {160, 80, 1} },
            { id = "R03_Wall_W", class = "wall",
              position = {520, FLOOR_Y + 1, 360}, size = {1, 80, 160} },
            { id = "R03_Wall_E", class = "wall",
              position = {679, FLOOR_Y + 1, 360}, size = {1, 80, 160} },

            ----------------------------------------------------------------
            -- R04: Barracks (160x80, ceil 45)
            ----------------------------------------------------------------
            { id = "R04_Floor", class = "floor",
              position = {360, FLOOR_Y, 380}, size = {160, 1, 80} },
            { id = "R04_Wall_S", class = "wall",
              position = {360, FLOOR_Y + 1, 380}, size = {160, 45, 1} },
            { id = "R04_Wall_N", class = "wall",
              position = {360, FLOOR_Y + 1, 459}, size = {160, 45, 1} },
            { id = "R04_Wall_W", class = "wall",
              position = {360, FLOOR_Y + 1, 380}, size = {1, 45, 80} },
            { id = "R04_Wall_E", class = "wall",
              position = {519, FLOOR_Y + 1, 380}, size = {1, 45, 80} },

            ----------------------------------------------------------------
            -- R05: Armory (140x100, ceil 55)
            ----------------------------------------------------------------
            { id = "R05_Floor", class = "floor",
              position = {320, FLOOR_Y, 480}, size = {140, 1, 100} },
            { id = "R05_Wall_S", class = "wall",
              position = {320, FLOOR_Y + 1, 480}, size = {140, 55, 1} },
            { id = "R05_Wall_N", class = "wall",
              position = {320, FLOOR_Y + 1, 579}, size = {140, 55, 1} },
            { id = "R05_Wall_W", class = "wall",
              position = {320, FLOOR_Y + 1, 480}, size = {1, 55, 100} },
            { id = "R05_Wall_E", class = "wall",
              position = {459, FLOOR_Y + 1, 480}, size = {1, 55, 100} },

            ----------------------------------------------------------------
            -- R06: Supply Store (60x80, ceil 40)
            ----------------------------------------------------------------
            { id = "R06_Floor", class = "floor",
              position = {460, FLOOR_Y, 520}, size = {60, 1, 80} },
            { id = "R06_Wall_S", class = "wall",
              position = {460, FLOOR_Y + 1, 520}, size = {60, 40, 1} },
            { id = "R06_Wall_N", class = "wall",
              position = {460, FLOOR_Y + 1, 599}, size = {60, 40, 1} },
            { id = "R06_Wall_W", class = "wall",
              position = {460, FLOOR_Y + 1, 520}, size = {1, 40, 80} },
            { id = "R06_Wall_E", class = "wall",
              position = {519, FLOOR_Y + 1, 520}, size = {1, 40, 80} },

            ----------------------------------------------------------------
            -- R07: Mess Hall (140x120, ceil 60)
            ----------------------------------------------------------------
            { id = "R07_Floor", class = "floor",
              position = {520, FLOOR_Y, 540}, size = {140, 1, 120} },
            { id = "R07_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 540}, size = {140, 60, 1} },
            { id = "R07_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 659}, size = {140, 60, 1} },
            { id = "R07_Wall_W", class = "wall",
              position = {520, FLOOR_Y + 1, 540}, size = {1, 60, 120} },
            { id = "R07_Wall_E", class = "wall",
              position = {659, FLOOR_Y + 1, 540}, size = {1, 60, 120} },

            ----------------------------------------------------------------
            -- R08: Kitchen (80x80, ceil 45)
            ----------------------------------------------------------------
            { id = "R08_Floor", class = "floor",
              position = {660, FLOOR_Y, 560}, size = {80, 1, 80} },
            { id = "R08_Wall_S", class = "wall",
              position = {660, FLOOR_Y + 1, 560}, size = {80, 45, 1} },
            { id = "R08_Wall_N", class = "wall",
              position = {660, FLOOR_Y + 1, 639}, size = {80, 45, 1} },
            { id = "R08_Wall_W", class = "wall",
              position = {660, FLOOR_Y + 1, 560}, size = {1, 45, 80} },
            { id = "R08_Wall_E", class = "wall",
              position = {739, FLOOR_Y + 1, 560}, size = {1, 45, 80} },

            ----------------------------------------------------------------
            -- R09: Overlook Gallery (80x180, ceil 90)
            ----------------------------------------------------------------
            { id = "R09_Floor", class = "floor",
              position = {900, FLOOR_Y, 300}, size = {80, 1, 180} },
            { id = "R09_Wall_S", class = "wall",
              position = {900, FLOOR_Y + 1, 300}, size = {80, 90, 1} },
            { id = "R09_Wall_N", class = "wall",
              position = {900, FLOOR_Y + 1, 479}, size = {80, 90, 1} },
            { id = "R09_Wall_W", class = "wall",
              position = {900, FLOOR_Y + 1, 300}, size = {1, 90, 180} },
            { id = "R09_Wall_E", class = "wall",
              position = {979, FLOOR_Y + 1, 300}, size = {1, 90, 180} },

            ----------------------------------------------------------------
            -- R10: Lower Chapel Narthex (140x100, ceil 70)
            ----------------------------------------------------------------
            { id = "R10_Floor", class = "floor",
              position = {840, FLOOR_Y, 520}, size = {140, 1, 100} },
            { id = "R10_Wall_S", class = "wall",
              position = {840, FLOOR_Y + 1, 520}, size = {140, 70, 1} },
            { id = "R10_Wall_N", class = "wall",
              position = {840, FLOOR_Y + 1, 619}, size = {140, 70, 1} },
            { id = "R10_Wall_W", class = "wall",
              position = {840, FLOOR_Y + 1, 520}, size = {1, 70, 100} },
            { id = "R10_Wall_E", class = "wall",
              position = {979, FLOOR_Y + 1, 520}, size = {1, 70, 100} },

            ----------------------------------------------------------------
            -- R11: Infirmary (120x80, ceil 45)
            ----------------------------------------------------------------
            { id = "R11_Floor", class = "floor",
              position = {360, FLOOR_Y, 260}, size = {120, 1, 80} },
            { id = "R11_Wall_S", class = "wall",
              position = {360, FLOOR_Y + 1, 260}, size = {120, 45, 1} },
            { id = "R11_Wall_N", class = "wall",
              position = {360, FLOOR_Y + 1, 339}, size = {120, 45, 1} },
            { id = "R11_Wall_W", class = "wall",
              position = {360, FLOOR_Y + 1, 260}, size = {1, 45, 80} },
            { id = "R11_Wall_E", class = "wall",
              position = {479, FLOOR_Y + 1, 260}, size = {1, 45, 80} },

            ----------------------------------------------------------------
            -- R12: Holding Cells (60x120, ceil 35)
            ----------------------------------------------------------------
            { id = "R12_Floor", class = "floor",
              position = {260, FLOOR_Y, 480}, size = {60, 1, 120} },
            { id = "R12_Wall_S", class = "wall",
              position = {260, FLOOR_Y + 1, 480}, size = {60, 35, 1} },
            { id = "R12_Wall_N", class = "wall",
              position = {260, FLOOR_Y + 1, 599}, size = {60, 35, 1} },
            { id = "R12_Wall_W", class = "wall",
              position = {260, FLOOR_Y + 1, 480}, size = {1, 35, 120} },
            { id = "R12_Wall_E", class = "wall",
              position = {319, FLOOR_Y + 1, 480}, size = {1, 35, 120} },

            ----------------------------------------------------------------
            -- CORRIDORS (10 wide interior, butt against room walls)
            ----------------------------------------------------------------

            -- C01: Stair Landing Connector (20x30, ceil 40)
            { id = "C01_Floor", class = "floor",
              position = {680, FLOOR_Y, 426}, size = {20, 1, 30} },
            { id = "C01_Wall_S", class = "wall",
              position = {680, FLOOR_Y + 1, 426}, size = {20, 40, 1} },
            { id = "C01_Wall_N", class = "wall",
              position = {680, FLOOR_Y + 1, 455}, size = {20, 40, 1} },

            -- C02: Hall to Lift (20x22, ceil 36)
            { id = "C02_Floor", class = "floor",
              position = {680, FLOOR_Y, 474}, size = {20, 1, 22} },
            { id = "C02_Wall_S", class = "wall",
              position = {680, FLOOR_Y + 1, 474}, size = {20, 36, 1} },
            { id = "C02_Wall_N", class = "wall",
              position = {680, FLOOR_Y + 1, 495}, size = {20, 36, 1} },

            -- C03: Hall to Barracks (20x32, ceil 32)
            { id = "C03_Floor", class = "floor",
              position = {520, FLOOR_Y, 404}, size = {20, 1, 32} },
            { id = "C03_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 404}, size = {20, 32, 1} },
            { id = "C03_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 435}, size = {20, 32, 1} },

            -- C04: Hall to Armory Wing (40x20, ceil 34)
            { id = "C04_Floor", class = "floor",
              position = {520, FLOOR_Y, 520}, size = {40, 1, 20} },
            { id = "C04_Wall_W", class = "wall",
              position = {520, FLOOR_Y + 1, 520}, size = {1, 34, 20} },
            { id = "C04_Wall_E", class = "wall",
              position = {559, FLOOR_Y + 1, 520}, size = {1, 34, 20} },

            -- C05: Hall to Mess (40x20, ceil 36)
            { id = "C05_Floor", class = "floor",
              position = {600, FLOOR_Y, 520}, size = {40, 1, 20} },
            { id = "C05_Wall_W", class = "wall",
              position = {600, FLOOR_Y + 1, 520}, size = {1, 36, 20} },
            { id = "C05_Wall_E", class = "wall",
              position = {639, FLOOR_Y + 1, 520}, size = {1, 36, 20} },

            -- C06: Gallery Bridge (160x40, ceil 50)
            { id = "C06_Floor", class = "floor",
              position = {740, FLOOR_Y, 380}, size = {160, 1, 40} },
            { id = "C06_Wall_S", class = "wall",
              position = {740, FLOOR_Y + 1, 380}, size = {160, 50, 1} },
            { id = "C06_Wall_N", class = "wall",
              position = {740, FLOOR_Y + 1, 419}, size = {160, 50, 1} },

            -- C07: Gallery to Chapel (30x40, ceil 42)
            { id = "C07_Floor", class = "floor",
              position = {920, FLOOR_Y, 480}, size = {30, 1, 40} },
            { id = "C07_Wall_W", class = "wall",
              position = {920, FLOOR_Y + 1, 480}, size = {1, 42, 40} },
            { id = "C07_Wall_E", class = "wall",
              position = {949, FLOOR_Y + 1, 480}, size = {1, 42, 40} },

            -- C08: Hall to Infirmary (40x28, ceil 32)
            { id = "C08_Floor", class = "floor",
              position = {480, FLOOR_Y, 292}, size = {40, 1, 28} },
            { id = "C08_Wall_S", class = "wall",
              position = {480, FLOOR_Y + 1, 292}, size = {40, 32, 1} },
            { id = "C08_Wall_N", class = "wall",
              position = {480, FLOOR_Y + 1, 319}, size = {40, 32, 1} },

            -- C09: Armory to Cells (20x20, ceil 28)
            { id = "C09_Floor", class = "floor",
              position = {300, FLOOR_Y, 580}, size = {20, 1, 20} },
            { id = "C09_Wall_S", class = "wall",
              position = {300, FLOOR_Y + 1, 580}, size = {20, 28, 1} },
            { id = "C09_Wall_N", class = "wall",
              position = {300, FLOOR_Y + 1, 599}, size = {20, 28, 1} },
        },
    },
}
