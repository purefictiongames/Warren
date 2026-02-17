--[[
    LibPureFiction Framework v2
    Styles.lua - Universal Style Definitions

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Central stylesheet for all domains (GUI, Geometry, etc.).
    Used by ClassResolver to compute the cascade formula.

    See docs/RESOLVER.md for the mental model.

    ============================================================================
    CASCADE FORMULA
    ============================================================================

    result = merge(parent, defaults, base[type], classes..., id, inline)

    This file defines:
        - base     : Styles by element type (Part, TextLabel, etc.)
        - classes  : Named style classes
        - ids      : Styles by specific element ID

    ============================================================================
    USAGE
    ============================================================================

    Layouts reference classes by name:
        { id = "wall", class = "brick_red", geometry = {...} }

    Multiple classes applied in order:
        { id = "wall", class = "brick_red weathered", geometry = {...} }

--]]

return {
    -- =========================================================================
    -- BASE STYLES (by element type)
    -- =========================================================================

    base = {
        -- GUI
        TextLabel = {
            backgroundTransparency = 1,
            font = "SourceSans",
            textColor = {255, 255, 255},
        },
        TextButton = {
            backgroundTransparency = 0.2,
            backgroundColor = {60, 60, 60},
            font = "SourceSans",
            textColor = {255, 255, 255},
        },
        Frame = {
            backgroundTransparency = 0.1,
            backgroundColor = {30, 30, 30},
        },

        -- Geometry
        Part = {
            Anchored = true,
            CanCollide = true,
            Material = "SmoothPlastic",
        },
        WedgePart = {
            Anchored = true,
            CanCollide = true,
            Material = "SmoothPlastic",
        },
    },

    -- =========================================================================
    -- CLASS STYLES
    -- =========================================================================

    classes = {
        ------------------------------------------------------------------------
        -- GEOMETRY - Wall Materials
        ------------------------------------------------------------------------

        brick_red = {
            Material = "Brick",
            Color = {180, 130, 100},
        },
        brick_dark = {
            Material = "Brick",
            Color = {150, 100, 75},
        },
        concrete = {
            Material = "Concrete",
            Color = {180, 175, 165},
        },
        stucco = {
            Material = "SmoothPlastic",
            Color = {245, 240, 230},
        },
        stucco_cream = {
            Material = "SmoothPlastic",
            Color = {235, 228, 215},
        },

        ------------------------------------------------------------------------
        -- GEOMETRY - Roof Materials
        ------------------------------------------------------------------------

        roof_slate = {
            Material = "Slate",
            Color = {55, 55, 60},
        },
        roof_terracotta = {
            Material = "Brick",
            Color = {140, 65, 45},
        },
        roof_shingle = {
            Material = "SmoothPlastic",
            Color = {60, 55, 50},
        },

        ------------------------------------------------------------------------
        -- GEOMETRY - Structural
        ------------------------------------------------------------------------

        frame_metal = {
            Material = "DiamondPlate",
            Color = {80, 80, 85},
        },
        glass = {
            Material = "Glass",
            Color = {180, 210, 230},
            Transparency = 0.4,
        },
        wood = {
            Material = "Wood",
            Color = {140, 100, 70},
        },
        wood_dark = {
            Material = "Wood",
            Color = {90, 65, 45},
        },

        ------------------------------------------------------------------------
        -- GEOMETRY - Ground
        ------------------------------------------------------------------------

        ground_grass = {
            Material = "Grass",
            Color = {80, 130, 60},
        },
        ground_cobble = {
            Material = "Cobblestone",
            Color = {140, 135, 130},
        },
        ground_dirt = {
            Material = "Ground",
            Color = {120, 100, 80},
        },

        ------------------------------------------------------------------------
        -- GEOMETRY - Collision/Invisible
        ------------------------------------------------------------------------

        collision = {
            Transparency = 1,
            CanCollide = true,
            CanQuery = true,
        },
        trigger = {
            Transparency = 1,
            CanCollide = false,
            CanQuery = true,
        },

        ------------------------------------------------------------------------
        -- GUI - Typography
        ------------------------------------------------------------------------

        ["hud-text"] = {
            textSize = 24,
            font = "GothamBold",
        },
        ["hud-large"] = {
            textSize = 36,
        },
        ["hud-small"] = {
            textSize = 16,
        },

        ------------------------------------------------------------------------
        -- GUI - Colors
        ------------------------------------------------------------------------

        gold = {
            textColor = {255, 170, 0},
        },
        white = {
            textColor = {255, 255, 255},
        },
        red = {
            textColor = {255, 80, 80},
        },
        green = {
            textColor = {80, 255, 80},
        },

        ------------------------------------------------------------------------
        -- CAVE - Element Roles
        ------------------------------------------------------------------------

        ["cave-wall"] = {
            Material = "Cobblestone",
            Anchored = true,
            CanCollide = true,
        },
        ["cave-ceiling"] = {
            Material = "Cobblestone",
            Anchored = true,
            CanCollide = true,
        },
        ["cave-floor"] = {
            Material = "CrackedLava",
            Anchored = true,
            CanCollide = true,
        },
        ["cave-truss"] = {
            Material = "DiamondPlate",
            Anchored = true,
            Color = {80, 80, 80},
        },
        ["cave-light-fixture"] = {
            Material = "Neon",
            Anchored = true,
            CanCollide = false,
        },
        ["cave-light-spacer"] = {
            Material = "Rock",
            Anchored = true,
            CanCollide = false,
        },
        ["cave-pad"] = {
            Material = "Neon",
            Anchored = true,
            CanCollide = true,
            Color = {180, 50, 255},
        },
        ["cave-pad-base"] = {
            Material = "Neon",
            Anchored = true,
            CanCollide = true,
        },

        ------------------------------------------------------------------------
        -- LOBBY - Portal Pads
        ------------------------------------------------------------------------

        ["lobby-pad"] = {
            Material = "Neon",
            Anchored = true,
            CanCollide = true,
            CanTouch = true,
            Color = {80, 180, 255},
            Transparency = 0.3,
        },
        ["lobby-pad-base"] = {
            Material = "Neon",
            Anchored = true,
            CanCollide = true,
            Color = {50, 120, 180},
        },

        ["cave-zone"] = {
            Anchored = true,
            CanCollide = false,
            CanTouch = true,
            Transparency = 1,
        },
        ["cave-spawn"] = {
            Anchored = true,
            CanCollide = false,
            Transparency = 1,
            Neutral = true,
        },
        -- ICE BIOME - Wall visibility classes
        ["ice-wall-clear"] = {
            Transparency = 1,
        },
        ["ice-wall-solid"] = {
            Transparency = 0.4,
        },
        ["outdoor-wall-solid"] = {
            Transparency = 0,
        },

        ["cave-point-light"] = {
            Brightness = 0.7,
            Range = 60,
            Shadows = false,
        },
        ["ice-spot-light"] = {
            Brightness = 0.5,
            Range = 50,
            Angle = 120,
            Shadows = false,
        },

        ------------------------------------------------------------------------
        -- CAVE - Palette Classes (10 themed color sets)
        ------------------------------------------------------------------------

        -- 1. Classic Lava: Gray stone, white-hot lava, red-orange glow
        ["palette-classic-lava"] = {
            wallColor = {120, 110, 100},
            floorColor = {255, 255, 240},
            lightColor = {255, 50, 20},
            fixtureColor = {255, 120, 40},
        },
        -- 2. Blue Inferno: Blue-gray stone, cyan-white flame, blue glow
        ["palette-blue-inferno"] = {
            wallColor = {90, 100, 120},
            floorColor = {200, 240, 255},
            lightColor = {30, 120, 255},
            fixtureColor = {100, 180, 255},
        },
        -- 3. Toxic Depths: Green-gray stone, bright green, green glow
        ["palette-toxic-depths"] = {
            wallColor = {90, 110, 90},
            floorColor = {180, 255, 120},
            lightColor = {50, 255, 50},
            fixtureColor = {120, 255, 80},
        },
        -- 4. Void Abyss: Purple-gray stone, magenta glow, purple light
        ["palette-void-abyss"] = {
            wallColor = {100, 90, 115},
            floorColor = {255, 150, 255},
            lightColor = {180, 50, 255},
            fixtureColor = {220, 100, 255},
        },
        -- 5. Golden Forge: Warm brown stone, golden-yellow lava, gold glow
        ["palette-golden-forge"] = {
            wallColor = {130, 110, 85},
            floorColor = {255, 220, 100},
            lightColor = {255, 180, 50},
            fixtureColor = {255, 200, 80},
        },
        -- 6. Frozen Fire: Ice blue stone, white-cyan flame, cyan glow
        ["palette-frozen-fire"] = {
            wallColor = {100, 115, 130},
            floorColor = {220, 255, 255},
            lightColor = {100, 220, 255},
            fixtureColor = {150, 240, 255},
        },
        -- 7. Blood Sanctum: Dark burgundy stone, crimson lava, deep red glow
        ["palette-blood-sanctum"] = {
            wallColor = {100, 70, 75},
            floorColor = {255, 100, 100},
            lightColor = {200, 30, 30},
            fixtureColor = {255, 60, 60},
        },
        -- 8. Solar Furnace: Tan stone, bright white-yellow, warm white glow
        ["palette-solar-furnace"] = {
            wallColor = {140, 130, 110},
            floorColor = {255, 255, 200},
            lightColor = {255, 240, 200},
            fixtureColor = {255, 250, 220},
        },
        -- 9. Nether Realm: Charcoal stone, deep orange, orange-red glow
        ["palette-nether-realm"] = {
            wallColor = {80, 75, 70},
            floorColor = {255, 150, 50},
            lightColor = {255, 100, 30},
            fixtureColor = {255, 130, 50},
        },
        -- 10. Spectral Cavern: Slate gray stone, pale ghostly blue, cold white
        ["palette-spectral-cavern"] = {
            wallColor = {95, 100, 110},
            floorColor = {200, 220, 255},
            lightColor = {180, 200, 255},
            fixtureColor = {200, 220, 255},
        },
        -- 11. Glacier Ice: White-blue stone, bright white snow, cold white glow
        ["palette-glacier-ice"] = {
            wallColor = {200, 215, 230},
            floorColor = {235, 245, 255},
            lightColor = {220, 235, 255},
            fixtureColor = {200, 225, 255},
        },
        -- 12. Highland Meadow: Warm brown stone, green grass, warm sunlight
        ["palette-highland-meadow"] = {
            wallColor = {130, 115, 90},
            floorColor = {85, 140, 55},
            lightColor = {255, 240, 200},
            fixtureColor = {180, 160, 130},
        },
        -- 13. Dungeon Keep: Dark gray stone, warm tan cobble, orange torchlight
        ["palette-dungeon-keep"] = {
            wallColor = {75, 70, 65},
            floorColor = {140, 125, 100},
            lightColor = {255, 160, 60},
            fixtureColor = {255, 180, 80},
        },
        -- 14. Desert Ruins: Warm tan sandstone, golden sand, bright sun
        ["palette-desert-ruins"] = {
            wallColor = {190, 165, 120},
            floorColor = {220, 195, 140},
            lightColor = {255, 235, 180},
            fixtureColor = {200, 175, 130},
        },
        -- 15. Sewer Works: Dark green-gray concrete, brown-green mud, sickly glow
        ["palette-sewer-works"] = {
            wallColor = {60, 70, 55},
            floorColor = {80, 70, 45},
            lightColor = {120, 180, 60},
            fixtureColor = {100, 160, 50},
        },
        -- 16. Crystal Cave: Dark basalt, bright cyan-white salt, purple glow
        ["palette-crystal-cave"] = {
            wallColor = {40, 35, 50},
            floorColor = {180, 220, 255},
            lightColor = {160, 80, 255},
            fixtureColor = {200, 140, 255},
        },
        -- 17. Village Green: Warm red-brown brick, green grass, warm daylight
        ["palette-village-green"] = {
            wallColor = {150, 90, 70},
            floorColor = {75, 130, 50},
            lightColor = {255, 245, 220},
            fixtureColor = {160, 110, 80},
        },
    },

    -- =========================================================================
    -- ID STYLES (highest specificity)
    -- =========================================================================

    ids = {
        -- Example: specific element overrides
    },
}
