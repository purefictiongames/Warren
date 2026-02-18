--[[
    IGW v2 Pipeline — MountainTerrainPainter
    Fills mountain volumes with terrain and hides mountain blockout Parts.
    Runs after DOM mount (needs mounted Instances + Canvas).
--]]

return {
    name = "MountainTerrainPainter",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onPaintTerrain = function(self, payload)
            local Dom = self._System.Dom
            local Canvas = Dom.Canvas
            local t0 = os.clock()

            local mountain = payload.mountain or {}
            local biome = payload.biome or {}
            local container = payload.container

            local wallMatName = biome.terrainWall or "Rock"
            local wallMaterial = Enum.Material[wallMatName]

            if not wallMaterial then
                warn("[MountainTerrainPainter] Invalid wall material: " .. wallMatName)
                wallMaterial = Enum.Material.Rock
            end

            ----------------------------------------------------------------
            -- 1. Hide blockout Parts + collect wedge instances
            ----------------------------------------------------------------

            local wedges = {}

            if container then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("BasePart") then
                        if child.Name:match("^Mountain_") or child.Name:match("^Slope_") then
                            child.Transparency = 1
                            child.CanCollide = false
                        end
                        if child:IsA("WedgePart") and child.Name:match("^Slope_") then
                            table.insert(wedges, child)
                        end
                    end
                end
            end

            -- Use buffer if available (orchestrator-managed), else fall back to Canvas
            local buf = payload.buffer

            ----------------------------------------------------------------
            -- 2. Fill mountain volumes with terrain
            ----------------------------------------------------------------

            for _, vol in ipairs(mountain) do
                local cf = CFrame.new(vol.position[1], vol.position[2], vol.position[3])
                local sz = Vector3.new(vol.dims[1], vol.dims[2], vol.dims[3])
                if buf then
                    buf:fillBlock(cf, sz, wallMaterial)
                else
                    Canvas.fillBlock(cf, sz, wallMaterial)
                end
            end

            ----------------------------------------------------------------
            -- 3. Fill slope wedges with terrain
            ----------------------------------------------------------------

            for _, wedge in ipairs(wedges) do
                if buf then
                    buf:fillWedge(wedge.CFrame, wedge.Size, wallMaterial)
                else
                    Canvas.fillWedge(wedge.CFrame, wedge.Size, wallMaterial)
                end
            end

            ----------------------------------------------------------------
            -- 4. Fill slope corners with voxel layers
            -- Each corner is the gap between two perpendicular face slopes.
            -- At each Y layer, the slope's run shrinks linearly (full at
            -- bottom, zero at top), so we fill a shrinking block per layer.
            ----------------------------------------------------------------

            local VOXEL = 4
            local CORNER_DEFS = {
                { xFace = "E", zFace = "N", xDir =  1, zDir =  1 },
                { xFace = "W", zFace = "N", xDir = -1, zDir =  1 },
                { xFace = "E", zFace = "S", xDir =  1, zDir = -1 },
                { xFace = "W", zFace = "S", xDir = -1, zDir = -1 },
            }

            local cornerFills = 0
            for _, vol in ipairs(mountain) do
                local oh = vol.overhangs
                if not oh then continue end

                local height = vol.dims[2]
                local bottom = vol.position[2] - height / 2
                local layers = math.floor(height / VOXEL)

                for _, corner in ipairs(CORNER_DEFS) do
                    local ohX = oh[corner.xFace] or 0
                    local ohZ = oh[corner.zFace] or 0
                    if ohX <= 0 or ohZ <= 0 then continue end

                    local cornerX = vol.position[1]
                        + corner.xDir * vol.dims[1] / 2
                    local cornerZ = vol.position[3]
                        + corner.zDir * vol.dims[3] / 2

                    for i = 0, layers - 1 do
                        -- Slope: full run at bottom, zero at top
                        local progress = (i + 1) / layers
                        local xExtent = ohX * (1 - progress)
                        local zExtent = ohZ * (1 - progress)

                        if xExtent < VOXEL or zExtent < VOXEL then continue end

                        local y = bottom + (i + 0.5) * VOXEL
                        local cx = cornerX + corner.xDir * xExtent / 2
                        local cz = cornerZ + corner.zDir * zExtent / 2

                        local cf = CFrame.new(cx, y, cz)
                        local sz = Vector3.new(xExtent, VOXEL, zExtent)
                        if buf then
                            buf:fillBlock(cf, sz, wallMaterial)
                        else
                            Canvas.fillBlock(cf, sz, wallMaterial)
                        end
                        cornerFills = cornerFills + 1
                    end
                end
            end

            print(string.format(
                "[MountainTerrainPainter] Filled %d volumes + %d wedges + %d corner voxels with %s — %.2fs",
                #mountain, #wedges, cornerFills, wallMatName, os.clock() - t0
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
