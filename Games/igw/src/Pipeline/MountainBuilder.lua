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
            -- Store in payload
            ----------------------------------------------------------------

            payload.mountain = volumes

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
                "[MountainBuilder] %d volumes, %d layers, %d peaks, %d pads (seed %d) — %.2fs",
                #volumes, layerCount, peakCount, padCount, seed, os.clock() - t0
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
