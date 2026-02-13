--[[
    Outpost - A small defensive structure
--]]

return {
    name = "Outpost",
    spec = {
        bounds = {24, 10, 24},
        origin = "corner",

        base = {
            part = { CanCollide = true },
        },

        classes = {
            floor = { Material = "Concrete", Color = {140, 135, 130} },
            wall = { Material = "Brick", Color = {95, 85, 80} },
            metal = { Material = "DiamondPlate", Color = {70, 75, 80} },
            glass = { Material = "Glass", Color = {180, 200, 220}, Transparency = 0.5 },
            glow = { Material = "Neon", Color = {80, 180, 255} },
            danger = { Material = "Neon", Color = {255, 60, 40} },
            crate = { Material = "Wood", Color = {120, 90, 60} },
        },

        parts = {
            -- Foundation
            { id = "foundation", class = "floor", position = {12, 0.25, 12}, size = {24, 0.5, 24} },

            -- Corner pillars
            { id = "pillar_nw", class = "wall", position = {2, 4, 2}, size = {2, 8, 2} },
            { id = "pillar_ne", class = "wall", position = {22, 4, 2}, size = {2, 8, 2} },
            { id = "pillar_sw", class = "wall", position = {2, 4, 22}, size = {2, 8, 2} },
            { id = "pillar_se", class = "wall", position = {22, 4, 22}, size = {2, 8, 2} },

            -- Walls with gaps for windows
            { id = "wall_n1", class = "wall", position = {7, 3, 1}, size = {6, 6, 1} },
            { id = "wall_n2", class = "wall", position = {17, 3, 1}, size = {6, 6, 1} },
            { id = "wall_s1", class = "wall", position = {7, 3, 23}, size = {6, 6, 1} },
            { id = "wall_s2", class = "wall", position = {17, 3, 23}, size = {6, 6, 1} },
            { id = "wall_w", class = "wall", position = {1, 3, 12}, size = {1, 6, 16} },
            { id = "wall_e", class = "wall", position = {23, 3, 12}, size = {1, 6, 16} },

            -- Windows
            { id = "window_n", class = "glass", position = {12, 4, 1}, size = {4, 4, 0.2} },
            { id = "window_s", class = "glass", position = {12, 4, 23}, size = {4, 4, 0.2} },

            -- Roof / platform
            { id = "roof", class = "metal", position = {12, 8.25, 12}, size = {22, 0.5, 22} },

            -- Central console
            { id = "console_base", class = "metal", position = {12, 1.5, 12}, size = {4, 3, 2} },
            { id = "console_screen", class = "glow", position = {12, 3.5, 11.4}, size = {3, 1.5, 0.2} },

            -- Crates
            { id = "crate1", class = "crate", position = {4, 1, 6}, size = {2, 2, 2} },
            { id = "crate2", class = "crate", position = {4, 1, 9}, size = {2, 2, 2} },
            { id = "crate3", class = "crate", position = {4, 3, 7.5}, size = {2, 2, 2} },

            -- Warning lights on pillars
            { id = "light_nw", class = "danger", position = {2, 7, 2}, size = {0.5, 0.5, 0.5} },
            { id = "light_ne", class = "glow", position = {22, 7, 2}, size = {0.5, 0.5, 0.5} },
            { id = "light_sw", class = "glow", position = {2, 7, 22}, size = {0.5, 0.5, 0.5} },
            { id = "light_se", class = "danger", position = {22, 7, 22}, size = {0.5, 0.5, 0.5} },

            -- Antenna on roof
            { id = "antenna_base", class = "metal", position = {18, 9, 18}, shape = "cylinder", height = 0.5, radius = 1 },
            { id = "antenna_pole", class = "metal", position = {18, 11, 18}, shape = "cylinder", height = 4, radius = 0.2 },
            { id = "antenna_dish", class = "metal", position = {18, 13, 18}, shape = "sphere", radius = 0.8 },
        },

        mounts = {
            { id = "turret_roof", position = {6, 8.5, 6}, facing = {0, 0, -1} },
            { id = "spawn_interior", position = {12, 0.5, 18}, facing = {0, 0, -1} },
        },
    },
}
