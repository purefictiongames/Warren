--[[
    Castle Dracula - Level 2: Inner Castle (Galleries / Library / Grand Hall)
    BaseShell - Floors and Walls (ceilings omitted for dev visibility)

    13 rooms + 12 corridors. Floor at Y=160 (above L1 ceilings).
    Towers R01/R02 continue vertically from L1.

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
        Positions from SVG map (1 unit = 1 stud)
--]]

local FLOOR_Y = 160  -- L2 floor height

return {
    name = "CastleDracula_L2_BaseShell",
    spec = {
        origin = "corner",

        classes = {
            floor = { Material = "Marble", Color = {85, 80, 75} },
            wall = { Material = "Brick", Color = {100, 95, 90} },
        },

        parts = {
            ----------------------------------------------------------------
            -- R01: Spiral Stair Tower Upper (40x40, ceil 95)
            ----------------------------------------------------------------
            { id = "R01_Floor", class = "floor",
              position = {700, FLOOR_Y, 420}, size = {40, 1, 40} },
            { id = "R01_Wall_S", class = "wall",
              position = {700, FLOOR_Y + 1, 420}, size = {40, 95, 1} },
            { id = "R01_Wall_N", class = "wall",
              position = {700, FLOOR_Y + 1, 459}, size = {40, 95, 1} },
            { id = "R01_Wall_W", class = "wall",
              position = {700, FLOOR_Y + 1, 420}, size = {1, 95, 40} },
            { id = "R01_Wall_E", class = "wall",
              position = {739, FLOOR_Y + 1, 420}, size = {1, 95, 40} },

            ----------------------------------------------------------------
            -- R02: Lift Shaft Upper (30x30, ceil 140)
            ----------------------------------------------------------------
            { id = "R02_Floor", class = "floor",
              position = {700, FLOOR_Y, 470}, size = {30, 1, 30} },
            { id = "R02_Wall_S", class = "wall",
              position = {700, FLOOR_Y + 1, 470}, size = {30, 140, 1} },
            { id = "R02_Wall_N", class = "wall",
              position = {700, FLOOR_Y + 1, 499}, size = {30, 140, 1} },
            { id = "R02_Wall_W", class = "wall",
              position = {700, FLOOR_Y + 1, 470}, size = {1, 140, 30} },
            { id = "R02_Wall_E", class = "wall",
              position = {729, FLOOR_Y + 1, 470}, size = {1, 140, 30} },

            ----------------------------------------------------------------
            -- R03: Grand Hall (320x220, ceil 110) - Major Hub
            ----------------------------------------------------------------
            { id = "R03_Floor", class = "floor",
              position = {520, FLOOR_Y, 340}, size = {320, 1, 220} },
            { id = "R03_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 340}, size = {320, 110, 1} },
            { id = "R03_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 559}, size = {320, 110, 1} },
            { id = "R03_Wall_W", class = "wall",
              position = {520, FLOOR_Y + 1, 340}, size = {1, 110, 220} },
            { id = "R03_Wall_E", class = "wall",
              position = {839, FLOOR_Y + 1, 340}, size = {1, 110, 220} },

            ----------------------------------------------------------------
            -- R04: Library (240x220, ceil 95) - West Wing
            ----------------------------------------------------------------
            { id = "R04_Floor", class = "floor",
              position = {280, FLOOR_Y, 300}, size = {240, 1, 220} },
            { id = "R04_Wall_S", class = "wall",
              position = {280, FLOOR_Y + 1, 300}, size = {240, 95, 1} },
            { id = "R04_Wall_N", class = "wall",
              position = {280, FLOOR_Y + 1, 519}, size = {240, 95, 1} },
            { id = "R04_Wall_W", class = "wall",
              position = {280, FLOOR_Y + 1, 300}, size = {1, 95, 220} },
            { id = "R04_Wall_E", class = "wall",
              position = {519, FLOOR_Y + 1, 300}, size = {1, 95, 220} },

            ----------------------------------------------------------------
            -- R05: Reading Nook (120x100, ceil 70)
            ----------------------------------------------------------------
            { id = "R05_Floor", class = "floor",
              position = {240, FLOOR_Y, 520}, size = {120, 1, 100} },
            { id = "R05_Wall_S", class = "wall",
              position = {240, FLOOR_Y + 1, 520}, size = {120, 70, 1} },
            { id = "R05_Wall_N", class = "wall",
              position = {240, FLOOR_Y + 1, 619}, size = {120, 70, 1} },
            { id = "R05_Wall_W", class = "wall",
              position = {240, FLOOR_Y + 1, 520}, size = {1, 70, 100} },
            { id = "R05_Wall_E", class = "wall",
              position = {359, FLOOR_Y + 1, 520}, size = {1, 70, 100} },

            ----------------------------------------------------------------
            -- R06: Archive Vault (120x100, ceil 60)
            ----------------------------------------------------------------
            { id = "R06_Floor", class = "floor",
              position = {280, FLOOR_Y, 200}, size = {120, 1, 100} },
            { id = "R06_Wall_S", class = "wall",
              position = {280, FLOOR_Y + 1, 200}, size = {120, 60, 1} },
            { id = "R06_Wall_N", class = "wall",
              position = {280, FLOOR_Y + 1, 299}, size = {120, 60, 1} },
            { id = "R06_Wall_W", class = "wall",
              position = {280, FLOOR_Y + 1, 200}, size = {1, 60, 100} },
            { id = "R06_Wall_E", class = "wall",
              position = {399, FLOOR_Y + 1, 200}, size = {1, 60, 100} },

            ----------------------------------------------------------------
            -- R07: Upper Gallery (140x180, ceil 100) - East Wing
            ----------------------------------------------------------------
            { id = "R07_Floor", class = "floor",
              position = {840, FLOOR_Y, 340}, size = {140, 1, 180} },
            { id = "R07_Wall_S", class = "wall",
              position = {840, FLOOR_Y + 1, 340}, size = {140, 100, 1} },
            { id = "R07_Wall_N", class = "wall",
              position = {840, FLOOR_Y + 1, 519}, size = {140, 100, 1} },
            { id = "R07_Wall_W", class = "wall",
              position = {840, FLOOR_Y + 1, 340}, size = {1, 100, 180} },
            { id = "R07_Wall_E", class = "wall",
              position = {979, FLOOR_Y + 1, 340}, size = {1, 100, 180} },

            ----------------------------------------------------------------
            -- R08: Overlook Walkway (80x40, ceil 110)
            ----------------------------------------------------------------
            { id = "R08_Floor", class = "floor",
              position = {900, FLOOR_Y, 300}, size = {80, 1, 40} },
            { id = "R08_Wall_S", class = "wall",
              position = {900, FLOOR_Y + 1, 300}, size = {80, 110, 1} },
            { id = "R08_Wall_N", class = "wall",
              position = {900, FLOOR_Y + 1, 339}, size = {80, 110, 1} },
            { id = "R08_Wall_W", class = "wall",
              position = {900, FLOOR_Y + 1, 300}, size = {1, 110, 40} },
            { id = "R08_Wall_E", class = "wall",
              position = {979, FLOOR_Y + 1, 300}, size = {1, 110, 40} },

            ----------------------------------------------------------------
            -- R09: Stone Passage (220x80, ceil 50) - North Wing
            ----------------------------------------------------------------
            { id = "R09_Floor", class = "floor",
              position = {520, FLOOR_Y, 260}, size = {220, 1, 80} },
            { id = "R09_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 260}, size = {220, 50, 1} },
            { id = "R09_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 339}, size = {220, 50, 1} },
            { id = "R09_Wall_W", class = "wall",
              position = {520, FLOOR_Y + 1, 260}, size = {1, 50, 80} },
            { id = "R09_Wall_E", class = "wall",
              position = {739, FLOOR_Y + 1, 260}, size = {1, 50, 80} },

            ----------------------------------------------------------------
            -- R10: Alchemy Lab (140x140, ceil 85) - Metroidvania Lock
            ----------------------------------------------------------------
            { id = "R10_Floor", class = "floor",
              position = {740, FLOOR_Y, 200}, size = {140, 1, 140} },
            { id = "R10_Wall_S", class = "wall",
              position = {740, FLOOR_Y + 1, 200}, size = {140, 85, 1} },
            { id = "R10_Wall_N", class = "wall",
              position = {740, FLOOR_Y + 1, 339}, size = {140, 85, 1} },
            { id = "R10_Wall_W", class = "wall",
              position = {740, FLOOR_Y + 1, 200}, size = {1, 85, 140} },
            { id = "R10_Wall_E", class = "wall",
              position = {879, FLOOR_Y + 1, 200}, size = {1, 85, 140} },

            ----------------------------------------------------------------
            -- R11: Chapel Upper Gallery (220x140, ceil 120) - South Wing
            ----------------------------------------------------------------
            { id = "R11_Floor", class = "floor",
              position = {900, FLOOR_Y, 620}, size = {220, 1, 140} },
            { id = "R11_Wall_S", class = "wall",
              position = {900, FLOOR_Y + 1, 620}, size = {220, 120, 1} },
            { id = "R11_Wall_N", class = "wall",
              position = {900, FLOOR_Y + 1, 759}, size = {220, 120, 1} },
            { id = "R11_Wall_W", class = "wall",
              position = {900, FLOOR_Y + 1, 620}, size = {1, 120, 140} },
            { id = "R11_Wall_E", class = "wall",
              position = {1119, FLOOR_Y + 1, 620}, size = {1, 120, 140} },

            ----------------------------------------------------------------
            -- R12: Gallery Storage (100x100, ceil 55) - Secret to Library
            ----------------------------------------------------------------
            { id = "R12_Floor", class = "floor",
              position = {420, FLOOR_Y, 560}, size = {100, 1, 100} },
            { id = "R12_Wall_S", class = "wall",
              position = {420, FLOOR_Y + 1, 560}, size = {100, 55, 1} },
            { id = "R12_Wall_N", class = "wall",
              position = {420, FLOOR_Y + 1, 659}, size = {100, 55, 1} },
            { id = "R12_Wall_W", class = "wall",
              position = {420, FLOOR_Y + 1, 560}, size = {1, 55, 100} },
            { id = "R12_Wall_E", class = "wall",
              position = {519, FLOOR_Y + 1, 560}, size = {1, 55, 100} },

            ----------------------------------------------------------------
            -- R13: Broken Balcony Drop (80x60, ceil 140) - One-way
            ----------------------------------------------------------------
            { id = "R13_Floor", class = "floor",
              position = {1120, FLOOR_Y, 520}, size = {80, 1, 60} },
            { id = "R13_Wall_S", class = "wall",
              position = {1120, FLOOR_Y + 1, 520}, size = {80, 140, 1} },
            { id = "R13_Wall_N", class = "wall",
              position = {1120, FLOOR_Y + 1, 579}, size = {80, 140, 1} },
            { id = "R13_Wall_W", class = "wall",
              position = {1120, FLOOR_Y + 1, 520}, size = {1, 140, 60} },
            { id = "R13_Wall_E", class = "wall",
              position = {1199, FLOOR_Y + 1, 520}, size = {1, 140, 60} },

            ----------------------------------------------------------------
            -- CORRIDORS
            ----------------------------------------------------------------

            -- C01: Stair Landing to Grand Hall (100x30, ceil 50)
            { id = "C01_Floor", class = "floor",
              position = {740, FLOOR_Y, 430}, size = {100, 1, 30} },
            { id = "C01_Wall_S", class = "wall",
              position = {740, FLOOR_Y + 1, 430}, size = {100, 50, 1} },
            { id = "C01_Wall_N", class = "wall",
              position = {740, FLOOR_Y + 1, 459}, size = {100, 50, 1} },

            -- C02: Grand Hall to Lift (20x30, ceil 48)
            { id = "C02_Floor", class = "floor",
              position = {680, FLOOR_Y, 500}, size = {20, 1, 30} },
            { id = "C02_Wall_W", class = "wall",
              position = {680, FLOOR_Y + 1, 500}, size = {1, 48, 30} },
            { id = "C02_Wall_E", class = "wall",
              position = {699, FLOOR_Y + 1, 500}, size = {1, 48, 30} },

            -- C03: Grand Hall to Library (20x60, ceil 55)
            { id = "C03_Floor", class = "floor",
              position = {500, FLOOR_Y, 420}, size = {20, 1, 60} },
            { id = "C03_Wall_S", class = "wall",
              position = {500, FLOOR_Y + 1, 420}, size = {20, 55, 1} },
            { id = "C03_Wall_N", class = "wall",
              position = {500, FLOOR_Y + 1, 479}, size = {20, 55, 1} },

            -- C04: Library to Reading Nook (40x20, ceil 45)
            { id = "C04_Floor", class = "floor",
              position = {320, FLOOR_Y, 520}, size = {40, 1, 20} },
            { id = "C04_Wall_W", class = "wall",
              position = {320, FLOOR_Y + 1, 520}, size = {1, 45, 20} },
            { id = "C04_Wall_E", class = "wall",
              position = {359, FLOOR_Y + 1, 520}, size = {1, 45, 20} },

            -- C05: Library to Vault (40x20, ceil 40)
            { id = "C05_Floor", class = "floor",
              position = {340, FLOOR_Y, 300}, size = {40, 1, 20} },
            { id = "C05_Wall_W", class = "wall",
              position = {340, FLOOR_Y + 1, 300}, size = {1, 40, 20} },
            { id = "C05_Wall_E", class = "wall",
              position = {379, FLOOR_Y + 1, 300}, size = {1, 40, 20} },

            -- C06: Grand Hall to Upper Gallery (20x60, ceil 55)
            { id = "C06_Floor", class = "floor",
              position = {840, FLOOR_Y, 420}, size = {20, 1, 60} },
            { id = "C06_Wall_S", class = "wall",
              position = {840, FLOOR_Y + 1, 420}, size = {20, 55, 1} },
            { id = "C06_Wall_N", class = "wall",
              position = {840, FLOOR_Y + 1, 479}, size = {20, 55, 1} },

            -- C07: Upper Gallery to Overlook (20x20, ceil 60)
            { id = "C07_Floor", class = "floor",
              position = {940, FLOOR_Y, 340}, size = {20, 1, 20} },
            { id = "C07_Wall_W", class = "wall",
              position = {940, FLOOR_Y + 1, 340}, size = {1, 60, 20} },
            { id = "C07_Wall_E", class = "wall",
              position = {959, FLOOR_Y + 1, 340}, size = {1, 60, 20} },

            -- C08: Grand Hall to Stone Passage (80x20, ceil 48)
            { id = "C08_Floor", class = "floor",
              position = {620, FLOOR_Y, 340}, size = {80, 1, 20} },
            { id = "C08_Wall_W", class = "wall",
              position = {620, FLOOR_Y + 1, 340}, size = {1, 48, 20} },
            { id = "C08_Wall_E", class = "wall",
              position = {699, FLOOR_Y + 1, 340}, size = {1, 48, 20} },

            -- C09: Stone Passage to Lab (20x40, ceil 42)
            { id = "C09_Floor", class = "floor",
              position = {740, FLOOR_Y, 300}, size = {20, 1, 40} },
            { id = "C09_Wall_S", class = "wall",
              position = {740, FLOOR_Y + 1, 300}, size = {20, 42, 1} },
            { id = "C09_Wall_N", class = "wall",
              position = {740, FLOOR_Y + 1, 339}, size = {20, 42, 1} },

            -- C10: Grand Hall to Chapel Upper (80x60, ceil 60)
            { id = "C10_Floor", class = "floor",
              position = {840, FLOOR_Y, 560}, size = {80, 1, 60} },
            { id = "C10_Wall_W", class = "wall",
              position = {840, FLOOR_Y + 1, 560}, size = {1, 60, 60} },
            { id = "C10_Wall_E", class = "wall",
              position = {919, FLOOR_Y + 1, 560}, size = {1, 60, 60} },

            -- C11: Grand Hall to Storage (40x20, ceil 40)
            { id = "C11_Floor", class = "floor",
              position = {520, FLOOR_Y, 560}, size = {40, 1, 20} },
            { id = "C11_Wall_S", class = "wall",
              position = {520, FLOOR_Y + 1, 560}, size = {40, 40, 1} },
            { id = "C11_Wall_N", class = "wall",
              position = {520, FLOOR_Y + 1, 579}, size = {40, 40, 1} },

            -- C12: Upper Gallery to Drop (140x20, ceil 55)
            { id = "C12_Floor", class = "floor",
              position = {980, FLOOR_Y, 520}, size = {140, 1, 20} },
            { id = "C12_Wall_S", class = "wall",
              position = {980, FLOOR_Y + 1, 520}, size = {140, 55, 1} },
            { id = "C12_Wall_N", class = "wall",
              position = {980, FLOOR_Y + 1, 539}, size = {140, 55, 1} },
        },
    },
}
