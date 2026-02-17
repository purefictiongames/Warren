--[[
    IGW v2 Pipeline — MountainBuilder
    Generates stacked, tapered mountain volumes with optional forking peaks.
    Drops pads on exterior faces where rooms can attach.
    Blockout mode — creates visible Parts for shape visualization.
--]]

--------------------------------------------------------------------------------
-- LAYER COLORS (brown base → white peak)
--------------------------------------------------------------------------------

local LAYER_COLORS = {
    { 120, 100,  80 },
    { 140, 120,  95 },
    { 160, 145, 115 },
    { 180, 170, 140 },
    { 200, 195, 175 },
    { 220, 215, 200 },
    { 240, 235, 225 },
    { 250, 248, 240 },
}

--------------------------------------------------------------------------------
-- FACE DEFINITIONS
--------------------------------------------------------------------------------

local SIDE_FACES = {
    { name = "E", axis = 1, dir =  1, normal = {  1, 0,  0 } },
    { name = "W", axis = 1, dir = -1, normal = { -1, 0,  0 } },
    { name = "N", axis = 3, dir =  1, normal = {  0, 0,  1 } },
    { name = "S", axis = 3, dir = -1, normal = {  0, 0, -1 } },
}

--------------------------------------------------------------------------------
-- NODE
--------------------------------------------------------------------------------

