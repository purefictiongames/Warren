--[[
    IGW v2 Pipeline — SpawnSetter
    Creates SpawnLocation element at room 1's floor + 3 studs.
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
            local room1 = rooms[1]

            if room1 then
                local floorY = room1.position[2] - room1.dims[2] / 2 + 3

                Dom.appendChild(payload.dom, Dom.createElement("SpawnLocation", {
                    class = "cave-spawn",
                    Name = "Spawn_Region_" .. (payload.regionNum or 1),
                    Size = { 6, 1, 6 },
                    Position = { room1.position[1], floorY, room1.position[3] },
                }))

                payload.spawn = {
                    position = { room1.position[1], floorY, room1.position[3] },
                    roomId = 1,
                }

                print(string.format("[SpawnSetter] Spawn at (%.1f, %.1f, %.1f)",
                    room1.position[1], floorY, room1.position[3]))
            end

            self.Out:Fire("buildPass", payload)
        end,
    },
}
