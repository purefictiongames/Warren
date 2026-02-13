--[[
    Lichtervelde - Belgian village centered on Sint-Jacobus de Meerdere church

    Inspired by the village in West Flanders, Belgium.
    Neo-Gothic church (1878-1880) with cruciform basilica layout and prominent bell tower.
    The church square (Kerkplein) forms the heart, with radiating streets and
    traditional Flemish architecture featuring red/brown brick and slate roofs.
--]]

return {
    name = "Lichtervelde",
    spec = {
        bounds = {200, 40, 200},
        origin = "center",

        base = {
            part = { CanCollide = true },
        },

        classes = {
            -- Ground
            cobblestone = { Material = "Cobblestone", Color = {120, 115, 110} },
            asphalt = { Material = "Pavement", Color = {55, 55, 60} },
            grass = { Material = "Grass", Color = {70, 120, 55} },
            sidewalk = { Material = "Concrete", Color = {170, 165, 160} },

            -- Church materials (Neo-Gothic)
            churchbrick = { Material = "Brick", Color = {140, 85, 70} },
            churchstone = { Material = "Limestone", Color = {200, 190, 175} },
            churchroof = { Material = "Slate", Color = {50, 50, 55} },
            stainedglass = { Material = "Glass", Color = {80, 60, 120}, Transparency = 0.3 },
            churchdoor = { Material = "Wood", Color = {50, 35, 25} },
            cross = { Material = "Metal", Color = {180, 160, 100} },

            -- Flemish houses
            redbrick = { Material = "Brick", Color = {150, 75, 60} },
            brownbrick = { Material = "Brick", Color = {130, 90, 70} },
            whitewash = { Material = "Concrete", Color = {235, 230, 220} },
            slatehouse = { Material = "Slate", Color = {60, 55, 50} },
            tileroof = { Material = "Brick", Color = {160, 80, 55} },
            woodtrim = { Material = "Wood", Color = {70, 50, 35} },
            housedoor = { Material = "Wood", Color = {60, 40, 30} },
            window = { Material = "Glass", Color = {180, 200, 220}, Transparency = 0.4 },

            -- Town features
            fountain = { Material = "Granite", Color = {140, 135, 130} },
            water = { Material = "Glass", Color = {60, 140, 180}, Transparency = 0.5 },
            lamppost = { Material = "Metal", Color = {35, 40, 45} },
            lamp = { Material = "Neon", Color = {255, 220, 150} },
            bench = { Material = "Wood", Color = {80, 60, 45} },
            hedge = { Material = "Grass", Color = {45, 85, 40} },
            tree = { Material = "Grass", Color = {50, 100, 45} },
            trunk = { Material = "Wood", Color = {75, 55, 40} },
        },

        parts = {
            ----------------------------------------------------------------
            -- GROUND PLANE
            ----------------------------------------------------------------
            { id = "ground", class = "grass", position = {0, -0.25, 0}, size = {200, 0.5, 200} },

            ----------------------------------------------------------------
            -- KERKPLEIN (CHURCH SQUARE)
            ----------------------------------------------------------------
            { id = "kerkplein", class = "cobblestone", position = {0, 0, 0}, size = {50, 0.1, 50} },
            { id = "kerkplein_walk_n", class = "sidewalk", position = {0, 0.05, -28}, size = {40, 0.1, 4} },
            { id = "kerkplein_walk_s", class = "sidewalk", position = {0, 0.05, 28}, size = {40, 0.1, 4} },

            ----------------------------------------------------------------
            -- SINT-JACOBUS DE MEERDERE CHURCH (Neo-Gothic)
            ----------------------------------------------------------------
            -- Main nave (east-west orientation, entrance facing west)
            { id = "church_nave", class = "churchbrick", position = {0, 8, 5}, size = {16, 16, 35} },

            -- Bell tower (prominent western facade)
            { id = "church_tower_base", class = "churchbrick", position = {0, 12, -15}, size = {12, 24, 12} },
            { id = "church_tower_mid", class = "churchbrick", position = {0, 28, -15}, size = {10, 8, 10} },
            { id = "church_tower_top", class = "churchbrick", position = {0, 35, -15}, size = {8, 6, 8} },
            { id = "church_spire", class = "churchroof", position = {0, 42, -15}, size = {6, 12, 6}, shape = "wedge", rotation = {0, 0, 0} },
            { id = "church_cross", class = "cross", position = {0, 49, -15}, size = {0.5, 3, 0.5} },

            -- Transept (north-south arms of cruciform)
            { id = "church_transept", class = "churchbrick", position = {0, 7, 8}, size = {30, 14, 12} },

            -- Chancel/Apse (eastern end)
            { id = "church_chancel", class = "churchbrick", position = {0, 6, 22}, size = {12, 12, 10} },
            { id = "church_apse", class = "churchbrick", position = {0, 6, 28}, shape = "cylinder", height = 12, radius = 5 },

            -- Church roofs
            { id = "church_nave_roof", class = "churchroof", position = {0, 17, 5}, size = {18, 4, 37} },
            { id = "church_transept_roof", class = "churchroof", position = {0, 15, 8}, size = {32, 3, 14} },
            { id = "church_chancel_roof", class = "churchroof", position = {0, 13, 22}, size = {14, 3, 12} },

            -- Main entrance (western portal)
            { id = "church_portal", class = "churchstone", position = {0, 5, -21}, size = {6, 10, 2} },
            { id = "church_door", class = "churchdoor", position = {0, 4, -21.5}, size = {4, 8, 0.5} },

            -- Gothic windows
            { id = "church_win_n1", class = "stainedglass", position = {-8, 8, 5}, size = {0.3, 8, 4} },
            { id = "church_win_n2", class = "stainedglass", position = {-8, 8, 0}, size = {0.3, 8, 4} },
            { id = "church_win_n3", class = "stainedglass", position = {-8, 8, 10}, size = {0.3, 8, 4} },
            { id = "church_win_s1", class = "stainedglass", position = {8, 8, 5}, size = {0.3, 8, 4} },
            { id = "church_win_s2", class = "stainedglass", position = {8, 8, 0}, size = {0.3, 8, 4} },
            { id = "church_win_s3", class = "stainedglass", position = {8, 8, 10}, size = {0.3, 8, 4} },
            { id = "church_rose_window", class = "stainedglass", position = {0, 18, -15}, shape = "cylinder", height = 0.3, radius = 3 },

            -- Tower clock faces
            { id = "clock_n", class = "churchstone", position = {0, 30, -20}, shape = "cylinder", height = 0.5, radius = 2 },
            { id = "clock_s", class = "churchstone", position = {0, 30, -10}, shape = "cylinder", height = 0.5, radius = 2 },

            ----------------------------------------------------------------
            -- STREETS RADIATING FROM SQUARE
            ----------------------------------------------------------------
            -- Hoogstraat (main street, north-south)
            { id = "hoogstraat_n", class = "asphalt", position = {0, 0, -50}, size = {10, 0.1, 50} },
            { id = "hoogstraat_s", class = "asphalt", position = {0, 0, 60}, size = {10, 0.1, 70} },

            -- Side streets (east-west)
            { id = "street_w", class = "asphalt", position = {-50, 0, 0}, size = {50, 0.1, 8} },
            { id = "street_e", class = "asphalt", position = {50, 0, 0}, size = {50, 0.1, 8} },

            -- Diagonal streets
            { id = "street_nw", class = "asphalt", position = {-40, 0, -40}, size = {8, 0.1, 40}, rotation = {0, 45, 0} },
            { id = "street_ne", class = "asphalt", position = {40, 0, -40}, size = {8, 0.1, 40}, rotation = {0, -45, 0} },

            -- Sidewalks along main street
            { id = "sidewalk_n_w", class = "sidewalk", position = {-7, 0.05, -50}, size = {4, 0.1, 50} },
            { id = "sidewalk_n_e", class = "sidewalk", position = {7, 0.05, -50}, size = {4, 0.1, 50} },

            ----------------------------------------------------------------
            -- FLEMISH HOUSES - NORTH SIDE OF SQUARE
            ----------------------------------------------------------------
            -- Row of houses facing the church
            { id = "house_n1", class = "redbrick", position = {-20, 5, -35}, size = {8, 10, 10} },
            { id = "house_n1_roof", class = "slatehouse", position = {-20, 11, -35}, size = {9, 4, 11} },
            { id = "house_n1_door", class = "housedoor", position = {-20, 2.5, -30}, size = {2, 5, 0.3} },
            { id = "house_n1_win1", class = "window", position = {-17, 6, -30}, size = {1.5, 2, 0.3} },
            { id = "house_n1_win2", class = "window", position = {-23, 6, -30}, size = {1.5, 2, 0.3} },

            { id = "house_n2", class = "whitewash", position = {-32, 4.5, -35}, size = {10, 9, 10} },
            { id = "house_n2_roof", class = "tileroof", position = {-32, 10, -35}, size = {11, 4, 11} },
            { id = "house_n2_trim", class = "woodtrim", position = {-32, 9, -30}, size = {10, 0.5, 0.3} },
            { id = "house_n2_door", class = "housedoor", position = {-30, 2.5, -30}, size = {2, 5, 0.3} },

            { id = "house_n3", class = "brownbrick", position = {-44, 5.5, -35}, size = {9, 11, 10} },
            { id = "house_n3_roof", class = "slatehouse", position = {-44, 12, -35}, size = {10, 4, 11} },

            ----------------------------------------------------------------
            -- FLEMISH HOUSES - EAST SIDE
            ----------------------------------------------------------------
            { id = "house_e1", class = "redbrick", position = {35, 4, 15}, size = {10, 8, 10} },
            { id = "house_e1_roof", class = "tileroof", position = {35, 9, 15}, size = {11, 3, 11} },

            { id = "house_e2", class = "whitewash", position = {35, 5, 28}, size = {10, 10, 10} },
            { id = "house_e2_roof", class = "slatehouse", position = {35, 11, 28}, size = {11, 4, 11} },

            { id = "house_e3", class = "brownbrick", position = {35, 4.5, 41}, size = {10, 9, 10} },
            { id = "house_e3_roof", class = "tileroof", position = {35, 10, 41}, size = {11, 3.5, 11} },

            ----------------------------------------------------------------
            -- FLEMISH HOUSES - WEST SIDE
            ----------------------------------------------------------------
            { id = "house_w1", class = "brownbrick", position = {-35, 5, 15}, size = {10, 10, 12} },
            { id = "house_w1_roof", class = "slatehouse", position = {-35, 11, 15}, size = {11, 4, 13} },

            { id = "house_w2", class = "redbrick", position = {-35, 4, 30}, size = {10, 8, 10} },
            { id = "house_w2_roof", class = "tileroof", position = {-35, 9, 30}, size = {11, 3, 11} },

            { id = "house_w3", class = "whitewash", position = {-35, 4.5, 43}, size = {10, 9, 10} },
            { id = "house_w3_roof", class = "slatehouse", position = {-35, 10, 43}, size = {11, 3.5, 11} },

            ----------------------------------------------------------------
            -- FLEMISH HOUSES - SOUTH (along Hoogstraat)
            ----------------------------------------------------------------
            { id = "house_s1", class = "redbrick", position = {15, 5, 55}, size = {10, 10, 12} },
            { id = "house_s1_roof", class = "slatehouse", position = {15, 11, 55}, size = {11, 4, 13} },

            { id = "house_s2", class = "brownbrick", position = {15, 4.5, 70}, size = {10, 9, 10} },
            { id = "house_s2_roof", class = "tileroof", position = {15, 10, 70}, size = {11, 3.5, 11} },

            { id = "house_s3", class = "whitewash", position = {-15, 5, 55}, size = {10, 10, 12} },
            { id = "house_s3_roof", class = "tileroof", position = {-15, 11, 55}, size = {11, 4, 13} },

            { id = "house_s4", class = "redbrick", position = {-15, 4, 70}, size = {10, 8, 10} },
            { id = "house_s4_roof", class = "slatehouse", position = {-15, 9, 70}, size = {11, 3, 11} },

            ----------------------------------------------------------------
            -- TOWN SQUARE FEATURES
            ----------------------------------------------------------------
            -- Small fountain in front of church
            { id = "fountain_base", class = "fountain", position = {0, 0.5, -28}, shape = "cylinder", height = 1, radius = 4 },
            { id = "fountain_basin", class = "water", position = {0, 0.8, -28}, shape = "cylinder", height = 0.4, radius = 3.5 },
            { id = "fountain_center", class = "fountain", position = {0, 2, -28}, shape = "cylinder", height = 3, radius = 0.8 },
            { id = "fountain_top", class = "fountain", position = {0, 4, -28}, shape = "sphere", radius = 0.6 },

            -- Lamp posts around square
            { id = "lamp_nw", class = "lamppost", position = {-20, 3, -25}, shape = "cylinder", height = 6, radius = 0.2 },
            { id = "lamp_nw_light", class = "lamp", position = {-20, 6.5, -25}, shape = "sphere", radius = 0.5 },
            { id = "lamp_ne", class = "lamppost", position = {20, 3, -25}, shape = "cylinder", height = 6, radius = 0.2 },
            { id = "lamp_ne_light", class = "lamp", position = {20, 6.5, -25}, shape = "sphere", radius = 0.5 },
            { id = "lamp_sw", class = "lamppost", position = {-20, 3, 25}, shape = "cylinder", height = 6, radius = 0.2 },
            { id = "lamp_sw_light", class = "lamp", position = {-20, 6.5, 25}, shape = "sphere", radius = 0.5 },
            { id = "lamp_se", class = "lamppost", position = {20, 3, 25}, shape = "cylinder", height = 6, radius = 0.2 },
            { id = "lamp_se_light", class = "lamp", position = {20, 6.5, 25}, shape = "sphere", radius = 0.5 },

            -- Benches
            { id = "bench_w", class = "bench", position = {-18, 0.8, -10}, size = {4, 1.6, 1.2} },
            { id = "bench_e", class = "bench", position = {18, 0.8, -10}, size = {4, 1.6, 1.2} },

            -- Trees around the square
            { id = "tree_nw_trunk", class = "trunk", position = {-22, 3, -22}, shape = "cylinder", height = 6, radius = 0.5 },
            { id = "tree_nw_crown", class = "tree", position = {-22, 8, -22}, shape = "sphere", radius = 4 },
            { id = "tree_ne_trunk", class = "trunk", position = {22, 3, -22}, shape = "cylinder", height = 6, radius = 0.5 },
            { id = "tree_ne_crown", class = "tree", position = {22, 8, -22}, shape = "sphere", radius = 4 },

            -- Hedges along church boundary
            { id = "hedge_church_w", class = "hedge", position = {-12, 1, 5}, size = {2, 2, 30} },
            { id = "hedge_church_e", class = "hedge", position = {12, 1, 5}, size = {2, 2, 30} },

            ----------------------------------------------------------------
            -- ROUNDABOUT (west side, per aerial image)
            ----------------------------------------------------------------
            { id = "roundabout", class = "asphalt", position = {-70, 0, 0}, shape = "cylinder", height = 0.1, radius = 12 },
            { id = "roundabout_center", class = "grass", position = {-70, 0.1, 0}, shape = "cylinder", height = 0.2, radius = 6 },
            { id = "roundabout_tree_trunk", class = "trunk", position = {-70, 3, 0}, shape = "cylinder", height = 6, radius = 0.6 },
            { id = "roundabout_tree_crown", class = "tree", position = {-70, 8, 0}, shape = "sphere", radius = 5 },

            ----------------------------------------------------------------
            -- DISTANT HOUSES (background)
            ----------------------------------------------------------------
            { id = "distant_n1", class = "redbrick", position = {-50, 4, -70}, size = {12, 8, 12} },
            { id = "distant_n1_roof", class = "slatehouse", position = {-50, 9, -70}, size = {13, 3, 13} },

            { id = "distant_n2", class = "brownbrick", position = {-30, 4, -70}, size = {10, 8, 10} },
            { id = "distant_n2_roof", class = "tileroof", position = {-30, 9, -70}, size = {11, 3, 11} },

            { id = "distant_n3", class = "whitewash", position = {30, 4.5, -70}, size = {12, 9, 10} },
            { id = "distant_n3_roof", class = "slatehouse", position = {30, 10, -70}, size = {13, 3.5, 11} },

            { id = "distant_n4", class = "redbrick", position = {50, 4, -70}, size = {10, 8, 12} },
            { id = "distant_n4_roof", class = "tileroof", position = {50, 9, -70}, size = {11, 3, 13} },

            -- More distant south
            { id = "distant_s1", class = "brownbrick", position = {40, 4, 85}, size = {12, 8, 10} },
            { id = "distant_s1_roof", class = "slatehouse", position = {40, 9, 85}, size = {13, 3, 11} },

            { id = "distant_s2", class = "redbrick", position = {-40, 4.5, 85}, size = {10, 9, 12} },
            { id = "distant_s2_roof", class = "tileroof", position = {-40, 10, 85}, size = {11, 3.5, 13} },
        },

        mounts = {
            { id = "church_entrance", position = {0, 0.5, -24}, facing = {0, 0, -1} },
            { id = "square_center", position = {0, 0.5, -20}, facing = {0, 0, -1} },
            { id = "hoogstraat_north", position = {0, 0.5, -75}, facing = {0, 0, -1} },
            { id = "hoogstraat_south", position = {0, 0.5, 90}, facing = {0, 0, 1} },
            { id = "roundabout_spawn", position = {-70, 0.5, 15}, facing = {1, 0, 0} },
        },
    },
}
