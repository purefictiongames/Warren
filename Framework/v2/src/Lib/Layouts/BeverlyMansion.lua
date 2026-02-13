--[[
    BeverlyMansion - Excessive wealth simulator
--]]

return {
    name = "BeverlyMansion",
    spec = {
        bounds = {120, 24, 100},
        origin = "corner",

        base = {
            part = { CanCollide = true },
        },

        classes = {
            -- Grounds
            lawn = { Material = "Grass", Color = {60, 140, 60} },
            driveway = { Material = "Pavement", Color = {40, 40, 45} },
            poolwater = { Material = "Glass", Color = {40, 180, 220}, Transparency = 0.4 },
            pooltile = { Material = "Marble", Color = {200, 220, 230} },
            hedge = { Material = "Grass", Color = {30, 90, 30} },

            -- Structure
            stucco = { Material = "Concrete", Color = {245, 235, 220} },
            trim = { Material = "Marble", Color = {255, 250, 245} },
            roof = { Material = "Slate", Color = {70, 55, 45} },
            column = { Material = "Marble", Color = {250, 245, 240} },

            -- Accents
            glass = { Material = "Glass", Color = {200, 220, 235}, Transparency = 0.3 },
            door = { Material = "Wood", Color = {80, 50, 30} },
            balcony = { Material = "Marble", Color = {240, 235, 230} },
            railing = { Material = "Metal", Color = {25, 25, 25} },
            gold = { Material = "Metal", Color = {220, 180, 80} },

            -- Garage
            garagedoor = { Material = "DiamondPlate", Color = {60, 60, 65} },

            -- Pool features
            diving = { Material = "Concrete", Color = {180, 175, 170} },
        },

        parts = {
            ----------------------------------------------------------------
            -- GROUNDS
            ----------------------------------------------------------------
            { id = "lawn", class = "lawn", position = {60, -0.25, 50}, size = {120, 0.5, 100} },
            { id = "driveway", class = "driveway", position = {60, 0, 12}, size = {30, 0.1, 24} },
            { id = "driveway_circle", class = "driveway", position = {60, 0, 30}, shape = "cylinder", height = 0.1, radius = 12 },

            -- Front hedges
            { id = "hedge_l1", class = "hedge", position = {20, 2, 5}, size = {30, 4, 3} },
            { id = "hedge_r1", class = "hedge", position = {100, 2, 5}, size = {30, 4, 3} },
            { id = "hedge_l2", class = "hedge", position = {8, 2, 25}, size = {3, 4, 40} },
            { id = "hedge_r2", class = "hedge", position = {112, 2, 25}, size = {3, 4, 40} },

            ----------------------------------------------------------------
            -- MAIN HOUSE - FIRST FLOOR
            ----------------------------------------------------------------
            { id = "main_base", class = "stucco", position = {60, 5, 60}, size = {70, 10, 50} },

            -- Front entrance inset
            { id = "entrance_floor", class = "trim", position = {60, 0.1, 33}, size = {20, 0.2, 6} },

            -- Grand columns
            { id = "column_l1", class = "column", position = {52, 6, 33}, shape = "cylinder", height = 12, radius = 1.2 },
            { id = "column_l2", class = "column", position = {56, 6, 33}, shape = "cylinder", height = 12, radius = 1.2 },
            { id = "column_r1", class = "column", position = {64, 6, 33}, shape = "cylinder", height = 12, radius = 1.2 },
            { id = "column_r2", class = "column", position = {68, 6, 33}, shape = "cylinder", height = 12, radius = 1.2 },

            -- Front door
            { id = "front_door", class = "door", position = {60, 5, 34.5}, size = {8, 10, 1} },
            { id = "door_frame", class = "gold", position = {60, 5, 34.3}, size = {9, 10.5, 0.3} },

            -- Windows - first floor
            { id = "win_f1", class = "glass", position = {38, 5, 35}, size = {6, 6, 0.3} },
            { id = "win_f2", class = "glass", position = {82, 5, 35}, size = {6, 6, 0.3} },
            { id = "win_f3", class = "glass", position = {30, 5, 35}, size = {4, 6, 0.3} },
            { id = "win_f4", class = "glass", position = {90, 5, 35}, size = {4, 6, 0.3} },

            ----------------------------------------------------------------
            -- MAIN HOUSE - SECOND FLOOR
            ----------------------------------------------------------------
            { id = "second_floor", class = "stucco", position = {60, 15, 60}, size = {60, 8, 45} },

            -- Balcony over entrance
            { id = "balcony_floor", class = "balcony", position = {60, 10.5, 34}, size = {24, 1, 8} },
            { id = "balcony_rail_f", class = "railing", position = {60, 12, 30.5}, size = {24, 2, 0.5} },
            { id = "balcony_rail_l", class = "railing", position = {48.5, 12, 34}, size = {0.5, 2, 7} },
            { id = "balcony_rail_r", class = "railing", position = {71.5, 12, 34}, size = {0.5, 2, 7} },
            { id = "balcony_door", class = "glass", position = {60, 14, 37.5}, size = {10, 6, 0.3} },

            -- Windows - second floor
            { id = "win_s1", class = "glass", position = {40, 14, 37.5}, size = {5, 5, 0.3} },
            { id = "win_s2", class = "glass", position = {80, 14, 37.5}, size = {5, 5, 0.3} },
            { id = "win_s3", class = "glass", position = {33, 14, 37.5}, size = {4, 5, 0.3} },
            { id = "win_s4", class = "glass", position = {87, 14, 37.5}, size = {4, 5, 0.3} },

            ----------------------------------------------------------------
            -- ROOF
            ----------------------------------------------------------------
            { id = "roof_main", class = "roof", position = {60, 20.5, 60}, size = {64, 3, 48} },
            { id = "roof_peak", class = "roof", position = {60, 22.5, 60}, size = {58, 2, 42}, shape = "wedge", rotation = {0, 0, 0} },

            ----------------------------------------------------------------
            -- WEST WING - GARAGE
            ----------------------------------------------------------------
            { id = "garage", class = "stucco", position = {18, 4, 55}, size = {24, 8, 30} },
            { id = "garage_door1", class = "garagedoor", position = {12, 3.5, 40}, size = {8, 7, 0.5} },
            { id = "garage_door2", class = "garagedoor", position = {24, 3.5, 40}, size = {8, 7, 0.5} },
            { id = "garage_roof", class = "roof", position = {18, 9, 55}, size = {26, 2, 32} },

            ----------------------------------------------------------------
            -- EAST WING - POOL HOUSE
            ----------------------------------------------------------------
            { id = "poolhouse", class = "stucco", position = {102, 3.5, 70}, size = {16, 7, 20} },
            { id = "poolhouse_glass", class = "glass", position = {94, 3, 70}, size = {0.3, 5, 14} },
            { id = "poolhouse_roof", class = "roof", position = {102, 8, 70}, size = {18, 2, 22} },

            ----------------------------------------------------------------
            -- POOL
            ----------------------------------------------------------------
            { id = "pool_deck", class = "pooltile", position = {100, 0.1, 50}, size = {35, 0.2, 25} },
            { id = "pool_water", class = "poolwater", position = {100, -1, 50}, size = {28, 2, 18} },
            { id = "pool_edge", class = "pooltile", position = {100, 0.3, 50}, size = {30, 0.6, 20} },

            -- Diving board
            { id = "diving_base", class = "diving", position = {114, 1, 50}, size = {2, 2, 3} },
            { id = "diving_board", class = "trim", position = {117, 2, 50}, size = {6, 0.3, 1.5} },

            -- Pool lounge areas
            { id = "lounge1", class = "trim", position = {88, 0.5, 42}, size = {6, 1, 2} },
            { id = "lounge2", class = "trim", position = {88, 0.5, 46}, size = {6, 1, 2} },
            { id = "lounge3", class = "trim", position = {88, 0.5, 50}, size = {6, 1, 2} },

            ----------------------------------------------------------------
            -- BACKYARD FEATURES
            ----------------------------------------------------------------
            -- Patio
            { id = "patio", class = "pooltile", position = {60, 0.1, 82}, size = {40, 0.2, 12} },

            -- Fountain
            { id = "fountain_base", class = "trim", position = {60, 1, 30}, shape = "cylinder", height = 2, radius = 4 },
            { id = "fountain_tier1", class = "trim", position = {60, 3, 30}, shape = "cylinder", height = 2, radius = 2.5 },
            { id = "fountain_tier2", class = "trim", position = {60, 5, 30}, shape = "cylinder", height = 2, radius = 1.5 },
            { id = "fountain_top", class = "gold", position = {60, 6.5, 30}, shape = "sphere", radius = 0.8 },

            -- Back hedge maze entrance
            { id = "backmaze_l", class = "hedge", position = {45, 2.5, 95}, size = {20, 5, 3} },
            { id = "backmaze_r", class = "hedge", position = {75, 2.5, 95}, size = {20, 5, 3} },
        },

        mounts = {
            { id = "front_entrance", position = {60, 0.5, 28}, facing = {0, 0, -1} },
            { id = "garage_spawn", position = {18, 0.5, 42}, facing = {0, 0, -1} },
            { id = "pool_spawn", position = {100, 0.5, 38}, facing = {0, 0, 1} },
            { id = "backyard_spawn", position = {60, 0.5, 88}, facing = {0, 0, 1} },
        },
    },
}