return {
    name = "MountainBuilder",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildMountain = function(self, payload)
            local Dom = self._System.Dom
            local t0 = os.clock()

            -- Config from cascade
            local baseWidth    = self:getAttribute("baseWidth") or 400
            local baseDepth    = self:getAttribute("baseDepth") or 400
            local layerHeight  = self:getAttribute("layerHeight") or 50
            local layerCount   = self:getAttribute("layerCount") or 6
            local taperRatio   = self:getAttribute("taperRatio") or 0.7
            local forkChance   = self:getAttribute("forkChance") or 25
            local maxPeaks     = self:getAttribute("maxPeaks") or 3
            local jitterRange  = self:getAttribute("jitterRange") or 0.15
            local origin       = self:getAttribute("origin") or { 0, 0, 0 }

            -- Room size config (shared with room masser via cascade)
            local scaleRange = self:getAttribute("scaleRange")
                or { min = 4, max = 12, minY = 4, maxY = 8 }
            local baseUnit = self:getAttribute("baseUnit") or 5
            local minRoomW = scaleRange.min * baseUnit
            local minRoomH = (scaleRange.minY or scaleRange.min) * baseUnit

            local seed = payload.seed or os.time()
            math.randomseed(seed)

            ----------------------------------------------------------------
            -- Generate mountain volume tree
            ----------------------------------------------------------------

            local volumes = {}
            local volumeById = {}
            local peakCount = 1
            local nextId = 1

            -- Base volume
            local base = {
                id = nextId,
                layer = 0,
                position = {
                    origin[1],
                    origin[2] + layerHeight / 2,
                    origin[3],
                },
                dims = { baseWidth, layerHeight, baseDepth },
                parentId = nil,
                childIds = {},
            }
            table.insert(volumes, base)
            volumeById[base.id] = base
            nextId = nextId + 1

            -- Grow layers upward
            local currentLayer = { base }

            for layer = 1, layerCount - 1 do
                local nextLayer = {}

                for _, parent in ipairs(currentLayer) do
                    local shouldFork = peakCount < maxPeaks
                        and math.random(1, 100) <= forkChance

                    local childCount = shouldFork and 2 or 1
                    if shouldFork then
                        peakCount = peakCount + 1
                    end

                    for c = 1, childCount do
                        -- Taper — forks are narrower
                        local taper = taperRatio
                        if shouldFork then
                            taper = taperRatio * 0.75
                        end

                        local childWidth = parent.dims[1] * taper
                        local childDepth = parent.dims[3] * taper

                        -- Jitter constrained to parent footprint
                        local maxJitterX = (parent.dims[1] - childWidth) / 2
                        local maxJitterZ = (parent.dims[3] - childDepth) / 2
                        local jitterX = maxJitterX * (math.random() * 2 - 1) * jitterRange
                        local jitterZ = maxJitterZ * (math.random() * 2 - 1) * jitterRange

                        -- Forks spread apart
                        if shouldFork then
                            local spreadX = maxJitterX * 0.5
                            local spreadZ = maxJitterZ * 0.5
                            if c == 1 then
                                jitterX = jitterX + spreadX
                                jitterZ = jitterZ + spreadZ
                            else
                                jitterX = jitterX - spreadX
                                jitterZ = jitterZ - spreadZ
                            end
                        end

                        local childY = parent.position[2]
                            + parent.dims[2] / 2
                            + layerHeight / 2

                        local child = {
                            id = nextId,
                            layer = layer,
                            position = {
                                parent.position[1] + jitterX,
                                childY,
                                parent.position[3] + jitterZ,
                            },
                            dims = { childWidth, layerHeight, childDepth },
                            parentId = parent.id,
                            childIds = {},
                        }
                        table.insert(volumes, child)
                        volumeById[child.id] = child
                        table.insert(parent.childIds, child.id)
                        table.insert(nextLayer, child)
                        nextId = nextId + 1
                    end
                end

                currentLayer = nextLayer
            end

            ----------------------------------------------------------------
            -- Generate pads on mountain faces (as DOM elements)
            ----------------------------------------------------------------

            local padCount = 0

            for _, vol in ipairs(volumes) do
                for _, face in ipairs(SIDE_FACES) do
                    local widthAxis = face.axis == 1 and 3 or 1
                    local faceWidth = vol.dims[widthAxis]
                    local faceHeight = vol.dims[2]

                    if faceWidth >= minRoomW and faceHeight >= minRoomH then
                        local spacing = minRoomW * 2
                        local numPads = math.max(1, math.floor(faceWidth / spacing))

                        for p = 1, numPads do
                            padCount = padCount + 1
                            local widthOffset = ((p - 0.5) / numPads - 0.5) * faceWidth

                            local pos = {
                                vol.position[1],
                                vol.position[2],
                                vol.position[3],
                            }
                            pos[face.axis] = vol.position[face.axis]
                                + face.dir * vol.dims[face.axis] / 2
                            pos[widthAxis] = vol.position[widthAxis] + widthOffset

                            local padNode = Dom.createElement("Model", {
                                Name = "Pad_" .. padCount,
                                PadPosition = pos,
                                PadNormal = {
                                    face.normal[1],
                                    face.normal[2],
                                    face.normal[3],
                                },
                                PadFaceWidth = faceWidth / numPads,
                                PadFaceHeight = faceHeight,
                                VolumeId = vol.id,
                                Layer = vol.layer,
                                Face = face.name,
                            })
                            Dom.addClass(padNode, "mountain-pad")
                            Dom.appendChild(payload.dom, padNode)
                        end
                    end
                end
            end

            ----------------------------------------------------------------
            -- Generate slope wedges for all layers
            -- Corners handled by terrain voxel fill in MountainTerrainPainter
            ----------------------------------------------------------------

            local WEDGE_FACES = {
                { name = "N", axis = 3, dir =  1, rot = CFrame.Angles(0, math.pi, 0),
                    depthAxis = 1 },
                { name = "S", axis = 3, dir = -1, rot = CFrame.Angles(0, 0, 0),
                    depthAxis = 1 },
                { name = "E", axis = 1, dir =  1, rot = CFrame.Angles(0, -math.pi/2, 0),
                    depthAxis = 3 },
                { name = "W", axis = 1, dir = -1, rot = CFrame.Angles(0, math.pi/2, 0),
                    depthAxis = 3 },
            }

            local baseMinSlope = self:getAttribute("baseMinSlope") or 40
            local baseMaxSlope = self:getAttribute("baseMaxSlope") or 100

            local wedgeCount = 0

            for _, vol in ipairs(volumes) do
                local overhangs = {}
                local colorIdx = math.min(vol.layer + 1, #LAYER_COLORS)
                local rgb = LAYER_COLORS[colorIdx]
                local wedgeHeight = vol.dims[2]

                -- Calculate per-face overhangs
                if vol.parentId then
                    local parent = volumeById[vol.parentId]
                    if parent then
                        for _, face in ipairs(WEDGE_FACES) do
                            local ax = face.axis
                            local parentEdge = parent.position[ax]
                                + face.dir * parent.dims[ax] / 2
                            local childEdge = vol.position[ax]
                                + face.dir * vol.dims[ax] / 2
                            local oh = (parentEdge - childEdge) * face.dir
                            overhangs[face.name] = oh > 1 and oh or 0
                        end
                    end
                elseif vol.layer == 0 then
                    -- Base layer: random overhangs
                    for _, face in ipairs(WEDGE_FACES) do
                        overhangs[face.name] = baseMinSlope
                            + math.random() * (baseMaxSlope - baseMinSlope)
                    end
                end

                -- Store overhangs for terrain painter corner fills
                vol.overhangs = overhangs

                -- Face wedges
                for _, face in ipairs(WEDGE_FACES) do
                    local oh = overhangs[face.name] or 0
                    if oh <= 0 then continue end

                    local ax = face.axis
                    local childEdge = vol.position[ax]
                        + face.dir * vol.dims[ax] / 2
                    local depthAx = face.depthAxis
                    local wedgeDepth = vol.dims[depthAx]

                    local cx = vol.position[1]
                    local cy = vol.position[2]
                    local cz = vol.position[3]
                    if ax == 1 then
                        cx = childEdge + face.dir * oh / 2
                    else
                        cz = childEdge + face.dir * oh / 2
                    end

                    wedgeCount = wedgeCount + 1
                    local wedge = Dom.createElement("WedgePart", {
                        Name = "Slope_" .. wedgeCount,
                        Size = Vector3.new(wedgeDepth, wedgeHeight, oh),
                        CFrame = CFrame.new(cx, cy, cz) * face.rot,
                        Anchored = true,
                        CanCollide = true,
                        Transparency = 0.3,
                        Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
                        Material = Enum.Material.SmoothPlastic,
                    })
                    Dom.appendChild(payload.dom, wedge)
                end
            end

            ----------------------------------------------------------------
            -- Store in payload + set spawn on base layer edge
            ----------------------------------------------------------------

            payload.mountain = volumes

            local baseTop = base.position[2] + base.dims[2] / 2
            payload.spawn = {
                position = {
                    base.position[1] + 10,
                    baseTop + 15,
                    base.position[3] + base.dims[3] / 2 + 10,
                },
            }

            ----------------------------------------------------------------
            -- Create blockout Parts (mountain volumes)
            ----------------------------------------------------------------

            for _, vol in ipairs(volumes) do
                local colorIdx = math.min(vol.layer + 1, #LAYER_COLORS)
                local rgb = LAYER_COLORS[colorIdx]

                local part = Dom.createElement("Part", {
                    Name = "Mountain_" .. vol.id,
                    Size = Vector3.new(vol.dims[1], vol.dims[2], vol.dims[3]),
                    Position = Vector3.new(
                        vol.position[1], vol.position[2], vol.position[3]
                    ),
                    Anchored = true,
                    CanCollide = true,
                    Transparency = 0.3,
                    Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
                    Material = Enum.Material.SmoothPlastic,
                })
                Dom.appendChild(payload.dom, part)
            end

            print(string.format(
                "[MountainBuilder] %d volumes, %d layers, %d peaks, %d wedges, %d pads (seed %d) — %.2fs",
                #volumes, layerCount, peakCount, wedgeCount, padCount, seed, os.clock() - t0
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
