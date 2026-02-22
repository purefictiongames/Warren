--[[
    IGW v2 Pipeline — TerrainPainterNode (Phase 2: Terrain Voxels)

    Computes a 2D height field from spline data, then rasterizes into Roblox
    terrain via VoxelBuffer in 512-stud tiles.

    Algorithm — 5-step height field per (x,z) column:
        1. Base envelope — multi-spine distance-based uplift
        2. Ridge peaks — additive max-blend from ridge segments
        3. Valley carving — subtractive U/V shapes from valley segments
        4. Point features — volcano cones, cirque bowls, pass depressions
        5. Surface noise — 2-octave Perlin, height-proportional amplitude

    Performance: spatial grid bucketing (32×32), squared-distance early reject,
    deferred sqrt, numeric for-loops, time-based yielding.

    Signal: onPaintTerrain(payload) → fires nodeComplete
--]]

local VOXEL = 4
local floor = math.floor
local ceil  = math.ceil
local abs   = math.abs
local sqrt  = math.sqrt
local exp   = math.exp
local rad   = math.rad
local cos   = math.cos
local sin   = math.sin
local huge  = math.huge
local max   = math.max
local min   = math.min
local noise = math.noise

return {
    name = "TerrainPainterNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onPaintTerrain = function(self, payload)
            -- Wrap in task.spawn: IPC dispatch is synchronous so the handler
            -- cannot yield. The spawned thread can yield freely; _syncCall
            -- polls via task.wait() until nodeComplete sets the flag.
            local selfRef = self
            task.spawn(function()
                local VoxelBuffer = selfRef._System.Dom.VoxelBuffer
                local startTime = os.clock()

                ----------------------------------------------------------------
                -- Config from attributes
                ----------------------------------------------------------------

                local mapWidth = selfRef:getAttribute("mapWidth") or 4000
                local mapDepth = selfRef:getAttribute("mapDepth") or 4000
                local groundY  = selfRef:getAttribute("groundY") or 0
                local tileSize = selfRef:getAttribute("tileSize") or 512

                -- Surface noise config
                local noiseAmplitude = selfRef:getAttribute("noiseAmplitude") or 0
                local noiseScale1    = selfRef:getAttribute("noiseScale1") or 200
                local noiseScale2    = selfRef:getAttribute("noiseScale2") or 80
                local noiseRatio     = selfRef:getAttribute("noiseRatio") or 0.65

                ----------------------------------------------------------------
                -- Data from payload
                ----------------------------------------------------------------

                local splines     = payload.splines or {}
                local biomeConfig = payload.biomeConfig or {}
                local biome       = payload.biome or {}
                local baseElev    = biomeConfig.baseElevation or {}
                local spineConfig = biomeConfig.spine or {}
                local featureDefs = biomeConfig.features or {}

                local crestHeight = baseElev.crestHeight or 350
                local edgeHeight  = baseElev.edgeHeight or 40

                -- Terrain material from biome
                local terrainFloor = biome.terrainFloor or "Grass"
                local material = Enum.Material[terrainFloor] or Enum.Material.Grass

                -- Snow on gentle slopes (only when base is Rock)
                local snowMaterial = Enum.Material.Snow
                local useSnowOnSlopes = (material == Enum.Material.Rock)
                local slopeThreshold = 0.6  -- ~31 degrees; below this → Snow

                -- Ice-blue tint for Rock terrain
                if useSnowOnSlopes then
                    workspace.Terrain:SetMaterialColor(
                        Enum.Material.Rock,
                        Color3.fromRGB(140, 160, 190)
                    )
                end

                ----------------------------------------------------------------
                -- Spine axis geometry
                ----------------------------------------------------------------

                local angle    = rad(spineConfig.angle or 15)
                local spineDX  = cos(angle)
                local spineDZ  = sin(angle)
                local perpDX   = -spineDZ
                local perpDZ   = spineDX

                local halfW = mapWidth / 2
                local halfD = mapDepth / 2
                local mapMinX = -halfW
                local mapMinZ = -halfD
                local gridW = floor(mapWidth / VOXEL)
                local gridD = floor(mapDepth / VOXEL)
                local diagonalExtent = min(halfW, halfD) * 0.85

                ----------------------------------------------------------------
                -- Helpers
                ----------------------------------------------------------------

                local function smoothstep(t)
                    if t <= 0 then return 0 end
                    if t >= 1 then return 1 end
                    return t * t * (3 - 2 * t)
                end

                local function lerp(a, b, t)
                    return a + (b - a) * t
                end

                -- Returns (t, distSq) — squared distance; caller sqrts only when needed
                local function projectOntoSegment(px, pz, ax, az, bx, bz)
                    local dx = bx - ax
                    local dz = bz - az
                    local lenSq = dx * dx + dz * dz
                    if lenSq < 0.001 then
                        local ex, ez = px - ax, pz - az
                        return 0, ex * ex + ez * ez
                    end
                    local t = ((px - ax) * dx + (pz - az) * dz) / lenSq
                    if t < 0 then t = 0 elseif t > 1 then t = 1 end
                    local cx = ax + t * dx
                    local cz = az + t * dz
                    local ex, ez = px - cx, pz - cz
                    return t, ex * ex + ez * ez
                end

                ----------------------------------------------------------------
                -- Preprocess: collect segments + AABB from splines
                -- Main spine segments excluded from ridgeSegs (handled in Step 1)
                ----------------------------------------------------------------

                local ridgeSegs = {}
                local valleySegs = {}
                local pointFeatures = {}

                for _, spline in ipairs(splines) do
                    local cps = spline.controlPoints
                    local isValley    = (spline.class == "valley")
                    local isMainSpine = (spline.subclass == "main_spine")
                    local isGlacial   = (spline.subclass == "glacial_valley")

                    for ci = 1, #cps - 1 do
                        local a = cps[ci]
                        local b = cps[ci + 1]
                        local seg = {
                            ax = a.x, az = a.z,
                            bx = b.x, bz = b.z,
                            elevA = a.elevation, elevB = b.elevation,
                            widthA = a.width or 100, widthB = b.width or 100,
                        }
                        if isValley then
                            seg.depthA = a.depth or 50
                            seg.depthB = b.depth or 50
                            seg.isGlacial = isGlacial
                            local expand = max(seg.widthA, seg.widthB) / 2
                            seg.minX = min(seg.ax, seg.bx) - expand
                            seg.maxX = max(seg.ax, seg.bx) + expand
                            seg.minZ = min(seg.az, seg.bz) - expand
                            seg.maxZ = max(seg.az, seg.bz) + expand
                            table.insert(valleySegs, seg)
                        elseif not isMainSpine then
                            -- main_spine handled via mainSpinePolylines (Step 1)
                            local expand = max(seg.widthA, seg.widthB) * 1.5
                            seg.minX = min(seg.ax, seg.bx) - expand
                            seg.maxX = max(seg.ax, seg.bx) + expand
                            seg.minZ = min(seg.az, seg.bz) - expand
                            seg.maxZ = max(seg.az, seg.bz) + expand
                            table.insert(ridgeSegs, seg)
                        end
                    end

                    for _, cp in ipairs(cps) do
                        if cp.featureClass then
                            table.insert(pointFeatures, {
                                class     = cp.featureClass,
                                x         = cp.x,
                                z         = cp.z,
                                elevation = cp.elevation,
                                width     = cp.width,
                                depth     = cp.depth,
                            })
                        end
                    end
                end

                ----------------------------------------------------------------
                -- Main spine polylines (Step 1 envelope + ridge blend)
                ----------------------------------------------------------------

                local mainSpinePolylines = {}
                for _, spline in ipairs(splines) do
                    if spline.subclass == "main_spine" then
                        local segs = {}
                        local cps = spline.controlPoints
                        for ci = 1, #cps - 1 do
                            table.insert(segs, {
                                ax = cps[ci].x, az = cps[ci].z,
                                bx = cps[ci+1].x, bz = cps[ci+1].z,
                                elevA = cps[ci].elevation,
                                elevB = cps[ci+1].elevation,
                                widthA = cps[ci].width or 100,
                                widthB = cps[ci+1].width or 100,
                            })
                        end
                        table.insert(mainSpinePolylines, segs)
                    end
                end

                ----------------------------------------------------------------
                -- Spatial grid for segment bucketing (32×32)
                ----------------------------------------------------------------

                local GRID_RES = 32
                local gridCellSize = mapWidth / GRID_RES

                local ridgeGrid = table.create(GRID_RES)
                local valleyGrid = table.create(GRID_RES)
                for gx = 1, GRID_RES do
                    ridgeGrid[gx] = table.create(GRID_RES)
                    valleyGrid[gx] = table.create(GRID_RES)
                    for gz = 1, GRID_RES do
                        ridgeGrid[gx][gz] = {}
                        valleyGrid[gx][gz] = {}
                    end
                end

                local function insertIntoGrid(grid, seg)
                    local gx1 = max(1, floor((seg.minX - mapMinX) / gridCellSize) + 1)
                    local gx2 = min(GRID_RES, floor((seg.maxX - mapMinX) / gridCellSize) + 1)
                    local gz1 = max(1, floor((seg.minZ - mapMinZ) / gridCellSize) + 1)
                    local gz2 = min(GRID_RES, floor((seg.maxZ - mapMinZ) / gridCellSize) + 1)
                    for gx = gx1, gx2 do
                        for gz = gz1, gz2 do
                            table.insert(grid[gx][gz], seg)
                        end
                    end
                end

                for si = 1, #ridgeSegs do
                    insertIntoGrid(ridgeGrid, ridgeSegs[si])
                end
                for si = 1, #valleySegs do
                    insertIntoGrid(valleyGrid, valleySegs[si])
                end

                print(string.format(
                    "[TerrainPainterNode] Grid %dx%d | %d ridge segs, %d valley segs, %d features, %d main spines | bucket %dx%d",
                    gridW, gridD, #ridgeSegs, #valleySegs, #pointFeatures, #mainSpinePolylines,
                    GRID_RES, GRID_RES
                ))

                ----------------------------------------------------------------
                -- Compute height field (Steps 1-5)
                ----------------------------------------------------------------

                local hField = table.create(gridW)
                for xi = 1, gridW do
                    hField[xi] = table.create(gridD, groundY)
                end

                local maxH = groundY

                -- Precompute envelope thresholds (squared for distSq comparison)
                local innerZone    = diagonalExtent * 0.15
                local falloffEnd   = diagonalExtent * 0.70
                local innerZoneSq  = innerZone * innerZone
                local falloffEndSq = falloffEnd * falloffEnd
                local beyondScale  = diagonalExtent * 0.3

                -- Noise seed offset
                local noiseSeed = (payload.seed or 0) * 0.01337

                -- Time-based yielding (~33ms budget per frame)
                local lastYield = os.clock()

                for xi = 1, gridW do
                    local wx = mapMinX + (xi - 0.5) * VOXEL
                    local gx = max(1, min(GRID_RES, floor((wx - mapMinX) / gridCellSize) + 1))
                    local hRow = hField[xi]

                    for zi = 1, gridD do
                        local wz = mapMinZ + (zi - 0.5) * VOXEL
                        local gz = max(1, min(GRID_RES, floor((wz - mapMinZ) / gridCellSize) + 1))

                        -- Step 1: Multi-spine base envelope + main spine ridge blend
                        local h
                        local ridgeMax = -huge

                        if #mainSpinePolylines > 0 then
                            local minDistSq = huge
                            local nearestElev = edgeHeight
                            for pi = 1, #mainSpinePolylines do
                                local poly = mainSpinePolylines[pi]
                                for si = 1, #poly do
                                    local seg = poly[si]
                                    local t, dSq = projectOntoSegment(
                                        wx, wz, seg.ax, seg.az, seg.bx, seg.bz
                                    )
                                    -- Track nearest for base envelope
                                    if dSq < minDistSq then
                                        minDistSq = dSq
                                        nearestElev = lerp(seg.elevA, seg.elevB, t)
                                    end

                                    -- Ridge contribution (merged, avoids duplicate projection)
                                    local elev = lerp(seg.elevA, seg.elevB, t)
                                    local hw = lerp(seg.widthA, seg.widthB, t) / 2
                                    local hwSq = hw * hw
                                    if dSq <= hwSq then
                                        local c = groundY + elev
                                        if c > ridgeMax then ridgeMax = c end
                                    elseif dSq <= hwSq * 9 then
                                        local f = 1 - ((sqrt(dSq) - hw) / (hw * 2))
                                        f = f * f
                                        local c = groundY + elev * f
                                        if c > ridgeMax then ridgeMax = c end
                                    end
                                end
                            end

                            -- Compute base envelope from minDistSq
                            if minDistSq < innerZoneSq then
                                h = groundY + nearestElev * 0.35
                            elseif minDistSq < falloffEndSq then
                                local md = sqrt(minDistSq)
                                local ft = (md - innerZone) / (falloffEnd - innerZone)
                                h = groundY + lerp(nearestElev * 0.35, edgeHeight, smoothstep(ft))
                            else
                                local md = sqrt(minDistSq)
                                local bt = min(1, (md - falloffEnd) / beyondScale)
                                h = groundY + lerp(edgeHeight, edgeHeight * 0.3, smoothstep(bt))
                            end
                        else
                            -- Fallback: original rectangular dome
                            local projAlong = wx * spineDX + wz * spineDZ
                            local projPerp  = wx * perpDX  + wz * perpDZ
                            local normAlong = abs(projAlong) / diagonalExtent
                            local normPerp  = abs(projPerp)  / diagonalExtent
                            local falloffT  = max(normAlong, normPerp)
                            if falloffT > 1 then falloffT = 1 end
                            h = groundY + lerp(
                                crestHeight * 0.35, edgeHeight,
                                smoothstep(falloffT)
                            )
                        end

                        -- Step 2: Ridge peaks (sub-ridges; main spine handled above)
                        local localRidge = ridgeGrid[gx][gz]
                        for si = 1, #localRidge do
                            local seg = localRidge[si]
                            if wx >= seg.minX and wx <= seg.maxX
                               and wz >= seg.minZ and wz <= seg.maxZ then
                                local t, dSq = projectOntoSegment(
                                    wx, wz, seg.ax, seg.az, seg.bx, seg.bz
                                )
                                local hw = lerp(seg.widthA, seg.widthB, t) / 2
                                local hwSq = hw * hw
                                if dSq <= hwSq then
                                    local c = groundY + lerp(seg.elevA, seg.elevB, t)
                                    if c > ridgeMax then ridgeMax = c end
                                elseif dSq <= hwSq * 9 then
                                    local elev = lerp(seg.elevA, seg.elevB, t)
                                    local f = 1 - ((sqrt(dSq) - hw) / (hw * 2))
                                    f = f * f
                                    local c = groundY + elev * f
                                    if c > ridgeMax then ridgeMax = c end
                                end
                            end
                        end

                        if ridgeMax > h then h = ridgeMax end

                        -- Step 3: Valley carving (subtractive)
                        local localValley = valleyGrid[gx][gz]
                        for si = 1, #localValley do
                            local seg = localValley[si]
                            if wx >= seg.minX and wx <= seg.maxX
                               and wz >= seg.minZ and wz <= seg.maxZ then
                                local t, dSq = projectOntoSegment(
                                    wx, wz, seg.ax, seg.az, seg.bx, seg.bz
                                )
                                local hw = lerp(seg.widthA, seg.widthB, t) / 2
                                local hwSq = hw * hw
                                if dSq <= hwSq then
                                    local depth = lerp(seg.depthA, seg.depthB, t)
                                    if seg.isGlacial then
                                        -- U-shape: dSq/hwSq avoids sqrt entirely
                                        h = h - depth * (1 - dSq / hwSq)
                                    else
                                        -- V-shape: needs sqrt for linear falloff
                                        h = h - depth * (1 - sqrt(dSq) / hw)
                                    end
                                end
                            end
                        end

                        -- Step 5: Surface noise (2-octave Perlin, height-proportional)
                        if noiseAmplitude > 0 then
                            local n1 = noise(wx / noiseScale1 + noiseSeed, wz / noiseScale1 + noiseSeed)
                            local n2 = noise(wx / noiseScale2 + noiseSeed + 100, wz / noiseScale2 + noiseSeed + 100)
                            local combined = n1 * noiseRatio + n2 * (1 - noiseRatio)
                            local heightRatio = max(0, (h - groundY) / crestHeight)
                            local scaledAmp = noiseAmplitude * (0.3 + 0.7 * heightRatio)
                            h = h + combined * scaledAmp
                        end

                        if h < groundY then h = groundY end
                        hRow[zi] = h
                        if h > maxH then maxH = h end
                    end

                    -- Time-based yielding (~33ms budget per frame)
                    if os.clock() - lastYield > 0.033 then
                        lastYield = os.clock()
                        task.wait()
                    end
                end

                ----------------------------------------------------------------
                -- Step 4: Point features (bounded second pass)
                ----------------------------------------------------------------

                for _, feat in ipairs(pointFeatures) do
                    local def = featureDefs[feat.class] or {}

                    if feat.class == "stratovolcano" or feat.class == "cinder_cone" then
                        local baseRadius
                        if feat.class == "stratovolcano" then
                            baseRadius = (feat.width or 500) / 2
                        else
                            baseRadius = def.baseRadius
                                and (def.baseRadius[1] + def.baseRadius[2]) / 2
                                or 75
                        end

                        local peakElev = feat.elevation

                        local xi1 = max(1, floor((feat.x - baseRadius - mapMinX) / VOXEL) + 1)
                        local xi2 = min(gridW, ceil((feat.x + baseRadius - mapMinX) / VOXEL))
                        local zi1 = max(1, floor((feat.z - baseRadius - mapMinZ) / VOXEL) + 1)
                        local zi2 = min(gridD, ceil((feat.z + baseRadius - mapMinZ) / VOXEL))

                        for xi = xi1, xi2 do
                            local wx = mapMinX + (xi - 0.5) * VOXEL
                            for zi = zi1, zi2 do
                                local wz = mapMinZ + (zi - 0.5) * VOXEL
                                local dx = wx - feat.x
                                local dz = wz - feat.z
                                local dist = sqrt(dx * dx + dz * dz)
                                if dist <= baseRadius then
                                    local featH = groundY + peakElev * smoothstep(1 - dist / baseRadius)
                                    if featH > hField[xi][zi] then
                                        hField[xi][zi] = featH
                                        if featH > maxH then maxH = featH end
                                    end
                                end
                            end
                        end

                    elseif feat.class == "cirque" then
                        local radius = (feat.width or 200) / 2
                        local depth  = def.depth
                            and (def.depth[1] + def.depth[2]) / 2
                            or 90

                        local xi1 = max(1, floor((feat.x - radius - mapMinX) / VOXEL) + 1)
                        local xi2 = min(gridW, ceil((feat.x + radius - mapMinX) / VOXEL))
                        local zi1 = max(1, floor((feat.z - radius - mapMinZ) / VOXEL) + 1)
                        local zi2 = min(gridD, ceil((feat.z + radius - mapMinZ) / VOXEL))

                        for xi = xi1, xi2 do
                            local wx = mapMinX + (xi - 0.5) * VOXEL
                            for zi = zi1, zi2 do
                                local wz = mapMinZ + (zi - 0.5) * VOXEL
                                local dx = wx - feat.x
                                local dz = wz - feat.z
                                local dist = sqrt(dx * dx + dz * dz)
                                if dist <= radius then
                                    local ratio = dist / radius
                                    local carve = depth * (1 - ratio * ratio)
                                    hField[xi][zi] = hField[xi][zi] - carve
                                    if hField[xi][zi] < groundY then
                                        hField[xi][zi] = groundY
                                    end
                                end
                            end
                        end

                    elseif feat.class == "pass" then
                        local width = feat.width or 200
                        local sigma = width / 3
                        local depth = def.depth
                            and (def.depth[1] + def.depth[2]) / 2
                            or 80
                        local extent = sigma * 3

                        local xi1 = max(1, floor((feat.x - extent - mapMinX) / VOXEL) + 1)
                        local xi2 = min(gridW, ceil((feat.x + extent - mapMinX) / VOXEL))
                        local zi1 = max(1, floor((feat.z - extent - mapMinZ) / VOXEL) + 1)
                        local zi2 = min(gridD, ceil((feat.z + extent - mapMinZ) / VOXEL))

                        local twoSigmaSq = 2 * sigma * sigma

                        for xi = xi1, xi2 do
                            local wx = mapMinX + (xi - 0.5) * VOXEL
                            for zi = zi1, zi2 do
                                local wz = mapMinZ + (zi - 0.5) * VOXEL
                                local dx = wx - feat.x
                                local dz = wz - feat.z
                                local distSq = dx * dx + dz * dz
                                local carve = depth * exp(-distSq / twoSigmaSq)
                                hField[xi][zi] = hField[xi][zi] - carve
                                if hField[xi][zi] < groundY then
                                    hField[xi][zi] = groundY
                                end
                            end
                        end
                    end
                end

                print(string.format(
                    "[TerrainPainterNode] Height field complete: min=%.0f max=%.0f (%.2fs)",
                    groundY, maxH, os.clock() - startTime
                ))

                ----------------------------------------------------------------
                -- Tiled voxel writing
                ----------------------------------------------------------------

                local tilesX = ceil(mapWidth / tileSize)
                local tilesZ = ceil(mapDepth / tileSize)
                local tileVoxels = tileSize / VOXEL

                print(string.format(
                    "[TerrainPainterNode] Writing %dx%d tiles (%d studs each)",
                    tilesX, tilesZ, tileSize
                ))

                local tileCount = 0

                for tx = 0, tilesX - 1 do
                    for tz = 0, tilesZ - 1 do
                        local tileMinX = mapMinX + tx * tileSize
                        local tileMinZ = mapMinZ + tz * tileSize
                        local tileMaxX = min(tileMinX + tileSize, mapMinX + mapWidth)
                        local tileMaxZ = min(tileMinZ + tileSize, mapMinZ + mapDepth)

                        -- Index range in global height field
                        local gxi1 = tx * tileVoxels + 1
                        local gxi2 = min(gxi1 + tileVoxels - 1, gridW)
                        local gzi1 = tz * tileVoxels + 1
                        local gzi2 = min(gzi1 + tileVoxels - 1, gridD)

                        local tileSX = gxi2 - gxi1 + 1
                        local tileSZ = gzi2 - gzi1 + 1

                        -- Build tile-local height and water arrays
                        local tileTerrain = table.create(tileSX)
                        local tileWater   = table.create(tileSX)

                        for lxi = 1, tileSX do
                            local tRow = table.create(tileSZ)
                            local wRow = table.create(tileSZ, false)
                            local gxi = gxi1 + lxi - 1
                            local gCol = hField[gxi]
                            for lzi = 1, tileSZ do
                                tRow[lzi] = gCol[gzi1 + lzi - 1]
                            end
                            tileTerrain[lxi] = tRow
                            tileWater[lxi]   = wRow
                        end

                        -- Create buffer and fill
                        local worldMin = Vector3.new(tileMinX, groundY - VOXEL, tileMinZ)
                        local worldMax = Vector3.new(tileMaxX, maxH + VOXEL, tileMaxZ)
                        local buf = VoxelBuffer.new(worldMin, worldMax)
                        buf:fillFromHeightField(
                            tileTerrain, tileWater,
                            material, Enum.Material.Water
                        )

                        -- Snow on gentle slopes: replace top voxel(s) with Snow
                        if useSnowOnSlopes then
                            local bufMnY = groundY - VOXEL
                            for lxi = 1, tileSX do
                                local gxi = gxi1 + lxi - 1
                                for lzi = 1, tileSZ do
                                    local gzi = gzi1 + lzi - 1
                                    local surfH = hField[gxi][gzi]
                                    if surfH <= groundY then continue end

                                    -- Finite-difference slope from global height field
                                    local hL = (gxi > 1) and hField[gxi-1][gzi] or surfH
                                    local hR = (gxi < gridW) and hField[gxi+1][gzi] or surfH
                                    local hD = (gzi > 1) and hField[gxi][gzi-1] or surfH
                                    local hU = (gzi < gridD) and hField[gxi][gzi+1] or surfH
                                    local dHdx = (hR - hL) / (2 * VOXEL)
                                    local dHdz = (hU - hD) / (2 * VOXEL)
                                    local slopeMag = sqrt(dHdx * dHdx + dHdz * dHdz)

                                    if slopeMag < slopeThreshold then
                                        -- Replace top 1-2 voxels with Snow
                                        local yiSurface = floor((surfH - bufMnY) / VOXEL) + 1
                                        buf:setVoxel(lxi, yiSurface, lzi, snowMaterial)
                                        if yiSurface > 1 then
                                            buf:setVoxel(lxi, yiSurface - 1, lzi, snowMaterial)
                                        end
                                    end
                                end
                            end
                        end

                        buf:flush()

                        tileCount = tileCount + 1
                        task.wait()
                    end
                end

                print(string.format(
                    "[TerrainPainterNode] Complete: %d tiles written (%.2fs total)",
                    tileCount, os.clock() - startTime
                ))

                -- Store height field for downstream nodes
                payload.heightField = hField
                payload.heightFieldGridW = gridW
                payload.heightFieldGridD = gridD
                payload.heightFieldMinX = mapMinX
                payload.heightFieldMinZ = mapMinZ

                -- Set spawn at map center, on terrain surface
                local spawnXi = max(1, floor(gridW / 2))
                local spawnZi = max(1, floor(gridD / 2))
                local spawnH = hField[spawnXi][spawnZi] + 5
                payload.spawn = { position = { 0, spawnH, 0 } }
                print(string.format(
                    "[TerrainPainterNode] Spawn set at (0, %.0f, 0)", spawnH
                ))

                selfRef.Out:Fire("nodeComplete", payload)
            end)
        end,
    },
}
