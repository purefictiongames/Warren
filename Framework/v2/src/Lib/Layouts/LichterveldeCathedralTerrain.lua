--[[
    LichterveldeCathedralTerrain
    Terrain definition for the cathedral grounds

    Used with workspace.Terrain:FillBlock() to create grass lawns
    around the cathedral. Cathedral should be offset +3 studs Y.
--]]

-- Match cathedral dimensions
local NAVE_LENGTH = 200
local NAVE_WIDTH = 70
local TRANSEPT_WIDTH = 130
local TRANSEPT_DEPTH = 65
local APSE_DEPTH = 40
local APSE_WIDTH = 50
local TOWER_DEPTH = 30

-- Terrain height (cathedral sits on top)
local TERRAIN_HEIGHT = 3

-- Lawn padding around structure
local LAWN_PADDING = 20

return {
    name = "LichterveldeCathedralTerrain",

    -- Origin matches cathedral (floor-center of nave)
    origin = "floor-center",

    -- Terrain fills: { position, size, material }
    -- Position is center of fill region, relative to cathedral origin
    fills = {
        -- Main base under entire cathedral footprint + padding
        {
            id = "base",
            position = {0, TERRAIN_HEIGHT/2, 0},
            size = {TRANSEPT_WIDTH + LAWN_PADDING*2, TERRAIN_HEIGHT, NAVE_LENGTH + APSE_DEPTH + TOWER_DEPTH + LAWN_PADDING*2},
            material = "Grass",
        },

        -- Left lawn (alongside nave, front of transept)
        {
            id = "lawn_left_front",
            position = {-NAVE_WIDTH/2 - LAWN_PADDING/2, TERRAIN_HEIGHT/2, -NAVE_LENGTH/4},
            size = {LAWN_PADDING, TERRAIN_HEIGHT, NAVE_LENGTH/2},
            material = "Grass",
        },

        -- Left lawn (alongside nave, behind transept)
        {
            id = "lawn_left_back",
            position = {-NAVE_WIDTH/2 - LAWN_PADDING/2, TERRAIN_HEIGHT/2, NAVE_LENGTH/4},
            size = {LAWN_PADDING, TERRAIN_HEIGHT, NAVE_LENGTH/2},
            material = "Grass",
        },

        -- Right lawn (alongside nave, front of transept)
        {
            id = "lawn_right_front",
            position = {NAVE_WIDTH/2 + LAWN_PADDING/2, TERRAIN_HEIGHT/2, -NAVE_LENGTH/4},
            size = {LAWN_PADDING, TERRAIN_HEIGHT, NAVE_LENGTH/2},
            material = "Grass",
        },

        -- Right lawn (alongside nave, behind transept)
        {
            id = "lawn_right_back",
            position = {NAVE_WIDTH/2 + LAWN_PADDING/2, TERRAIN_HEIGHT/2, NAVE_LENGTH/4},
            size = {LAWN_PADDING, TERRAIN_HEIGHT, NAVE_LENGTH/2},
            material = "Grass",
        },

        -- Apse lawn extension
        {
            id = "lawn_apse",
            position = {0, TERRAIN_HEIGHT/2, NAVE_LENGTH/2 + APSE_DEPTH/2 + LAWN_PADDING/2},
            size = {APSE_WIDTH + LAWN_PADDING*2, TERRAIN_HEIGHT, APSE_DEPTH + LAWN_PADDING},
            material = "Grass",
        },
    },

    -- Helper to apply terrain fills
    build = function(self, offset)
        offset = offset or Vector3.new(0, 0, 0)
        local terrain = workspace.Terrain
        local materials = {
            Grass = Enum.Material.Grass,
            Pavement = Enum.Material.Pavement,
            Cobblestone = Enum.Material.Cobblestone,
        }

        for _, fill in ipairs(self.fills) do
            local pos = Vector3.new(fill.position[1], fill.position[2], fill.position[3]) + offset
            local size = Vector3.new(fill.size[1], fill.size[2], fill.size[3])
            local mat = materials[fill.material] or Enum.Material.Grass

            terrain:FillBlock(CFrame.new(pos), size, mat)
        end

        return self
    end,

    -- Clear terrain in the region
    clear = function(self, offset)
        offset = offset or Vector3.new(0, 0, 0)
        local terrain = workspace.Terrain

        for _, fill in ipairs(self.fills) do
            local pos = Vector3.new(fill.position[1], fill.position[2], fill.position[3]) + offset
            local size = Vector3.new(fill.size[1], fill.size[2], fill.size[3])

            terrain:FillBlock(CFrame.new(pos), size, Enum.Material.Air)
        end

        return self
    end,
}
