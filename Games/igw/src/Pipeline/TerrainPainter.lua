--[[
    IGW v2 Pipeline — TerrainPainter
    Post-mount: paints terrain shells, carves interiors, carves doorways,
    adds lava veins, floor material, granite patches, and fixture clearance.
--]]

return {
    name = "TerrainPainter",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildPass = function(self, payload)
            local biome = payload.biome or {}

            local t0 = os.clock()

            -- Outdoor biomes use IceTerrainPainter instead; pass through
            if biome.terrainStyle == "outdoor" then
                self.Out:Fire("buildPass", payload)
                return
            end

            local Dom = self._System.Dom
            local Canvas = Dom.Canvas
            local StyleBridge = self._System.StyleBridge
            local Styles = self._System.Styles
            local ClassResolver = self._System.ClassResolver

            local rooms = payload.rooms
            local portalAssignments = payload.portalAssignments or {}
            local lights = payload.lights or {}
            local pads = payload.pads or {}
            local regionNum = payload.regionNum or 1
            local paletteClass = payload.paletteClass or StyleBridge.getPaletteClass(regionNum)

            -- Resolve palette colors for terrain materials
            local palette = StyleBridge.resolvePalette(paletteClass, Styles, ClassResolver)

            local biome = payload.biome or {}
            local wallMaterialName = biome.terrainWall or self:getAttribute("wallMaterial") or "Rock"
            local floorMaterialName = biome.terrainFloor or self:getAttribute("floorMaterial") or "CrackedLava"
            local wallMaterial = Enum.Material[wallMaterialName]
            local floorMaterial = Enum.Material[floorMaterialName]
            local noiseScale = self:getAttribute("noiseScale") or 8
            local noiseThreshold = self:getAttribute("noiseThreshold") or 0.35
            local patchScale = self:getAttribute("patchScale") or 12
            local patchThreshold = self:getAttribute("patchThreshold") or 0.4

            -- Set terrain material colors (parameterized for biome)
            Canvas.setMaterialColors(palette, wallMaterial, floorMaterial)

            -- Use buffer if available (orchestrator-managed), else fall back to Canvas
            local buf = payload.buffer

            -- PASS 1: Fill terrain shells (skip portal rooms)
            for id, room in pairs(rooms) do
                if not portalAssignments[id] then
                    if buf then
                        buf:fillShell(room.position, room.dims, 0, wallMaterial)
                    else
                        Canvas.fillShell(room.position, room.dims, 0, wallMaterial)
                    end
                end
            end

            -- PASS 2: Carve interiors (skip portal rooms)
            for id, room in pairs(rooms) do
                if not portalAssignments[id] then
                    if buf then
                        buf:carveInterior(room.position, room.dims, 0)
                    else
                        Canvas.carveInterior(room.position, room.dims, 0)
                    end
                end
            end

            -- PASS 3: Paint lava veins (skip portal rooms)
            for id, room in pairs(rooms) do
                if not portalAssignments[id] then
                    local opts = {
                        roomPos = room.position,
                        roomDims = room.dims,
                        material = floorMaterial,
                        noiseScale = noiseScale,
                        threshold = noiseThreshold,
                    }
                    if buf then
                        buf:paintNoise(opts)
                    else
                        Canvas.paintNoise(opts)
                    end
                end
            end

            -- PASS 4: Paint floors (skip portal rooms)
            for id, room in pairs(rooms) do
                if not portalAssignments[id] then
                    if buf then
                        buf:paintFloor(room.position, room.dims, floorMaterial)
                    else
                        Canvas.paintFloor(room.position, room.dims, floorMaterial)
                    end
                end
            end

            -- PASS 5: Mix granite patches (skip portal rooms)
            for id, room in pairs(rooms) do
                if not portalAssignments[id] then
                    local opts = {
                        roomPos = room.position,
                        roomDims = room.dims,
                        material = wallMaterial,
                        noiseScale = patchScale,
                        threshold = patchThreshold,
                    }
                    if buf then
                        buf:mixPatches(opts)
                    else
                        Canvas.mixPatches(opts)
                    end
                end
            end

            -- Carve clearance around lights (only if position data present)
            for _, light in ipairs(lights) do
                if light.position and light.size then
                    local fixturePos = Vector3.new(light.position[1], light.position[2], light.position[3])
                    local fixtureSize = Vector3.new(light.size[1], light.size[2], light.size[3])
                    if buf then
                        buf:carveMargin(CFrame.new(fixturePos), fixtureSize, 2)
                    else
                        Canvas.carveMargin(CFrame.new(fixturePos), fixtureSize, 2)
                    end
                end
            end

            -- Carve clearance around pads (only if position data present)
            for _, pad in ipairs(pads) do
                if pad.position then
                    local padPos = Vector3.new(pad.position[1], pad.position[2], pad.position[3])
                    local padSize = Vector3.new(6, 1, 6)
                    if buf then
                        buf:carveMargin(CFrame.new(padPos), padSize, 2)
                    else
                        Canvas.carveMargin(CFrame.new(padPos), padSize, 2)
                    end
                end
            end

            -- Count rooms for report
            local roomCount = 0
            for _ in pairs(rooms) do roomCount = roomCount + 1 end

            print(string.format("[TerrainPainter] Painted terrain for %d rooms — %.2fs", roomCount, os.clock() - t0))

            payload.roomCount = roomCount
            payload.doorCount = payload.doors and #payload.doors or 0

            self.Out:Fire("buildPass", payload)
        end,
    },
}
