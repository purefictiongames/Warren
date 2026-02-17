--[[
    Warren DOM Architecture v2.5
    Canvas.lua - Terrain Painting API

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Canvas wraps workspace.Terrain with a clean imperative API for cave
    construction. Palette data comes from the style system (resolved
    externally), so Canvas has no dependency on Styles.lua itself.

    Replaces the terrain functions from LayoutInstantiator.lua.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    Canvas.setMaterialColors(paletteColors) -- Set terrain material colors (no clear)
    Canvas.fillBlock(cframe, size, mat)   -- Fill solid block
    Canvas.carveBlock(cframe, size)       -- Fill with Air
    Canvas.paintNoise(options)            -- Noise scatter (lava veins)
    Canvas.paintFloor(pos, dims, mat)     -- Floor surface layer
    Canvas.mixPatches(options)            -- Noise material mixing (granite)
    Canvas.carveDoorway(cframe, size)     -- Door clearing
    Canvas.carveMargin(cframe, size, m)   -- Fixture/pad clearance
    ```
--]]

local Canvas = {}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local VOXEL_SIZE = 4  -- Roblox terrain minimum voxel size

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local _terrain = nil  -- Set during init

local function getTerrain()
    if not _terrain then
        _terrain = workspace.Terrain
    end
    return _terrain
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
    Set terrain material colors from a palette.
    Does NOT clear existing terrain — terrain is managed per-zone.

    @param palette table - { wallColor = Color3, floorColor = Color3 }
]]
function Canvas.setMaterialColors(palette, wallMaterial, floorMaterial)
    local terrain = getTerrain()
    wallMaterial = wallMaterial or Enum.Material.Rock
    floorMaterial = floorMaterial or Enum.Material.CrackedLava

    if palette.wallColor then
        terrain:SetMaterialColor(wallMaterial, palette.wallColor)
    end
    if palette.floorColor then
        terrain:SetMaterialColor(floorMaterial, palette.floorColor)
    end
end

--[[
    Fill a solid terrain block.

    @param cframe CFrame - Center of the block
    @param size Vector3 - Dimensions of the block
    @param material Enum.Material - Terrain material
]]
function Canvas.fillBlock(cframe, size, material)
    getTerrain():FillBlock(cframe, size, material)
end

--[[
    Carve a block by filling with Air.

    @param cframe CFrame - Center of the block
    @param size Vector3 - Dimensions of the block
]]
function Canvas.carveBlock(cframe, size)
    getTerrain():FillBlock(cframe, size, Enum.Material.Air)
end

--[[
    Fill a terrain shell around a room (solid, no carving).

    @param roomPos table - {x, y, z} room center
    @param roomDims table - {w, h, d} room dimensions
    @param gap number - Gap between interior and terrain shell
    @param material Enum.Material - Shell material
]]
function Canvas.fillShell(roomPos, roomDims, gap, material)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])
    local shellSize = dims + Vector3.new(
        2 * (gap + VOXEL_SIZE),
        2 * (gap + VOXEL_SIZE),
        2 * (gap + VOXEL_SIZE)
    )
    getTerrain():FillBlock(CFrame.new(pos), shellSize, material)
end

--[[
    Clear terrain in a room's shell zone (fill with Air).
    Mirrors fillShell dimensions so exactly the same volume is cleared.

    @param roomPos table - {x, y, z} room center
    @param roomDims table - {w, h, d} room dimensions
    @param gap number - Gap between interior and terrain shell
]]
function Canvas.clearShell(roomPos, roomDims, gap)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])
    local shellSize = dims + Vector3.new(
        2 * (gap + VOXEL_SIZE),
        2 * (gap + VOXEL_SIZE),
        2 * (gap + VOXEL_SIZE)
    )
    getTerrain():FillBlock(CFrame.new(pos), shellSize, Enum.Material.Air)
end

--[[
    Carve out the interior of a room.

    @param roomPos table - {x, y, z} room center
    @param roomDims table - {w, h, d} room dimensions
    @param gap number - Gap size
]]
function Canvas.carveInterior(roomPos, roomDims, gap)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])
    local interiorSize = dims + Vector3.new(2 * gap, 2 * gap, 2 * gap)
    getTerrain():FillBlock(CFrame.new(pos), interiorSize, Enum.Material.Air)
end

--[[
    Paint noise-based veins through terrain shell (e.g., lava veins).

    @param options table:
        - roomPos: {x, y, z}
        - roomDims: {w, h, d}
        - material: Enum.Material - Vein material
        - noiseScale: number (default 8)
        - threshold: number (default 0.55)
]]
function Canvas.paintNoise(options)
    local terrain = getTerrain()
    local pos = Vector3.new(options.roomPos[1], options.roomPos[2], options.roomPos[3])
    local dims = Vector3.new(options.roomDims[1], options.roomDims[2], options.roomDims[3])
    local noiseScale = options.noiseScale or 8
    local threshold = options.threshold or 0.55
    local material = options.material

    local shellMin = pos - dims/2 - Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
    local shellMax = pos + dims/2 + Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
    local interiorMin = pos - dims/2
    local interiorMax = pos + dims/2

    for x = shellMin.X, shellMax.X, VOXEL_SIZE do
        for y = shellMin.Y, shellMax.Y, VOXEL_SIZE do
            for z = shellMin.Z, shellMax.Z, VOXEL_SIZE do
                local inInterior = x > interiorMin.X and x < interiorMax.X
                    and y > interiorMin.Y and y < interiorMax.Y
                    and z > interiorMin.Z and z < interiorMax.Z

                if not inInterior then
                    local n = math.noise(x / noiseScale, y / noiseScale, z / noiseScale)
                    if n > threshold then
                        terrain:FillBlock(
                            CFrame.new(x, y, z),
                            Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE),
                            material
                        )
                    end
                end
            end
        end
    end
end

--[[
    Paint floor material on the exterior floor surface of a room.

    @param roomPos table - {x, y, z}
    @param roomDims table - {w, h, d}
    @param material Enum.Material - Floor material
]]
function Canvas.paintFloor(roomPos, roomDims, material)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])

    local floorY = pos.Y - dims.Y / 2 - VOXEL_SIZE / 2
    local floorPos = Vector3.new(pos.X, floorY, pos.Z)
    local floorSize = Vector3.new(dims.X + VOXEL_SIZE * 2, VOXEL_SIZE, dims.Z + VOXEL_SIZE * 2)
    getTerrain():FillBlock(CFrame.new(floorPos), floorSize, material)
end

--[[
    Mix patches of a secondary material into room floors using noise.

    @param options table:
        - roomPos: {x, y, z}
        - roomDims: {w, h, d}
        - material: Enum.Material - Patch material
        - noiseScale: number (default 12)
        - threshold: number (default 0.4) -- ~30% coverage
]]
function Canvas.mixPatches(options)
    local terrain = getTerrain()
    local pos = Vector3.new(options.roomPos[1], options.roomPos[2], options.roomPos[3])
    local dims = Vector3.new(options.roomDims[1], options.roomDims[2], options.roomDims[3])
    local noiseScale = options.noiseScale or 12
    local threshold = options.threshold or 0.4
    local material = options.material

    local floorY = pos.Y - dims.Y / 2 - VOXEL_SIZE / 2
    local minX = pos.X - dims.X / 2 - VOXEL_SIZE
    local maxX = pos.X + dims.X / 2 + VOXEL_SIZE
    local minZ = pos.Z - dims.Z / 2 - VOXEL_SIZE
    local maxZ = pos.Z + dims.Z / 2 + VOXEL_SIZE

    for x = minX, maxX, VOXEL_SIZE do
        for z = minZ, maxZ, VOXEL_SIZE do
            local n = math.noise(x / noiseScale, floorY / noiseScale, z / noiseScale)
            if n > threshold then
                terrain:FillBlock(
                    CFrame.new(x, floorY, z),
                    Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE),
                    material
                )
            end
        end
    end
end

--[[
    Mix a secondary material into an existing terrain block using noise.

    @param cframe CFrame - Center of the block
    @param size Vector3 - Dimensions of the block
    @param material Enum.Material - Secondary material to mix in
    @param noiseScale number - Noise frequency (default 6)
    @param threshold number - Noise threshold (default 0.3, ~35% coverage)
]]
function Canvas.mixBlock(cframe, size, material, noiseScale, threshold)
    local terrain = getTerrain()
    noiseScale = noiseScale or 6
    threshold = threshold or 0.3

    local pos = cframe.Position
    local half = size / 2
    local minX = pos.X - half.X
    local maxX = pos.X + half.X
    local minY = pos.Y - half.Y
    local maxY = pos.Y + half.Y
    local minZ = pos.Z - half.Z
    local maxZ = pos.Z + half.Z

    for x = minX, maxX, VOXEL_SIZE do
        for y = minY, maxY, VOXEL_SIZE do
            for z = minZ, maxZ, VOXEL_SIZE do
                local n = math.noise(x / noiseScale, y / noiseScale, z / noiseScale)
                if n > threshold then
                    terrain:FillBlock(
                        CFrame.new(x, y, z),
                        Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE),
                        material
                    )
                end
            end
        end
    end
end

--[[
    Carve a doorway in terrain. Expands by 1 voxel to account for overlap.

    @param cframe CFrame - Door center
    @param size Vector3 - Door cutter size
]]
function Canvas.carveDoorway(cframe, size)
    local terrainClearSize = size + Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
    getTerrain():FillBlock(cframe, terrainClearSize, Enum.Material.Air)
end

--[[
    Carve a clearance margin around a fixture or pad.

    @param cframe CFrame - Fixture center
    @param size Vector3 - Fixture size
    @param margin number - Clearance margin in studs (default 2)
]]
function Canvas.carveMargin(cframe, size, margin)
    margin = margin or 2
    local carveSize = size + Vector3.new(margin * 2, margin * 2, margin * 2)
    getTerrain():FillBlock(cframe, carveSize, Enum.Material.Air)
end

--[[
    Get the voxel size constant.

    @return number
]]
function Canvas.getVoxelSize()
    return VOXEL_SIZE
end

return Canvas
