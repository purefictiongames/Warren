--[[
    IGW v2 Pipeline — MountainLightBuilder
    Places light sources under the floor of rooms whose center is inside
    a mountain volume. The terrain buries the fixture, producing ambient
    light with no visible source.
    Plan phase: adds DOM elements before mount.
--]]

local function pointInsideVolume(pos, vol)
    for axis = 1, 3 do
        local half = vol.dims[axis] / 2
        if pos[axis] < vol.position[axis] - half
            or pos[axis] > vol.position[axis] + half then
            return false
        end
    end
    return true
end

local function isInsideMountain(roomPos, mountain)
    for _, vol in ipairs(mountain) do
        if pointInsideVolume(roomPos, vol) then
            return true
        end
    end
    return false
end

return {
    name = "MountainLightBuilder",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildLights = function(self, payload)
            local Dom = self._System.Dom
            local rooms = payload.rooms
            local mountain = payload.mountain or {}
            local biome = payload.biome or {}
            local paletteClass = payload.paletteClass or ""
            local lights = {}
            local lightId = 1

            local lightType = biome.lightType or "PointLight"
            local lightStyle = biome.lightStyle or "cave-point-light"

            -- Find room DOM models by attribute
            local roomModels = {}
            for _, child in ipairs(Dom.getChildren(payload.dom)) do
                local rid = Dom.getAttribute(child, "RoomId")
                if rid then
                    roomModels[rid] = child
                end
            end

            local skipped = 0
            for id, room in pairs(rooms) do
                if not isInsideMountain(room.position, mountain) then
                    skipped = skipped + 1
                    continue
                end

                -- Place light source under the floor center, buried in terrain
                local floorY = room.position[2] - room.dims[2] / 2
                local lightPos = {
                    room.position[1],
                    floorY - 2,
                    room.position[3],
                }

                local parent = roomModels[id] or payload.dom

                local fixture = Dom.createElement("Part", {
                    class = "cave-light-fixture " .. paletteClass,
                    Name = "Light_" .. lightId,
                    Size = { 1, 1, 1 },
                    Position = lightPos,
                    Transparency = 1,
                    CanCollide = false,
                })
                Dom.appendChild(fixture, Dom.createElement(lightType, {
                    class = lightStyle .. " " .. paletteClass,
                    Name = lightType,
                }))
                Dom.appendChild(parent, fixture)

                table.insert(lights, {
                    id = lightId,
                    roomId = id,
                })
                lightId = lightId + 1
            end

            payload.lights = lights
            print(string.format(
                "[MountainLightBuilder] Built %d buried lights (%d surface rooms skipped)",
                #lights, skipped
            ))
            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
