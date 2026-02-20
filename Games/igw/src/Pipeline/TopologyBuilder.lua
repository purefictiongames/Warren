--[[
    IGW v2 Pipeline — TopologyBuilder

    Generates terrain topology as polygon contour layers. Reads featureSeeds
    and terrainProfiles from payload, dispatches to growFeature (convex) or
    growConcaveFeature (concave) based on profile geometry type.

    Replaces TopologyManager with separated concerns:
    - TerrainBlockoutManager decides inventory + positions
    - FeaturePlacer computes AABB bounds
    - TopologyBuilder generates polygon layers (this node)

    Convex profiles: rolling, hill, mountain, peak, plateau
    Concave profiles: lake (inverted hill → bowl)

    Region expansion runs all three phases internally (no IPC round-trips).

    Output (payload):
        .features  — array of feature objects with layers[]
        .spawn     — { position } at tallest convex peak
--]]

--------------------------------------------------------------------------------
-- POLYGON HELPERS
--------------------------------------------------------------------------------

local function makeBasePolygon(cx, cz, width, depth, numVerts, noiseAmp, noiseSeed)
    local verts = {}
    local TAU = math.pi * 2
    for i = 1, numVerts do
        local angle = (i - 1) / numVerts * TAU
        local baseX = math.cos(angle) * width / 2
        local baseZ = math.sin(angle) * depth / 2
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

local function shrinkPolygon(vertices, cx, cz, shrinkFactor, jitterAmount)
    local out = {}
    for i = 1, #vertices do
        local vx, vz = vertices[i][1], vertices[i][2]
        local nx = cx + (vx - cx) * shrinkFactor
        local nz = cz + (vz - cz) * shrinkFactor
        nx = nx + (math.random() * 2 - 1) * jitterAmount
        nz = nz + (math.random() * 2 - 1) * jitterAmount
        out[i] = { nx, nz }
    end
    return out
