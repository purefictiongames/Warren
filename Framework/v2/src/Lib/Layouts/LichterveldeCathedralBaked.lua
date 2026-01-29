--[[
    LichterveldeCathedralBaked
    Scanned/baked version of the cathedral with absolute positions
    Use this for static placement without the computed layout overhead
--]]

return {
    name = "LichterveldeCathedralBaked",
    spec = {
        origin = "corner",
        bounds = {150, 155, 260},

        classes = {
            wall = { Color = {210, 200, 175}, Material = "Concrete", CanCollide = false },
            wall_trim = { Color = {180, 170, 155}, Material = "Concrete", CanCollide = false },
            roof = { Color = {55, 55, 60}, Material = "SmoothPlastic", CanCollide = false },
            window = { Color = {70, 80, 100}, Material = "SmoothPlastic", CanCollide = false },
            door = { Color = {50, 45, 40}, Material = "SmoothPlastic", CanCollide = false },
            collision = { Material = "SmoothPlastic", Transparency = 1 },
        },

        parts = {
            -- WALLS
            { id = "Wall_Nave_Left", class = "wall", position = {117, 28, 280}, size = {4, 55, 200} },
            { id = "Wall_Nave_Right", class = "wall", position = {183, 28, 280}, size = {4, 55, 200} },
            { id = "Wall_Nave_Front_Left", class = "wall", position = {124, 28, 182}, size = {17, 55, 4} },
            { id = "Wall_Nave_Front_Right", class = "wall", position = {177, 28, 182}, size = {17, 55, 4} },
            { id = "Wall_Transept_Left_Outer", class = "wall", position = {87, 28, 240}, size = {4, 55, 65} },
            { id = "Wall_Transept_Right_Outer", class = "wall", position = {213, 28, 240}, size = {4, 55, 65} },
            { id = "Wall_Transept_Left_Front", class = "wall", position = {100, 28, 210}, size = {30, 55, 4} },
            { id = "Wall_Transept_Left_Back", class = "wall", position = {100, 28, 271}, size = {30, 55, 4} },
            { id = "Wall_Transept_Right_Front", class = "wall", position = {200, 28, 210}, size = {30, 55, 4} },
            { id = "Wall_Transept_Right_Back", class = "wall", position = {200, 28, 271}, size = {30, 55, 4} },
            { id = "Wall_Apse_Back", class = "wall", position = {150, 25, 388}, size = {34, 50, 4} },
            { id = "Wall_Apse_Left", class = "wall", position = {127, 25, 370}, size = {4, 50, 32} },
            { id = "Wall_Apse_Right", class = "wall", position = {173, 25, 370}, size = {4, 50, 32} },
            { id = "Wall_Apse_Corner_Left", class = "wall", position = {131, 25, 386}, size = {4, 50, 12}, rotation = {0, 35, 0} },
            { id = "Wall_Apse_Corner_Right", class = "wall", position = {169, 25, 386}, size = {4, 50, 12}, rotation = {0, -35, 0} },

            -- TOWER
            { id = "Tower_Base", class = "wall", position = {150, 45, 170}, size = {36, 90, 30} },
            { id = "Tower_Upper", class = "wall", position = {150, 103, 170}, size = {32, 25, 26} },
            { id = "Tower_Band_Lower", class = "wall_trim", position = {150, 36, 155}, size = {38, 3, 1} },
            { id = "Tower_Band_Upper", class = "wall_trim", position = {150, 90, 155}, size = {38, 2, 1} },
            { id = "Tower_Spire_Left_Base", class = "wall", position = {137, 119, 160}, size = {8, 8, 8} },
            { id = "Tower_Spire_Right_Base", class = "wall", position = {163, 119, 160}, size = {8, 8, 8} },

            -- ROOFS
            { id = "Roof_Nave_Left", class = "roof", shape = "wedge", position = {132, 68, 280}, size = {204, 25, 37}, rotation = {0, 90, 0} },
            { id = "Roof_Nave_Right", class = "roof", shape = "wedge", position = {169, 68, 280}, size = {204, 25, 37}, rotation = {0, -90, 0} },
            { id = "Roof_Transept_Left_Front", class = "roof", shape = "wedge", position = {113, 65, 224}, size = {55, 20, 35} },
            { id = "Roof_Transept_Left_Back", class = "roof", shape = "wedge", position = {113, 65, 256}, size = {55, 20, 35}, rotation = {0, 180, 0} },
            { id = "Roof_Transept_Right_Front", class = "roof", shape = "wedge", position = {188, 65, 224}, size = {55, 20, 35} },
            { id = "Roof_Transept_Right_Back", class = "roof", shape = "wedge", position = {188, 65, 256}, size = {55, 20, 35}, rotation = {0, 180, 0} },
            { id = "Roof_Apse_Left", class = "roof", shape = "wedge", position = {138, 58, 375}, size = {45, 16, 25}, rotation = {0, 90, 0} },
            { id = "Roof_Apse_Right", class = "roof", shape = "wedge", position = {163, 58, 375}, size = {45, 16, 25}, rotation = {0, -90, 0} },
            { id = "Tower_Spire_Left_Mid", class = "roof", shape = "wedge", position = {137, 131, 158}, size = {6, 15, 4} },
            { id = "Tower_Spire_Left_Mid2", class = "roof", shape = "wedge", position = {137, 131, 162}, size = {6, 15, 4}, rotation = {0, 180, 0} },
            { id = "Tower_Spire_Right_Mid", class = "roof", shape = "wedge", position = {163, 131, 158}, size = {6, 15, 4} },
            { id = "Tower_Spire_Right_Mid2", class = "roof", shape = "wedge", position = {163, 131, 162}, size = {6, 15, 4}, rotation = {0, 180, 0} },

            -- DOOR (structural frame only, no thin detail parts)
            { id = "Door_Main_Frame", class = "wall_trim", position = {150, 10, 155}, size = {16, 20, 2} },

            -- BUTTRESSES
            { id = "Buttress_L_01", class = "wall", position = {114, 22, 200}, size = {4, 44, 3} },
            { id = "Buttress_L_02", class = "wall", position = {114, 22, 230}, size = {4, 44, 3} },
            { id = "Buttress_L_03", class = "wall", position = {114, 22, 260}, size = {4, 44, 3} },
            { id = "Buttress_L_04", class = "wall", position = {114, 22, 290}, size = {4, 44, 3} },
            { id = "Buttress_L_05", class = "wall", position = {114, 22, 320}, size = {4, 44, 3} },
            { id = "Buttress_L_06", class = "wall", position = {114, 22, 350}, size = {4, 44, 3} },
            { id = "Buttress_R_01", class = "wall", position = {187, 22, 200}, size = {4, 44, 3} },
            { id = "Buttress_R_02", class = "wall", position = {187, 22, 230}, size = {4, 44, 3} },
            { id = "Buttress_R_03", class = "wall", position = {187, 22, 260}, size = {4, 44, 3} },
            { id = "Buttress_R_04", class = "wall", position = {187, 22, 290}, size = {4, 44, 3} },
            { id = "Buttress_R_05", class = "wall", position = {187, 22, 320}, size = {4, 44, 3} },
            { id = "Buttress_R_06", class = "wall", position = {187, 22, 350}, size = {4, 44, 3} },
            { id = "Buttress_Transept_L_Front", class = "wall", position = {84, 22, 212}, size = {4, 44, 4} },
            { id = "Buttress_Transept_L_Back", class = "wall", position = {84, 22, 269}, size = {4, 44, 4} },
            { id = "Buttress_Transept_R_Front", class = "wall", position = {217, 22, 212}, size = {4, 44, 4} },
            { id = "Buttress_Transept_R_Back", class = "wall", position = {217, 22, 269}, size = {4, 44, 4} },
            { id = "Buttress_Apse_Left", class = "wall", position = {124, 20, 375}, size = {4, 40, 4} },
            { id = "Buttress_Apse_Right", class = "wall", position = {177, 20, 375}, size = {4, 40, 4} },

            -- TRIM
            { id = "Trim_Base_Nave_Left", class = "wall_trim", position = {115, 1, 280}, size = {2, 2, 204} },
            { id = "Trim_Base_Nave_Right", class = "wall_trim", position = {186, 1, 280}, size = {2, 2, 204} },
            { id = "Trim_Base_Transept_Left", class = "wall_trim", position = {85, 1, 240}, size = {2, 2, 69} },
            { id = "Trim_Base_Transept_Right", class = "wall_trim", position = {216, 1, 240}, size = {2, 2, 69} },

            -- COLLISION
            { id = "Collision_Nave", class = "collision", position = {150, 40, 280}, size = {70, 80, 200} },
            { id = "Collision_Transept", class = "collision", position = {150, 40, 240}, size = {130, 80, 65} },
            { id = "Collision_Tower", class = "collision", position = {150, 60, 170}, size = {36, 120, 30} },
            { id = "Collision_Apse", class = "collision", position = {150, 30, 370}, size = {50, 60, 40} },
        },
    },
}
