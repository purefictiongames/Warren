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
    buf:fillFeature(layers, groundY, material, feather)
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
local noise = math.noise
local clamp = math.clamp
local sqrt  = math.sqrt
local atan2 = math.atan2
local cos   = math.cos
local sin   = math.sin
local PI    = math.pi

local Air = Enum.Material.Air

--------------------------------------------------------------------------------
-- Radial distance helpers (used by fillFeature)
--------------------------------------------------------------------------------

local NUM_BINS  = 72
local BIN_ANGLE = 2 * PI / NUM_BINS
local binCos = table.create(NUM_BINS)
local binSin = table.create(NUM_BINS)
for b = 1, NUM_BINS do
    local a = -PI + (b - 0.5) * BIN_ANGLE
    binCos[b] = cos(a)
    binSin[b] = sin(a)
end

--- Build a sorted vertex profile (angle + radius from centroid) for a polygon.
--- Used by sampleVertexRadius for smooth, artifact-free radius lookup.
local function buildVertexProfile(verts, nv, cx, cz)
    local profile = table.create(nv)
    for i = 1, nv do
        local dx = verts[i][1] - cx
        local dz = verts[i][2] - cz
        profile[i] = {
            angle = atan2(dz, dx),
            radius = sqrt(dx * dx + dz * dz),
        }
    end
    table.sort(profile, function(a, b) return a.angle < b.angle end)
    return profile
end

--- Sample polygon radius at a query angle by interpolating between vertex radii.
--- Smoother than ray-polygon intersection — no artifacts when ray aligns with
--- a vertex (which causes both adjacent edges to have near-zero cross products,
--- returning 1e9 and creating vertical spikes in the terrain).
local function sampleVertexRadius(profile, nv, queryAngle)
    local lo, hi
    for i = 1, nv - 1 do
        if queryAngle >= profile[i].angle and queryAngle < profile[i + 1].angle then
            lo, hi = i, i + 1
            break
        end
    end
    if not lo then
        lo, hi = nv, 1 -- wraps around ±π boundary
    end

    local aLo = profile[lo].angle
    local aHi = profile[hi].angle
    if aHi <= aLo then aHi = aHi + 2 * PI end
    local qa = queryAngle
    if qa < aLo then qa = qa + 2 * PI end

    local range = aHi - aLo
    if range < 1e-10 then return profile[lo].radius end
    local t = (qa - aLo) / range
    return profile[lo].radius * (1 - t) + profile[hi].radius * t
end

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

