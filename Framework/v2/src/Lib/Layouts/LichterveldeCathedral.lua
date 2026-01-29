--[[
    LichterveldeCathedral
    St. Jacob's Cathedral (Sint-Jacobuskerk) - Low-Poly Interpretive Model

    BrookHaven-style cathedral using only Parts (Blocks + Wedges)
    Exterior shell only - no interior required

    Reference: Top-down + 4 elevation views
    Style: Low-poly, suggestive detailing
--]]

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Scale and Dimensions (in studs)
local NAVE_LENGTH = 200
local NAVE_WIDTH = 70
local NAVE_WALL_HEIGHT = 55

local TRANSEPT_WIDTH = 130  -- Total width (both arms)
local TRANSEPT_DEPTH = 65
local TRANSEPT_WALL_HEIGHT = 55

local APSE_DEPTH = 40
local APSE_WIDTH = 50
local APSE_WALL_HEIGHT = 50

local TOWER_WIDTH = 36
local TOWER_DEPTH = 30
local TOWER_BASE_HEIGHT = 90
local TOWER_UPPER_HEIGHT = 25
local SPIRE_HEIGHT = 30

local ROOF_PITCH = 25  -- Rise over half-width
local ROOF_OVERHANG = 2

local WALL_THICKNESS = 4
local BUTTRESS_DEPTH = 4
local BUTTRESS_WIDTH = 3

local WINDOW_WIDTH = 8
local WINDOW_HEIGHT = 25
local WINDOW_ARCH_HEIGHT = 4
local WINDOW_INSET = 0.5

-- Colors (RGB 0-255)
local COLOR_WALL = {180, 130, 100}          -- Reddish-brown brick
local COLOR_WALL_DARK = {150, 100, 75}      -- Darker brick trim
local COLOR_ROOF = {55, 55, 60}             -- Dark slate
local COLOR_WINDOW = {70, 80, 100}          -- Bluish-gray glass
local COLOR_DOOR = {50, 45, 40}             -- Dark wood
local COLOR_FOOTPRINT = {200, 200, 200}     -- Light gray (guide only)

-- ============================================================================
-- LAYOUT SPEC
-- ============================================================================