end

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
    name = "TopologyBuilder",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._regions = {}
            self._config = nil
            self._baseSeed = nil
            self._profiles = nil
            -- TerrainBlockoutManager config (cached for region expansion)
            self._blockoutConfig = nil
        end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    ------------------------------------------------------------------------
    -- Grow a convex feature (rolling/hill/mountain/peak/plateau)
    ------------------------------------------------------------------------

    _growFeature = function(self, fx, fz, profile, baseW, baseD, noiseSeed, groundY)
        local cfg = self._config
        local numVerts = profile.numVerts or 8
        local noiseAmp = profile.noiseAmp or 0.25

        local currentVerts = makeBasePolygon(
            fx, fz, baseW, baseD,
            numVerts, noiseAmp, noiseSeed
        )

        local bMinX, bMaxX, bMinZ, bMaxZ = polygonAABB(currentVerts)

        local feature = {
            cx = fx,
            cz = fz,
            boundMinX = bMinX,
            boundMaxX = bMaxX,
            boundMinZ = bMinZ,
            boundMaxZ = bMaxZ,
            peakY = groundY,
            layers = {},
            profileType = nil,  -- set by caller
            geometry = "convex",
        }

        local currentCX, currentCZ = fx, fz

        for layer = 0, profile.maxLayers - 1 do
            local layerY = groundY + layer * profile.layerH

            table.insert(feature.layers, {
                y = layerY,
                height = profile.layerH,
                vertices = currentVerts,
            })

            feature.peakY = layerY + profile.layerH

            local lMinX, lMaxX, lMinZ, lMaxZ = polygonAABB(currentVerts)
            local extentX = lMaxX - lMinX
            local extentZ = lMaxZ - lMinZ

            if extentX < cfg.minRegionSize or extentZ < cfg.minRegionSize then
                break
            end

            if math.random() * 100 < cfg.attritionChance then
                break
            end

            -- Shrink for next layer
            local shrink = profile.shrinkMin
                + math.random()
                * (profile.shrinkMax - profile.shrinkMin)

            -- Plateau: flat top (no shrink for last N layers)
            if profile.flatTop then
                local remaining = profile.maxLayers - 1 - layer
                if remaining <= (profile.flatTopLayers or 3) then
                    shrink = 1.0
                end
            end

            local maxDrift = (1 - shrink) * math.max(extentX, extentZ) * 0.2
            currentCX = currentCX + (math.random() * 2 - 1) * maxDrift
            currentCZ = currentCZ + (math.random() * 2 - 1) * maxDrift

            local jitter = (1 - shrink) * math.max(extentX, extentZ) * 0.05
            currentVerts = shrinkPolygon(
                currentVerts, currentCX, currentCZ,
                shrink, jitter
            )
        end

        return feature
    end,

    ------------------------------------------------------------------------
    -- Generate features for a region (used by both initial build + expansion)
    ------------------------------------------------------------------------

    _generateRegion = function(self, rx, rz, featureSeeds, groundY)
        local key = rx .. "," .. rz
        if self._regions[key] then
            return self._regions[key]
        end

        local t0 = os.clock()
        local profiles = self._profiles
        local allFeatures = {}
        local peakElevation = 0
        local peakFeature = nil

        local profileCounts = {}

        for _, seed in ipairs(featureSeeds) do
            local profileName = seed.profileName
            local profile = profiles[profileName]
            if not profile then continue end

            profileCounts[profileName] = (profileCounts[profileName] or 0) + 1

            -- All features use the same convex growth algorithm.
            -- Concave features (lakes) get the same organic hill shape
            -- which the painter inverts into a bowl.
            local feature = self:_growFeature(
                seed.cx, seed.cz, profile,
                seed.baseWidth, seed.baseDepth,
                seed.noiseSeed, groundY
            )

            feature.profileType = profileName
            feature.geometry = profile.geometry
            if profile.depth then
                feature.depth = profile.depth
            end
            if profile.fillRatio then
                feature.fillRatio = profile.fillRatio
            end

            -- Refine AABB from actual polygon vertices
            if #feature.layers > 0 then
                local baseVerts = feature.layers[1].vertices
                local bMinX, bMaxX, bMinZ, bMaxZ = polygonAABB(baseVerts)
                feature.boundMinX = bMinX
                feature.boundMaxX = bMaxX
                feature.boundMinZ = bMinZ
                feature.boundMaxZ = bMaxZ
            end

            -- Track peak (convex only)
            if feature.geometry ~= "concave" and feature.peakY > peakElevation then
                peakElevation = feature.peakY
                peakFeature = feature
            end

            table.insert(allFeatures, feature)
        end

        -- Stats
        local totalLayers = 0
        for _, f in ipairs(allFeatures) do
            totalLayers = totalLayers + #f.layers
        end

        local parts = {}
        for name, count in pairs(profileCounts) do
            table.insert(parts, name .. "=" .. count)
        end

        print(string.format(
            "[TopologyBuilder] Region (%d,%d): %d features (%s),"
                .. " %d layers, peak %d studs — %.2fs",
            rx, rz,
            #allFeatures, table.concat(parts, " "),
            totalLayers,
            math.floor(peakElevation),
            os.clock() - t0
        ))

        local result = {
            features = allFeatures,
            peakElevation = peakElevation,
            peakFeature = peakFeature,
        }

        self._regions[key] = result
        return result
    end,

    ------------------------------------------------------------------------
    -- Region expansion: blockout + place + build internally (no IPC)
    ------------------------------------------------------------------------

    _expandRegion = function(self, rx, rz)
        local key = rx .. "," .. rz
        if self._regions[key] then
            return self._regions[key]
        end

        local cfg = self._blockoutConfig
        if not cfg then
            warn("[TopologyBuilder] No blockout config for expansion")
            return { features = {}, peakElevation = 0 }
        end

        local profiles = self._profiles

        -- Deterministic seed per region
        local regionSeed = self._baseSeed + rx * 73856093 + rz * 19349663
        math.randomseed(regionSeed)

        -- Region origin in world space
        local originX = cfg.origin[1] + rx * cfg.mapWidth
        local originZ = cfg.origin[3] + rz * cfg.mapDepth

        -- Spine
        local spineRad = math.rad(cfg.spineAngle)
        local perpDirX = -math.sin(spineRad)
        local perpDirZ = math.cos(spineRad)
        local spineW2 = 2 * cfg.spineWidth * cfg.spineWidth

        local noiseSeedCounter = regionSeed * 0.001
        local featureSeeds = {}
        local idx = 0

        local PROFILE_ORDER = { "rolling", "hill", "mountain", "peak", "plateau", "lake" }

        local baseWeights = {
            rolling  = cfg.rollingWeight or 0.25,
            hill     = cfg.hillWeight or 0.45,
            mountain = cfg.mountainWeight or 0.25,
            peak     = cfg.peakWeight or 0.08,
            plateau  = cfg.plateauWeight or 0.05,
            lake     = cfg.lakeWeight or 0.04,
        }

        local cols = math.max(1, math.floor(cfg.mapWidth / cfg.featureSpacing))
        local rows = math.max(1, math.floor(cfg.mapDepth / cfg.featureSpacing))

        for gr = 1, rows do
            for gc = 1, cols do
                local fx = originX - cfg.mapWidth / 2
                    + (gc - 0.5) / cols * cfg.mapWidth
                local fz = originZ - cfg.mapDepth / 2
                    + (gr - 0.5) / rows * cfg.mapDepth
                fx = fx + (math.random() * 2 - 1) * cfg.featureSpacing * cfg.jitterRange
                fz = fz + (math.random() * 2 - 1) * cfg.featureSpacing * cfg.jitterRange

                local normX = (fx - originX) / (cfg.mapWidth / 2)
                local normZ = (fz - originZ) / (cfg.mapDepth / 2)
                local perpDist = math.abs(normX * perpDirX + normZ * perpDirZ)
                local spineProx = math.exp(-perpDist * perpDist / spineW2)

                local weights = {
                    rolling  = baseWeights.rolling  * (1 - spineProx * 0.8),
                    hill     = baseWeights.hill     * (1 - spineProx * 0.3),
                    mountain = baseWeights.mountain * (1 + spineProx * 2),
                    peak     = baseWeights.peak     * (1 + spineProx * 4),
                    plateau  = baseWeights.plateau  * (1 + spineProx * 0.5),
                    lake     = baseWeights.lake     * (1 - spineProx * 0.9),
                }

                local totalW = 0
                for _, name in ipairs(PROFILE_ORDER) do
                    totalW = totalW + weights[name]
                end

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

                local profile = profiles[selectedType]
                if not profile then
                    selectedType = "hill"
                    profile = profiles.hill
                end

                local sizeFactor = 0.5 + spineProx * 0.5
                if profile.geometry == "concave" then
                    sizeFactor = 0.6 + math.random() * 0.4
                end

                local baseW = profile.baseMin
                    + math.random() * (profile.baseMax - profile.baseMin) * sizeFactor
                local baseD
                if profile.aspectRatio then
                    baseD = baseW * profile.aspectRatio
                else
                    baseD = baseW * (0.5 + math.random() * 0.5)
                end

                idx = idx + 1
                noiseSeedCounter = noiseSeedCounter + 1.37

                featureSeeds[idx] = {
                    cx = fx,
                    cz = fz,
                    baseWidth = baseW,
                    baseDepth = baseD,
                    profileName = selectedType,
                    noiseSeed = noiseSeedCounter,
                }
            end
        end

        local groundY = cfg.groundY + cfg.groundHeight
        return self:_generateRegion(rx, rz, featureSeeds, groundY)
    end,

    In = {
        onBuildTopology = function(self, payload)
            -- Config
            self._config = {
                minRegionSize   = self:getAttribute("minRegionSize") or 20,
                attritionChance = self:getAttribute("attritionChance") or 3,
            }

            self._profiles = payload.terrainProfiles
            self._baseSeed = payload.seed or os.time()

            -- Cache blockout config for region expansion
            self._blockoutConfig = {
                mapWidth       = 4000,
                mapDepth       = 4000,
                groundHeight   = 4,
                groundY        = 0,
                featureSpacing = 667,
                jitterRange    = 0.3,
                spineAngle     = 15,
                spineWidth     = 0.2,
                rollingWeight  = 0.25,
                hillWeight     = 0.45,
                mountainWeight = 0.25,
                peakWeight     = 0.08,
                plateauWeight  = 0.05,
                lakeWeight     = 0.04,
                origin         = { 0, 0, 0 },
            }

            -- Read blockout config from payload's DOM FeatureMap attributes
            -- (or use defaults — blockout manager already ran)
            if payload.dom and payload.dom.children then
                for _, child in ipairs(payload.dom.children) do
                    if child.props and child.props.Name == "FeatureMap" then
                        -- Found FeatureMap, blockout already configured
                        break
                    end
                end
            end

            local featureSeeds = payload.featureSeeds or {}
            if not self._profiles then
                warn("[TopologyBuilder] No terrainProfiles on payload")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            local groundY = 0
            if payload.groundFill then
                groundY = payload.groundFill.y + payload.groundFill.height / 2
            end

            -- Generate origin region
            local result = self:_generateRegion(0, 0, featureSeeds, groundY)

            payload.features = result.features

            -- Spawn on tallest convex peak
            if result.peakFeature then
                payload.spawn = {
                    position = {
                        result.peakFeature.cx,
                        result.peakElevation + 15,
                        result.peakFeature.cz,
                    },
                }
            end

            self.Out:Fire("nodeComplete", payload)
        end,

        onExpandRegion = function(self, data)
            local result = self:_expandRegion(data.rx, data.rz)
            data._msgId = nil
            self.Out:Fire("regionReady", {
                rx = data.rx,
                rz = data.rz,
                features = result.features,
                peakElevation = result.peakElevation,
            })
        end,
    },
}
