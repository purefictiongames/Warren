--[[
    AtomicRanch/Ceiling

    L-shaped ceiling mirroring the foundation footprint.
    Sits on top of walls (Y = 0, positioned by House container).
--]]

-- Dimensions (mirror Foundation)
local MAIN_W = 64
local MAIN_D = 40
local CARPORT_W = 20
local CARPORT_D = 20
local CEIL_H = 0.5

-- Inset from exterior walls to avoid interference
local INSET = 1

return {
    name = "AtomicRanch_Ceiling",
    spec = {
        origin = "corner",

        classes = {
            ceiling = { Material = "SmoothPlastic", Color = {255, 250, 245} },
        },

        parts = {
            -- Main house ceiling (inset from all exterior edges)
            { id = "CeilMain", class = "ceiling",
              position = {INSET, 0, INSET},
              size = {MAIN_W - 2*INSET, CEIL_H, MAIN_D - 2*INSET} },

            -- Carport ceiling (inset from exterior edges)
            { id = "CeilCarport", class = "ceiling",
              position = {INSET, 0, MAIN_D + INSET},
              size = {CARPORT_W - 2*INSET, CEIL_H, CARPORT_D - 2*INSET} },
        },
    },
}
