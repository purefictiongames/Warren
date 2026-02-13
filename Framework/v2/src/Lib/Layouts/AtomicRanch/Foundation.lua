--[[
    AtomicRanch/Foundation

    L-shaped foundation slab for the atomic ranch house.

    Footprint:
        Main house: 64' x 40'
        Carport: 20' x 20' (northwest extension)

    Origin: Southwest corner at (0, 0, 0)
    +X = East, +Z = North, +Y = Up
--]]

-- Dimensions
local MAIN_W = 64       -- Main house width (E-W)
local MAIN_D = 40       -- Main house depth (N-S)
local CARPORT_W = 20    -- Carport width
local CARPORT_D = 20    -- Carport depth
local SLAB_H = 0.5      -- Slab thickness

return {
    name = "AtomicRanch_Foundation",
    spec = {
        origin = "corner",

        classes = {
            slab = { Material = "Concrete", Color = {170, 165, 160} },
        },

        parts = {
            -- Main house slab
            { id = "SlabMain", class = "slab",
              position = {0, 0, 0},
              size = {MAIN_W, SLAB_H, MAIN_D} },

            -- Carport slab (extends north from west side)
            { id = "SlabCarport", class = "slab",
              position = {0, 0, MAIN_D},
              size = {CARPORT_W, SLAB_H, CARPORT_D} },
        },
    },
}
