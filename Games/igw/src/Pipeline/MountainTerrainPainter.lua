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
            -- 1. Hide mountain blockout Parts
            ----------------------------------------------------------------

            if container then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("BasePart") and child.Name:match("^Mountain_") then
                        child.Transparency = 1
                        child.CanCollide = false
                    end
                end
            end

            ----------------------------------------------------------------
            -- 2. Fill mountain volumes with terrain
            ----------------------------------------------------------------

            for _, vol in ipairs(mountain) do
                Canvas.fillBlock(
                    CFrame.new(vol.position[1], vol.position[2], vol.position[3]),
                    Vector3.new(vol.dims[1], vol.dims[2], vol.dims[3]),
                    wallMaterial
                )
            end

            print(string.format(
                "[MountainTerrainPainter] Filled %d mountain volumes with %s — %.2fs",
                #mountain, wallMatName, os.clock() - t0
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
