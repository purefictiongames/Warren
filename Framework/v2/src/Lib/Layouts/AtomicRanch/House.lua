--[[
    AtomicRanch/House

    Main container that assembles the house components.
    Uses xref to combine Foundation, ExteriorWalls, InteriorWalls, Ceiling, Roof, and Openings.
--]]

local Foundation = require(script.Parent.Foundation)
local ExteriorWalls = require(script.Parent.ExteriorWalls)
local InteriorWalls = require(script.Parent.InteriorWalls)
local Ceiling = require(script.Parent.Ceiling)
local Roof = require(script.Parent.Roof)
local Openings = require(script.Parent.Openings)

-- Vertical dimensions
local SLAB_H = 0.5
local WALL_H = 10
local CEIL_H = 0.5

return {
    name = "AtomicRanch_House",
    spec = {
        origin = "corner",

        parts = {
            -- Foundation at ground level
            { id = "foundation",
              xref = Foundation,
              position = {0, 0, 0},
            },

            -- Exterior walls sit on top of foundation
            { id = "exterior",
              xref = ExteriorWalls,
              position = {0, SLAB_H, 0},
            },

            -- Interior walls sit on top of foundation
            { id = "interior",
              xref = InteriorWalls,
              position = {0, SLAB_H, 0},
            },

            -- Ceiling sits on top of walls
            { id = "ceiling",
              xref = Ceiling,
              position = {0, SLAB_H + WALL_H, 0},
            },

            -- Roof sits on top of ceiling
            { id = "roof",
              xref = Roof,
              position = {0, SLAB_H + WALL_H + CEIL_H, 0},
            },

            -- Global openings (applied to all intersecting walls)
            { id = "openings",
              xref = Openings,
              position = {0, SLAB_H, 0},  -- Same as walls
            },
        },
    },
}
