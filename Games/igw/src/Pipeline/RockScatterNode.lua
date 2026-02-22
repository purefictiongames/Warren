--[[
    IGW v2 Pipeline — RockScatterNode

    Two-pass rock scatter on terrain surfaces:
      Pass 1 (boulders): round ellipsoid blobs on gentle slopes
      Pass 2 (flagstone): thin oriented slabs on steep/vertical faces

    Slope detected from height field gradient. Rocks above slopeThreshold
    become flagstone — flat, angular, oriented along the cliff face like
    calving/exfoliation formations.

    Two-level clustering: place cluster centers, scatter individual rocks.
    Rocks are additive — only Air voxels are filled (existing terrain untouched).

    Reads payload.heightField (cached from TerrainPainterNode).
    Reads payload.biomeConfig.rocks for scatter parameters.

    Signal: onScatterRocks(payload) → fires nodeComplete
--]]

local VOXEL = 4
local floor = math.floor
local ceil  = math.ceil
local sqrt  = math.sqrt
local max   = math.max
local min   = math.min
local cos   = math.cos
local sin   = math.sin
local pi2   = math.pi * 2

return {
    name = "RockScatterNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onScatterRocks = function(self, payload)
            local selfRef = self
            task.spawn(function()
                local startTime = os.clock()

                ----------------------------------------------------------------
                -- Height field from payload
                ----------------------------------------------------------------

                local hField = payload.heightField
                local gridW  = payload.heightFieldGridW
                local gridD  = payload.heightFieldGridD
                local mapMinX = payload.heightFieldMinX
                local mapMinZ = payload.heightFieldMinZ

                if not hField then
                    warn("[RockScatterNode] No height field on payload, skipping")
                    selfRef.Out:Fire("nodeComplete", payload)
                    return
                end

                local mapWidth = gridW * VOXEL
                local mapDepth = gridD * VOXEL

                ----------------------------------------------------------------
                -- Rocks config from biomeConfig
                ----------------------------------------------------------------

                local rocksConfig = payload.biomeConfig and payload.biomeConfig.rocks or {}

                local density          = rocksConfig.density or 400
                local sizeRange        = rocksConfig.sizeRange or { 6, 20 }
                local amplitude        = rocksConfig.amplitude or { 0.5, 1.2 }
                local clusterTightness = rocksConfig.clusterTightness or 0.7
                local clusterSize      = rocksConfig.clusterSize or { 3, 10 }
                local materialName     = rocksConfig.material or "Rock"
                local minHeight        = rocksConfig.minHeight or 15
                local slopeThreshold   = rocksConfig.slopeThreshold or 0.7

                local flagCfg = rocksConfig.flagstone or {}
                local flagWidthRange  = flagCfg.widthRange or { 8, 20 }
                local flagHeightRange = flagCfg.heightRange or { 6, 16 }
                local flagThickness   = flagCfg.thickness or { 2, 5 }
                local flagMatName     = flagCfg.material or "Slate"

                local groundY      = selfRef:getAttribute("groundY") or 0
                local material     = Enum.Material[materialName] or Enum.Material.Rock
                local flagMaterial = Enum.Material[flagMatName] or Enum.Material.Slate

                local seed = (payload.seed or os.time()) + 31337
                local rng = Random.new(seed)

                ----------------------------------------------------------------
                -- Cluster geometry
                ----------------------------------------------------------------

                local avgClusterSize = (clusterSize[1] + clusterSize[2]) / 2
                local numClusters = max(1, floor(density / avgClusterSize))

                -- tightness 0 → radius 120, tightness 1 → radius 15
                local scatterRadius = 120 - clusterTightness * 105

                ----------------------------------------------------------------
                -- Height field helpers
                ----------------------------------------------------------------

                local function sampleHeight(wx, wz)
                    local xi = max(1, min(gridW, floor((wx - mapMinX) / VOXEL) + 1))
                    local zi = max(1, min(gridD, floor((wz - mapMinZ) / VOXEL) + 1))
                    return hField[xi][zi]
                end

                -- Gradient via central differences (2-voxel step)
                local step = VOXEL * 2
                local function sampleGradient(wx, wz)
                    local hL = sampleHeight(wx - step, wz)
                    local hR = sampleHeight(wx + step, wz)
                    local hD = sampleHeight(wx, wz - step)
                    local hU = sampleHeight(wx, wz + step)
                    local gx = (hR - hL) / (step * 2)
                    local gz = (hU - hD) / (step * 2)
                    return gx, gz, sqrt(gx * gx + gz * gz)
                end

                ----------------------------------------------------------------
                -- Generate clusters → split into boulders vs flagstone
                ----------------------------------------------------------------

                local boulders = {}
                local flagstones = {}

                for _ = 1, numClusters do
                    local cx = mapMinX + rng:NextNumber() * mapWidth
                    local cz = mapMinZ + rng:NextNumber() * mapDepth
                    local ch = sampleHeight(cx, cz)

                    if ch >= groundY + minHeight then
                        local n = rng:NextInteger(
                            clusterSize[1],
                            max(clusterSize[1], clusterSize[2])
                        )
                        for _ = 1, n do
                            local angle = rng:NextNumber() * pi2
                            local dist = rng:NextNumber() * scatterRadius
                            local rx = cx + cos(angle) * dist
                            local rz = cz + sin(angle) * dist
                            local rh = sampleHeight(rx, rz)

                            if rh >= groundY + minHeight then
                                local gx, gz, gradMag = sampleGradient(rx, rz)

                                if gradMag >= slopeThreshold then
                                    -- Flagstone: oriented flat slab
                                    local w = flagWidthRange[1]
                                        + rng:NextNumber() * (flagWidthRange[2] - flagWidthRange[1])
                                    local h = flagHeightRange[1]
                                        + rng:NextNumber() * (flagHeightRange[2] - flagHeightRange[1])
                                    local t = flagThickness[1]
                                        + rng:NextNumber() * (flagThickness[2] - flagThickness[1])

                                    -- Face normal = gradient direction (points uphill)
                                    -- We want slab flush against the cliff face
                                    local nx = gx / gradMag
                                    local nz = gz / gradMag

                                    table.insert(flagstones, {
                                        x = rx, z = rz,
                                        surfaceY = rh,
                                        halfWidth = w / 2,
                                        halfHeight = h / 2,
                                        halfThick = t / 2,
                                        nx = nx, nz = nz,     -- face normal (XZ)
                                        tx = -nz, tz = nx,    -- tangent (perpendicular in XZ)
                                    })
                                else
                                    -- Boulder: round ellipsoid
                                    local radius = sizeRange[1]
                                        + rng:NextNumber() * (sizeRange[2] - sizeRange[1])
                                    local amp = amplitude[1]
                                        + rng:NextNumber() * (amplitude[2] - amplitude[1])

                                    table.insert(boulders, {
                                        x = rx, z = rz,
                                        surfaceY = rh,
                                        radius = radius,
                                        amp = amp,
                                    })
                                end
                            end
                        end
                    end
                end

                print(string.format(
                    "[RockScatterNode] %d boulders + %d flagstones in %d clusters (slope>=%.2f) | mat=%s/%s (seed %d)",
                    #boulders, #flagstones, numClusters, slopeThreshold,
                    materialName, flagMatName, seed
                ))

                ----------------------------------------------------------------
                -- Pass 1: Stamp boulders as ellipsoid voxel blobs
                ----------------------------------------------------------------

                local terrain = workspace.Terrain
                local stamped = 0
                local lastYield = os.clock()

                for ri = 1, #boulders do
                    local rock = boulders[ri]
                    local bRad = rock.radius
                    local ry = bRad * rock.amp
                    local cx = rock.x
                    local cz = rock.z
                    local cy = rock.surfaceY + ry * 0.3

                    local bminX = floor((cx - bRad) / VOXEL) * VOXEL
                    local bminY = floor((cy - ry) / VOXEL) * VOXEL
                    local bminZ = floor((cz - bRad) / VOXEL) * VOXEL
                    local bmaxX = ceil((cx + bRad) / VOXEL) * VOXEL
                    local bmaxY = ceil((cy + ry) / VOXEL) * VOXEL
                    local bmaxZ = ceil((cz + bRad) / VOXEL) * VOXEL

                    if bmaxX <= bminX then bmaxX = bminX + VOXEL end
                    if bmaxY <= bminY then bmaxY = bminY + VOXEL end
                    if bmaxZ <= bminZ then bmaxZ = bminZ + VOXEL end

                    local region = Region3.new(
                        Vector3.new(bminX, bminY, bminZ),
                        Vector3.new(bmaxX, bmaxY, bmaxZ)
                    )

                    local materials, occupancy = terrain:ReadVoxels(region, VOXEL)
                    local sizeX = #materials
                    if sizeX == 0 then continue end
                    local sizeY = #materials[1]
                    if sizeY == 0 then continue end
                    local sizeZ = #materials[1][1]
                    if sizeZ == 0 then continue end

                    local changed = false
                    local rxSq = bRad * bRad
                    local rySq = ry * ry

                    for xi = 1, sizeX do
                        local vx = bminX + (xi - 0.5) * VOXEL
                        local dx = vx - cx
                        local dxSq = dx * dx
                        for yi = 1, sizeY do
                            local vy = bminY + (yi - 0.5) * VOXEL
                            local dy = vy - cy
                            local dySq = dy * dy
                            local matRow = materials[xi][yi]
                            local occRow = occupancy[xi][yi]
                            for zi = 1, sizeZ do
                                local vz = bminZ + (zi - 0.5) * VOXEL
                                local dz = vz - cz

                                local ellipDist = (dxSq + dz * dz) / rxSq + dySq / rySq

                                if ellipDist <= 1 and matRow[zi] == Enum.Material.Air then
                                    matRow[zi] = material
                                    occRow[zi] = max(occRow[zi], 1 - ellipDist * 0.3)
                                    changed = true
                                end
                            end
                        end
                    end

                    if changed then
                        terrain:WriteVoxels(region, VOXEL, materials, occupancy)
                        stamped = stamped + 1
                    end

                    if os.clock() - lastYield > 0.033 then
                        lastYield = os.clock()
                        task.wait()
                    end
                end

                ----------------------------------------------------------------
                -- Pass 2: Stamp flagstones as oriented flat slabs
                --
                -- Each flagstone is an oriented ellipsoid:
                --   normal axis  (N) = halfThick  → thin protrusion from cliff
                --   tangent axis (T) = halfWidth  → wide along cliff face
                --   vertical    (Y) = halfHeight → tall along cliff face
                --
                -- Voxel test in local frame:
                --   (localN/halfThick)² + (localT/halfWidth)² + (dy/halfHeight)² <= 1
                ----------------------------------------------------------------

                local flagStamped = 0

                for fi = 1, #flagstones do
                    local slab = flagstones[fi]
                    local hw = slab.halfWidth
                    local hh = slab.halfHeight
                    local ht = slab.halfThick
                    local cx = slab.x
                    local cz = slab.z
                    -- Center slab at surface, slight embed into face
                    local cy = slab.surfaceY + hh * 0.2
                    local nx = slab.nx
                    local nz = slab.nz
                    local tx = slab.tx
                    local tz = slab.tz

                    -- Bounding box: max possible extent in world space
                    local extentXZ = max(hw, ht) + 1
                    local bminX = floor((cx - extentXZ) / VOXEL) * VOXEL
                    local bminY = floor((cy - hh) / VOXEL) * VOXEL
                    local bminZ = floor((cz - extentXZ) / VOXEL) * VOXEL
                    local bmaxX = ceil((cx + extentXZ) / VOXEL) * VOXEL
                    local bmaxY = ceil((cy + hh) / VOXEL) * VOXEL
                    local bmaxZ = ceil((cz + extentXZ) / VOXEL) * VOXEL

                    if bmaxX <= bminX then bmaxX = bminX + VOXEL end
                    if bmaxY <= bminY then bmaxY = bminY + VOXEL end
                    if bmaxZ <= bminZ then bmaxZ = bminZ + VOXEL end

                    local region = Region3.new(
                        Vector3.new(bminX, bminY, bminZ),
                        Vector3.new(bmaxX, bmaxY, bmaxZ)
                    )

                    local materials, occupancy = terrain:ReadVoxels(region, VOXEL)
                    local sizeX = #materials
                    if sizeX == 0 then continue end
                    local sizeY = #materials[1]
                    if sizeY == 0 then continue end
                    local sizeZ = #materials[1][1]
                    if sizeZ == 0 then continue end

                    local changed = false
                    local hwSq = hw * hw
                    local hhSq = hh * hh
                    local htSq = ht * ht

                    for xi = 1, sizeX do
                        local vx = bminX + (xi - 0.5) * VOXEL
                        local dx = vx - cx
                        for yi = 1, sizeY do
                            local vy = bminY + (yi - 0.5) * VOXEL
                            local dy = vy - cy
                            local dySq = dy * dy
                            local matRow = materials[xi][yi]
                            local occRow = occupancy[xi][yi]
                            for zi = 1, sizeZ do
                                local vz = bminZ + (zi - 0.5) * VOXEL
                                local dz = vz - cz

                                -- Project onto local axes
                                local localN = dx * nx + dz * nz
                                local localT = dx * tx + dz * tz

                                -- Oriented ellipsoid test
                                local ellipDist = (localN * localN) / htSq
                                    + (localT * localT) / hwSq
                                    + dySq / hhSq

                                if ellipDist <= 1 and matRow[zi] == Enum.Material.Air then
                                    matRow[zi] = flagMaterial
                                    -- Sharp falloff for angular look
                                    occRow[zi] = max(occRow[zi], 1 - ellipDist * 0.15)
                                    changed = true
                                end
                            end
                        end
                    end

                    if changed then
                        terrain:WriteVoxels(region, VOXEL, materials, occupancy)
                        flagStamped = flagStamped + 1
                    end

                    if os.clock() - lastYield > 0.033 then
                        lastYield = os.clock()
                        task.wait()
                    end
                end

                print(string.format(
                    "[RockScatterNode] Complete: %d/%d boulders + %d/%d flagstones (%.2fs)",
                    stamped, #boulders, flagStamped, #flagstones,
                    os.clock() - startTime
                ))

                selfRef.Out:Fire("nodeComplete", payload)
            end)
        end,
    },
}
