--[[
    IGW v2 Pipeline — WaterFloodNode

    Chunk painting chain node. Sits after TopologyTerrainPainter, before
    ChunkManager receives chunkDone. Floods air below waterLevel with Water.

    Chain: ChunkManager → TopologyTerrainPainter → WaterFloodNode → ChunkManager

    Paint chunks: waits one frame (terrain WriteVoxels commit), then
    ReadVoxels + fill Air below waterLevel + WriteVoxels, then forwards
    chunkDone. Clear chunks: passes through immediately.
--]]

local VOXEL = 4

return {
    name = "WaterFloodNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onChunkDone = function(self, data)
            local waterLevel = data.waterLevel
            local bounds = data.bounds

            -- Only flood paint actions that have a water level set
            if data.action == "paint" and waterLevel and bounds then
                -- Wait one frame for terrain WriteVoxels to commit
                task.wait()

                local terrain = workspace.Terrain
                local waterMat = Enum.Material.Water

                -- Ground elevation from groundFill
                local groundY = 0
                local gf = data.groundFill
                if gf then
                    groundY = gf.position[2] + gf.size[2] / 2
                end

                local scanMinY = groundY - 10
                local scanMaxY = waterLevel + VOXEL

                local region = Region3.new(
                    Vector3.new(bounds.minX, scanMinY, bounds.minZ),
                    Vector3.new(bounds.maxX, scanMaxY, bounds.maxZ)
                ):ExpandToGrid(VOXEL)

                local mats, occs = terrain:ReadVoxels(region, VOXEL)
                local changed = false

                -- Per-column top-down fill: water only above terrain surface.
                -- Scan from top of Y range downward; stop at first solid voxel.
                for xi = 1, #mats do
                    for zi = 1, #mats[xi][1] do
                        for yi = #mats[xi], 1, -1 do
                            if occs[xi][yi][zi] == 0 then
                                mats[xi][yi][zi] = waterMat
                                occs[xi][yi][zi] = 1
                                changed = true
                            else
                                break
                            end
                        end
                    end
                end

                if changed then
                    terrain:WriteVoxels(region, VOXEL, mats, occs)
                end
            end

            -- Forward to ChunkManager
            data._msgId = nil
            self.Out:Fire("chunkDone", data)
        end,
    },
}
