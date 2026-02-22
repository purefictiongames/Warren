--[[
    IGW v2 Pipeline — CaveCutterNode

    Carves cave entrances into terrain voxels. Each cave is a dungeon
    transition point: mouth → connecting tube(s) → terminal chamber.

    Structure (always 3-4 CPs):
      CP 1 — Mouth: at cliff face (extends slightly outside for visible arch)
      CP 2 — Tube: narrower connecting passage (optional second tube)
      CP 3 — Chamber: wide terminal room (dungeon entrance point)

    Placement: gradient-based on steep cliff faces. Entry direction is
    perpendicular to slope (into the mountain).

    Cross-section: box-with-arch (flat floor + elliptical ceiling).

    Stores payload.caveEntrances[] with chamber positions + orientations
    for downstream dungeon layout nodes to connect to.

    Overwrites payload.spawn to place player near the first cave mouth.

    Signal: onCarveCaves(payload) → fires nodeComplete
--]]

local VOXEL = 4
local floor = math.floor
local ceil  = math.ceil
local sqrt  = math.sqrt
local max   = math.max
local min   = math.min
local huge  = math.huge

return {
    name = "CaveCutterNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onCarveCaves = function(self, payload)
            local selfRef = self
            task.spawn(function()
                local startTime = os.clock()

                ----------------------------------------------------------------
                -- Height field from payload
                ----------------------------------------------------------------

                local hField  = payload.heightField
                local gridW   = payload.heightFieldGridW
                local gridD   = payload.heightFieldGridD
                local mapMinX = payload.heightFieldMinX
                local mapMinZ = payload.heightFieldMinZ

                if not hField then
                    warn("[CaveCutterNode] No height field on payload, skipping")
                    selfRef.Out:Fire("nodeComplete", payload)
                    return
                end

                local mapWidth = gridW * VOXEL
                local mapDepth = gridD * VOXEL
                local groundY  = selfRef:getAttribute("groundY") or 0

                ----------------------------------------------------------------
                -- Cave config from biomeConfig
                ----------------------------------------------------------------

                local caveCfg = payload.biomeConfig and payload.biomeConfig.caves or {}

                local countRange       = caveCfg.count or { 8, 15 }
                local mouthWidthRange  = caveCfg.mouthWidth or { 20, 50 }
                local mouthHeightRange = caveCfg.mouthHeight or { 15, 35 }
                local depthRange       = caveCfg.depth or { 30, 80 }
                local tubeSegments     = caveCfg.tubeSegments or { 1, 2 }
                local jitterRange      = caveCfg.jitter or { 4, 10 }
                local chamberScale     = caveCfg.chamberScale or { 1.8, 2.8 }
                local slopeThreshold   = caveCfg.slopeThreshold or 0.5
                local minElevation     = caveCfg.minElevation or 25
                local minSpacing       = caveCfg.minSpacing or 80
                local minSpacingSq     = minSpacing * minSpacing

                local seed = (payload.seed or os.time()) + 77777
                local rng = Random.new(seed)

                ----------------------------------------------------------------
                -- Height field helpers
                ----------------------------------------------------------------

                local function sampleHeight(wx, wz)
                    local xi = max(1, min(gridW, floor((wx - mapMinX) / VOXEL) + 1))
                    local zi = max(1, min(gridD, floor((wz - mapMinZ) / VOXEL) + 1))
                    return hField[xi][zi]
                end

                local gradStep = VOXEL * 2
                local function sampleGradient(wx, wz)
                    local hL = sampleHeight(wx - gradStep, wz)
                    local hR = sampleHeight(wx + gradStep, wz)
                    local hD = sampleHeight(wx, wz - gradStep)
                    local hU = sampleHeight(wx, wz + gradStep)
                    local gx = (hR - hL) / (gradStep * 2)
                    local gz = (hU - hD) / (gradStep * 2)
                    return gx, gz, sqrt(gx * gx + gz * gz)
                end

                ----------------------------------------------------------------
                -- Find steep-face candidates
                ----------------------------------------------------------------

                local candidates = {}
                local numSamples = 600

                for _ = 1, numSamples do
                    local wx = mapMinX + rng:NextNumber() * mapWidth
                    local wz = mapMinZ + rng:NextNumber() * mapDepth
                    local h = sampleHeight(wx, wz)

                    if h >= groundY + minElevation then
                        local gx, gz, gm = sampleGradient(wx, wz)
                        if gm >= slopeThreshold then
                            table.insert(candidates, {
                                x = wx, z = wz, y = h,
                                gx = gx, gz = gz, gm = gm,
                            })
                        end
                    end
                end

                -- Shuffle candidates
                for i = #candidates, 2, -1 do
                    local j = rng:NextInteger(1, i)
                    candidates[i], candidates[j] = candidates[j], candidates[i]
                end

                -- Pick caves with minimum spacing
                local targetCount = rng:NextInteger(
                    countRange[1], max(countRange[1], countRange[2])
                )
                local selected = {}

                for ci = 1, #candidates do
                    if #selected >= targetCount then break end
                    local cand = candidates[ci]
                    local tooClose = false
                    for si = 1, #selected do
                        local prev = selected[si]
                        local dx = cand.x - prev.x
                        local dz = cand.z - prev.z
                        if dx * dx + dz * dz < minSpacingSq then
                            tooClose = true
                            break
                        end
                    end
                    if not tooClose then
                        table.insert(selected, cand)
                    end
                end

                ----------------------------------------------------------------
                -- Generate cave paths: mouth → tube(s) → chamber
                ----------------------------------------------------------------

                local caves = {}

                for ci = 1, #selected do
                    local cand = selected[ci]

                    -- Direction into mountain = opposite of gradient
                    local dirX = -cand.gx / cand.gm
                    local dirZ = -cand.gz / cand.gm
                    local perpX = -dirZ
                    local perpZ = dirX

                    local mouthW = mouthWidthRange[1]
                        + rng:NextNumber() * (mouthWidthRange[2] - mouthWidthRange[1])
                    local mouthH = mouthHeightRange[1]
                        + rng:NextNumber() * (mouthHeightRange[2] - mouthHeightRange[1])
                    local depth = depthRange[1]
                        + rng:NextNumber() * (depthRange[2] - depthRange[1])
                    local numTubes = rng:NextInteger(
                        tubeSegments[1], max(tubeSegments[1], tubeSegments[2])
                    )

                    -- Mouth inset: extend tube slightly past cliff face
                    local mouthInset = max(8, mouthW * 0.3)

                    -- Chamber scale
                    local chMult = chamberScale[1]
                        + rng:NextNumber() * (chamberScale[2] - chamberScale[1])

                    -- Build CPs: mouth + N tubes + chamber
                    local numCPs = 2 + numTubes  -- mouth, tubes, chamber
                    local cps = {}

                    for i = 1, numCPs do
                        local frac = (i - 1) / max(1, numCPs - 1)
                        local dist = -mouthInset + (depth + mouthInset) * frac

                        local halfW, halfH

                        if i == 1 then
                            -- Mouth: full size
                            halfW = mouthW / 2
                            halfH = mouthH / 2
                        elseif i == numCPs then
                            -- Chamber: widened terminal room
                            halfW = (mouthW / 2) * chMult
                            halfH = (mouthH / 2) * chMult
                        else
                            -- Tube: narrower connecting passage (60-80% of mouth)
                            local tubeTaper = 0.6 + rng:NextNumber() * 0.2
                            halfW = (mouthW / 2) * tubeTaper
                            halfH = (mouthH / 2) * tubeTaper
                        end

                        -- Lateral + vertical jitter (skip mouth CP)
                        local jitLat = 0
                        local jitVert = 0
                        if i > 1 and i < numCPs then
                            jitLat  = (rng:NextNumber() - 0.5) * 2 * jitterRange[2]
                            jitVert = (rng:NextNumber() - 0.5) * 2 * jitterRange[1]
                        end

                        cps[i] = {
                            x = cand.x + dirX * dist + perpX * jitLat,
                            z = cand.z + dirZ * dist + perpZ * jitLat,
                            y = cand.y + jitVert - frac * 3,
                            halfW = max(VOXEL, halfW),
                            halfH = max(VOXEL, halfH),
                        }
                    end

                    -- Chamber CP (last one) — store for dungeon entrance data
                    local chamberCP = cps[numCPs]

                    table.insert(caves, {
                        cps = cps,
                        mouthX = cand.x,
                        mouthZ = cand.z,
                        mouthY = cand.y,
                        dirX = dirX,
                        dirZ = dirZ,
                        chamber = chamberCP,
                    })
                end

                print(string.format(
                    "[CaveCutterNode] %d caves from %d candidates (slope>=%.2f, elev>=%d) (seed %d)",
                    #caves, #candidates, slopeThreshold, minElevation, seed
                ))

                ----------------------------------------------------------------
                -- Carve each cave into terrain voxels
                ----------------------------------------------------------------

                -- 2D segment projection: returns (t, dist)
                local function projectOntoSeg(px, pz, ax, az, bx, bz)
                    local dx = bx - ax
                    local dz = bz - az
                    local lenSq = dx * dx + dz * dz
                    if lenSq < 0.001 then
                        local ex, ez = px - ax, pz - az
                        return 0, sqrt(ex * ex + ez * ez)
                    end
                    local t = ((px - ax) * dx + (pz - az) * dz) / lenSq
                    if t < 0 then t = 0 elseif t > 1 then t = 1 end
                    local cx = ax + t * dx
                    local cz = az + t * dz
                    local ex, ez = px - cx, pz - cz
                    return t, sqrt(ex * ex + ez * ez)
                end

                local terrain = workspace.Terrain
                local carved = 0
                local lastYield = os.clock()

                for ci = 1, #caves do
                    local cave = caves[ci]
                    local cps = cave.cps
                    local numSegs = #cps - 1
                    if numSegs < 1 then continue end

                    -- Compute 3D bounding box
                    local bbMinX, bbMinY, bbMinZ =  huge,  huge,  huge
                    local bbMaxX, bbMaxY, bbMaxZ = -huge, -huge, -huge

                    for i = 1, #cps do
                        local cp = cps[i]
                        local ext = max(cp.halfW, cp.halfH) + VOXEL * 2
                        bbMinX = min(bbMinX, cp.x - ext)
                        bbMaxX = max(bbMaxX, cp.x + ext)
                        bbMinY = min(bbMinY, cp.y - VOXEL * 2)
                        bbMaxY = max(bbMaxY, cp.y + cp.halfH * 2 + VOXEL * 2)
                        bbMinZ = min(bbMinZ, cp.z - ext)
                        bbMaxZ = max(bbMaxZ, cp.z + ext)
                    end

                    -- Align to voxel grid
                    bbMinX = floor(bbMinX / VOXEL) * VOXEL
                    bbMinY = floor(bbMinY / VOXEL) * VOXEL
                    bbMinZ = floor(bbMinZ / VOXEL) * VOXEL
                    bbMaxX = ceil(bbMaxX / VOXEL) * VOXEL
                    bbMaxY = ceil(bbMaxY / VOXEL) * VOXEL
                    bbMaxZ = ceil(bbMaxZ / VOXEL) * VOXEL

                    -- Safety: skip absurdly large caves
                    if bbMaxX - bbMinX > 600 then continue end
                    if bbMaxY - bbMinY > 300 then continue end
                    if bbMaxZ - bbMinZ > 600 then continue end

                    local region = Region3.new(
                        Vector3.new(bbMinX, bbMinY, bbMinZ),
                        Vector3.new(bbMaxX, bbMaxY, bbMaxZ)
                    )

                    local materials, occupancy = terrain:ReadVoxels(region, VOXEL)
                    local sizeX = #materials
                    if sizeX == 0 then continue end
                    local sizeY = #materials[1]
                    if sizeY == 0 then continue end
                    local sizeZ = #materials[1][1]
                    if sizeZ == 0 then continue end

                    local changed = false

                    for xi = 1, sizeX do
                        local vx = bbMinX + (xi - 0.5) * VOXEL
                        for yi = 1, sizeY do
                            local vy = bbMinY + (yi - 0.5) * VOXEL
                            local matSlice = materials[xi][yi]
                            local occSlice = occupancy[xi][yi]
                            for zi = 1, sizeZ do
                                if matSlice[zi] ~= Enum.Material.Air then
                                    local vz = bbMinZ + (zi - 0.5) * VOXEL

                                    -- Find nearest path segment
                                    local bestDist = huge
                                    local bestFloorY = 0
                                    local bestHalfW = 0
                                    local bestHalfH = 0

                                    for si = 1, numSegs do
                                        local a = cps[si]
                                        local b = cps[si + 1]
                                        local t, dh = projectOntoSeg(
                                            vx, vz, a.x, a.z, b.x, b.z
                                        )
                                        if dh < bestDist then
                                            bestDist   = dh
                                            bestFloorY = a.y + (b.y - a.y) * t
                                            bestHalfW  = a.halfW + (b.halfW - a.halfW) * t
                                            bestHalfH  = a.halfH + (b.halfH - a.halfH) * t
                                        end
                                    end

                                    -- Box-with-arch cross-section test
                                    -- Lower half: rectangular (flat floor, full width)
                                    -- Upper half: elliptical arch
                                    local dy = vy - bestFloorY

                                    if dy >= 0 and bestDist <= bestHalfW then
                                        local carve = false

                                        if dy <= bestHalfH then
                                            -- Rectangular lower zone
                                            carve = true
                                        elseif dy <= bestHalfH * 2 then
                                            -- Elliptical arch upper zone
                                            local archDy = dy - bestHalfH
                                            local nH = bestDist / bestHalfW
                                            local nV = archDy / bestHalfH
                                            if nH * nH + nV * nV <= 1 then
                                                carve = true
                                            end
                                        end

                                        if carve then
                                            matSlice[zi] = Enum.Material.Air
                                            occSlice[zi] = 0
                                            changed = true
                                        end
                                    end
                                end
                            end
                        end
                    end

                    if changed then
                        terrain:WriteVoxels(region, VOXEL, materials, occupancy)
                        carved = carved + 1
                    end

                    if os.clock() - lastYield > 0.033 then
                        lastYield = os.clock()
                        task.wait()
                    end
                end

                ----------------------------------------------------------------
                -- Store cave entrances for dungeon layout wiring
                ----------------------------------------------------------------

                local entrances = {}
                for ci = 1, #caves do
                    local cave = caves[ci]
                    local ch = cave.chamber
                    table.insert(entrances, {
                        x = ch.x,
                        y = ch.y,
                        z = ch.z,
                        halfW = ch.halfW,
                        halfH = ch.halfH,
                        dirX = cave.dirX,
                        dirZ = cave.dirZ,
                        mouthX = cave.mouthX,
                        mouthZ = cave.mouthZ,
                        mouthY = cave.mouthY,
                    })
                end
                payload.caveEntrances = entrances

                ----------------------------------------------------------------
                -- Set spawn near first cave mouth
                ----------------------------------------------------------------

                if #caves > 0 then
                    local first = caves[1]
                    -- 15 studs downhill from mouth (in front of the opening)
                    local spawnX = first.mouthX - first.dirX * 15
                    local spawnZ = first.mouthZ - first.dirZ * 15
                    local spawnY = sampleHeight(spawnX, spawnZ) + 5
                    payload.spawn = { position = { spawnX, spawnY, spawnZ } }
                    print(string.format(
                        "[CaveCutterNode] Spawn → (%.0f, %.0f, %.0f) near cave 1",
                        spawnX, spawnY, spawnZ
                    ))
                end

                print(string.format(
                    "[CaveCutterNode] Complete: %d/%d caves carved, %d entrances stored (%.2fs)",
                    carved, #caves, #entrances, os.clock() - startTime
                ))

                selfRef.Out:Fire("nodeComplete", payload)
            end)
        end,
    },
}
