--[[
    Warren DOM Architecture v3.0
    Canvas.lua - Terrain Painting API (Factory + Utility)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Canvas is the public entry point for terrain operations. v3.0 introduces
    VoxelBuffer for batched writes — create a buffer, fill it, flush once.

    Canvas also exposes backward-compatible one-shot wrappers (fillBlock,
    paintNoise, etc.) that call terrain directly. Unmigrated consumers keep
    working with zero code changes. Migrated consumers use createBuffer()
    for the real performance win.

    ============================================================================
    USAGE (new — buffered)
    ============================================================================

    ```lua
    local buf = Canvas.createBuffer(worldMin, worldMax)
    buf:fillBlock(cframe, size, material)
    buf:fillFeature(layers, groundY, material, feather)
    buf:flush()  -- ONE WriteVoxels call
    ```

    ============================================================================
    USAGE (legacy — one-shot, unchanged API)
    ============================================================================

    ```lua
    Canvas.setMaterialColors(palette, wall, floor)
    Canvas.fillBlock(cframe, size, mat)
    Canvas.carveBlock(cframe, size)
    Canvas.paintNoise(options)
    ```
--]]

local VoxelBuffer = require(script.Parent.VoxelBuffer)

local Canvas = {}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local VOXEL_SIZE = 4  -- Roblox terrain minimum voxel size

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local _terrain = nil

local function getTerrain()
    if not _terrain then
        _terrain = workspace.Terrain
    end
    return _terrain
end

--------------------------------------------------------------------------------
-- FACTORY (new v3.0 API)
--------------------------------------------------------------------------------

--[[
    Create an empty VoxelBuffer spanning [worldMin, worldMax].
    All terrain ops write into the buffer. Call buf:flush() to commit.

    @param worldMin Vector3 - Lower corner in world studs
    @param worldMax Vector3 - Upper corner in world studs
    @return VoxelBuffer
]]
function Canvas.createBuffer(worldMin, worldMax)
    return VoxelBuffer.new(worldMin, worldMax)
end

--[[
    Create a VoxelBuffer pre-loaded with existing terrain via ReadVoxels.

    @param worldMin Vector3 - Lower corner in world studs
    @param worldMax Vector3 - Upper corner in world studs
    @return VoxelBuffer
]]
function Canvas.readBuffer(worldMin, worldMax)
    return VoxelBuffer.fromTerrain(worldMin, worldMax)
end

--[[
    Clear a terrain region (fill with Air). Direct FillBlock — no buffer
    allocation needed since this is already one API call.

    @param worldMin Vector3 - Lower corner in world studs
    @param worldMax Vector3 - Upper corner in world studs
]]
function Canvas.clearRegion(worldMin, worldMax)
    local center = (worldMin + worldMax) / 2
    local size = worldMax - worldMin
    getTerrain():FillBlock(CFrame.new(center), size, Enum.Material.Air)
end

--------------------------------------------------------------------------------
-- UTILITY (engine-level, no buffer)
--------------------------------------------------------------------------------

--[[
    Set terrain material colors from a palette.
    Does NOT clear existing terrain — terrain is managed per-zone.

    @param palette table - { wallColor = Color3, floorColor = Color3 }
    @param wallMaterial Enum.Material? - defaults to Rock
    @param floorMaterial Enum.Material? - defaults to CrackedLava
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
    Get the voxel size constant.

    @return number
]]
function Canvas.getVoxelSize()
    return VOXEL_SIZE
end

--------------------------------------------------------------------------------
-- BACKWARD-COMPAT ONE-SHOT WRAPPERS
--
-- These call terrain directly (same as v2.5). Unmigrated consumers keep
-- working unchanged. For batched performance, use createBuffer() instead.
--------------------------------------------------------------------------------

function Canvas.fillBlock(cframe, size, material)
    getTerrain():FillBlock(cframe, size, material)
end

function Canvas.carveBlock(cframe, size)
    getTerrain():FillBlock(cframe, size, Enum.Material.Air)
end

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

function Canvas.carveInterior(roomPos, roomDims, gap)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])
    local interiorSize = dims + Vector3.new(2 * gap, 2 * gap, 2 * gap)
    getTerrain():FillBlock(CFrame.new(pos), interiorSize, Enum.Material.Air)
end

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

function Canvas.paintFloor(roomPos, roomDims, material)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])

    local floorY = pos.Y - dims.Y / 2 - VOXEL_SIZE / 2
    local floorPos = Vector3.new(pos.X, floorY, pos.Z)
    local floorSize = Vector3.new(dims.X + VOXEL_SIZE * 2, VOXEL_SIZE, dims.Z + VOXEL_SIZE * 2)
    getTerrain():FillBlock(CFrame.new(floorPos), floorSize, material)
end

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

function Canvas.carveDoorway(cframe, size)
    local terrainClearSize = size + Vector3.new(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
    getTerrain():FillBlock(cframe, terrainClearSize, Enum.Material.Air)
end

function Canvas.carveMargin(cframe, size, margin)
    margin = margin or 2
    local carveSize = size + Vector3.new(margin * 2, margin * 2, margin * 2)
    getTerrain():FillBlock(cframe, carveSize, Enum.Material.Air)
end

return Canvas
