--[[
    Castle Dracula - Level 2: Inner Castle
    Door Openings - Cut holes between rooms and corridors

    Parts with geometry = "negate" are CSG subtracted from intersecting walls.

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
--]]

local FLOOR_Y = 160  -- L2 floor height

return {
    name = "CastleDracula_L2_Openings",
    spec = {
        origin = "corner",

        parts = {
            ----------------------------------------------------------------
            -- C01: Stair Landing to Grand Hall
            ----------------------------------------------------------------
            -- R01 east wall to C01
            { id = "D_R01_C01", geometry = "negate",
              position = {738, FLOOR_Y + 1, 431}, size = {3, 14, 28} },
            -- C01 west end (already open to Grand Hall interior)

            ----------------------------------------------------------------
            -- C02: Grand Hall to Lift
            ----------------------------------------------------------------
            -- Grand Hall south wall to C02
            { id = "D_R03_C02", geometry = "negate",
              position = {681, FLOOR_Y + 1, 558}, size = {18, 12, 3} },
            -- C02 to R02 west wall
            { id = "D_C02_R02", geometry = "negate",
              position = {699, FLOOR_Y + 1, 501}, size = {3, 12, 28} },

            ----------------------------------------------------------------
            -- C03: Grand Hall to Library
            ----------------------------------------------------------------
            -- Grand Hall west wall to C03
            { id = "D_R03_C03", geometry = "negate",
              position = {518, FLOOR_Y + 1, 421}, size = {3, 14, 58} },
            -- C03 to Library east wall
            { id = "D_C03_R04", geometry = "negate",
              position = {518, FLOOR_Y + 1, 421}, size = {3, 14, 58} },

            ----------------------------------------------------------------
            -- C04: Library to Reading Nook
            ----------------------------------------------------------------
            -- Library south wall to C04
            { id = "D_R04_C04", geometry = "negate",
              position = {321, FLOOR_Y + 1, 518}, size = {38, 12, 3} },
            -- C04 to R05 north wall
            { id = "D_C04_R05", geometry = "negate",
              position = {321, FLOOR_Y + 1, 539}, size = {38, 12, 3} },

            ----------------------------------------------------------------
            -- C05: Library to Vault
            ----------------------------------------------------------------
            -- Library north wall to C05
            { id = "D_R04_C05", geometry = "negate",
              position = {341, FLOOR_Y + 1, 298}, size = {38, 10, 3} },
            -- C05 to R06 south wall
            { id = "D_C05_R06", geometry = "negate",
              position = {341, FLOOR_Y + 1, 319}, size = {38, 10, 3} },

            ----------------------------------------------------------------
            -- C06: Grand Hall to Upper Gallery
            ----------------------------------------------------------------
            -- Grand Hall east wall to C06
            { id = "D_R03_C06", geometry = "negate",
              position = {838, FLOOR_Y + 1, 421}, size = {3, 14, 58} },
            -- C06 to R07 west wall
            { id = "D_C06_R07", geometry = "negate",
              position = {859, FLOOR_Y + 1, 421}, size = {3, 14, 58} },

            ----------------------------------------------------------------
            -- C07: Upper Gallery to Overlook
            ----------------------------------------------------------------
            -- R07 north wall to C07
            { id = "D_R07_C07", geometry = "negate",
              position = {941, FLOOR_Y + 1, 338}, size = {18, 12, 3} },
            -- C07 to R08 south wall
            { id = "D_C07_R08", geometry = "negate",
              position = {941, FLOOR_Y + 1, 359}, size = {18, 12, 3} },

            ----------------------------------------------------------------
            -- C08: Grand Hall to Stone Passage
            ----------------------------------------------------------------
            -- Grand Hall north wall to C08
            { id = "D_R03_C08", geometry = "negate",
              position = {621, FLOOR_Y + 1, 338}, size = {78, 12, 3} },
            -- C08 to R09 south wall
            { id = "D_C08_R09", geometry = "negate",
              position = {621, FLOOR_Y + 1, 359}, size = {78, 12, 3} },

            ----------------------------------------------------------------
            -- C09: Stone Passage to Lab
            ----------------------------------------------------------------
            -- R09 east wall to C09
            { id = "D_R09_C09", geometry = "negate",
              position = {738, FLOOR_Y + 1, 301}, size = {3, 12, 38} },
            -- C09 to R10 west wall
            { id = "D_C09_R10", geometry = "negate",
              position = {759, FLOOR_Y + 1, 301}, size = {3, 12, 38} },

            ----------------------------------------------------------------
            -- C10: Grand Hall to Chapel Upper
            ----------------------------------------------------------------
            -- Grand Hall south wall to C10
            { id = "D_R03_C10", geometry = "negate",
              position = {841, FLOOR_Y + 1, 558}, size = {78, 14, 3} },
            -- C10 to R11 north wall
            { id = "D_C10_R11", geometry = "negate",
              position = {901, FLOOR_Y + 1, 619}, size = {78, 14, 3} },

            ----------------------------------------------------------------
            -- C11: Grand Hall to Storage
            ----------------------------------------------------------------
            -- Grand Hall south wall to C11
            { id = "D_R03_C11", geometry = "negate",
              position = {521, FLOOR_Y + 1, 558}, size = {38, 10, 3} },
            -- C11 to R12 north wall
            { id = "D_C11_R12", geometry = "negate",
              position = {521, FLOOR_Y + 1, 579}, size = {38, 10, 3} },

            ----------------------------------------------------------------
            -- C12: Upper Gallery to Drop
            ----------------------------------------------------------------
            -- R07 east wall to C12
            { id = "D_R07_C12", geometry = "negate",
              position = {978, FLOOR_Y + 1, 521}, size = {3, 12, 18} },
            -- C12 to R13 west wall
            { id = "D_C12_R13", geometry = "negate",
              position = {1119, FLOOR_Y + 1, 521}, size = {3, 12, 58} },

            ----------------------------------------------------------------
            -- Direct connections
            ----------------------------------------------------------------
            -- R07 to R08 (gallery to overlook - shared wall)
            { id = "D_R07_R08", geometry = "negate",
              position = {901, FLOOR_Y + 1, 338}, size = {78, 14, 3} },
        },
    },
}
