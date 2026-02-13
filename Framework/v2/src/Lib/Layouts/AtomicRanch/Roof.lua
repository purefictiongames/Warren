--[[
    AtomicRanch/Roof

    Low-pitch gable roof with flat carport extension.

    Main house: gable roof, ridge runs E-W at Z=20
    Carport: flat roof at eave height

    Local origin at ceiling top (Y=0 in this layout = ceiling surface)
--]]

local PITCH = 15  -- degrees
local PITCH_RAD = math.rad(PITCH)

-- Dimensions
local MAIN_W = 64
local MAIN_D = 40
local CARPORT_W = 20
local CARPORT_D = 20
local ROOF_T = 0.5

-- Calculated values
local HALF_D = MAIN_D / 2                       -- 20 (ridge position)
local RISE = HALF_D * math.tan(PITCH_RAD)       -- ~5.36 (ridge height above eave)
local SLOPE = HALF_D / math.cos(PITCH_RAD)      -- ~20.71 (panel width along slope)

-- Panel positioning (center-based math, converted to corner-based)
local PANEL_CENTER_Y = RISE / 2
local SOUTH_CENTER_Z = HALF_D / 2               -- 10
local NORTH_CENTER_Z = HALF_D + HALF_D / 2      -- 30

return {
    name = "AtomicRanch_Roof",
    spec = {
        origin = "corner",

        classes = {
            roof = { Material = "Slate", Color = {101, 67, 33} },
            gable = { Material = "SmoothPlastic", Color = {240, 235, 225} },
        },

        parts = {
            ----------------------------------------------------------------
            -- MAIN ROOF PANELS (rotated slabs)
            ----------------------------------------------------------------

            -- South panel: slopes down from ridge toward south wall
            { id = "RoofSouth", class = "roof",
              position = {0, PANEL_CENTER_Y - ROOF_T/2, SOUTH_CENTER_Z - SLOPE/2},
              size = {MAIN_W, ROOF_T, SLOPE},
              rotation = {-PITCH, 0, 0} },

            -- North panel: slopes down from ridge toward north wall
            { id = "RoofNorth", class = "roof",
              position = {0, PANEL_CENTER_Y - ROOF_T/2, NORTH_CENTER_Z - SLOPE/2},
              size = {MAIN_W, ROOF_T, SLOPE},
              rotation = {PITCH, 0, 0} },

            ----------------------------------------------------------------
            -- GABLE END CAPS (wedges)
            ----------------------------------------------------------------

            -- East gable - south half (slope rises toward ridge)
            { id = "GableEastSouth", class = "gable", shape = "wedge",
              position = {MAIN_W - ROOF_T, 0, 0},
              size = {ROOF_T, RISE, HALF_D},
              rotation = {0, 0, 0} },

            -- East gable - north half (slope falls from ridge)
            { id = "GableEastNorth", class = "gable", shape = "wedge",
              position = {MAIN_W - ROOF_T, 0, HALF_D},
              size = {ROOF_T, RISE, HALF_D},
              rotation = {0, 180, 0} },

            -- West gable - south half
            { id = "GableWestSouth", class = "gable", shape = "wedge",
              position = {0, 0, 0},
              size = {ROOF_T, RISE, HALF_D},
              rotation = {0, 0, 0} },

            -- West gable - north half
            { id = "GableWestNorth", class = "gable", shape = "wedge",
              position = {0, 0, HALF_D},
              size = {ROOF_T, RISE, HALF_D},
              rotation = {0, 180, 0} },

            ----------------------------------------------------------------
            -- CARPORT ROOF (flat at eave height)
            ----------------------------------------------------------------

            { id = "CarportRoof", class = "roof",
              position = {0, 0, MAIN_D},
              size = {CARPORT_W, ROOF_T, CARPORT_D} },
        },
    },
}
