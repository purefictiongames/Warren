--[[
    IGW v2 Pipeline — TopologyTerrainPainter

    Stateless terrain executor. Receives paint/clear signals from
    ChunkManager with chunk bounds + filtered topology data.

    paintChunk: fills ground slab + volume shells + slopes for one chunk.
    clearChunk: fills chunk column with Air to unload terrain.

    v3.0: All fills write into a VoxelBuffer, flushed in ONE WriteVoxels
    call per chunk. Replaces ~hundreds of individual FillBlock/FillWedge
    calls with pure Lua array writes + one API call.

    Adaptive dithering: gap scales with elevation. Gentle low terrain
    uses large gaps (max savings), steep high terrain uses tight gaps
    (preserves snapping on vertical faces).
--]]

local FILL    = 1   -- studs of terrain to fill per shell face
local MIN_GAP = 3   -- tightest gap (high elevation / steep)
local MAX_GAP = 7   -- loosest gap (low elevation / gentle)

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
        -- Paint one chunk: ground + volume shells + slopes
        --------------------------------------------------------------------

        onPaintChunk = function(self, data)
            local Canvas = self._System.Dom.Canvas
            local bounds = data.bounds
            local volumes = data.volumes or {}
            local slopes = data.slopes or {}
            local biome = data.biome or {}
            local peakElev = data.peakElevation or 500
            local groundY = 0
            if data.groundFill then
                groundY = data.groundFill.position[2]
                    - data.groundFill.size[2] / 2
            end

            local wallMatName = biome.terrainWall or "Rock"
            local wallMaterial = Enum.Material[wallMatName]
            if not wallMaterial then
                wallMaterial = Enum.Material.Rock
            end

            local chunkW = bounds.maxX - bounds.minX
            local chunkD = bounds.maxZ - bounds.minZ
            local chunkCX = (bounds.minX + bounds.maxX) / 2
            local chunkCZ = (bounds.minZ + bounds.maxZ) / 2

            -- Elevation range for gap interpolation
            local elevRange = math.max(1, peakElev - groundY)

            ----------------------------------------------------------------
            -- Create buffer spanning chunk bounds
            ----------------------------------------------------------------

            local buf = Canvas.createBuffer(
                Vector3.new(bounds.minX, -10, bounds.minZ),
                Vector3.new(bounds.maxX, peakElev + 4, bounds.maxZ)
            )

            ----------------------------------------------------------------
            -- 1. Ground plane (clipped to chunk)
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
            -- 2. Volume shells (top + 4 sides, adaptive gap)
            ----------------------------------------------------------------

            for _, vol in ipairs(volumes) do
                local x = vol.position[1]
                local y = vol.position[2]
                local z = vol.position[3]
                local w, h, d = vol.dims[1], vol.dims[2], vol.dims[3]

                -- Elevation fraction: 0 at ground, 1 at peak
                local elevFrac = math.clamp(
                    (y - groundY) / elevRange, 0, 1
                )
                local gap = MAX_GAP
                    - (MAX_GAP - MIN_GAP) * elevFrac

                if w <= FILL * 2 or d <= FILL * 2 then
                    buf:fillBlock(
                        CFrame.new(x, y, z),
                        Vector3.new(w, h, d),
                        wallMaterial
                    )
                else
                    -- Top (inset on X + Z)
                    buf:fillBlock(
                        CFrame.new(x, y + h / 2 - FILL / 2, z),
                        Vector3.new(w - gap, FILL, d - gap),
                        wallMaterial
                    )
                    -- East +X (inset on Y + Z)
                    buf:fillBlock(
                        CFrame.new(x + w / 2 - FILL / 2, y, z),
                        Vector3.new(FILL, h - gap, d - gap),
                        wallMaterial
                    )
                    -- West -X (inset on Y + Z)
                    buf:fillBlock(
                        CFrame.new(x - w / 2 + FILL / 2, y, z),
                        Vector3.new(FILL, h - gap, d - gap),
                        wallMaterial
                    )
                    -- North +Z (inset on X + Y)
                    buf:fillBlock(
                        CFrame.new(x, y, z + d / 2 - FILL / 2),
                        Vector3.new(w - gap, h - gap, FILL),
                        wallMaterial
                    )
                    -- South -Z (inset on X + Y)
                    buf:fillBlock(
                        CFrame.new(x, y, z - d / 2 + FILL / 2),
                        Vector3.new(w - gap, h - gap, FILL),
                        wallMaterial
                    )
                end
            end

            ----------------------------------------------------------------
            -- 3. Slopes
            ----------------------------------------------------------------

            for _, slope in ipairs(slopes) do
                buf:fillWedge(
                    slope.cframe, slope.size, wallMaterial
                )
            end

            ----------------------------------------------------------------
            -- 4. Flush — ONE WriteVoxels call for entire chunk
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
                Vector3.new(bounds.minX, -10, bounds.minZ),
                Vector3.new(bounds.maxX, peakH, bounds.maxZ)
            )

            data._msgId = nil
            self.Out:Fire("chunkDone", data)
        end,
    },
}
