--[[
    Castle Dracula - Level 3: Inner Keep / Clockwork / Defenses
    Door Openings - Cut holes between rooms and corridors

    Parts with geometry = "negate" are CSG subtracted from intersecting walls.

    Coordinate System:
        Origin (0,0,0) at southwest corner, ground level
        +X = East, +Z = North, +Y = Up
--]]

local FLOOR_Y = 280  -- L3 floor height

return {
    name = "CastleDracula_L3_Openings",
    spec = {
        origin = "corner",

        parts = {
            ----------------------------------------------------------------
            -- C01: Stair to Control Hall
            ----------------------------------------------------------------
            -- R01 east wall to C01
            { id = "D_R01_C01", geometry = "negate",
              position = {738, FLOOR_Y + 1, 431}, size = {3, 14, 28} },
            -- C01 already opens into R03 (no wall between)

            ----------------------------------------------------------------
            -- C03: Control Hall to Turret Power
            ----------------------------------------------------------------
            -- R03 west wall to C03
            { id = "D_R03_C03", geometry = "negate",
              position = {518, FLOOR_Y + 1, 421}, size = {3, 12, 38} },
            -- C03 to R04 east wall
            { id = "D_C03_R04", geometry = "negate",
              position = {518, FLOOR_Y + 1, 421}, size = {3, 12, 38} },
        },
    },
}
