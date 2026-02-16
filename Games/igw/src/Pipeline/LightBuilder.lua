--[[
    IGW v2 Pipeline — LightBuilder
    Places one light fixture per room on a wall without a door.
--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node
local Dom = Warren.Dom

local WALL_ORDER = { "N", "S", "E", "W" }

local LightBuilder = Node.extend({
    name = "LightBuilder",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildPass = function(self, payload)
            local rooms = payload.rooms
            local doors = payload.doors or {}
            local paletteClass = payload.paletteClass or ""
            local lights = {}
            local lightId = 1

            -- Build door faces map per room
            local roomDoorFaces = {}
            for _, door in ipairs(doors) do
                local roomA = rooms[door.fromRoom]
                local roomB = rooms[door.toRoom]
                if not (roomA and roomB) then continue end

                if door.axis == 1 then
                    if roomA.position[1] < roomB.position[1] then
                        roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                        roomDoorFaces[door.fromRoom]["E"] = true
                        roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                        roomDoorFaces[door.toRoom]["W"] = true
                    else
                        roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                        roomDoorFaces[door.fromRoom]["W"] = true
                        roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                        roomDoorFaces[door.toRoom]["E"] = true
                    end
                elseif door.axis == 3 then
                    if roomA.position[3] < roomB.position[3] then
                        roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                        roomDoorFaces[door.fromRoom]["N"] = true
                        roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                        roomDoorFaces[door.toRoom]["S"] = true
                    else
                        roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                        roomDoorFaces[door.fromRoom]["S"] = true
                        roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                        roomDoorFaces[door.toRoom]["N"] = true
                    end
                end
            end

            -- Find room DOM models by attribute
            local roomModels = {}
            for _, child in ipairs(Dom.getChildren(payload.dom)) do
                local rid = Dom.getAttribute(child, "RoomId")
                if rid then
                    roomModels[rid] = child
                end
            end

            for id, room in pairs(rooms) do
                local doorFaces = roomDoorFaces[id] or {}

                -- Pick first wall without a door
                local chosenWall = nil
                for _, wallName in ipairs(WALL_ORDER) do
                    if not doorFaces[wallName] then
                        chosenWall = wallName
                        break
                    end
                end
                chosenWall = chosenWall or "N"

                local wallDef = {
                    N = { axis = 3, dir = 1, sizeAxis = 1 },
                    S = { axis = 3, dir = -1, sizeAxis = 1 },
                    E = { axis = 1, dir = 1, sizeAxis = 3 },
                    W = { axis = 1, dir = -1, sizeAxis = 3 },
                }
                local wall = wallDef[chosenWall]

                local wallWidth = room.dims[wall.sizeAxis]
                local stripWidth = math.clamp(wallWidth * 0.5, 4, 12)

                local lightPos = {
                    room.position[1],
                    room.position[2] + room.dims[2] / 2 - 2,
                    room.position[3],
                }
                lightPos[wall.axis] = room.position[wall.axis] + wall.dir * (room.dims[wall.axis] / 2 - 0.1)

                local lightSize
                if wall.sizeAxis == 1 then
                    lightSize = { stripWidth, 1, 0.3 }
                else
                    lightSize = { 0.3, 1, stripWidth }
                end

                -- Wall direction for spacer offset
                local wallDirs = {
                    N = {0, 0, 1}, S = {0, 0, -1},
                    E = {1, 0, 0}, W = {-1, 0, 0},
                }
                local wallDir = wallDirs[chosenWall]
                local spacerThickness = 1.5
                local spacerSize, spacerOffset

                if math.abs(wallDir[1]) > 0 then
                    spacerSize = { spacerThickness, lightSize[2], lightSize[3] }
                    spacerOffset = { wallDir[1] * (lightSize[1]/2 + spacerThickness/2), 0, 0 }
                else
                    spacerSize = { lightSize[1], lightSize[2], spacerThickness }
                    spacerOffset = { 0, 0, wallDir[3] * (lightSize[3]/2 + spacerThickness/2) }
                end

                local parent = roomModels[id] or payload.dom

                -- Spacer
                Dom.appendChild(parent, Dom.createElement("Part", {
                    class = "cave-light-spacer " .. paletteClass,
                    Name = "Light_" .. lightId .. "_Spacer",
                    Size = spacerSize,
                    Position = {
                        lightPos[1] + spacerOffset[1],
                        lightPos[2] + spacerOffset[2],
                        lightPos[3] + spacerOffset[3],
                    },
                }))

                -- Fixture with PointLight child
                local fixture = Dom.createElement("Part", {
                    class = "cave-light-fixture " .. paletteClass,
                    Name = "Light_" .. lightId,
                    Size = lightSize,
                    Position = lightPos,
                })
                Dom.appendChild(fixture, Dom.createElement("PointLight", {
                    class = "cave-point-light " .. paletteClass,
                    Name = "PointLight",
                }))
                Dom.appendChild(parent, fixture)

                table.insert(lights, {
                    id = lightId,
                    roomId = id,
                    position = lightPos,
                    size = lightSize,
                    wall = chosenWall,
                })
                lightId = lightId + 1
            end

            payload.lights = lights

            print(string.format("[LightBuilder] Built %d lights", #lights))

            self.Out:Fire("buildPass", payload)
        end,
    },
})

return LightBuilder
