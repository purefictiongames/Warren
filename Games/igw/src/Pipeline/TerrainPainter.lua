--[[
    IGW v2 Pipeline — TerrainPainter
    Post-mount: paints terrain shells, carves interiors, carves doorways,
    adds lava veins, floor material, granite patches, and fixture clearance.
--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node
local Dom = Warren.Dom
local Canvas = Dom.Canvas
local StyleBridge = Dom.StyleBridge
local Styles = Warren.Styles
local ClassResolver = Warren.ClassResolver

local TerrainPainter = Node.extend({
    name = "TerrainPainter",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildPass = function(self, payload)
            local rooms = payload.rooms
            local lights = payload.lights or {}
            local pads = payload.pads or {}
            local regionNum = payload.regionNum or 1
            local paletteClass = payload.paletteClass or StyleBridge.getPaletteClass(regionNum)

            -- Resolve palette colors for terrain materials
            local palette = StyleBridge.resolvePalette(paletteClass, Styles, ClassResolver)

            local wallMaterial = Enum.Material.Rock
            local floorMaterial = Enum.Material.CrackedLava

            -- Set terrain material colors
            Canvas.setMaterialColors(palette)

            -- PASS 1: Fill terrain shells
            for _, room in pairs(rooms) do
                Canvas.fillShell(room.position, room.dims, 0, wallMaterial)
            end

            -- PASS 2: Carve interiors
            for _, room in pairs(rooms) do
                Canvas.carveInterior(room.position, room.dims, 0)
            end

            -- PASS 3: Paint lava veins
            for _, room in pairs(rooms) do
                Canvas.paintNoise({
                    roomPos = room.position,
                    roomDims = room.dims,
                    material = floorMaterial,
                    noiseScale = 8,
                    threshold = 0.35,
                })
            end

            -- PASS 4: Paint floors
            for _, room in pairs(rooms) do
                Canvas.paintFloor(room.position, room.dims, floorMaterial)
            end

            -- PASS 5: Mix granite patches
            for _, room in pairs(rooms) do
                Canvas.mixPatches({
                    roomPos = room.position,
                    roomDims = room.dims,
                    material = wallMaterial,
                    noiseScale = 12,
                    threshold = 0.4,
                })
            end

            -- Carve clearance around lights
            for _, light in ipairs(lights) do
                local fixturePos = Vector3.new(light.position[1], light.position[2], light.position[3])
                local fixtureSize = Vector3.new(light.size[1], light.size[2], light.size[3])
                Canvas.carveMargin(CFrame.new(fixturePos), fixtureSize, 2)
            end

            -- Carve clearance around pads
            for _, pad in ipairs(pads) do
                local padPos = Vector3.new(pad.position[1], pad.position[2], pad.position[3])
                local padSize = Vector3.new(6, 1, 6)
                Canvas.carveMargin(CFrame.new(padPos), padSize, 2)
            end

            -- Count rooms for report
            local roomCount = 0
            for _ in pairs(rooms) do roomCount = roomCount + 1 end

            print(string.format("[TerrainPainter] Painted terrain for %d rooms", roomCount))

            payload.roomCount = roomCount
            payload.doorCount = payload.doors and #payload.doors or 0

            self.Out:Fire("buildPass", payload)
        end,
    },
})

return TerrainPainter
