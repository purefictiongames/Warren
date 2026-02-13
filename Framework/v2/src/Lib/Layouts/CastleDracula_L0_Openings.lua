--[[
    Castle Dracula - Level 0: Grotto / Crypt
    Door Openings - Cut holes between rooms and corridors

    Parts with geometry = "negate" are CSG subtracted from intersecting walls.
    AABB intersection auto-detects which walls to cut.

    Door sizes based on room scale:
    - Large (grand halls): 10w x 14h
    - Medium (chambers): 6w x 10h
    - Small (passages): 4w x 8h

    Corridor width: 10 studs exterior, 8 studs interior (1-stud walls)
    Door openings: 8 studs to fit inside corridor walls

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
--]]

return {
    name = "CastleDracula_L0_Openings",
    spec = {
        origin = "corner",

        parts = {
            ----------------------------------------------------------------
            -- ROOM TO ROOM (shared walls)
            ----------------------------------------------------------------

            -- R01 to R02: East wall of R01 (x=259), centered in overlap
            { id = "D_R01_R02", geometry = "negate",
              position = {258, 1, 456}, size = {3, 10, 8} },

            -- R04 to R05: Shared at x=620, z=400-440 overlap
            { id = "D_R04_R05", geometry = "negate",
              position = {618, 1, 410}, size = {4, 14, 10} },

            -- R05 to R06: Shared at x=660, z=340-400 overlap
            { id = "D_R05_R06", geometry = "negate",
              position = {658, 1, 360}, size = {4, 10, 8} },

            ----------------------------------------------------------------
            -- CORRIDOR C01: R02 to R03 (interior z=456-464)
            ----------------------------------------------------------------
            -- R02 east wall to C01
            { id = "D_R02_C01", geometry = "negate",
              position = {278, 1, 456}, size = {3, 10, 8} },
            -- C01 to R03 west wall
            { id = "D_C01_R03", geometry = "negate",
              position = {319, 1, 456}, size = {3, 10, 8} },

            ----------------------------------------------------------------
            -- CORRIDOR C02: R03 to R04 (interior z=456-464)
            ----------------------------------------------------------------
            -- R03 east wall to C02
            { id = "D_R03_C02", geometry = "negate",
              position = {398, 1, 456}, size = {3, 12, 8} },
            -- C02 to R04 west wall
            { id = "D_C02_R04", geometry = "negate",
              position = {459, 1, 456}, size = {3, 14, 8} },

            ----------------------------------------------------------------
            -- CORRIDOR C03: R04 to R11/R12 (interior z=448-456)
            ----------------------------------------------------------------
            -- R04 east wall to C03
            { id = "D_R04_C03", geometry = "negate",
              position = {618, 1, 448}, size = {3, 14, 8} },
            -- C03 to R11 west wall
            { id = "D_C03_R11", geometry = "negate",
              position = {699, 1, 448}, size = {3, 12, 8} },
            -- C03 to R12 (north side of corridor)
            { id = "D_C03_R12", geometry = "negate",
              position = {700, 1, 469}, size = {8, 10, 3} },

            ----------------------------------------------------------------
            -- CORRIDOR C04: R04 to R07 (interior x=480-488)
            ----------------------------------------------------------------
            -- R04 south wall to C04
            { id = "D_R04_C04", geometry = "negate",
              position = {480, 1, 518}, size = {8, 14, 3} },
            -- C04 to R07 north wall
            { id = "D_C04_R07", geometry = "negate",
              position = {480, 1, 559}, size = {8, 12, 3} },

            ----------------------------------------------------------------
            -- CORRIDOR C05: R07 to R13 (interior z=580-588)
            ----------------------------------------------------------------
            -- R07 east wall to C05
            { id = "D_R07_C05", geometry = "negate",
              position = {508, 1, 580}, size = {3, 10, 8} },
            -- C05 to R13 west wall
            { id = "D_C05_R13", geometry = "negate",
              position = {519, 1, 580}, size = {3, 12, 8} },

            ----------------------------------------------------------------
            -- CORRIDOR C06: R07 to R09 (interior x=460-468)
            ----------------------------------------------------------------
            -- R07 south wall to C06
            { id = "D_R07_C06", geometry = "negate",
              position = {460, 1, 618}, size = {8, 10, 3} },
            -- C06 to R09 north wall
            { id = "D_C06_R09", geometry = "negate",
              position = {460, 1, 659}, size = {8, 10, 3} },

            ----------------------------------------------------------------
            -- CORRIDOR C07: R07 to R16 (interior z=576-584)
            ----------------------------------------------------------------
            -- R07 west wall to C07
            { id = "D_R07_C07", geometry = "negate",
              position = {419, 1, 576}, size = {3, 10, 8} },
            -- C07 to R16 east wall
            { id = "D_C07_R16", geometry = "negate",
              position = {408, 1, 576}, size = {3, 10, 8} },

            ----------------------------------------------------------------
            -- C08/C09: R08 to R17 to R18
            ----------------------------------------------------------------
            -- R08 to R17 (corner connection)
            { id = "D_R08_R17", geometry = "negate",
              position = {334, 1, 640}, size = {6, 10, 5} },
            -- R17 to C09
            { id = "D_R17_C09", geometry = "negate",
              position = {299, 1, 641}, size = {3, 10, 8} },
            -- C09 to R18
            { id = "D_C09_R18", geometry = "negate",
              position = {279, 1, 649}, size = {3, 10, 3} },

            ----------------------------------------------------------------
            -- CORRIDOR C10: R09 to R10 (interior z=665-673)
            ----------------------------------------------------------------
            -- R09 east wall to C10
            { id = "D_R09_C10", geometry = "negate",
              position = {528, 1, 665}, size = {3, 10, 8} },
            -- C10 to R10 west wall
            { id = "D_C10_R10", geometry = "negate",
              position = {559, 1, 665}, size = {3, 10, 8} },

            ----------------------------------------------------------------
            -- CORRIDOR C11: R13 to R10 (interior x=580-588)
            ----------------------------------------------------------------
            -- R13 north wall to C11
            { id = "D_R13_C11", geometry = "negate",
              position = {580, 1, 658}, size = {8, 10, 3} },
            -- C11 to R10 south wall
            { id = "D_C11_R10", geometry = "negate",
              position = {580, 1, 649}, size = {8, 10, 3} },

            ----------------------------------------------------------------
            -- CORRIDOR C12: R13 to R14 (interior x=488-496)
            ----------------------------------------------------------------
            -- R13 south wall to C12
            { id = "D_R13_C12", geometry = "negate",
              position = {488, 1, 658}, size = {8, 12, 3} },
            -- C12 to R14 north wall
            { id = "D_C12_R14", geometry = "negate",
              position = {488, 1, 679}, size = {8, 10, 3} },

            ----------------------------------------------------------------
            -- CORRIDOR C13: R14 to R15 (interior z=720-728)
            ----------------------------------------------------------------
            -- R14 east wall to C13
            { id = "D_R14_C13", geometry = "negate",
              position = {503, 1, 720}, size = {3, 10, 8} },
            -- C13 to R15 west wall
            { id = "D_C13_R15", geometry = "negate",
              position = {519, 1, 720}, size = {3, 12, 8} },

            ----------------------------------------------------------------
            -- CORRIDOR C14: R08 to R09 (interior z=665-673)
            ----------------------------------------------------------------
            -- R08 south wall to C14
            { id = "D_R08_C14", geometry = "negate",
              position = {365, 1, 688}, size = {8, 10, 3} },
            -- C14 to R09 west wall
            { id = "D_C14_R09", geometry = "negate",
              position = {419, 1, 665}, size = {3, 10, 8} },
        },
    },
}
