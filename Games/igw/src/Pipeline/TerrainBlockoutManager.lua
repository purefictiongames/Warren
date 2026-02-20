--[[
    IGW v2 Pipeline — TerrainBlockoutManager

    Decides feature inventory and positions. Seeds features on a jittered
    grid with spine-biased profile selection. Creates DOM FeatureMap folder
    with Feature_N child nodes carrying profile metadata.

    Extended profiles: rolling, hill, mountain, peak, plateau, lake.
    Concave features (lake) are suppressed near spine.

    Output (payload):
        .featureSeeds  — array of { cx, cz, baseWidth, baseDepth, profileName, noiseSeed }
        .groundFill    — { y, height } for the ground plane
        DOM            — FeatureMap/Feature_N Folders with class="feature {type}"
--]]

local PROFILE_ORDER = { "rolling", "hill", "mountain", "peak", "plateau", "lake" }

return {
    name = "TerrainBlockoutManager",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBlockoutTerrain = function(self, payload)
            local Dom = self._System.Dom

            -- Config from attributes
            local mapWidth       = self:getAttribute("mapWidth") or 4000
            local mapDepth       = self:getAttribute("mapDepth") or 4000
            local groundHeight   = self:getAttribute("groundHeight") or 4
            local groundY        = self:getAttribute("groundY") or 0
            local featureSpacing = self:getAttribute("featureSpacing") or 667
            local jitterRange    = self:getAttribute("jitterRange") or 0.3
            local spineAngle     = self:getAttribute("spineAngle") or 15
            local spineWidth     = self:getAttribute("spineWidth") or 0.2
            local origin         = self:getAttribute("origin") or { 0, 0, 0 }

            -- Profile weights
            local baseWeights = {
                rolling  = self:getAttribute("rollingWeight") or 0.25,
                hill     = self:getAttribute("hillWeight") or 0.45,
                mountain = self:getAttribute("mountainWeight") or 0.25,
                peak     = self:getAttribute("peakWeight") or 0.08,
                plateau  = self:getAttribute("plateauWeight") or 0.05,
                lake     = self:getAttribute("lakeWeight") or 0.04,
            }

            local profiles = payload.terrainProfiles
            if not profiles then
                warn("[TerrainBlockoutManager] No terrainProfiles on payload")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            -- Seed RNG
            local seed = payload.seed or os.time()
            math.randomseed(seed)

            -- Spine direction vectors
            local spineRad = math.rad(spineAngle)
            local perpDirX = -math.sin(spineRad)
            local perpDirZ = math.cos(spineRad)
            local spineW2 = 2 * spineWidth * spineWidth

            -- Create DOM FeatureMap folder
            local featureMapFolder = Dom.createElement("Folder", {
                Name = "FeatureMap",
            })
            Dom.appendChild(payload.dom, featureMapFolder)

            local featureSeeds = {}
            local noiseSeedCounter = seed * 0.001
            local idx = 0

            -- Grid seeding
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
                        * featureSpacing * jitterRange
                    fz = fz + (math.random() * 2 - 1)
                        * featureSpacing * jitterRange

                    -- Spine proximity (0 = edge, 1 = on spine)
                    local normX = (fx - origin[1]) / (mapWidth / 2)
                    local normZ = (fz - origin[3]) / (mapDepth / 2)
                    local perpDist = math.abs(
                        normX * perpDirX + normZ * perpDirZ
                    )
                    local spineProx = math.exp(
                        -perpDist * perpDist / spineW2
                    )

                    -- Bias weights: taller types near spine, concave away from spine
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

                    local profile = profiles[selectedType]
                    if not profile then
                        selectedType = "hill"
                        profile = profiles.hill
                    end

                    -- Base size (bigger near spine for convex)
                    local sizeFactor = 0.5 + spineProx * 0.5
                    if profile.geometry == "concave" then
                        sizeFactor = 0.6 + math.random() * 0.4
                    end

                    local baseW = profile.baseMin
                        + math.random()
                        * (profile.baseMax - profile.baseMin)
                        * sizeFactor
                    local baseD
                    if profile.aspectRatio then
                        baseD = baseW * profile.aspectRatio
                    else
                        baseD = baseW * (0.5 + math.random() * 0.5)
                    end

                    idx = idx + 1
                    noiseSeedCounter = noiseSeedCounter + 1.37

                    -- Create DOM feature node
                    local featureNode = Dom.createElement("Folder", {
                        Name = "Feature_" .. idx,
                        class = "feature " .. selectedType,
                        profileType = selectedType,
                        geometry = profile.geometry,
                        cx = fx,
                        cz = fz,
                        baseWidth = baseW,
                        baseDepth = baseD,
                    })
                    Dom.appendChild(featureMapFolder, featureNode)

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

            -- Ground fill
            payload.featureSeeds = featureSeeds
            payload.groundFill = {
                y = groundY + groundHeight / 2,
                height = groundHeight,
            }

            print(string.format(
                "[TerrainBlockoutManager] %d features seeded on %dx%d grid",
                idx, cols, rows
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