return {
    name = "LichterveldeCathedral",
    spec = {
        origin = "floor-center",
        offset = {0, 5, 0},  -- Raised to sit on grass mound
        bounds = {TRANSEPT_WIDTH + 20, TOWER_BASE_HEIGHT + TOWER_UPPER_HEIGHT + SPIRE_HEIGHT + 10, NAVE_LENGTH + APSE_DEPTH + 20},

        -- ====================================================================
        -- DEFAULTS & CLASSES
        -- ====================================================================

        defaults = {
            Material = "SmoothPlastic",
            CanCollide = false,
        },

        base = {
            part = { Anchored = true },
        },

        classes = {
            -- Structural
            wall = { Color = COLOR_WALL, Material = "Brick", CanCollide = true },
            wall_trim = { Color = COLOR_WALL_DARK, Material = "Brick", CanCollide = true },

            -- Roofing
            roof = { Color = COLOR_ROOF },

            -- Details
            window = { Color = COLOR_WINDOW },
            door = { Color = COLOR_DOOR },

            -- Footprint guides (layout only)
            footprint = { Color = COLOR_FOOTPRINT, Transparency = 0.6 },

            -- Collision hulls
            collision = { Transparency = 1, CanCollide = true, CanQuery = true },
        },

        parts = {
            -- ================================================================
            -- STRUCTURE - Main Wall Volumes
            -- ================================================================

            -- Nave walls (left and right) with transept openings and windows
            { id = "Wall_Nave_Left", class = "wall",
              position = {-NAVE_WIDTH/2 + WALL_THICKNESS/2, NAVE_WALL_HEIGHT/2, 0},
              size = {WALL_THICKNESS, NAVE_WALL_HEIGHT, NAVE_LENGTH},
              holes = {
                { position = {0, -5, 40}, size = {6, TRANSEPT_WALL_HEIGHT - 5, TRANSEPT_DEPTH - 4} },  -- transept opening
                { position = {0, 5, -60}, size = {6, WINDOW_HEIGHT, WINDOW_WIDTH} },
                { position = {0, 5, -30}, size = {6, WINDOW_HEIGHT, WINDOW_WIDTH} },
              }},

            { id = "Wall_Nave_Right", class = "wall",
              position = {NAVE_WIDTH/2 - WALL_THICKNESS/2, NAVE_WALL_HEIGHT/2, 0},
              size = {WALL_THICKNESS, NAVE_WALL_HEIGHT, NAVE_LENGTH},
              holes = {
                { position = {0, -5, 40}, size = {6, TRANSEPT_WALL_HEIGHT - 5, TRANSEPT_DEPTH - 4} },  -- transept opening
                { position = {0, 5, -60}, size = {6, WINDOW_HEIGHT, WINDOW_WIDTH} },
                { position = {0, 5, -30}, size = {6, WINDOW_HEIGHT, WINDOW_WIDTH} },
              }},

            -- Nave front walls (connect nave to tower on each side)
            -- Front of nave at Z = -100, tower width = 36, nave width = 70
            -- Each side wall spans from nave edge (±35) to tower edge (±18)
            { id = "Wall_Nave_Front_Left", class = "wall",
              position = {-(NAVE_WIDTH/2 + TOWER_WIDTH/2)/2, NAVE_WALL_HEIGHT/2, -NAVE_LENGTH/2 + WALL_THICKNESS/2},
              size = {(NAVE_WIDTH - TOWER_WIDTH)/2, NAVE_WALL_HEIGHT, WALL_THICKNESS} },

            { id = "Wall_Nave_Front_Right", class = "wall",
              position = {(NAVE_WIDTH/2 + TOWER_WIDTH/2)/2, NAVE_WALL_HEIGHT/2, -NAVE_LENGTH/2 + WALL_THICKNESS/2},
              size = {(NAVE_WIDTH - TOWER_WIDTH)/2, NAVE_WALL_HEIGHT, WALL_THICKNESS} },

            -- Transept walls with large window holes
            { id = "Wall_Transept_Left_Outer", class = "wall",
              position = {-TRANSEPT_WIDTH/2 + WALL_THICKNESS/2, TRANSEPT_WALL_HEIGHT/2, 40},
              size = {WALL_THICKNESS, TRANSEPT_WALL_HEIGHT, TRANSEPT_DEPTH},
              holes = {
                { position = {0, 5, 0}, size = {6, WINDOW_HEIGHT + 5, WINDOW_WIDTH + 4} },
              }},

            { id = "Wall_Transept_Right_Outer", class = "wall",
              position = {TRANSEPT_WIDTH/2 - WALL_THICKNESS/2, TRANSEPT_WALL_HEIGHT/2, 40},
              size = {WALL_THICKNESS, TRANSEPT_WALL_HEIGHT, TRANSEPT_DEPTH},
              holes = {
                { position = {0, 5, 0}, size = {6, WINDOW_HEIGHT + 5, WINDOW_WIDTH + 4} },
              }},

            { id = "Wall_Transept_Left_Front", class = "wall",
              position = {-(NAVE_WIDTH/2 + (TRANSEPT_WIDTH/2 - NAVE_WIDTH/2)/2), TRANSEPT_WALL_HEIGHT/2, 40 - TRANSEPT_DEPTH/2 + WALL_THICKNESS/2},
              size = {TRANSEPT_WIDTH/2 - NAVE_WIDTH/2, TRANSEPT_WALL_HEIGHT, WALL_THICKNESS} },

            { id = "Wall_Transept_Left_Back", class = "wall",
              position = {-(NAVE_WIDTH/2 + (TRANSEPT_WIDTH/2 - NAVE_WIDTH/2)/2), TRANSEPT_WALL_HEIGHT/2, 40 + TRANSEPT_DEPTH/2 - WALL_THICKNESS/2},
              size = {TRANSEPT_WIDTH/2 - NAVE_WIDTH/2, TRANSEPT_WALL_HEIGHT, WALL_THICKNESS} },

            { id = "Wall_Transept_Right_Front", class = "wall",
              position = {NAVE_WIDTH/2 + (TRANSEPT_WIDTH/2 - NAVE_WIDTH/2)/2, TRANSEPT_WALL_HEIGHT/2, 40 - TRANSEPT_DEPTH/2 + WALL_THICKNESS/2},
              size = {TRANSEPT_WIDTH/2 - NAVE_WIDTH/2, TRANSEPT_WALL_HEIGHT, WALL_THICKNESS} },

            { id = "Wall_Transept_Right_Back", class = "wall",
              position = {NAVE_WIDTH/2 + (TRANSEPT_WIDTH/2 - NAVE_WIDTH/2)/2, TRANSEPT_WALL_HEIGHT/2, 40 + TRANSEPT_DEPTH/2 - WALL_THICKNESS/2},
              size = {TRANSEPT_WIDTH/2 - NAVE_WIDTH/2, TRANSEPT_WALL_HEIGHT, WALL_THICKNESS} },

            -- Nave back wall with apse opening
            { id = "Wall_Nave_Back", class = "wall",
              position = {0, NAVE_WALL_HEIGHT/2, NAVE_LENGTH/2 - WALL_THICKNESS/2},
              size = {NAVE_WIDTH, NAVE_WALL_HEIGHT, WALL_THICKNESS},
              holes = {
                { position = {0, -5, 0}, size = {APSE_WIDTH - 4, APSE_WALL_HEIGHT - 5, 6} },  -- apse opening
              }},

            -- Apse walls (attached to nave back opening)
            { id = "Wall_Apse_Back", class = "wall",
              position = {0, APSE_WALL_HEIGHT/2, NAVE_LENGTH/2 + APSE_DEPTH - WALL_THICKNESS/2},
              size = {APSE_WIDTH, APSE_WALL_HEIGHT, WALL_THICKNESS},
              holes = {
                { position = {-12, 5, 0}, size = {WINDOW_WIDTH, WINDOW_HEIGHT, 6} },
                { position = {0, 8, 0}, size = {WINDOW_WIDTH, WINDOW_HEIGHT + 5, 6} },
                { position = {12, 5, 0}, size = {WINDOW_WIDTH, WINDOW_HEIGHT, 6} },
              }},

            { id = "Wall_Apse_Left", class = "wall",
              position = {-APSE_WIDTH/2 + WALL_THICKNESS/2, APSE_WALL_HEIGHT/2, NAVE_LENGTH/2 + APSE_DEPTH/2},
              size = {WALL_THICKNESS, APSE_WALL_HEIGHT, APSE_DEPTH} },

            { id = "Wall_Apse_Right", class = "wall",
              position = {APSE_WIDTH/2 - WALL_THICKNESS/2, APSE_WALL_HEIGHT/2, NAVE_LENGTH/2 + APSE_DEPTH/2},
              size = {WALL_THICKNESS, APSE_WALL_HEIGHT, APSE_DEPTH} },

            -- ================================================================
            -- ROOFS - Wedge Parts
            -- ================================================================
            --[[
                ROOF HIERARCHY (must obey):
                1. Nave roof (primary) - ridge height = NAVE_WALL_HEIGHT + ROOF_PITCH
                2. Transept roofs (secondary) - ridge ~5 studs BELOW nave ridge
                3. Apse roof (tertiary) - simplified, lower than nave

                WEDGE ORIENTATION NOTES:
                - WedgePart: high edge at local +Z, low edge at local -Z
                - Slope runs from back-top to front-bottom
                - For 90° Y rotations, swap X and Z in size
            --]]

            -- NAVE ROOF (primary, get this perfect first)
            -- Ridge runs along Z (north-south), slopes down toward ±X
            { id = "Roof_Nave_Left", class = "roof", shape = "wedge",
              position = {-(NAVE_WIDTH/4 + ROOF_OVERHANG/2), NAVE_WALL_HEIGHT + ROOF_PITCH/2, 0},
              size = {NAVE_LENGTH + ROOF_OVERHANG*2, ROOF_PITCH, NAVE_WIDTH/2 + ROOF_OVERHANG},
              rotation = {0, 90, 0} },

            { id = "Roof_Nave_Right", class = "roof", shape = "wedge",
              position = {NAVE_WIDTH/4 + ROOF_OVERHANG/2, NAVE_WALL_HEIGHT + ROOF_PITCH/2, 0},
              size = {NAVE_LENGTH + ROOF_OVERHANG*2, ROOF_PITCH, NAVE_WIDTH/2 + ROOF_OVERHANG},
              rotation = {0, -90, 0} },

            -- TRANSEPT ROOFS (secondary, 5 studs below nave ridge)
            -- Ridge runs along X (east-west), slopes down toward ±Z
            -- No rotation needed for Z-facing slopes, 180° to flip
            -- Transept arm width = (TRANSEPT_WIDTH - NAVE_WIDTH) / 2 = 30 studs each side
            -- size = {length_along_ridge, rise, run_to_eave}

            -- Left transept arm - extended inward to meet nave roof
            -- Extends from outer edge (X=-65) to overlap with nave (X=-10)
            -- Width = 55, center at X = -37.5
            { id = "Roof_Transept_Left_Front", class = "roof", shape = "wedge",
              position = {-37.5, TRANSEPT_WALL_HEIGHT + (ROOF_PITCH - 5)/2, 40 - TRANSEPT_DEPTH/4},
              size = {55, ROOF_PITCH - 5, TRANSEPT_DEPTH/2 + ROOF_OVERHANG},
              rotation = {0, 0, 0} },

            { id = "Roof_Transept_Left_Back", class = "roof", shape = "wedge",
              position = {-37.5, TRANSEPT_WALL_HEIGHT + (ROOF_PITCH - 5)/2, 40 + TRANSEPT_DEPTH/4},
              size = {55, ROOF_PITCH - 5, TRANSEPT_DEPTH/2 + ROOF_OVERHANG},
              rotation = {0, 180, 0} },

            -- Right transept arm - extended inward to meet nave roof
            { id = "Roof_Transept_Right_Front", class = "roof", shape = "wedge",
              position = {37.5, TRANSEPT_WALL_HEIGHT + (ROOF_PITCH - 5)/2, 40 - TRANSEPT_DEPTH/4},
              size = {55, ROOF_PITCH - 5, TRANSEPT_DEPTH/2 + ROOF_OVERHANG},
              rotation = {0, 0, 0} },

            { id = "Roof_Transept_Right_Back", class = "roof", shape = "wedge",
              position = {37.5, TRANSEPT_WALL_HEIGHT + (ROOF_PITCH - 5)/2, 40 + TRANSEPT_DEPTH/4},
              size = {55, ROOF_PITCH - 5, TRANSEPT_DEPTH/2 + ROOF_OVERHANG},
              rotation = {0, 180, 0} },

            -- APSE ROOF
            { id = "Roof_Apse_Left", class = "roof", shape = "wedge",
              position = {-(APSE_WIDTH/4), APSE_WALL_HEIGHT + 8, NAVE_LENGTH/2 + APSE_DEPTH/2},
              size = {APSE_DEPTH + 5, 16, APSE_WIDTH/2},
              rotation = {0, 90, 0} },

            { id = "Roof_Apse_Right", class = "roof", shape = "wedge",
              position = {APSE_WIDTH/4, APSE_WALL_HEIGHT + 8, NAVE_LENGTH/2 + APSE_DEPTH/2},
              size = {APSE_DEPTH + 5, 16, APSE_WIDTH/2},
              rotation = {0, -90, 0} },

            -- ================================================================
            -- TOWER (hollow construction)
            -- ================================================================

            -- Tower front wall (entrance side) with door and window
            { id = "Tower_Wall_Front", class = "wall",
              position = {0, TOWER_BASE_HEIGHT/2, -NAVE_LENGTH/2 - 10 - TOWER_DEPTH/2 + WALL_THICKNESS/2},
              size = {TOWER_WIDTH, TOWER_BASE_HEIGHT, WALL_THICKNESS},
              holes = {
                { position = {0, -TOWER_BASE_HEIGHT/2 + 12, 0}, size = {14, 22, 6} },  -- main door
                { position = {0, 10, 0}, size = {10, 18, 6} },  -- upper window
              }},

            -- Tower back wall (connects to nave) with door
            { id = "Tower_Wall_Back", class = "wall",
              position = {0, TOWER_BASE_HEIGHT/2, -NAVE_LENGTH/2 - 10 + TOWER_DEPTH/2 - WALL_THICKNESS/2},
              size = {TOWER_WIDTH, TOWER_BASE_HEIGHT, WALL_THICKNESS},
              holes = {
                { position = {0, -TOWER_BASE_HEIGHT/2 + 12, 0}, size = {14, 22, 6} },  -- interior door
              }},

            -- Tower left wall
            { id = "Tower_Wall_Left", class = "wall",
              position = {-TOWER_WIDTH/2 + WALL_THICKNESS/2, TOWER_BASE_HEIGHT/2, -NAVE_LENGTH/2 - 10},
              size = {WALL_THICKNESS, TOWER_BASE_HEIGHT, TOWER_DEPTH - WALL_THICKNESS*2} },

            -- Tower right wall
            { id = "Tower_Wall_Right", class = "wall",
              position = {TOWER_WIDTH/2 - WALL_THICKNESS/2, TOWER_BASE_HEIGHT/2, -NAVE_LENGTH/2 - 10},
              size = {WALL_THICKNESS, TOWER_BASE_HEIGHT, TOWER_DEPTH - WALL_THICKNESS*2} },

            -- Tower upper section (slightly inset for banding)
            { id = "Tower_Upper", class = "wall",
              position = {0, TOWER_BASE_HEIGHT + TOWER_UPPER_HEIGHT/2, -NAVE_LENGTH/2 - 10},
              size = {TOWER_WIDTH - 4, TOWER_UPPER_HEIGHT, TOWER_DEPTH - 4} },

            -- Tower band trim
            { id = "Tower_Band_Lower", class = "wall_trim",
              position = {0, TOWER_BASE_HEIGHT * 0.4, -NAVE_LENGTH/2 - 10 - TOWER_DEPTH/2 - 0.5},
              size = {TOWER_WIDTH + 2, 3, 1} },

            { id = "Tower_Band_Upper", class = "wall_trim",
              position = {0, TOWER_BASE_HEIGHT, -NAVE_LENGTH/2 - 10 - TOWER_DEPTH/2 - 0.5},
              size = {TOWER_WIDTH + 2, 2, 1} },

            -- Left spire
            { id = "Tower_Spire_Left_Base", class = "wall",
              position = {-TOWER_WIDTH/2 + 5, TOWER_BASE_HEIGHT + TOWER_UPPER_HEIGHT + 4, -NAVE_LENGTH/2 - 10 - TOWER_DEPTH/2 + 5},
              size = {8, 8, 8} },

            { id = "Tower_Spire_Left_Mid", class = "roof", shape = "wedge",
              position = {-TOWER_WIDTH/2 + 5, TOWER_BASE_HEIGHT + TOWER_UPPER_HEIGHT + 8 + SPIRE_HEIGHT/4, -NAVE_LENGTH/2 - 10 - TOWER_DEPTH/2 + 5 - 2},
              size = {6, SPIRE_HEIGHT/2, 4},
              rotation = {0, 0, 0} },

            { id = "Tower_Spire_Left_Mid2", class = "roof", shape = "wedge",
              position = {-TOWER_WIDTH/2 + 5, TOWER_BASE_HEIGHT + TOWER_UPPER_HEIGHT + 8 + SPIRE_HEIGHT/4, -NAVE_LENGTH/2 - 10 - TOWER_DEPTH/2 + 5 + 2},
              size = {6, SPIRE_HEIGHT/2, 4},
              rotation = {0, 180, 0} },

            -- Right spire
            { id = "Tower_Spire_Right_Base", class = "wall",
              position = {TOWER_WIDTH/2 - 5, TOWER_BASE_HEIGHT + TOWER_UPPER_HEIGHT + 4, -NAVE_LENGTH/2 - 10 - TOWER_DEPTH/2 + 5},
              size = {8, 8, 8} },

            { id = "Tower_Spire_Right_Mid", class = "roof", shape = "wedge",
              position = {TOWER_WIDTH/2 - 5, TOWER_BASE_HEIGHT + TOWER_UPPER_HEIGHT + 8 + SPIRE_HEIGHT/4, -NAVE_LENGTH/2 - 10 - TOWER_DEPTH/2 + 5 - 2},
              size = {6, SPIRE_HEIGHT/2, 4},
              rotation = {0, 0, 0} },

            { id = "Tower_Spire_Right_Mid2", class = "roof", shape = "wedge",
              position = {TOWER_WIDTH/2 - 5, TOWER_BASE_HEIGHT + TOWER_UPPER_HEIGHT + 8 + SPIRE_HEIGHT/4, -NAVE_LENGTH/2 - 10 - TOWER_DEPTH/2 + 5 + 2},
              size = {6, SPIRE_HEIGHT/2, 4},
              rotation = {0, 180, 0} },

            -- ================================================================
            -- BUTTRESSES - Nave (Left Side)
            -- ================================================================

            { id = "Buttress_L_01", class = "wall",
              position = {-NAVE_WIDTH/2 - BUTTRESS_DEPTH/2 + 0.5, NAVE_WALL_HEIGHT * 0.4, -80},
              size = {BUTTRESS_DEPTH, NAVE_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH} },

            { id = "Buttress_L_02", class = "wall",
              position = {-NAVE_WIDTH/2 - BUTTRESS_DEPTH/2 + 0.5, NAVE_WALL_HEIGHT * 0.4, -50},
              size = {BUTTRESS_DEPTH, NAVE_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH} },

            { id = "Buttress_L_03", class = "wall",
              position = {-NAVE_WIDTH/2 - BUTTRESS_DEPTH/2 + 0.5, NAVE_WALL_HEIGHT * 0.4, -20},
              size = {BUTTRESS_DEPTH, NAVE_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH} },

            { id = "Buttress_L_04", class = "wall",
              position = {-NAVE_WIDTH/2 - BUTTRESS_DEPTH/2 + 0.5, NAVE_WALL_HEIGHT * 0.4, 10},
              size = {BUTTRESS_DEPTH, NAVE_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH} },


            -- ================================================================
            -- BUTTRESSES - Nave (Right Side)
            -- ================================================================

            { id = "Buttress_R_01", class = "wall",
              position = {NAVE_WIDTH/2 + BUTTRESS_DEPTH/2 - 0.5, NAVE_WALL_HEIGHT * 0.4, -80},
              size = {BUTTRESS_DEPTH, NAVE_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH} },

            { id = "Buttress_R_02", class = "wall",
              position = {NAVE_WIDTH/2 + BUTTRESS_DEPTH/2 - 0.5, NAVE_WALL_HEIGHT * 0.4, -50},
              size = {BUTTRESS_DEPTH, NAVE_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH} },

            { id = "Buttress_R_03", class = "wall",
              position = {NAVE_WIDTH/2 + BUTTRESS_DEPTH/2 - 0.5, NAVE_WALL_HEIGHT * 0.4, -20},
              size = {BUTTRESS_DEPTH, NAVE_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH} },

            { id = "Buttress_R_04", class = "wall",
              position = {NAVE_WIDTH/2 + BUTTRESS_DEPTH/2 - 0.5, NAVE_WALL_HEIGHT * 0.4, 10},
              size = {BUTTRESS_DEPTH, NAVE_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH} },


            -- ================================================================
            -- BUTTRESSES - Transept Corners
            -- ================================================================

            { id = "Buttress_Transept_L_Front", class = "wall",
              position = {-TRANSEPT_WIDTH/2 - BUTTRESS_DEPTH/2 + 0.5, TRANSEPT_WALL_HEIGHT * 0.4, 40 - TRANSEPT_DEPTH/2 + 4},
              size = {BUTTRESS_DEPTH, TRANSEPT_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH + 1} },

            { id = "Buttress_Transept_L_Back", class = "wall",
              position = {-TRANSEPT_WIDTH/2 - BUTTRESS_DEPTH/2 + 0.5, TRANSEPT_WALL_HEIGHT * 0.4, 40 + TRANSEPT_DEPTH/2 - 4},
              size = {BUTTRESS_DEPTH, TRANSEPT_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH + 1} },

            { id = "Buttress_Transept_R_Front", class = "wall",
              position = {TRANSEPT_WIDTH/2 + BUTTRESS_DEPTH/2 - 0.5, TRANSEPT_WALL_HEIGHT * 0.4, 40 - TRANSEPT_DEPTH/2 + 4},
              size = {BUTTRESS_DEPTH, TRANSEPT_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH + 1} },

            { id = "Buttress_Transept_R_Back", class = "wall",
              position = {TRANSEPT_WIDTH/2 + BUTTRESS_DEPTH/2 - 0.5, TRANSEPT_WALL_HEIGHT * 0.4, 40 + TRANSEPT_DEPTH/2 - 4},
              size = {BUTTRESS_DEPTH, TRANSEPT_WALL_HEIGHT * 0.8, BUTTRESS_WIDTH + 1} },

            -- ================================================================
            -- TRIM - Exterior footprint, height = 13
            -- Trim depth = BUTTRESS_DEPTH + 1 = 5
            -- ================================================================

            -- Nave left exterior (from tower connection to transept front)
            { id = "Trim_Nave_Left_Front", class = "wall_trim",
              position = {-NAVE_WIDTH/2 - 2.5, 6.5, ((-NAVE_LENGTH/2) + (40 - TRANSEPT_DEPTH/2)) / 2},
              size = {5, 13, (40 - TRANSEPT_DEPTH/2) - (-NAVE_LENGTH/2)} },

            -- Nave left exterior (from transept back to apse)
            { id = "Trim_Nave_Left_Back", class = "wall_trim",
              position = {-NAVE_WIDTH/2 - 2.5, 6.5, ((40 + TRANSEPT_DEPTH/2) + NAVE_LENGTH/2) / 2},
              size = {5, 13, NAVE_LENGTH/2 - (40 + TRANSEPT_DEPTH/2)} },

            -- Nave right exterior (from tower connection to transept front)
            { id = "Trim_Nave_Right_Front", class = "wall_trim",
              position = {NAVE_WIDTH/2 + 2.5, 6.5, ((-NAVE_LENGTH/2) + (40 - TRANSEPT_DEPTH/2)) / 2},
              size = {5, 13, (40 - TRANSEPT_DEPTH/2) - (-NAVE_LENGTH/2)} },

            -- Nave right exterior (from transept back to apse)
            { id = "Trim_Nave_Right_Back", class = "wall_trim",
              position = {NAVE_WIDTH/2 + 2.5, 6.5, ((40 + TRANSEPT_DEPTH/2) + NAVE_LENGTH/2) / 2},
              size = {5, 13, NAVE_LENGTH/2 - (40 + TRANSEPT_DEPTH/2)} },

            -- Transept left outer
            { id = "Trim_Transept_Left_Outer", class = "wall_trim",
              position = {-TRANSEPT_WIDTH/2 - 2.5, 6.5, 40},
              size = {5, 13, TRANSEPT_DEPTH} },

            -- Transept left front
            { id = "Trim_Transept_Left_Front", class = "wall_trim",
              position = {-(NAVE_WIDTH/2 + TRANSEPT_WIDTH/2) / 2, 6.5, 40 - TRANSEPT_DEPTH/2 - 2.5},
              size = {TRANSEPT_WIDTH/2 - NAVE_WIDTH/2, 13, 5} },

            -- Transept left back
            { id = "Trim_Transept_Left_Back", class = "wall_trim",
              position = {-(NAVE_WIDTH/2 + TRANSEPT_WIDTH/2) / 2, 6.5, 40 + TRANSEPT_DEPTH/2 + 2.5},
              size = {TRANSEPT_WIDTH/2 - NAVE_WIDTH/2, 13, 5} },

            -- Transept right outer
            { id = "Trim_Transept_Right_Outer", class = "wall_trim",
              position = {TRANSEPT_WIDTH/2 + 2.5, 6.5, 40},
              size = {5, 13, TRANSEPT_DEPTH} },

            -- Transept right front
            { id = "Trim_Transept_Right_Front", class = "wall_trim",
              position = {(NAVE_WIDTH/2 + TRANSEPT_WIDTH/2) / 2, 6.5, 40 - TRANSEPT_DEPTH/2 - 2.5},
              size = {TRANSEPT_WIDTH/2 - NAVE_WIDTH/2, 13, 5} },

            -- Transept right back
            { id = "Trim_Transept_Right_Back", class = "wall_trim",
              position = {(NAVE_WIDTH/2 + TRANSEPT_WIDTH/2) / 2, 6.5, 40 + TRANSEPT_DEPTH/2 + 2.5},
              size = {TRANSEPT_WIDTH/2 - NAVE_WIDTH/2, 13, 5} },

            -- Apse left
            { id = "Trim_Apse_Left", class = "wall_trim",
              position = {-APSE_WIDTH/2 - 2.5, 6.5, NAVE_LENGTH/2 + APSE_DEPTH/2},
              size = {5, 13, APSE_DEPTH} },

            -- Apse right
            { id = "Trim_Apse_Right", class = "wall_trim",
              position = {APSE_WIDTH/2 + 2.5, 6.5, NAVE_LENGTH/2 + APSE_DEPTH/2},
              size = {5, 13, APSE_DEPTH} },

            -- Apse back
            { id = "Trim_Apse_Back", class = "wall_trim",
              position = {0, 6.5, NAVE_LENGTH/2 + APSE_DEPTH + 2.5},
              size = {APSE_WIDTH, 13, 5} },

            -- Apse transition corners (where nave narrows to apse)
            { id = "Trim_Apse_Transition_Left", class = "wall_trim",
              position = {-(NAVE_WIDTH/2 + APSE_WIDTH/2) / 2, 6.5, NAVE_LENGTH/2 + 2.5},
              size = {(NAVE_WIDTH - APSE_WIDTH) / 2, 13, 5} },

            { id = "Trim_Apse_Transition_Right", class = "wall_trim",
              position = {(NAVE_WIDTH/2 + APSE_WIDTH/2) / 2, 6.5, NAVE_LENGTH/2 + 2.5},
              size = {(NAVE_WIDTH - APSE_WIDTH) / 2, 13, 5} },

            -- COLLISION HULLS removed - walls now have PreciseConvexDecomposition collision
        },

        -- ====================================================================
        -- MOUNT POINTS (for future expansion)
        -- ====================================================================

        mounts = {
            { id = "entrance", position = {0, 0, -NAVE_LENGTH/2 - 25}, facing = {0, 0, -1} },
            { id = "altar", position = {0, 0, NAVE_LENGTH/2 + APSE_DEPTH - 10}, facing = {0, 0, 1} },
        },
    },
}
