--[[
    Castle Dracula - Level 0: Grotto / Crypt
    BaseShell - Floors and Walls (ceilings omitted for dev visibility)

    18 rooms total. Solid walls everywhere, doorways cut separately.

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
        Positions from SVG map (1 unit = 1 stud)
--]]

--------------------------------------------------------------------------------
-- LAYOUT
--------------------------------------------------------------------------------

return {
    name = "CastleDracula_L0_BaseShell",
    spec = {
        origin = "corner",

        classes = {
            floor = { Material = "Slate", Color = {60, 55, 50} },
            wall = { Material = "Slate", Color = {80, 75, 70} },
        },

        parts = {
            ----------------------------------------------------------------
            -- R01: Collapsed Cave Entry (60x80, ceil 35)
            ----------------------------------------------------------------
            { id = "R01_Floor", class = "floor",
              position = {200, 0, 420}, size = {60, 1, 80} },
            { id = "R01_Wall_S", class = "wall",
              position = {200, 1, 420}, size = {60, 35, 1} },
            { id = "R01_Wall_N", class = "wall",
              position = {200, 1, 499}, size = {60, 35, 1} },
            { id = "R01_Wall_W", class = "wall",
              position = {200, 1, 420}, size = {1, 35, 80} },
            { id = "R01_Wall_E", class = "wall",
              position = {259, 1, 420}, size = {1, 35, 80} },

            ----------------------------------------------------------------
            -- R02: Narrow Rock Corridor (20x70, ceil 18)
            ----------------------------------------------------------------
            { id = "R02_Floor", class = "floor",
              position = {260, 0, 432}, size = {20, 1, 70} },
            { id = "R02_Wall_S", class = "wall",
              position = {260, 1, 432}, size = {20, 18, 1} },
            { id = "R02_Wall_N", class = "wall",
              position = {260, 1, 501}, size = {20, 18, 1} },
            { id = "R02_Wall_W", class = "wall",
              position = {260, 1, 432}, size = {1, 18, 70} },
            { id = "R02_Wall_E", class = "wall",
              position = {279, 1, 432}, size = {1, 18, 70} },

            ----------------------------------------------------------------
            -- R03: Crypt Antechamber (80x80, ceil 45)
            ----------------------------------------------------------------
            { id = "R03_Floor", class = "floor",
              position = {320, 0, 420}, size = {80, 1, 80} },
            { id = "R03_Wall_S", class = "wall",
              position = {320, 1, 420}, size = {80, 45, 1} },
            { id = "R03_Wall_N", class = "wall",
              position = {320, 1, 499}, size = {80, 45, 1} },
            { id = "R03_Wall_W", class = "wall",
              position = {320, 1, 420}, size = {1, 45, 80} },
            { id = "R03_Wall_E", class = "wall",
              position = {399, 1, 420}, size = {1, 45, 80} },

            ----------------------------------------------------------------
            -- R04: Grand Sunken Crypt Hall (160x120, ceil 70, floor -10)
            ----------------------------------------------------------------
            { id = "R04_Floor", class = "floor",
              position = {460, -10, 400}, size = {160, 1, 120} },
            { id = "R04_Wall_S", class = "wall",
              position = {460, -9, 400}, size = {160, 70, 1} },
            { id = "R04_Wall_N", class = "wall",
              position = {460, -9, 519}, size = {160, 70, 1} },
            { id = "R04_Wall_W", class = "wall",
              position = {460, -9, 400}, size = {1, 70, 120} },
            { id = "R04_Wall_E", class = "wall",
              position = {619, -9, 400}, size = {1, 70, 120} },

            ----------------------------------------------------------------
            -- R05: Broken Crypt Balcony (40x120, ceil 120)
            ----------------------------------------------------------------
            { id = "R05_Floor", class = "floor",
              position = {620, 0, 320}, size = {40, 1, 120} },
            { id = "R05_Wall_S", class = "wall",
              position = {620, 1, 320}, size = {40, 120, 1} },
            { id = "R05_Wall_N", class = "wall",
              position = {620, 1, 439}, size = {40, 120, 1} },
            { id = "R05_Wall_W", class = "wall",
              position = {620, 1, 320}, size = {1, 120, 120} },
            { id = "R05_Wall_E", class = "wall",
              position = {659, 1, 320}, size = {1, 120, 120} },

            ----------------------------------------------------------------
            -- R06: Grave Warden Passage (25x60, ceil 22)
            ----------------------------------------------------------------
            { id = "R06_Floor", class = "floor",
              position = {660, 0, 340}, size = {25, 1, 60} },
            { id = "R06_Wall_S", class = "wall",
              position = {660, 1, 340}, size = {25, 22, 1} },
            { id = "R06_Wall_N", class = "wall",
              position = {660, 1, 399}, size = {25, 22, 1} },
            { id = "R06_Wall_W", class = "wall",
              position = {660, 1, 340}, size = {1, 22, 60} },
            { id = "R06_Wall_E", class = "wall",
              position = {684, 1, 340}, size = {1, 22, 60} },

            ----------------------------------------------------------------
            -- R07: Ossuary Chamber (90x60, ceil 30)
            ----------------------------------------------------------------
            { id = "R07_Floor", class = "floor",
              position = {420, 0, 560}, size = {90, 1, 60} },
            { id = "R07_Wall_S", class = "wall",
              position = {420, 1, 560}, size = {90, 30, 1} },
            { id = "R07_Wall_N", class = "wall",
              position = {420, 1, 619}, size = {90, 30, 1} },
            { id = "R07_Wall_W", class = "wall",
              position = {420, 1, 560}, size = {1, 30, 60} },
            { id = "R07_Wall_E", class = "wall",
              position = {509, 1, 560}, size = {1, 30, 60} },

            ----------------------------------------------------------------
            -- R08: Collapsed Burial Room (50x50, ceil 15)
            ----------------------------------------------------------------
            { id = "R08_Floor", class = "floor",
              position = {340, 0, 640}, size = {50, 1, 50} },
            { id = "R08_Wall_S", class = "wall",
              position = {340, 1, 640}, size = {50, 15, 1} },
            { id = "R08_Wall_N", class = "wall",
              position = {340, 1, 689}, size = {50, 15, 1} },
            { id = "R08_Wall_W", class = "wall",
              position = {340, 1, 640}, size = {1, 15, 50} },
            { id = "R08_Wall_E", class = "wall",
              position = {389, 1, 640}, size = {1, 15, 50} },

            ----------------------------------------------------------------
            -- R09: Twin Sarcophagus Hall (110x30, ceil 28)
            ----------------------------------------------------------------
            { id = "R09_Floor", class = "floor",
              position = {420, 0, 660}, size = {110, 1, 30} },
            { id = "R09_Wall_S", class = "wall",
              position = {420, 1, 660}, size = {110, 28, 1} },
            { id = "R09_Wall_N", class = "wall",
              position = {420, 1, 689}, size = {110, 28, 1} },
            { id = "R09_Wall_W", class = "wall",
              position = {420, 1, 660}, size = {1, 28, 30} },
            { id = "R09_Wall_E", class = "wall",
              position = {529, 1, 660}, size = {1, 28, 30} },

            ----------------------------------------------------------------
            -- R10: Hidden Reliquary (40x40, ceil 25)
            ----------------------------------------------------------------
            { id = "R10_Floor", class = "floor",
              position = {560, 0, 650}, size = {40, 1, 40} },
            { id = "R10_Wall_S", class = "wall",
              position = {560, 1, 650}, size = {40, 25, 1} },
            { id = "R10_Wall_N", class = "wall",
              position = {560, 1, 689}, size = {40, 25, 1} },
            { id = "R10_Wall_W", class = "wall",
              position = {560, 1, 650}, size = {1, 25, 40} },
            { id = "R10_Wall_E", class = "wall",
              position = {599, 1, 650}, size = {1, 25, 40} },

            ----------------------------------------------------------------
            -- R11: Spiral Stair Tower (40x40, ceil 90)
            ----------------------------------------------------------------
            { id = "R11_Floor", class = "floor",
              position = {700, 0, 420}, size = {40, 1, 40} },
            { id = "R11_Wall_S", class = "wall",
              position = {700, 1, 420}, size = {40, 90, 1} },
            { id = "R11_Wall_N", class = "wall",
              position = {700, 1, 459}, size = {40, 90, 1} },
            { id = "R11_Wall_W", class = "wall",
              position = {700, 1, 420}, size = {1, 90, 40} },
            { id = "R11_Wall_E", class = "wall",
              position = {739, 1, 420}, size = {1, 90, 40} },

            ----------------------------------------------------------------
            -- R12: Broken Lift Shaft (30x30, ceil 120)
            ----------------------------------------------------------------
            { id = "R12_Floor", class = "floor",
              position = {700, 0, 470}, size = {30, 1, 30} },
            { id = "R12_Wall_S", class = "wall",
              position = {700, 1, 470}, size = {30, 120, 1} },
            { id = "R12_Wall_N", class = "wall",
              position = {700, 1, 499}, size = {30, 120, 1} },
            { id = "R12_Wall_W", class = "wall",
              position = {700, 1, 470}, size = {1, 120, 30} },
            { id = "R12_Wall_E", class = "wall",
              position = {729, 1, 470}, size = {1, 120, 30} },

            ----------------------------------------------------------------
            -- R13: Flooded Cavern (140x100, ceil 55)
            ----------------------------------------------------------------
            { id = "R13_Floor", class = "floor",
              position = {520, 0, 560}, size = {140, 1, 100} },
            { id = "R13_Wall_S", class = "wall",
              position = {520, 1, 560}, size = {140, 55, 1} },
            { id = "R13_Wall_N", class = "wall",
              position = {520, 1, 659}, size = {140, 55, 1} },
            { id = "R13_Wall_W", class = "wall",
              position = {520, 1, 560}, size = {1, 55, 100} },
            { id = "R13_Wall_E", class = "wall",
              position = {659, 1, 560}, size = {1, 55, 100} },

            ----------------------------------------------------------------
            -- R14: Stalagmite Pass (25x90, ceil 40)
            ----------------------------------------------------------------
            { id = "R14_Floor", class = "floor",
              position = {480, 0, 680}, size = {25, 1, 90} },
            { id = "R14_Wall_S", class = "wall",
              position = {480, 1, 680}, size = {25, 40, 1} },
            { id = "R14_Wall_N", class = "wall",
              position = {480, 1, 769}, size = {25, 40, 1} },
            { id = "R14_Wall_W", class = "wall",
              position = {480, 1, 680}, size = {1, 40, 90} },
            { id = "R14_Wall_E", class = "wall",
              position = {504, 1, 680}, size = {1, 40, 90} },

            ----------------------------------------------------------------
            -- R15: Ancient Ritual Cave (100x100, ceil 80)
            ----------------------------------------------------------------
            { id = "R15_Floor", class = "floor",
              position = {520, 0, 700}, size = {100, 1, 100} },
            { id = "R15_Wall_S", class = "wall",
              position = {520, 1, 700}, size = {100, 80, 1} },
            { id = "R15_Wall_N", class = "wall",
              position = {520, 1, 799}, size = {100, 80, 1} },
            { id = "R15_Wall_W", class = "wall",
              position = {520, 1, 700}, size = {1, 80, 100} },
            { id = "R15_Wall_E", class = "wall",
              position = {619, 1, 700}, size = {1, 80, 100} },

            ----------------------------------------------------------------
            -- R16: Cracked Ledge Drop (20x40, ceil 18)
            ----------------------------------------------------------------
            { id = "R16_Floor", class = "floor",
              position = {390, 0, 560}, size = {20, 1, 40} },
            { id = "R16_Wall_S", class = "wall",
              position = {390, 1, 560}, size = {20, 18, 1} },
            { id = "R16_Wall_N", class = "wall",
              position = {390, 1, 599}, size = {20, 18, 1} },
            { id = "R16_Wall_W", class = "wall",
              position = {390, 1, 560}, size = {1, 18, 40} },
            { id = "R16_Wall_E", class = "wall",
              position = {409, 1, 560}, size = {1, 18, 40} },

            ----------------------------------------------------------------
            -- R17: Burial Pit (35x35, ceil 40)
            ----------------------------------------------------------------
            { id = "R17_Floor", class = "floor",
              position = {300, 0, 610}, size = {35, 1, 35} },
            { id = "R17_Wall_S", class = "wall",
              position = {300, 1, 610}, size = {35, 40, 1} },
            { id = "R17_Wall_N", class = "wall",
              position = {300, 1, 644}, size = {35, 40, 1} },
            { id = "R17_Wall_W", class = "wall",
              position = {300, 1, 610}, size = {1, 40, 35} },
            { id = "R17_Wall_E", class = "wall",
              position = {334, 1, 610}, size = {1, 40, 35} },

            ----------------------------------------------------------------
            -- R18: Sealed Stone Door (60x20, ceil 22)
            ----------------------------------------------------------------
            { id = "R18_Floor", class = "floor",
              position = {220, 0, 650}, size = {60, 1, 20} },
            { id = "R18_Wall_S", class = "wall",
              position = {220, 1, 650}, size = {60, 22, 1} },
            { id = "R18_Wall_N", class = "wall",
              position = {220, 1, 669}, size = {60, 22, 1} },
            { id = "R18_Wall_W", class = "wall",
              position = {220, 1, 650}, size = {1, 22, 20} },
            { id = "R18_Wall_E", class = "wall",
              position = {279, 1, 650}, size = {1, 22, 20} },

            ----------------------------------------------------------------
            -- CORRIDORS (10 wide, butt against room walls)
            ----------------------------------------------------------------

            -- C01: R02 to R03 (x=280 to x=320, 10 wide)
            { id = "C01_Floor", class = "floor",
              position = {280, 0, 455}, size = {40, 1, 10} },
            { id = "C01_Wall_S", class = "wall",
              position = {280, 1, 455}, size = {40, 18, 1} },
            { id = "C01_Wall_N", class = "wall",
              position = {280, 1, 464}, size = {40, 18, 1} },

            -- C02: R03 to R04 (x=400 to x=460, 10 wide)
            { id = "C02_Floor", class = "floor",
              position = {400, 0, 455}, size = {60, 1, 10} },
            { id = "C02_Wall_S", class = "wall",
              position = {400, 1, 455}, size = {60, 18, 1} },
            { id = "C02_Wall_N", class = "wall",
              position = {400, 1, 464}, size = {60, 18, 1} },

            -- C03: R04 to R11/R12 (x=620 to x=700, 10 wide)
            { id = "C03_Floor", class = "floor",
              position = {620, 0, 447}, size = {80, 1, 10} },
            { id = "C03_Wall_S", class = "wall",
              position = {620, 1, 447}, size = {80, 20, 1} },
            { id = "C03_Wall_N", class = "wall",
              position = {620, 1, 456}, size = {80, 20, 1} },

            -- C04: R04 to R07 (z=520 to z=560, 10 wide)
            { id = "C04_Floor", class = "floor",
              position = {479, 0, 520}, size = {10, 1, 40} },
            { id = "C04_Wall_W", class = "wall",
              position = {479, 1, 520}, size = {1, 20, 40} },
            { id = "C04_Wall_E", class = "wall",
              position = {488, 1, 520}, size = {1, 20, 40} },

            -- C05: R07 to R13 (x=510 to x=520, 10 wide)
            { id = "C05_Floor", class = "floor",
              position = {510, 0, 579}, size = {10, 1, 10} },
            { id = "C05_Wall_S", class = "wall",
              position = {510, 1, 579}, size = {10, 20, 1} },
            { id = "C05_Wall_N", class = "wall",
              position = {510, 1, 588}, size = {10, 20, 1} },

            -- C06: R07 to R09 (z=620 to z=660, 10 wide)
            { id = "C06_Floor", class = "floor",
              position = {459, 0, 620}, size = {10, 1, 40} },
            { id = "C06_Wall_W", class = "wall",
              position = {459, 1, 620}, size = {1, 20, 40} },
            { id = "C06_Wall_E", class = "wall",
              position = {468, 1, 620}, size = {1, 20, 40} },

            -- C07: R07 to R16 (x=410 to x=420, 10 wide)
            { id = "C07_Floor", class = "floor",
              position = {410, 0, 575}, size = {10, 1, 10} },
            { id = "C07_Wall_S", class = "wall",
              position = {410, 1, 575}, size = {10, 18, 1} },
            { id = "C07_Wall_N", class = "wall",
              position = {410, 1, 584}, size = {10, 18, 1} },

            -- C08: R08 to R17 (corner connection, 6x6)
            { id = "C08_Floor", class = "floor",
              position = {335, 0, 640}, size = {5, 1, 5} },

            -- C09: R17 to R18 (x=280 to x=300, 10 wide)
            { id = "C09_Floor", class = "floor",
              position = {280, 0, 640}, size = {20, 1, 10} },
            { id = "C09_Wall_S", class = "wall",
              position = {280, 1, 640}, size = {20, 18, 1} },
            { id = "C09_Wall_N", class = "wall",
              position = {280, 1, 649}, size = {20, 18, 1} },

            -- C10: R09 to R10 (x=530 to x=560, 10 wide)
            { id = "C10_Floor", class = "floor",
              position = {530, 0, 664}, size = {30, 1, 10} },
            { id = "C10_Wall_S", class = "wall",
              position = {530, 1, 664}, size = {30, 20, 1} },
            { id = "C10_Wall_N", class = "wall",
              position = {530, 1, 673}, size = {30, 20, 1} },

            -- C11: R13 to R10 (z=650 to z=660, 10 wide)
            { id = "C11_Floor", class = "floor",
              position = {579, 0, 650}, size = {10, 1, 10} },
            { id = "C11_Wall_W", class = "wall",
              position = {579, 1, 650}, size = {1, 20, 10} },
            { id = "C11_Wall_E", class = "wall",
              position = {588, 1, 650}, size = {1, 20, 10} },

            -- C12: R13 to R14 (z=660 to z=680, 10 wide)
            { id = "C12_Floor", class = "floor",
              position = {487, 0, 660}, size = {10, 1, 20} },
            { id = "C12_Wall_W", class = "wall",
              position = {487, 1, 660}, size = {1, 20, 20} },
            { id = "C12_Wall_E", class = "wall",
              position = {496, 1, 660}, size = {1, 20, 20} },

            -- C13: R14 to R15 (x=505 to x=520, 10 wide)
            { id = "C13_Floor", class = "floor",
              position = {505, 0, 719}, size = {15, 1, 10} },
            { id = "C13_Wall_S", class = "wall",
              position = {505, 1, 719}, size = {15, 20, 1} },
            { id = "C13_Wall_N", class = "wall",
              position = {505, 1, 728}, size = {15, 20, 1} },

            -- C14: R08 to R09 (x=390 to x=420, 10 wide)
            { id = "C14_Floor", class = "floor",
              position = {390, 0, 664}, size = {30, 1, 10} },
            { id = "C14_Wall_S", class = "wall",
              position = {390, 1, 664}, size = {30, 15, 1} },
            { id = "C14_Wall_N", class = "wall",
              position = {390, 1, 673}, size = {30, 15, 1} },
        },
    },
}
