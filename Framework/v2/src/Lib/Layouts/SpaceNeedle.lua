--[[
    SpaceNeedle - Miniature Seattle landmark

    The Space Needle was built for the 1962 World's Fair (Century 21 Exposition).
    Designed by John Graham & Company with Victor Steinbrueck's hourglass tripod concept.
    A Googie/Space Age icon standing 605 feet tall with its distinctive flying saucer
    observation deck.

    This is approximately 1:10 scale (60 studs tall).
--]]

return {
    name = "SpaceNeedle",
    spec = {
        bounds = {40, 65, 40},
        origin = "floor-center",

        base = {
            part = { CanCollide = true },
        },

        classes = {
            -- Structure
            steel = { Material = "Metal", Color = {230, 230, 235} },
            steeldark = { Material = "DiamondPlate", Color = {180, 180, 185} },
            core = { Material = "Metal", Color = {200, 200, 205} },

            -- Saucer/observation deck
            saucertop = { Material = "SmoothPlastic", Color = {245, 245, 250} },
            saucerbottom = { Material = "Metal", Color = {220, 220, 225} },
            windows = { Material = "Glass", Color = {160, 200, 230}, Transparency = 0.3 },
            windowframe = { Material = "Metal", Color = {60, 60, 65} },

            -- Spire
            spire = { Material = "Metal", Color = {235, 235, 240} },
            beacon = { Material = "Neon", Color = {255, 100, 80} },

            -- Base/plaza
            concrete = { Material = "Concrete", Color = {160, 155, 150} },
            plaza = { Material = "Pavement", Color = {140, 140, 145} },
            grass = { Material = "Grass", Color = {75, 130, 60} },

            -- Accent lighting
            glow = { Material = "Neon", Color = {255, 200, 100} },
        },

        parts = {
            ----------------------------------------------------------------
            -- GROUND / PLAZA
            ----------------------------------------------------------------
            { id = "ground", class = "grass", position = {0, -0.25, 0}, size = {40, 0.5, 40} },
            { id = "plaza", class = "plaza", position = {0, 0, 0}, shape = "cylinder", height = 0.1, radius = 15 },
            { id = "foundation", class = "concrete", position = {0, 0.3, 0}, shape = "cylinder", height = 0.6, radius = 8 },

            ----------------------------------------------------------------
            -- TRIPOD LEGS (hourglass profile - 3 legs at 120 degree spacing)
            -- Each leg: wide at base, pinches at "waist" (~37 studs), flares to saucer
            ----------------------------------------------------------------

            -- LEG 1 (North) - Lower section (base to waist)
            { id = "leg1_base", class = "steel", position = {0, 1, -5}, shape = "cylinder", height = 2, radius = 1.2 },
            { id = "leg1_lower1", class = "steel", position = {0, 5, -4.5}, shape = "cylinder", height = 8, radius = 0.9 },
            { id = "leg1_lower2", class = "steel", position = {0, 14, -3.8}, shape = "cylinder", height = 10, radius = 0.7 },
            { id = "leg1_lower3", class = "steel", position = {0, 25, -2.8}, shape = "cylinder", height = 12, radius = 0.6 },
            -- Waist (narrowest point)
            { id = "leg1_waist", class = "steeldark", position = {0, 35, -2}, shape = "cylinder", height = 6, radius = 0.5 },
            -- Upper section (waist to saucer)
            { id = "leg1_upper1", class = "steel", position = {0, 42, -2.5}, shape = "cylinder", height = 8, radius = 0.6 },
            { id = "leg1_upper2", class = "steel", position = {0, 49, -3.5}, shape = "cylinder", height = 6, radius = 0.7 },

            -- LEG 2 (Southwest) - rotated 120 degrees
            { id = "leg2_base", class = "steel", position = {4.3, 1, 2.5}, shape = "cylinder", height = 2, radius = 1.2 },
            { id = "leg2_lower1", class = "steel", position = {3.9, 5, 2.25}, shape = "cylinder", height = 8, radius = 0.9 },
            { id = "leg2_lower2", class = "steel", position = {3.3, 14, 1.9}, shape = "cylinder", height = 10, radius = 0.7 },
            { id = "leg2_lower3", class = "steel", position = {2.4, 25, 1.4}, shape = "cylinder", height = 12, radius = 0.6 },
            { id = "leg2_waist", class = "steeldark", position = {1.7, 35, 1}, shape = "cylinder", height = 6, radius = 0.5 },
            { id = "leg2_upper1", class = "steel", position = {2.2, 42, 1.25}, shape = "cylinder", height = 8, radius = 0.6 },
            { id = "leg2_upper2", class = "steel", position = {3, 49, 1.75}, shape = "cylinder", height = 6, radius = 0.7 },

            -- LEG 3 (Southeast) - rotated 240 degrees
            { id = "leg3_base", class = "steel", position = {-4.3, 1, 2.5}, shape = "cylinder", height = 2, radius = 1.2 },
            { id = "leg3_lower1", class = "steel", position = {-3.9, 5, 2.25}, shape = "cylinder", height = 8, radius = 0.9 },
            { id = "leg3_lower2", class = "steel", position = {-3.3, 14, 1.9}, shape = "cylinder", height = 10, radius = 0.7 },
            { id = "leg3_lower3", class = "steel", position = {-2.4, 25, 1.4}, shape = "cylinder", height = 12, radius = 0.6 },
            { id = "leg3_waist", class = "steeldark", position = {-1.7, 35, 1}, shape = "cylinder", height = 6, radius = 0.5 },
            { id = "leg3_upper1", class = "steel", position = {-2.2, 42, 1.25}, shape = "cylinder", height = 8, radius = 0.6 },
            { id = "leg3_upper2", class = "steel", position = {-3, 49, 1.75}, shape = "cylinder", height = 6, radius = 0.7 },

            ----------------------------------------------------------------
            -- CENTRAL CORE (elevator shaft)
            ----------------------------------------------------------------
            { id = "core_lower", class = "core", position = {0, 15, 0}, shape = "cylinder", height = 30, radius = 1.5 },
            { id = "core_upper", class = "core", position = {0, 40, 0}, shape = "cylinder", height = 20, radius = 1.2 },

            ----------------------------------------------------------------
            -- FLYING SAUCER (observation deck + restaurant)
            ----------------------------------------------------------------
            -- Bottom of saucer (sloped underside)
            { id = "saucer_under", class = "saucerbottom", position = {0, 50, 0}, shape = "cylinder", height = 1.5, radius = 5 },

            -- Main saucer body
            { id = "saucer_main", class = "saucertop", position = {0, 52, 0}, shape = "cylinder", height = 2.5, radius = 7 },

            -- Window band (dark ring around the saucer)
            { id = "saucer_windows", class = "windows", position = {0, 52.5, 0}, shape = "cylinder", height = 1.5, radius = 7.2 },
            { id = "window_frame_top", class = "windowframe", position = {0, 53.5, 0}, shape = "cylinder", height = 0.3, radius = 7.3 },
            { id = "window_frame_bot", class = "windowframe", position = {0, 51.5, 0}, shape = "cylinder", height = 0.3, radius = 7.3 },

            -- Upper observation deck ring
            { id = "saucer_top", class = "saucertop", position = {0, 54, 0}, shape = "cylinder", height = 1, radius = 6 },

            -- Halo ring (the iconic rim)
            { id = "halo", class = "steel", position = {0, 53, 0}, shape = "cylinder", height = 0.4, radius = 8 },

            ----------------------------------------------------------------
            -- SPIRE (above saucer)
            ----------------------------------------------------------------
            { id = "spire_base", class = "spire", position = {0, 55.5, 0}, shape = "cylinder", height = 2, radius = 1 },
            { id = "spire_mid", class = "spire", position = {0, 58, 0}, shape = "cylinder", height = 3, radius = 0.6 },
            { id = "spire_upper", class = "spire", position = {0, 61, 0}, shape = "cylinder", height = 3, radius = 0.35 },
            { id = "spire_tip", class = "spire", position = {0, 63.5, 0}, shape = "cylinder", height = 2, radius = 0.2 },

            -- Aircraft warning beacon
            { id = "beacon", class = "beacon", position = {0, 65, 0}, shape = "sphere", radius = 0.4 },

            ----------------------------------------------------------------
            -- LEG CROSS-BRACING (structural detail)
            ----------------------------------------------------------------
            -- Horizontal rings connecting legs at key heights
            { id = "brace_low", class = "steeldark", position = {0, 8, 0}, shape = "cylinder", height = 0.3, radius = 4 },
            { id = "brace_mid", class = "steeldark", position = {0, 20, 0}, shape = "cylinder", height = 0.3, radius = 3 },
            { id = "brace_waist", class = "steeldark", position = {0, 35, 0}, shape = "cylinder", height = 0.4, radius = 2 },

            ----------------------------------------------------------------
            -- SKYLINE LEVEL (intermediate observation - optional detail)
            ----------------------------------------------------------------
            { id = "skyline_platform", class = "saucerbottom", position = {0, 10, 0}, shape = "cylinder", height = 0.5, radius = 3 },
            { id = "skyline_rail", class = "windowframe", position = {0, 10.5, 0}, shape = "cylinder", height = 0.3, radius = 3.2 },

            ----------------------------------------------------------------
            -- GROUND LEVEL DETAILS
            ----------------------------------------------------------------
            -- Entry pavilion base
            { id = "pavilion", class = "concrete", position = {0, 0.75, 8}, size = {8, 1.5, 6} },
            { id = "pavilion_glass", class = "windows", position = {0, 1.5, 11}, size = {6, 2, 0.3} },

            -- Accent lights on plaza
            { id = "light1", class = "glow", position = {6, 0.3, 0}, shape = "sphere", radius = 0.3 },
            { id = "light2", class = "glow", position = {-6, 0.3, 0}, shape = "sphere", radius = 0.3 },
            { id = "light3", class = "glow", position = {0, 0.3, 6}, shape = "sphere", radius = 0.3 },
            { id = "light4", class = "glow", position = {3, 0.3, -5.2}, shape = "sphere", radius = 0.3 },
            { id = "light5", class = "glow", position = {-3, 0.3, -5.2}, shape = "sphere", radius = 0.3 },
        },

        mounts = {
            { id = "plaza_spawn", position = {0, 0.5, 12}, facing = {0, 0, -1} },
            { id = "observation_deck", position = {0, 55, 0}, facing = {0, 0, -1} },
        },
    },
}
