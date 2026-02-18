--[[
    IGW v2 Pipeline — TopologyManager

    Generates terrain topology as polygon contour layers (no DOM Parts).
    Features (rolling hills, hills, mountains, peaks) are seeded across
    the map on a jittered grid. Each profile has its own layer height
    and shrink rate — rolling hills use thick layers with aggressive
    shrink (gentle domes), peaks use thin layers with slow shrink
    (steep spires). Spine proximity biases toward taller feature types.

    Each feature is a stack of shrinking polygon layers. The polygon
    vertices have Perlin noise deformation for organic, non-rectangular
    shapes. Marching cubes bridges between shrinking layers naturally —
    same gap-bridging effect proven with FILL=1/GAP=7.

    Output (payload):
        .groundFill   — { position, size } for the ground plane
        .features     — array of feature objects, each with:
            cx, cz, boundMinX/MaxX/MinZ/MaxZ, peakY,
            layers = [{ y, height, vertices = {{x,z},...} }, ...]
        .spawn        — { position } at tallest peak
--]]

--------------------------------------------------------------------------------
-- FEATURE PROFILES
-- Each profile produces a different terrain shape from the same growth
-- algorithm. The shrink rate IS the slope angle.
--   Fast shrink (0.60) → wide overhang per step → gentle slope (~5deg)
--   Slow shrink (0.99) → narrow overhang → steep slope (~45deg+)
--------------------------------------------------------------------------------

local PROFILES = {
    rolling = {
        baseMin = 3200, baseMax = 10000,
        layerH  = 20,
        shrinkMin = 0.60, shrinkMax = 0.72,
        maxLayers = 8,
        numVerts = 8,
        noiseAmp = 0.30,
    },
    hill = {
        baseMin = 1600, baseMax = 4800,
        layerH  = 12,
        shrinkMin = 0.70, shrinkMax = 0.82,
        maxLayers = 30,
        numVerts = 8,
        noiseAmp = 0.25,
    },
    mountain = {
        baseMin = 1000, baseMax = 2800,
        layerH  = 6,
        shrinkMin = 0.88, shrinkMax = 0.95,
        maxLayers = 60,
        numVerts = 8,
        noiseAmp = 0.20,
    },
    peak = {
        baseMin = 480,  baseMax = 1600,
        layerH  = 4,
        shrinkMin = 0.95, shrinkMax = 0.99,
        maxLayers = 120,
        numVerts = 8,
        noiseAmp = 0.15,
    },
}

local PROFILE_ORDER = { "rolling", "hill", "mountain", "peak" }

--------------------------------------------------------------------------------
-- POLYGON HELPERS
--------------------------------------------------------------------------------

--- Generate an N-gon centered at (cx, cz) with Perlin noise deformation.
--- width/depth define the bounding ellipse radii.
local function makeBasePolygon(cx, cz, width, depth, numVerts, noiseAmp, noiseSeed)
    local verts = {}
    local TAU = math.pi * 2
    for i = 1, numVerts do
        local angle = (i - 1) / numVerts * TAU
        local baseX = math.cos(angle) * width / 2
        local baseZ = math.sin(angle) * depth / 2
        -- Perlin deformation: +-noiseAmp fraction of radius
        local n = math.noise(
            baseX * 0.01 + noiseSeed,
            baseZ * 0.01 + noiseSeed * 1.7,
            noiseSeed * 0.3
        )
        local scale = 1 + n * noiseAmp
        verts[i] = { cx + baseX * scale, cz + baseZ * scale }
    end
    return verts
end

--- Scale polygon vertices toward center, add per-vertex jitter.
local function shrinkPolygon(vertices, cx, cz, shrinkFactor, jitterAmount)
    local out = {}
    for i = 1, #vertices do
        local vx, vz = vertices[i][1], vertices[i][2]
        -- Shrink toward center
        local nx = cx + (vx - cx) * shrinkFactor
        local nz = cz + (vz - cz) * shrinkFactor
        -- Jitter
        nx = nx + (math.random() * 2 - 1) * jitterAmount
        nz = nz + (math.random() * 2 - 1) * jitterAmount
        out[i] = { nx, nz }
    end
    return out
end

--- Compute AABB from polygon vertices.
local function polygonAABB(vertices)
    local mnX, mxX = vertices[1][1], vertices[1][1]
    local mnZ, mxZ = vertices[1][2], vertices[1][2]
    for i = 2, #vertices do
        local vx, vz = vertices[i][1], vertices[i][2]
        if vx < mnX then mnX = vx end
        if vx > mxX then mxX = vx end
        if vz < mnZ then mnZ = vz end
        if vz > mxZ then mxZ = vz end
    end
    return mnX, mxX, mnZ, mxZ
end

--------------------------------------------------------------------------------
-- NODE
--------------------------------------------------------------------------------

