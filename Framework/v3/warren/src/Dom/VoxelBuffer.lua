--[[
    Warren DOM Architecture v3.0
    VoxelBuffer.lua - Buffered Terrain Write API

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    VoxelBuffer holds two 3D Lua arrays (materials + occupancy) aligned to the
    4-stud voxel grid. All terrain ops write into the arrays. One flush() call
    writes the entire buffer via Terrain:WriteVoxels.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local buf = VoxelBuffer.new(worldMin, worldMax)
    buf:fillBlock(cframe, size, material)
    buf:fillWedge(cframe, size, material)
    buf:flush()  -- ONE WriteVoxels call
    ```
--]]

local VoxelBuffer = {}
VoxelBuffer.__index = VoxelBuffer

local VOXEL = 4
local floor = math.floor
local ceil  = math.ceil
local max   = math.max
local min   = math.min
local abs   = math.abs
local noise = math.noise
local clamp = math.clamp

local Air = Enum.Material.Air

--------------------------------------------------------------------------------
-- Grid snapping
--------------------------------------------------------------------------------

local function snapDown(val)
    return floor(val / VOXEL) * VOXEL
end

local function snapUp(val)
    return ceil(val / VOXEL) * VOXEL
end

--- World-space range → clamped 1-based index range. Returns nil,nil if outside.
local function indexRange(wMin, wMax, bufMin, bufSize)
    local i1 = max(1, floor((wMin - bufMin) / VOXEL) + 1)
    local i2 = min(bufSize, ceil((wMax - bufMin) / VOXEL))
    if i1 > i2 then return nil, nil end
    return i1, i2
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- Create an empty buffer spanning [worldMin, worldMax], snapped to voxel grid.
function VoxelBuffer.new(worldMin, worldMax)
    local mnX = snapDown(worldMin.X)
    local mnY = snapDown(worldMin.Y)
    local mnZ = snapDown(worldMin.Z)
    local mxX = snapUp(worldMax.X)
    local mxY = snapUp(worldMax.Y)
    local mxZ = snapUp(worldMax.Z)

    local sX = (mxX - mnX) / VOXEL
    local sY = (mxY - mnY) / VOXEL
    local sZ = (mxZ - mnZ) / VOXEL

    local mats = table.create(sX)
    local occs = table.create(sX)
    for xi = 1, sX do
        mats[xi] = table.create(sY)
        occs[xi] = table.create(sY)
        for yi = 1, sY do
            mats[xi][yi] = table.create(sZ, Air)
            occs[xi][yi] = table.create(sZ, 0)
        end
    end

    return setmetatable({
        _mnX = mnX, _mnY = mnY, _mnZ = mnZ,
        _mxX = mxX, _mxY = mxY, _mxZ = mxZ,
        _sX = sX, _sY = sY, _sZ = sZ,
        _materials = mats,
        _occupancy = occs,
    }, VoxelBuffer)
end

--- Create a buffer pre-loaded with existing terrain via ReadVoxels.
function VoxelBuffer.fromTerrain(worldMin, worldMax)
    local mnX = snapDown(worldMin.X)
    local mnY = snapDown(worldMin.Y)
    local mnZ = snapDown(worldMin.Z)
    local mxX = snapUp(worldMax.X)
    local mxY = snapUp(worldMax.Y)
    local mxZ = snapUp(worldMax.Z)

    local region = Region3.new(
        Vector3.new(mnX, mnY, mnZ),
        Vector3.new(mxX, mxY, mxZ)
    )
    local mats, occs = workspace.Terrain:ReadVoxels(region, VOXEL)

    local sX = (mxX - mnX) / VOXEL
    local sY = (mxY - mnY) / VOXEL
    local sZ = (mxZ - mnZ) / VOXEL

    return setmetatable({
        _mnX = mnX, _mnY = mnY, _mnZ = mnZ,
        _mxX = mxX, _mxY = mxY, _mxZ = mxZ,
        _sX = sX, _sY = sY, _sZ = sZ,
        _materials = mats,
        _occupancy = occs,
    }, VoxelBuffer)
end

--------------------------------------------------------------------------------
-- Coordinate mapping
--------------------------------------------------------------------------------

--- World studs → 1-based array index.
function VoxelBuffer:worldToIndex(wx, wy, wz)
    return
        floor((wx - self._mnX) / VOXEL) + 1,
        floor((wy - self._mnY) / VOXEL) + 1,
        floor((wz - self._mnZ) / VOXEL) + 1
end

--- 1-based array index → voxel cell center in world studs.
function VoxelBuffer:indexToWorld(xi, yi, zi)
    return
        self._mnX + (xi - 0.5) * VOXEL,
        self._mnY + (yi - 0.5) * VOXEL,
        self._mnZ + (zi - 0.5) * VOXEL
end

--------------------------------------------------------------------------------
-- Single-voxel primitives
--------------------------------------------------------------------------------

--- Set a single voxel by array index (bounds-checked, no-op if outside).
function VoxelBuffer:setVoxel(xi, yi, zi, material, occ)
    if xi >= 1 and xi <= self._sX
        and yi >= 1 and yi <= self._sY
        and zi >= 1 and zi <= self._sZ then
        self._materials[xi][yi][zi] = material
        self._occupancy[xi][yi][zi] = occ or 1
    end
end

--- Get a single voxel by array index (returns Air,0 if outside).
function VoxelBuffer:getVoxel(xi, yi, zi)
    if xi >= 1 and xi <= self._sX
        and yi >= 1 and yi <= self._sY
        and zi >= 1 and zi <= self._sZ then
        return self._materials[xi][yi][zi], self._occupancy[xi][yi][zi]
    end
    return Air, 0
end

--------------------------------------------------------------------------------
-- Geometry primitives
--------------------------------------------------------------------------------

--- Fill an axis-aligned block. CFrame position = center, size = full dims.
--- Occupancy defaults to 1.0 (solid). Pass 0<occ<1 for partial fills.
function VoxelBuffer:fillBlock(cframe, size, material, occ)
    occ = occ or 1
    local pos = cframe.Position
    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2

    local xi1, xi2 = indexRange(pos.X - hx, pos.X + hx, self._mnX, self._sX)
    if not xi1 then return end
    local yi1, yi2 = indexRange(pos.Y - hy, pos.Y + hy, self._mnY, self._sY)
    if not yi1 then return end
    local zi1, zi2 = indexRange(pos.Z - hz, pos.Z + hz, self._mnZ, self._sZ)
    if not zi1 then return end

    local mats = self._materials
    local occs = self._occupancy
    for xi = xi1, xi2 do
        local col = mats[xi]
        local oCol = occs[xi]
        for yi = yi1, yi2 do
            local row = col[yi]
            local oRow = oCol[yi]
            for zi = zi1, zi2 do
                row[zi] = material
                oRow[zi] = occ
            end
        end
    end
end

--- Carve (fill with Air, occupancy 0).
function VoxelBuffer:carveBlock(cframe, size)
    self:fillBlock(cframe, size, Air, 0)
end

--- Fill a wedge volume. Uses CFrame to transform voxel centers into wedge-local
--- space for the slope test.
---
--- Roblox WedgePart convention: full height at local -Z, slopes to zero at +Z.
--- Cross-section (YZ): right triangle with hypotenuse from (-halfZ, +halfY) to
--- (+halfZ, -halfY).
function VoxelBuffer:fillWedge(cframe, size, material, occ)
    occ = occ or 1
    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
    local sizeY, sizeZ = size.Y, size.Z

    -- Conservative axis-aligned bounding box in world space
    local pos = cframe.Position
    local maxHalf = max(hx, hy, hz)
    local xi1, xi2 = indexRange(pos.X - maxHalf, pos.X + maxHalf, self._mnX, self._sX)
    if not xi1 then return end
    local yi1, yi2 = indexRange(pos.Y - maxHalf, pos.Y + maxHalf, self._mnY, self._sY)
    if not yi1 then return end
    local zi1, zi2 = indexRange(pos.Z - maxHalf, pos.Z + maxHalf, self._mnZ, self._sZ)
    if not zi1 then return end

    local inv = cframe:Inverse()
    local mats = self._materials
    local occs = self._occupancy
    local mnX, mnY, mnZ = self._mnX, self._mnY, self._mnZ

    for xi = xi1, xi2 do
        local wx = mnX + (xi - 0.5) * VOXEL
        local col = mats[xi]
        local oCol = occs[xi]
        for yi = yi1, yi2 do
            local wy = mnY + (yi - 0.5) * VOXEL
            local row = col[yi]
            local oRow = oCol[yi]
            for zi = zi1, zi2 do
                local wz = mnZ + (zi - 0.5) * VOXEL
                local lp = inv * Vector3.new(wx, wy, wz)
                local lx, ly, lz = lp.X, lp.Y, lp.Z

                if abs(lx) <= hx and ly >= -hy and abs(lz) <= hz then
                    -- Slope test: hypotenuse from (-halfZ, halfY) to (+halfZ, -halfY)
                    local slopeMax = hy - sizeY * (lz + hz) / sizeZ
                    if ly <= slopeMax then
                        row[zi] = material
                        oRow[zi] = occ
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Room composite ops
--------------------------------------------------------------------------------

--- Fill a solid terrain shell around a room.
function VoxelBuffer:fillShell(roomPos, roomDims, gap, material)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])
    local pad = 2 * (gap + VOXEL)
    local shellSize = dims + Vector3.new(pad, pad, pad)
    self:fillBlock(CFrame.new(pos), shellSize, material)
end

--- Clear terrain in a room's shell zone.
function VoxelBuffer:clearShell(roomPos, roomDims, gap)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])
    local pad = 2 * (gap + VOXEL)
    local shellSize = dims + Vector3.new(pad, pad, pad)
    self:carveBlock(CFrame.new(pos), shellSize)
end

--- Carve out the interior of a room.
function VoxelBuffer:carveInterior(roomPos, roomDims, gap)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])
    local pad = 2 * gap
    local interiorSize = dims + Vector3.new(pad, pad, pad)
    self:carveBlock(CFrame.new(pos), interiorSize)
end

--------------------------------------------------------------------------------
-- Decorative ops
--------------------------------------------------------------------------------

--- Paint noise-based veins through terrain shell (e.g., lava veins).
function VoxelBuffer:paintNoise(options)
    local pos = Vector3.new(options.roomPos[1], options.roomPos[2], options.roomPos[3])
    local dims = Vector3.new(options.roomDims[1], options.roomDims[2], options.roomDims[3])
    local noiseScale = options.noiseScale or 8
    local threshold = options.threshold or 0.55
    local material = options.material

    local shellMinX = pos.X - dims.X / 2 - VOXEL
    local shellMaxX = pos.X + dims.X / 2 + VOXEL
    local shellMinY = pos.Y - dims.Y / 2 - VOXEL
    local shellMaxY = pos.Y + dims.Y / 2 + VOXEL
    local shellMinZ = pos.Z - dims.Z / 2 - VOXEL
    local shellMaxZ = pos.Z + dims.Z / 2 + VOXEL

    local intMinX = pos.X - dims.X / 2
    local intMaxX = pos.X + dims.X / 2
    local intMinY = pos.Y - dims.Y / 2
    local intMaxY = pos.Y + dims.Y / 2
    local intMinZ = pos.Z - dims.Z / 2
    local intMaxZ = pos.Z + dims.Z / 2

    local xi1, xi2 = indexRange(shellMinX, shellMaxX, self._mnX, self._sX)
    if not xi1 then return end
    local yi1, yi2 = indexRange(shellMinY, shellMaxY, self._mnY, self._sY)
    if not yi1 then return end
    local zi1, zi2 = indexRange(shellMinZ, shellMaxZ, self._mnZ, self._sZ)
    if not zi1 then return end

    local mats = self._materials
    local occs = self._occupancy
    local mnX, mnY, mnZ = self._mnX, self._mnY, self._mnZ

    for xi = xi1, xi2 do
        local wx = mnX + (xi - 0.5) * VOXEL
        local col = mats[xi]
        local oCol = occs[xi]
        for yi = yi1, yi2 do
            local wy = mnY + (yi - 0.5) * VOXEL
            local inInteriorXY = wx > intMinX and wx < intMaxX
                and wy > intMinY and wy < intMaxY
            local row = col[yi]
            local oRow = oCol[yi]
            for zi = zi1, zi2 do
                local wz = mnZ + (zi - 0.5) * VOXEL
                local inInterior = inInteriorXY
                    and wz > intMinZ and wz < intMaxZ
                if not inInterior then
                    local n = noise(wx / noiseScale, wy / noiseScale, wz / noiseScale)
                    if n > threshold then
                        row[zi] = material
                        oRow[zi] = 1
                    end
                end
            end
        end
    end
end

--- Paint floor material on the exterior floor surface of a room.
function VoxelBuffer:paintFloor(roomPos, roomDims, material)
    local pos = Vector3.new(roomPos[1], roomPos[2], roomPos[3])
    local dims = Vector3.new(roomDims[1], roomDims[2], roomDims[3])
    local floorY = pos.Y - dims.Y / 2 - VOXEL / 2
    local floorPos = Vector3.new(pos.X, floorY, pos.Z)
    local floorSize = Vector3.new(dims.X + VOXEL * 2, VOXEL, dims.Z + VOXEL * 2)
    self:fillBlock(CFrame.new(floorPos), floorSize, material)
end

--- Mix patches of a secondary material into room floors using noise.
function VoxelBuffer:mixPatches(options)
    local pos = Vector3.new(options.roomPos[1], options.roomPos[2], options.roomPos[3])
    local dims = Vector3.new(options.roomDims[1], options.roomDims[2], options.roomDims[3])
    local noiseScale = options.noiseScale or 12
    local threshold = options.threshold or 0.4
    local material = options.material

    local floorY = pos.Y - dims.Y / 2 - VOXEL / 2
    local minX = pos.X - dims.X / 2 - VOXEL
    local maxX = pos.X + dims.X / 2 + VOXEL
    local minZ = pos.Z - dims.Z / 2 - VOXEL
    local maxZ = pos.Z + dims.Z / 2 + VOXEL

    local xi1, xi2 = indexRange(minX, maxX, self._mnX, self._sX)
    if not xi1 then return end
    local yi = max(1, min(self._sY, floor((floorY - self._mnY) / VOXEL) + 1))
    local zi1, zi2 = indexRange(minZ, maxZ, self._mnZ, self._sZ)
    if not zi1 then return end

    local mats = self._materials
    local occs = self._occupancy
    local mnX, mnZ = self._mnX, self._mnZ

    for xi = xi1, xi2 do
        local wx = mnX + (xi - 0.5) * VOXEL
        local row = mats[xi][yi]
        local oRow = occs[xi][yi]
        for zi = zi1, zi2 do
            local wz = mnZ + (zi - 0.5) * VOXEL
            local n = noise(wx / noiseScale, floorY / noiseScale, wz / noiseScale)
            if n > threshold then
                row[zi] = material
                oRow[zi] = 1
            end
        end
    end
end

--- Mix a secondary material into an existing terrain block using noise.
function VoxelBuffer:mixBlock(cframe, size, material, noiseScale, threshold)
    noiseScale = noiseScale or 6
    threshold = threshold or 0.3

    local pos = cframe.Position
    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2

    local xi1, xi2 = indexRange(pos.X - hx, pos.X + hx, self._mnX, self._sX)
    if not xi1 then return end
    local yi1, yi2 = indexRange(pos.Y - hy, pos.Y + hy, self._mnY, self._sY)
    if not yi1 then return end
    local zi1, zi2 = indexRange(pos.Z - hz, pos.Z + hz, self._mnZ, self._sZ)
    if not zi1 then return end

    local mats = self._materials
    local occs = self._occupancy
    local mnX, mnY, mnZ = self._mnX, self._mnY, self._mnZ

    for xi = xi1, xi2 do
        local wx = mnX + (xi - 0.5) * VOXEL
        local col = mats[xi]
        local oCol = occs[xi]
        for yi = yi1, yi2 do
            local wy = mnY + (yi - 0.5) * VOXEL
            local row = col[yi]
            local oRow = oCol[yi]
            for zi = zi1, zi2 do
                local wz = mnZ + (zi - 0.5) * VOXEL
                local n = noise(wx / noiseScale, wy / noiseScale, wz / noiseScale)
                if n > threshold then
                    row[zi] = material
                    oRow[zi] = 1
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Carving
--------------------------------------------------------------------------------

--- Carve a doorway. Expands by 1 voxel to account for overlap.
function VoxelBuffer:carveDoorway(cframe, size)
    local terrainClearSize = size + Vector3.new(VOXEL, VOXEL, VOXEL)
    self:carveBlock(cframe, terrainClearSize)
end

--- Carve clearance margin around a fixture or pad.
function VoxelBuffer:carveMargin(cframe, size, margin)
    margin = margin or 2
    local carveSize = size + Vector3.new(margin * 2, margin * 2, margin * 2)
    self:carveBlock(cframe, carveSize)
end

--------------------------------------------------------------------------------
-- Flush
--------------------------------------------------------------------------------

--- Write entire buffer to workspace.Terrain in one API call.
function VoxelBuffer:flush()
    local region = Region3.new(
        Vector3.new(self._mnX, self._mnY, self._mnZ),
        Vector3.new(self._mxX, self._mxY, self._mxZ)
    )
    workspace.Terrain:WriteVoxels(region, VOXEL, self._materials, self._occupancy)
end

return VoxelBuffer
