--[[
    IGW v2 Pipeline — SplinePlannerNode (Subtractive Terrain)

    Generates ridge + valley splines and tags point features on CPs.
    Reads spine params from payload.biomeConfig (resolved by InventoryNode).

    Ridge splines:
        1. Main spine along diagonal axis with alternating peak/saddle CPs
        2. Sub-ridges branching perpendicular at interior CPs (recursive)
        3. Point features tagged: stratovolcano at peaks, pass at saddles

    Valley splines:
        1. Primary valleys perpendicular to nearest ridge, head near crest
        2. Glacial (wide/deep) or fluvial (narrow/shallow)
        3. Recursive tributaries branching at 30-60° from parent

    Output (payload):
        .splines — array of spline tables (see data structure below)

    Spline data structure:
        {
            class = "ridge" | "valley",
            subclass = "main_spine" | "sub_ridge" | "glacial_valley" | "fluvial_valley",
            depth = 0,
            parentIndex = nil,
            controlPoints = {
                { x, z, elevation, width, featureClass? },
            },
        }
--]]

return {
    name = "SplinePlannerNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onPlanSplines = function(self, payload)
            local biomeConfig = payload.biomeConfig
            local inventory = payload.inventory or {}
            local spine = biomeConfig and biomeConfig.spine or {}
            local baseElev = biomeConfig and biomeConfig.baseElevation or {}
            local featureDefs = biomeConfig and biomeConfig.features or {}

            local mapWidth = self:getAttribute("mapWidth") or 4000
            local mapDepth = self:getAttribute("mapDepth") or 4000
            local origin = self:getAttribute("origin") or { 0, 0, 0 }

            local seed = (payload.seed or os.time()) + 7919
            local rng = Random.new(seed)

            -- Spine geometry
            local angle = math.rad(spine.angle or 15)
            local spineDirX = math.cos(angle)
            local spineDirZ = math.sin(angle)
            local perpDirX = -spineDirZ
            local perpDirZ = spineDirX

            local halfW = mapWidth / 2
            local halfD = mapDepth / 2
            local originX = origin[1]
            local originZ = origin[3] or origin[2] or 0
            local diagonalExtent = math.min(halfW, halfD) * 0.85

            local crestHeight = baseElev.crestHeight or 350
            local edgeHeight = baseElev.edgeHeight or 40
            local ridgeCPs = spine.ridgeCPs or 8
            local lateralJitter = spine.lateralJitter or 100
            local subRidgeChance = spine.subRidgeChance or 0.4
            local maxBranchDepth = spine.maxBranchDepth or 2
            local numRidgeSpines = spine.numRidgeSpines or 1
            local spineSpacing = spine.spineSpacing or 600
            local subRidgeExtent = spine.subRidgeExtent or 0.35

            local splines = {}
            local allMainSpineIndices = {}  -- spline indices for all main spines

            -- Track remaining point features for tagging
            local remaining = {}
            for k, v in pairs(inventory) do
                remaining[k] = v
            end

            ----------------------------------------------------------------
            -- Helper: consume a point feature from remaining inventory
            ----------------------------------------------------------------
            local function consumeFeature(className)
                if remaining[className] and remaining[className] > 0 then
                    remaining[className] = remaining[className] - 1
                    return true
                end
                return false
            end

            ----------------------------------------------------------------
            -- Helper: roll a dimension from a feature def range
            ----------------------------------------------------------------
            local function rollRange(range)
                if not range then return 0 end
                return rng:NextNumber(range[1], math.max(range[1], range[2]))
            end

            ----------------------------------------------------------------
            -- MAIN RIDGES: multi-spine loop with perpendicular offset
            ----------------------------------------------------------------

            for spineIdx = 1, numRidgeSpines do
                -- Perpendicular offset for parallel spines
                local offsetIndex = spineIdx - (numRidgeSpines + 1) / 2
                local perpOffset = offsetIndex * spineSpacing

                -- Elevation attenuation for outer spines
                local distFromCenter = math.abs(offsetIndex) / math.max(1, (numRidgeSpines - 1) / 2)
                local elevScale = math.max(0.6, 1 - distFromCenter * 0.15)

                local mainCPs = {}
                for i = 1, ridgeCPs do
                    local t = (i - 1) / (ridgeCPs - 1)  -- 0..1
                    local along = (t * 2 - 1) * diagonalExtent

                    local px = originX + along * spineDirX + perpOffset * perpDirX
                    local pz = originZ + along * spineDirZ + perpOffset * perpDirZ

                    -- Lateral jitter
                    local lateralOffset = (rng:NextNumber() * 2 - 1) * lateralJitter
                    px = px + lateralOffset * perpDirX
                    pz = pz + lateralOffset * perpDirZ

                    -- Alternating peaks (even index) and saddles (odd index)
                    local isPeak = (i % 2 == 0)

                    -- Elevation: bell curve along spine, peaks higher than saddles
                    local spineT = 1 - math.abs(t * 2 - 1)  -- 0 at edges, 1 at center
                    local baseAtT = edgeHeight + (crestHeight - edgeHeight) * spineT
                    baseAtT = baseAtT * elevScale

                    local elevation, width, featureClass
                    if isPeak then
                        elevation = baseAtT * (0.9 + rng:NextNumber() * 0.2)
                        width = 150 + rng:NextNumber() * 100
                        featureClass = nil

                        -- Tag stratovolcano at highest peaks
                        if spineT > 0.5 and consumeFeature("stratovolcano") then
                            local volcanoDef = featureDefs.stratovolcano
                            featureClass = "stratovolcano"
                            elevation = rollRange(volcanoDef and volcanoDef.height or { 200, 400 })
                            width = rollRange(volcanoDef and volcanoDef.baseRadius or { 250, 500 }) * 2
                        end
                    else
                        elevation = baseAtT * (0.4 + rng:NextNumber() * 0.3)
                        width = 200 + rng:NextNumber() * 150
                        featureClass = nil

                        -- Tag pass at saddle CPs near center
                        if spineT > 0.3 and consumeFeature("pass") then
                            local passDef = featureDefs.pass
                            featureClass = "pass"
                            width = rollRange(passDef and passDef.width or { 80, 300 })
                            -- Pass depth = how far below the ridge crest
                            elevation = baseAtT * 0.3
                        end
                    end

                    table.insert(mainCPs, {
                        x = px,
                        z = pz,
                        elevation = elevation,
                        width = width,
                        featureClass = featureClass,
                    })
                end

                local splineIdx = #splines + 1
                table.insert(splines, {
                    class = "ridge",
                    subclass = "main_spine",
                    depth = 0,
                    parentIndex = nil,
                    controlPoints = mainCPs,
                })
                table.insert(allMainSpineIndices, splineIdx)
            end

            ----------------------------------------------------------------
            -- SUB-RIDGES: branch from interior CPs of ALL main spines
            ----------------------------------------------------------------

            local function buildSubRidge(parentCPs, parentIdx, branchCP, depth, parentSplineIdx)
                if depth > maxBranchDepth then return end
                if rng:NextNumber() > subRidgeChance then return end

                -- Branch perpendicular to parent direction
                local sign = (rng:NextNumber() < 0.5) and -1 or 1
                local branchDirX = perpDirX * sign
                local branchDirZ = perpDirZ * sign

                -- Angular jitter ±25°
                local jAngle = (rng:NextNumber() * 2 - 1) * math.rad(25)
                local cj, sj = math.cos(jAngle), math.sin(jAngle)
                branchDirX, branchDirZ =
                    branchDirX * cj - branchDirZ * sj,
                    branchDirX * sj + branchDirZ * cj

                -- 2-4 CPs descending in elevation
                local numCPs = 2 + rng:NextInteger(0, 2)
                local subCPs = {}
                local baseElv = branchCP.elevation * 0.8

                for j = 1, numCPs do
                    local frac = j / numCPs
                    local dist = frac * diagonalExtent * subRidgeExtent
                    local elev = baseElv * (1 - frac * 0.7)

                    local cpX = branchCP.x + dist * branchDirX
                        + (rng:NextNumber() * 2 - 1) * 60
                    local cpZ = branchCP.z + dist * branchDirZ
                        + (rng:NextNumber() * 2 - 1) * 60

                    -- Tag cinder cones on sub-ridge CPs
                    local feat = nil
                    if rng:NextNumber() < 0.3 and consumeFeature("cinder_cone") then
                        local coneDef = featureDefs.cinder_cone
                        feat = "cinder_cone"
                        elev = elev + rollRange(coneDef and coneDef.height or { 30, 80 })
                    end

                    table.insert(subCPs, {
                        x = cpX,
                        z = cpZ,
                        elevation = elev,
                        width = 100 + rng:NextNumber() * 120,
                        featureClass = feat,
                    })
                end

                local splineIdx = #splines + 1
                table.insert(splines, {
                    class = "ridge",
                    subclass = "sub_ridge",
                    depth = depth,
                    parentIndex = parentSplineIdx,
                    controlPoints = subCPs,
                })

                -- Recursive sub-branches from interior sub-ridge CPs
                for k = 2, #subCPs - 1 do
                    buildSubRidge(subCPs, k, subCPs[k], depth + 1, splineIdx)
                end
            end

            -- Trigger sub-ridges from ALL main spines
            for _, msIdx in ipairs(allMainSpineIndices) do
                local msSpline = splines[msIdx]
                local msCPs = msSpline.controlPoints
                for i = 2, #msCPs - 1 do
                    buildSubRidge(msCPs, i, msCPs[i], 1, msIdx)
                end
            end

            -- Tag remaining cinder cones on random existing ridge CPs
            for si, spline in ipairs(splines) do
                if spline.class == "ridge" then
                    for _, cp in ipairs(spline.controlPoints) do
                        if not cp.featureClass and consumeFeature("cinder_cone") then
                            local coneDef = featureDefs.cinder_cone
                            cp.featureClass = "cinder_cone"
                            cp.elevation = cp.elevation
                                + rollRange(coneDef and coneDef.height or { 30, 80 })
                        end
                    end
                end
            end

            ----------------------------------------------------------------
            -- VALLEY SPLINES: glacial + fluvial, with tributaries
            ----------------------------------------------------------------

            local valleysPerSide = spine.valleysPerSide or { 3, 5 }
            local tributaryChance = spine.tributaryChance or 0.5
            local maxTribDepth = spine.maxTributaryDepth or 2

            local numValleys = rng:NextInteger(valleysPerSide[1],
                math.max(valleysPerSide[1], valleysPerSide[2]))

            local function buildValley(startX, startZ, startElev, flowDirX, flowDirZ,
                                       subclass, depth, parentSplineIdx)
                local isGlacial = (subclass == "glacial_valley")
                local def = featureDefs[subclass] or {}

                local numCPs = 3 + rng:NextInteger(0, 2)
                local maxDist = diagonalExtent * (isGlacial and 0.6 or 0.4)
                local valleyCPs = {}

                for j = 0, numCPs - 1 do
                    local frac = j / math.max(1, numCPs - 1)
                    local dist = frac * maxDist

                    -- Meander perpendicular to flow
                    local wobble = (rng:NextNumber() * 2 - 1) * 80 * frac
                    local wobbleDirX = -flowDirZ
                    local wobbleDirZ = flowDirX

                    local cpWidth = rollRange(def.width or (isGlacial and { 150, 400 } or { 30, 100 }))
                    local cpDepth = rollRange(def.depth or (isGlacial and { 80, 200 } or { 20, 80 }))

                    -- Width narrows toward head (frac=0), widens toward mouth
                    cpWidth = cpWidth * (0.4 + frac * 0.6)
                    -- Depth shallows toward mouth
                    cpDepth = cpDepth * (1 - frac * 0.5)

                    -- Tag cirque at valley head (frac ≈ 0)
                    local feat = nil
                    if j == 0 and isGlacial and consumeFeature("cirque") then
                        local cirqueDef = featureDefs.cirque
                        feat = "cirque"
                        cpWidth = rollRange(cirqueDef and cirqueDef.diameter or { 120, 350 })
                    end

                    table.insert(valleyCPs, {
                        x = startX + dist * flowDirX + wobble * wobbleDirX,
                        z = startZ + dist * flowDirZ + wobble * wobbleDirZ,
                        elevation = startElev * (1 - frac * 0.8),
                        width = cpWidth,
                        depth = cpDepth,
                        featureClass = feat,
                    })
                end

                local splineIdx = #splines + 1
                table.insert(splines, {
                    class = "valley",
                    subclass = subclass,
                    depth = depth,
                    parentIndex = parentSplineIdx,
                    controlPoints = valleyCPs,
                })

                -- Recursive tributaries from interior valley CPs
                if depth < maxTribDepth then
                    for k = 2, #valleyCPs - 1 do
                        if rng:NextNumber() < tributaryChance then
                            local cp = valleyCPs[k]
                            -- Tributary branches at 30-60° from parent valley
                            local tribAngle = (rng:NextNumber() * 30 + 30) * math.pi / 180
                            local tribSign = (rng:NextNumber() < 0.5) and -1 or 1
                            local ca, sa = math.cos(tribAngle * tribSign), math.sin(tribAngle * tribSign)
                            local tdx = flowDirX * ca - flowDirZ * sa
                            local tdz = flowDirX * sa + flowDirZ * ca

                            buildValley(cp.x, cp.z, cp.elevation,
                                tdx, tdz,
                                "fluvial_valley", depth + 1, splineIdx)
                        end
                    end
                end
            end

            -- Pool all main-spine CPs for valley sourcing
            local allRidgeCPs = {}
            for _, msIdx in ipairs(allMainSpineIndices) do
                local msCPs = splines[msIdx].controlPoints
                for ci = 2, #msCPs - 1 do
                    table.insert(allRidgeCPs, msCPs[ci])
                end
            end

            -- Spawn primary valleys distributed across all main-spine CPs
            for vi = 1, numValleys do
                if #allRidgeCPs == 0 then break end
                local cpIdx = rng:NextInteger(1, #allRidgeCPs)
                local cp = allRidgeCPs[cpIdx]

                -- Flow perpendicular to spine, alternating sides
                local sign = (vi % 2 == 0) and -1 or 1
                local flowDirX = perpDirX * sign
                local flowDirZ = perpDirZ * sign

                -- Slight directional jitter
                local jAngle = (rng:NextNumber() * 2 - 1) * math.rad(20)
                local cj, sj = math.cos(jAngle), math.sin(jAngle)
                flowDirX, flowDirZ =
                    flowDirX * cj - flowDirZ * sj,
                    flowDirX * sj + flowDirZ * cj

                -- Alternate glacial/fluvial (glacial more common early)
                local subclass
                local glacialRemaining = remaining.glacial_valley or 0
                local fluvialRemaining = remaining.fluvial_valley or 0

                if glacialRemaining > 0 and (fluvialRemaining == 0 or rng:NextNumber() < 0.6) then
                    subclass = "glacial_valley"
                    remaining.glacial_valley = glacialRemaining - 1
                elseif fluvialRemaining > 0 then
                    subclass = "fluvial_valley"
                    remaining.fluvial_valley = fluvialRemaining - 1
                else
                    continue
                end

                buildValley(cp.x, cp.z, cp.elevation, flowDirX, flowDirZ,
                    subclass, 0, nil)
            end

            ----------------------------------------------------------------
            -- Stats
            ----------------------------------------------------------------

            local ridgeCount, valleyCount, totalCPs = 0, 0, 0
            local featureTags = {}
            for _, s in ipairs(splines) do
                if s.class == "ridge" then ridgeCount = ridgeCount + 1 end
                if s.class == "valley" then valleyCount = valleyCount + 1 end
                totalCPs = totalCPs + #s.controlPoints
                for _, cp in ipairs(s.controlPoints) do
                    if cp.featureClass then
                        featureTags[cp.featureClass] = (featureTags[cp.featureClass] or 0) + 1
                    end
                end
            end

            local tagParts = {}
            for k, v in pairs(featureTags) do
                table.insert(tagParts, k .. "=" .. v)
            end
            table.sort(tagParts)

            print(string.format(
                "[SplinePlannerNode] %d ridges, %d valleys, %d CPs | Tagged: %s (seed %d)",
                ridgeCount, valleyCount, totalCPs,
                #tagParts > 0 and table.concat(tagParts, " ") or "none",
                seed
            ))

            payload.splines = splines
            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
