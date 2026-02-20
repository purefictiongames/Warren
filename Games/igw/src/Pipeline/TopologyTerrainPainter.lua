--[[
    IGW v2 Pipeline — TopologyTerrainPainter

    Stateless terrain executor. Receives paint/clear signals from
    ChunkManager with chunk bounds + filtered feature data.

    paintChunk: ground slab + per-feature fillFeature, one flush.
    clearChunk: fills chunk column with Air to unload terrain.

    Uses proven fillFeature path — each feature writes its own voxels
    directly into the buffer. No composed height field.
--]]

return {
    name = "TopologyTerrainPainter",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        --------------------------------------------------------------------
        -- Paint one chunk: ground + per-feature fills + flush
        --------------------------------------------------------------------

        onPaintChunk = function(self, data)
            local Canvas = self._System.Dom.Canvas
            local bounds = data.bounds
            local features = data.features or {}
            local biome = data.biome or {}
            local peakElev = data.peakElevation or 500

            local wallMatName = biome.terrainWall or "Rock"
            local wallMaterial = Enum.Material[wallMatName]
            if not wallMaterial then
                wallMaterial = Enum.Material.Rock
            end

            local chunkW = bounds.maxX - bounds.minX
            local chunkD = bounds.maxZ - bounds.minZ
            local chunkCX = (bounds.minX + bounds.maxX) / 2
            local chunkCZ = (bounds.minZ + bounds.maxZ) / 2

            local buf = Canvas.createBuffer(
                Vector3.new(bounds.minX, -10, bounds.minZ),
                Vector3.new(bounds.maxX, peakElev + 4, bounds.maxZ)
            )

            ----------------------------------------------------------------
            -- 1. Ground plane
            ----------------------------------------------------------------

            local gf = data.groundFill
            if gf then
                buf:fillBlock(
                    CFrame.new(chunkCX, gf.position[2], chunkCZ),
                    Vector3.new(chunkW, gf.size[2], chunkD),
                    wallMaterial
                )
            end

            ----------------------------------------------------------------
            -- 2. Per-feature fillFeature (convex only for now)
            ----------------------------------------------------------------

            local groundY = 0
            if gf then
                groundY = gf.position[2] + gf.size[2] / 2
            end

            for _, feature in ipairs(features) do
                if feature.geometry ~= "concave" then
                    local extentX = (feature.boundMaxX or 0) - (feature.boundMinX or 0)
                    local extentZ = (feature.boundMaxZ or 0) - (feature.boundMinZ or 0)
                    local baseExtent = math.max(extentX, extentZ)
                    local feather = math.max(50, baseExtent * 0.3)

                    buf:fillFeature(
                        feature.layers,
                        groundY,
                        wallMaterial,
                        feather
                    )
                end
            end

            ----------------------------------------------------------------
            -- 3. Flush
            ----------------------------------------------------------------

            buf:flush()

            data._msgId = nil
            self.Out:Fire("chunkDone", data)
        end,

        --------------------------------------------------------------------
        -- Clear one chunk: fill column with Air
        --------------------------------------------------------------------

        onClearChunk = function(self, data)
            local Canvas = self._System.Dom.Canvas
            local bounds = data.bounds
            local peakH = (data.peakElevation or 500) + 50

            Canvas.clearRegion(
                Vector3.new(bounds.minX, -50, bounds.minZ),
                Vector3.new(bounds.maxX, peakH, bounds.maxZ)
            )

            data._msgId = nil
            self.Out:Fire("chunkDone", data)
        end,
    },
}
