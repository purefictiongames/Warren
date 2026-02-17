--[[
    IGW v2 Pipeline — TrussBuilder
    Creates TrussPart elements for doors that need vertical connectors.
    Plan phase: adds DOM elements before mount.
--]]

return {
    name = "TrussBuilder",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildTrusses = function(self, payload)
            local Dom = self._System.Dom
            local rooms = payload.rooms
            local doors = payload.doors or {}
            local floorThreshold = self:getAttribute("floorThreshold") or 6.5
            local wt = self:getAttribute("wallThickness") or 1
            local trusses = {}
            local trussId = 1

            for _, door in ipairs(doors) do
                local roomA = rooms[door.fromRoom]
                local roomB = rooms[door.toRoom]
                if not (roomA and roomB) then continue end

                if door.axis == 2 then
                    -- Ceiling hole: truss from lower floor to upper floor
                    local lowerRoom, upperRoom
                    if roomA.position[2] < roomB.position[2] then
                        lowerRoom, upperRoom = roomA, roomB
                    else
                        lowerRoom, upperRoom = roomB, roomA
                    end

                    local lowerFloor = lowerRoom.position[2] - lowerRoom.dims[2] / 2
                    local upperFloor = upperRoom.position[2] - upperRoom.dims[2] / 2
                    local trussHeight = upperFloor - lowerFloor

                    local trussX = door.center[1] - door.width / 2 + 1

                    Dom.appendChild(payload.dom, Dom.createElement("TrussPart", {
                        class = "cave-truss",
                        Name = "Truss_" .. trussId,
                        Size = { 2, trussHeight, 2 },
                        Position = { trussX, lowerFloor + trussHeight / 2, door.center[3] },
                    }))

                    table.insert(trusses, {
                        id = trussId,
                        doorId = door.id,
                        type = "ceiling",
                    })
                    trussId = trussId + 1
                else
                    -- Wall hole: check each room independently
                    for _, entry in ipairs({
                        { room = roomA, id = door.fromRoom },
                        { room = roomB, id = door.toRoom },
                    }) do
                        local room = entry.room
                        local wallBottom = room.position[2] - room.dims[2] / 2
                        local holeBottom = door.bottom
                        local dist = holeBottom - wallBottom

                        if dist > floorThreshold then
                            local trussPos = {
                                door.center[1],
                                wallBottom + dist / 2,
                                door.center[3],
                            }
                            local dirToRoom = room.position[door.axis] > door.center[door.axis] and 1 or -1
                            trussPos[door.axis] = door.center[door.axis] + dirToRoom * (wt / 2 + 1)

                            Dom.appendChild(payload.dom, Dom.createElement("TrussPart", {
                                class = "cave-truss",
                                Name = "Truss_" .. trussId,
                                Size = { 2, dist, 2 },
                                Position = { trussPos[1], trussPos[2], trussPos[3] },
                            }))

                            table.insert(trusses, {
                                id = trussId,
                                doorId = door.id,
                                type = "wall",
                            })
                            trussId = trussId + 1
                        end
                    end
                end
            end

            payload.trusses = trusses
            print(string.format("[TrussBuilder] Built %d trusses", #trusses))
            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
