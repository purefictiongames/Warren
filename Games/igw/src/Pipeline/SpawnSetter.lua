--[[
    IGW v2 Pipeline — SpawnSetter
    Picks a safe default spawn room and creates a SpawnLocation element.

    Avoids rooms with floor holes (vertical doors) so the player doesn't
    fall through on spawn. Walks main-path rooms in order, picks the first
    one with no vertical connections.

    The orchestrator may override this spawn position after the build
    completes (e.g. portal transitions spawn at the return portal room).
--]]

return {
    name = "SpawnSetter",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildPass = function(self, payload)
            local Dom = self._System.Dom
            local rooms = payload.rooms
            local doors = payload.doors or {}

            -- Build set of rooms with vertical doors (floor/ceiling holes)
            local hasFloorHole = {}
            for _, door in ipairs(doors) do
                if door.axis == 2 then
                    hasFloorHole[door.fromRoom] = true
                    hasFloorHole[door.toRoom] = true
                end
            end

            -- Walk main-path rooms in order, pick the first with no floor hole
            local spawnRoom = nil
            for id = 1, 999 do
                local room = rooms[id]
                if not room then break end
                if room.pathType == "main" and not hasFloorHole[id] then
                    spawnRoom = room
                    break
                end
            end

            -- Fallback: room 1
            if not spawnRoom and rooms[1] then
                spawnRoom = rooms[1]
            end

            if spawnRoom then
                local floorY = spawnRoom.position[2] - spawnRoom.dims[2] / 2 + 3

                Dom.appendChild(payload.dom, Dom.createElement("SpawnLocation", {
                    class = "cave-spawn",
                    Name = "Spawn_Region_" .. (payload.regionNum or 1),
                    Size = { 6, 1, 6 },
                    Position = { spawnRoom.position[1], floorY, spawnRoom.position[3] },
                }))

                payload.spawn = {
                    position = { spawnRoom.position[1], floorY, spawnRoom.position[3] },
                    roomId = spawnRoom.id,
                }

                print(string.format("[SpawnSetter] Spawn at room %d (%.1f, %.1f, %.1f)",
                    spawnRoom.id, spawnRoom.position[1], floorY, spawnRoom.position[3]))
            end

            self.Out:Fire("buildPass", payload)
        end,
    },
}