--- Fill an entire feature as a smooth height-field using radial distance.
---
--- For each (x,z) column, computes a continuous radial distance from the
--- feature centroid, modulated by the base polygon shape (via precomputed
--- angular bins). Height is smoothly interpolated between layers using
--- the layer stack as a 1D radial profile with smoothstep transitions.
--- No per-layer polygon containment tests — eliminates the concentric
--- contour rings that cause stratification artifacts.
---
--- @param layers  array of {y, height, vertices={{x,z},...}}  bottom-to-top
--- @param groundY number  base ground elevation (bottom of fill)
--- @param material Enum.Material
--- @param feather number?  falloff distance beyond base polygon in studs (default 16)
function VoxelBuffer:fillFeature(layers, groundY, material, feather)
    if #layers == 0 then return end
    feather = feather or 16
    local nLayers = #layers

    -- 1. Compute centroid from base layer (widest polygon)
    local baseVerts = layers[1].vertices
    local nBase = #baseVerts
    local cx, cz = 0, 0
    for _, v in ipairs(baseVerts) do
        cx = cx + v[1]
        cz = cz + v[2]
    end
    cx = cx / nBase
    cz = cz / nBase

    -- 2. Precompute polygon radius at angular bins for each layer
    --    layerRadii[li][bin] = distance from centroid to polygon edge
    local layerRadii = table.create(nLayers)
    local layerTopY  = table.create(nLayers)
    for li = 1, nLayers do
        local verts = layers[li].vertices
        local nv = #verts
        local profile = buildVertexProfile(verts, nv, cx, cz)
        local radii = table.create(NUM_BINS)
        for b = 1, NUM_BINS do
            local angle = -PI + (b - 0.5) * BIN_ANGLE
            radii[b] = sampleVertexRadius(profile, nv, angle)
        end
        layerRadii[li] = radii
        layerTopY[li] = layers[li].y + layers[li].height
    end

    -- 3. Bounding box from base layer vertices + feather
    local xLo, xHi = baseVerts[1][1], baseVerts[1][1]
    local zLo, zHi = baseVerts[1][2], baseVerts[1][2]
    for i = 2, nBase do
        local vx, vz = baseVerts[i][1], baseVerts[i][2]
        if vx < xLo then xLo = vx end
        if vx > xHi then xHi = vx end
        if vz < zLo then zLo = vz end
        if vz > zHi then zHi = vz end
    end
    xLo = xLo - feather
    xHi = xHi + feather
    zLo = zLo - feather
    zHi = zHi + feather

    local xi1, xi2 = indexRange(xLo, xHi, self._mnX, self._sX)
    if not xi1 then return end
    local zi1, zi2 = indexRange(zLo, zHi, self._mnZ, self._sZ)
    if not zi1 then return end

    local mats = self._materials
    local occs = self._occupancy
    local mnX, mnY, mnZ = self._mnX, self._mnY, self._mnZ

    -- ================================================================
    -- Phase 1: Compute height field into 2D array
    -- ================================================================
    local hW = xi2 - xi1 + 1
    local hD = zi2 - zi1 + 1
    local hField = table.create(hW)
    for i = 1, hW do
        hField[i] = table.create(hD, groundY)
    end

    for zi = zi1, zi2 do
        local wz = mnZ + (zi - 0.5) * VOXEL
        local dzC = wz - cz
        local hzi = zi - zi1 + 1

        for xi = xi1, xi2 do
            local wx = mnX + (xi - 0.5) * VOXEL
            local dxC = wx - cx
            local hxi = xi - xi1 + 1

            -- Distance + angle from centroid
            local dist = sqrt(dxC * dxC + dzC * dzC)
            if dist < 0.001 then dist = 0.001 end
            local angle = atan2(dzC, dxC)

            -- Angular bin with linear interpolation
            local binF = (angle + PI) / BIN_ANGLE + 0.5
            local bin1 = floor(binF)
            local binT = binF - bin1
            local bin2 = bin1 + 1
            if bin1 < 1 then bin1 = bin1 + NUM_BINS end
            if bin1 > NUM_BINS then bin1 = bin1 - NUM_BINS end
            if bin2 < 1 then bin2 = bin2 + NUM_BINS end
            if bin2 > NUM_BINS then bin2 = bin2 - NUM_BINS end

            -- Base polygon radius at this angle (lerp between bins)
            local baseR = layerRadii[1][bin1] * (1 - binT) + layerRadii[1][bin2] * binT
            if baseR < 0.01 then continue end

            -- Normalized distance: 0 = centroid, 1 = base polygon edge
            local normDist = dist / baseR
            local featherNorm = feather / baseR

            if normDist > 1 + featherNorm then continue end

            -- Compute surface height from radial profile
            local surfaceY

            if normDist > 1 then
                -- Outside base polygon: feather zone → fade to ground
                local t = 1 - (normDist - 1) / featherNorm
                t = t * t * (3 - 2 * t) -- smoothstep
                surfaceY = groundY + (layerTopY[1] - groundY) * t
            else
                -- Inside base polygon: walk layers to find height
                -- Layers: 1=base (widest, lowest), N=peak (narrowest, highest)
                surfaceY = layerTopY[1]

                for li = 2, nLayers do
                    local r = layerRadii[li][bin1] * (1 - binT) + layerRadii[li][bin2] * binT
                    local normR = r / baseR

                    if normDist <= normR then
                        -- Inside this layer → update floor height
                        surfaceY = layerTopY[li]
                    else
                        -- Between layer li-1 (outer) and layer li (inner)
                        local rPrev = layerRadii[li - 1][bin1] * (1 - binT) + layerRadii[li - 1][bin2] * binT
                        local normPrev = rPrev / baseR
                        local range = normPrev - normR
                        if range > 0.001 then
                            local t = (normPrev - normDist) / range
                            t = t * t * (3 - 2 * t) -- smoothstep
                            surfaceY = layerTopY[li - 1] + t * (layerTopY[li] - layerTopY[li - 1])
                        end
                        break
                    end
                end
            end

            hField[hxi][hzi] = surfaceY
        end
    end

    -- ================================================================
    -- Phase 2: Smooth height field (3×3 weighted average)
    -- Eliminates columnar artifacts on cliff faces: adjacent columns
    -- converge to similar heights so marching cubes generates a smooth
    -- surface instead of individual voxel-column bumps.
    -- On gentle slopes neighbors already match — smoothing is a no-op.
    -- ================================================================
    local smoothed = table.create(hW)
    for i = 1, hW do
        smoothed[i] = table.create(hD, groundY)
    end

    for hxi = 1, hW do
        local col = hField[hxi]
        for hzi = 1, hD do
            local h = col[hzi]
            if h <= groundY then
                smoothed[hxi][hzi] = groundY
                continue
            end
            local sum = h * 4
            local wt = 4
            if hxi > 1  and hField[hxi - 1][hzi] > groundY then
                sum = sum + hField[hxi - 1][hzi]; wt = wt + 1
            end
            if hxi < hW and hField[hxi + 1][hzi] > groundY then
                sum = sum + hField[hxi + 1][hzi]; wt = wt + 1
            end
            if hzi > 1  and col[hzi - 1] > groundY then
                sum = sum + col[hzi - 1]; wt = wt + 1
            end
            if hzi < hD and col[hzi + 1] > groundY then
                sum = sum + col[hzi + 1]; wt = wt + 1
            end
            smoothed[hxi][hzi] = sum / wt
        end
    end

    -- ================================================================
    -- Phase 3: Fill columns from smoothed height field
    -- ================================================================
    for zi = zi1, zi2 do
        local hzi = zi - zi1 + 1
        for xi = xi1, xi2 do
            local hxi = xi - xi1 + 1
            local surfaceY = smoothed[hxi][hzi]

            if surfaceY > groundY then
                local yiGround = max(1, floor((groundY - mnY) / VOXEL) + 1)
                local yiSurface = floor((surfaceY - mnY) / VOXEL) + 1

                -- Solid voxels below surface
                local yiSolid = min(yiSurface - 1, self._sY)
                for yi = yiGround, yiSolid do
                    mats[xi][yi][zi] = material
                    occs[xi][yi][zi] = 1
                end

                -- Top voxel: fractional occupancy for sub-voxel smoothing
                local yiTop = min(yiSurface, self._sY)
                if yiTop >= 1 and yiTop >= yiGround then
                    local voxelBottom = mnY + (yiTop - 1) * VOXEL
                    local topFrac = clamp((surfaceY - voxelBottom) / VOXEL, 0, 1)
                    if topFrac > occs[xi][yiTop][zi] then
                        mats[xi][yiTop][zi] = material
                        occs[xi][yiTop][zi] = topFrac
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