return {
    name = "TopologyManager",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildTopology = function(self, payload)
            local t0 = os.clock()

            ----------------------------------------------------------------
            -- Config
            ----------------------------------------------------------------

            local mapWidth        = self:getAttribute("mapWidth") or 4000
            local mapDepth        = self:getAttribute("mapDepth") or 4000
            local groundHeight    = self:getAttribute("groundHeight") or 4
            local groundY         = self:getAttribute("groundY") or 0
            local origin          = self:getAttribute("origin") or { 0, 0, 0 }

            local featureSpacing  = self:getAttribute("featureSpacing") or 667
            local jitterRange     = self:getAttribute("jitterRange") or 0.3
            local minRegionSize   = self:getAttribute("minRegionSize") or 20
            local attritionChance = self:getAttribute("attritionChance") or 3

            local spineAngle      = self:getAttribute("spineAngle") or 15
            local spineWidth      = self:getAttribute("spineWidth") or 0.2

            local rollingWeight   = self:getAttribute("rollingWeight") or 0.35
            local hillWeight      = self:getAttribute("hillWeight") or 0.60
            local mountainWeight  = self:getAttribute("mountainWeight") or 0.33
            local peakWeight      = self:getAttribute("peakWeight") or 0.10

            local perimeterRadius = self:getAttribute("perimeterRadius") or 800
            local perimeterCount  = self:getAttribute("perimeterCount") or 12

            local seed = payload.seed or os.time()
            math.randomseed(seed)

            -- Spine direction vectors
            local spineRad = math.rad(spineAngle)
            local perpDirX  = -math.sin(spineRad)
            local perpDirZ  =  math.cos(spineRad)
            local spineW2   = 2 * spineWidth * spineWidth

            ----------------------------------------------------------------
            -- Accumulators
            ----------------------------------------------------------------

            local allFeatures = {}
            local peakElevation = 0
            local peakFeature = nil
            local profileCounts = {}
            for _, name in ipairs(PROFILE_ORDER) do
                profileCounts[name] = 0
            end

            -- Base weight table (before spine bias)
            local baseWeights = {
                rolling  = rollingWeight,
                hill     = hillWeight,
                mountain = mountainWeight,
                peak     = peakWeight,
            }

            local noiseSeedCounter = seed * 0.001

            ----------------------------------------------------------------
            -- Helper: grow a single feature as polygon layers
            ----------------------------------------------------------------

            local function growFeature(fx, fz, profile, baseW, baseD)
                local baseY = groundY + groundHeight
                local numVerts = profile.numVerts or 8
                local noiseAmp = profile.noiseAmp or 0.25

                -- Generate base polygon with Perlin deformation
                noiseSeedCounter = noiseSeedCounter + 1.37
                local currentVerts = makeBasePolygon(
                    fx, fz, baseW, baseD,
                    numVerts, noiseAmp, noiseSeedCounter
                )

                -- Compute AABB from base layer (largest)
                local bMinX, bMaxX, bMinZ, bMaxZ = polygonAABB(currentVerts)

                local feature = {
                    cx = fx,
                    cz = fz,
                    boundMinX = bMinX,
                    boundMaxX = bMaxX,
                    boundMinZ = bMinZ,
                    boundMaxZ = bMaxZ,
                    peakY = baseY,
                    layers = {},
                }

                local currentCX, currentCZ = fx, fz

                for layer = 0, profile.maxLayers - 1 do
                    local layerY = baseY + layer * profile.layerH

                    -- Store layer
                    table.insert(feature.layers, {
                        y = layerY,
                        height = profile.layerH,
                        vertices = currentVerts,
                    })

                    feature.peakY = layerY + profile.layerH

                    -- Check minimum extent via AABB
                    local lMinX, lMaxX, lMinZ, lMaxZ = polygonAABB(currentVerts)
                    local extentX = lMaxX - lMinX
                    local extentZ = lMaxZ - lMinZ

                    if extentX < minRegionSize or extentZ < minRegionSize then
                        break
                    end

                    -- Attrition (random plateau)
                    if math.random() * 100 < attritionChance then
                        break
                    end

                    -- Shrink for next layer
                    local shrink = profile.shrinkMin
                        + math.random()
                        * (profile.shrinkMax - profile.shrinkMin)

                    -- Center drift
                    local maxDrift = (1 - shrink) * math.max(extentX, extentZ) * 0.2
                    currentCX = currentCX + (math.random() * 2 - 1) * maxDrift
                    currentCZ = currentCZ + (math.random() * 2 - 1) * maxDrift

                    local jitter = (1 - shrink) * math.max(extentX, extentZ) * 0.05
                    currentVerts = shrinkPolygon(
                        currentVerts, currentCX, currentCZ,
                        shrink, jitter
                    )
                end

                -- Track peak
                if feature.peakY > peakElevation then
                    peakElevation = feature.peakY
                    peakFeature = feature
                end

                table.insert(allFeatures, feature)
            end

            ----------------------------------------------------------------
            -- 1. Ground plane
            ----------------------------------------------------------------

            payload.groundFill = {
                position = {
                    origin[1],
                    groundY + groundHeight / 2,
                    origin[3],
                },
                size = { mapWidth, groundHeight, mapDepth },
            }

            ----------------------------------------------------------------
            -- 2. Seed features on jittered grid
            ----------------------------------------------------------------

            local cols = math.max(1, math.floor(mapWidth / featureSpacing))
            local rows = math.max(1, math.floor(mapDepth / featureSpacing))

            for gr = 1, rows do
                for gc = 1, cols do
                    -- Grid cell center + jitter
                    local fx = origin[1] - mapWidth / 2
                        + (gc - 0.5) / cols * mapWidth
                    local fz = origin[3] - mapDepth / 2
                        + (gr - 0.5) / rows * mapDepth
                    fx = fx + (math.random() * 2 - 1)
                        * featureSpacing * 0.3
                    fz = fz + (math.random() * 2 - 1)
                        * featureSpacing * 0.3

                    -- Spine proximity (0 = edge, 1 = on spine)
                    local normX = (fx - origin[1]) / (mapWidth / 2)
                    local normZ = (fz - origin[3]) / (mapDepth / 2)
                    local perpDist = math.abs(
                        normX * perpDirX + normZ * perpDirZ
                    )
                    local spineProx = math.exp(
                        -perpDist * perpDist / spineW2
                    )

                    -- Bias weights toward taller types near spine
                    local weights = {
                        rolling  = baseWeights.rolling
                            * (1 - spineProx * 0.8),
                        hill     = baseWeights.hill
                            * (1 - spineProx * 0.3),
                        mountain = baseWeights.mountain
                            * (1 + spineProx * 2),
                        peak     = baseWeights.peak
                            * (1 + spineProx * 4),
                    }
                    local totalW = 0
                    for _, name in ipairs(PROFILE_ORDER) do
                        totalW = totalW + weights[name]
                    end

                    -- Weighted random selection
                    local r = math.random() * totalW
                    local selectedType = PROFILE_ORDER[1]
                    local acc = 0
                    for _, name in ipairs(PROFILE_ORDER) do
                        acc = acc + weights[name]
                        if r <= acc then
                            selectedType = name
                            break
                        end
                    end

                    local profile = PROFILES[selectedType]
                    profileCounts[selectedType] =
                        profileCounts[selectedType] + 1

                    -- Base size (bigger near spine)
                    local sizeFactor = 0.5 + spineProx * 0.5
                    local baseW = profile.baseMin
                        + math.random()
                        * (profile.baseMax - profile.baseMin)
                        * sizeFactor
                    local baseD = baseW * (0.5 + math.random() * 0.5)

                    growFeature(fx, fz, profile, baseW, baseD)
                end
            end

            ----------------------------------------------------------------
            -- 3. Perimeter features (visual interest at horizon)
            ----------------------------------------------------------------

            local perimSeeded = 0
            if perimeterCount > 0 and perimeterRadius > 0 then
                local PERIM_WEIGHTS = { 0.40, 0.50, 0.10, 0.00 }

                for i = 1, perimeterCount do
                    -- Evenly spaced angles with jitter
                    local angle = (i - 1) / perimeterCount
                        * math.pi * 2
                        + (math.random() - 0.5) * 0.4
                    -- Radial jitter so they're not on a perfect circle
                    local dist = perimeterRadius
                        * (0.85 + math.random() * 0.30)

                    local fx = origin[1]
                        + math.cos(angle) * dist
                    local fz = origin[3]
                        + math.sin(angle) * dist

                    -- Weighted random (biased toward rolling/hill)
                    local r = math.random()
                    local acc = 0
                    local selectedType = "rolling"
                    for idx, name in ipairs(PROFILE_ORDER) do
                        acc = acc + PERIM_WEIGHTS[idx]
                        if r <= acc then
                            selectedType = name
                            break
                        end
                    end

                    local profile = PROFILES[selectedType]
                    profileCounts[selectedType] =
                        profileCounts[selectedType] + 1

                    -- Slightly smaller than grid features
                    local baseW = profile.baseMin
                        + math.random()
                        * (profile.baseMax - profile.baseMin)
                        * 0.7
                    local baseD = baseW
                        * (0.5 + math.random() * 0.5)

                    growFeature(fx, fz, profile, baseW, baseD)
                    perimSeeded = perimSeeded + 1
                end
            end

            ----------------------------------------------------------------
            -- 4. Payload
            ----------------------------------------------------------------

            payload.features = allFeatures

            -- Spawn at tallest peak
            if peakFeature then
                payload.spawn = {
                    position = {
                        peakFeature.cx,
                        peakElevation + 15,
                        peakFeature.cz,
                    },
                }
            end

            ----------------------------------------------------------------
            -- Stats
            ----------------------------------------------------------------

            local totalLayers = 0
            for _, f in ipairs(allFeatures) do
                totalLayers = totalLayers + #f.layers
            end

            local parts = {}
            for _, name in ipairs(PROFILE_ORDER) do
                table.insert(parts,
                    name .. "=" .. profileCounts[name])
            end

            print(string.format(
                "[TopologyManager] %d features (%s) + %d perimeter,"
                    .. " %d total layers, peak %d studs"
                    .. " — seed %d — %.2fs",
                #allFeatures, table.concat(parts, " "),
                perimSeeded,
                totalLayers,
                math.floor(peakElevation),
                seed, os.clock() - t0
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
