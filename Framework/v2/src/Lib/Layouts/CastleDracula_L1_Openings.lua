--[[
    Castle Dracula - Level 1: Lower Castle / Guard Quarters
    Door Openings - Cut holes between rooms and corridors

    Parts with geometry = "negate" are CSG subtracted from intersecting walls.
    AABB intersection auto-detects which walls to cut.

    Corridor interior: 8 studs (walls on edges)
    Door openings: 8 studs wide to fit inside corridor walls

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
--]]

local FLOOR_Y = 70  -- L1 floor height

return {
    name = "CastleDracula_L1_Openings",
    spec = {
        origin = "corner",

        parts = {
            ----------------------------------------------------------------
            -- C01: Stair Landing Connector (R03 to R01)
            ----------------------------------------------------------------
            -- R03 east wall to C01
            { id = "D_R03_C01", geometry = "negate",
              position = {678, FLOOR_Y + 1, 427}, size = {3, 12, 28} },
            -- C01 to R01 west wall
            { id = "D_C01_R01", geometry = "negate",
              position = {699, FLOOR_Y + 1, 427}, size = {3, 12, 28} },

            ----------------------------------------------------------------
            -- C02: Hall to Lift (R03 to R02)
            ----------------------------------------------------------------
            -- R03 east wall to C02
            { id = "D_R03_C02", geometry = "negate",
              position = {678, FLOOR_Y + 1, 475}, size = {3, 10, 20} },
            -- C02 to R02 west wall
            { id = "D_C02_R02", geometry = "negate",
              position = {699, FLOOR_Y + 1, 475}, size = {3, 10, 20} },

            ----------------------------------------------------------------
            -- C03: Hall to Barracks (R03 to R04)
            ----------------------------------------------------------------
            -- R03 west wall to C03 (actually R04 east wall)
            { id = "D_R04_C03", geometry = "negate",
              position = {518, FLOOR_Y + 1, 405}, size = {3, 10, 30} },
            -- C03 to R03 west wall
            { id = "D_C03_R03", geometry = "negate",
              position = {538, FLOOR_Y + 1, 405}, size = {3, 10, 30} },

            ----------------------------------------------------------------
            -- C04: Hall to Armory Wing (R03 to R06)
            ----------------------------------------------------------------
            -- R03 south wall to C04
            { id = "D_R03_C04", geometry = "negate",
              position = {521, FLOOR_Y + 1, 518}, size = {38, 10, 3} },
            -- C04 to R06 north wall
            { id = "D_C04_R06", geometry = "negate",
              position = {521, FLOOR_Y + 1, 539}, size = {38, 10, 3} },

            ----------------------------------------------------------------
            -- C05: Hall to Mess (R03 to R07)
            ----------------------------------------------------------------
            -- R03 south wall to C05
            { id = "D_R03_C05", geometry = "negate",
              position = {601, FLOOR_Y + 1, 518}, size = {38, 10, 3} },
            -- C05 to R07 north wall
            { id = "D_C05_R07", geometry = "negate",
              position = {601, FLOOR_Y + 1, 539}, size = {38, 10, 3} },

            ----------------------------------------------------------------
            -- C06: Gallery Bridge (R03 area to R09)
            ----------------------------------------------------------------
            -- East end to R09 west wall
            { id = "D_C06_R09", geometry = "negate",
              position = {899, FLOOR_Y + 1, 381}, size = {3, 14, 38} },

            ----------------------------------------------------------------
            -- C07: Gallery to Chapel (R09 to R10)
            ----------------------------------------------------------------
            -- R09 south wall to C07
            { id = "D_R09_C07", geometry = "negate",
              position = {921, FLOOR_Y + 1, 478}, size = {28, 12, 3} },
            -- C07 to R10 north wall
            { id = "D_C07_R10", geometry = "negate",
              position = {921, FLOOR_Y + 1, 519}, size = {28, 12, 3} },

            ----------------------------------------------------------------
            -- C08: Hall to Infirmary (R03 to R11)
            ----------------------------------------------------------------
            -- R03 north wall area to C08
            { id = "D_R03_C08", geometry = "negate",
              position = {481, FLOOR_Y + 1, 318}, size = {38, 10, 3} },
            -- C08 to R11 south wall
            { id = "D_C08_R11", geometry = "negate",
              position = {481, FLOOR_Y + 1, 291}, size = {38, 10, 3} },

            ----------------------------------------------------------------
            -- C09: Armory to Cells (R05 to R12)
            ----------------------------------------------------------------
            -- R05 west wall to C09
            { id = "D_R05_C09", geometry = "negate",
              position = {318, FLOOR_Y + 1, 581}, size = {3, 10, 18} },
            -- C09 to R12 east wall
            { id = "D_C09_R12", geometry = "negate",
              position = {299, FLOOR_Y + 1, 581}, size = {3, 10, 18} },

            ----------------------------------------------------------------
            -- Direct room connections
            ----------------------------------------------------------------
            -- R05 to R06 (shared wall)
            { id = "D_R05_R06", geometry = "negate",
              position = {458, FLOOR_Y + 1, 521}, size = {3, 10, 58} },

            -- R06 to R07 (shared wall at corner)
            { id = "D_R06_R07", geometry = "negate",
              position = {518, FLOOR_Y + 1, 541}, size = {3, 10, 58} },

            -- R07 to R08 (shared wall)
            { id = "D_R07_R08", geometry = "negate",
              position = {658, FLOOR_Y + 1, 561}, size = {3, 10, 58} },
        },
    },
}
