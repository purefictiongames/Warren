--[[
    IGW v2 Pipeline — SandPainterNode

    Chunk painting chain node. Sits after WaterFloodNode. Two passes:

    1. Sand paint: replaces solid terrain voxels at or below sandLevel
       with Sand — paints water beds and beaches.

    2. Shoreline erosion: for each column, finds the topmost solid voxel.
       If it's within 1 voxel of waterLevel (a shoreline column), sinks
       that top voxel to Water. Eliminates the surface-tension blending
       artifact where solid and liquid voxels share the same Y layer.

    Chain: ... → WaterFloodNode → SandPainterNode → ChunkManager
--]]

local VOXEL = 4

return {
    name = "SandPainterNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onChunkDone = function(self, data)
            local sandLevel = data.sandLevel
            local waterLevel = data.waterLevel
            local bounds = data.bounds

            if data.action == "paint" and sandLevel and bounds then
                -- Wait one frame for prior WriteVoxels to commit
                task.wait()

                local terrain = workspace.Terrain
                local sandMat = Enum.Material.Sand
                local waterMat = Enum.Material.Water

                local groundY = 0
                local gf = data.groundFill
                if gf then
                    groundY = gf.position[2] + gf.size[2] / 2
                end

                local scanMinY = groundY - 10
                local scanMaxY = sandLevel + VOXEL

                local region = Region3.new(
                    Vector3.new(bounds.minX, scanMinY, bounds.minZ),
                    Vector3.new(bounds.maxX, scanMaxY, bounds.maxZ)
                )

                local mats, occs = terrain:ReadVoxels(region, VOXEL)
                local changed = false

                --------------------------------------------------------
                -- Pass 1: Paint sand on solid voxels below sandLevel
                --------------------------------------------------------

                for xi = 1, #mats do
                    for yi = 1, #mats[xi] do
                        for zi = 1, #mats[xi][yi] do
                            if occs[xi][yi][zi] > 0
                                and mats[xi][yi][zi] ~= waterMat
                            then
                                mats[xi][yi][zi] = sandMat
                                changed = true
                            end
                        end
                    end
                end

                -- Pass 2: shoreline carve (disabled for debugging)

                if changed then
                    terrain:WriteVoxels(region, VOXEL, mats, occs)
                end
            end

            -- Forward to next in chain
            data._msgId = nil
            self.Out:Fire("chunkDone", data)
        end,
    },
}
