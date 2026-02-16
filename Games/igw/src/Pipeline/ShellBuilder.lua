--[[
    IGW v2 Pipeline — ShellBuilder
    Creates wall/floor/ceiling Part children and zone Part for each room.
--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node
local Dom = Warren.Dom

local ShellBuilder = Node.extend({
    name = "ShellBuilder",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildPass = function(self, payload)
            local rooms = payload.rooms
            local config = payload.config
            local paletteClass = payload.paletteClass or ""
            local wt = config.wallThickness or 1
            local regionNum = payload.regionNum or 1

            -- Find room DOM Models by name
            local roomModels = {}
            for _, child in ipairs(Dom.getChildren(payload.dom)) do
                local roomId = Dom.getAttribute(child, "RoomId")
                if roomId then
                    roomModels[roomId] = child
                end
            end

            for id, room in pairs(rooms) do
                local roomModel = roomModels[id]
                if not roomModel then continue end

                local pos = room.position
                local dims = room.dims

                -- Floor
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = "cave-floor " .. paletteClass,
                    Name = "Floor",
                    Size = { dims[1] + 2*wt, wt, dims[3] + 2*wt },
                    Position = { pos[1], pos[2] - dims[2]/2 - wt/2, pos[3] },
                }))

                -- Ceiling
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = "cave-ceiling " .. paletteClass,
                    Name = "Ceiling",
                    Size = { dims[1] + 2*wt, wt, dims[3] + 2*wt },
                    Position = { pos[1], pos[2] + dims[2]/2 + wt/2, pos[3] },
                }))

                -- North wall (+Z)
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = "cave-wall " .. paletteClass,
                    Name = "Wall_N",
                    Size = { dims[1] + 2*wt, dims[2], wt },
                    Position = { pos[1], pos[2], pos[3] + dims[3]/2 + wt/2 },
                }))

                -- South wall (-Z)
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = "cave-wall " .. paletteClass,
                    Name = "Wall_S",
                    Size = { dims[1] + 2*wt, dims[2], wt },
                    Position = { pos[1], pos[2], pos[3] - dims[3]/2 - wt/2 },
                }))

                -- East wall (+X)
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = "cave-wall " .. paletteClass,
                    Name = "Wall_E",
                    Size = { wt, dims[2], dims[3] },
                    Position = { pos[1] + dims[1]/2 + wt/2, pos[2], pos[3] },
                }))

                -- West wall (-X)
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = "cave-wall " .. paletteClass,
                    Name = "Wall_W",
                    Size = { wt, dims[2], dims[3] },
                    Position = { pos[1] - dims[1]/2 - wt/2, pos[2], pos[3] },
                }))

                -- Invisible zone part for player detection
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = "cave-zone",
                    Name = "RoomZone_" .. id,
                    Size = { dims[1], dims[2], dims[3] },
                    Position = { pos[1], pos[2], pos[3] },
                    RoomId = id,
                    RegionNum = regionNum,
                }))
            end

            self.Out:Fire("buildPass", payload)
        end,
    },
})

return ShellBuilder
