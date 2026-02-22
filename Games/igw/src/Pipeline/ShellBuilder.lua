--[[
    IGW v2 Pipeline — ShellBuilder
    Creates wall/floor/ceiling Part children and zone Part for each room.
--]]

return {
    name = "ShellBuilder",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildShells = function(self, payload)
            local Dom = self._System.Dom
            local rooms = payload.rooms
            local paletteClass = payload.paletteClass or ""
            local wt = self:getAttribute("wallThickness") or 1
            local regionNum = payload.regionNum or 1
            local biome = payload.biome or {}
            local isOutdoor = biome.terrainStyle == "outdoor"

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

                -- Outdoor biomes: walls start as ice-wall-clear (transparent);
                -- IceTerrainPainter promotes door walls to ice-wall-solid later.
                local wallClass = "cave-wall " .. paletteClass
                    .. (isOutdoor and " ice-wall-clear" or "")
                local ceilingClass = "cave-ceiling " .. paletteClass
                    .. (isOutdoor and " ice-wall-clear" or "")
                local floorClass = "cave-floor " .. paletteClass
                    .. (isOutdoor and " ice-wall-clear" or "")

                -- Floor (biome.partFloor overrides class style when present)
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = floorClass,
                    Material = biome.partFloor,
                    Name = "Floor",
                    Size = { dims[1] + 2*wt, wt, dims[3] + 2*wt },
                    Position = { pos[1], pos[2] - dims[2]/2 - wt/2, pos[3] },
                }))

                -- Ceiling
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = ceilingClass,
                    Material = biome.partWall,
                    Name = "Ceiling",
                    Size = { dims[1] + 2*wt, wt, dims[3] + 2*wt },
                    Position = { pos[1], pos[2] + dims[2]/2 + wt/2, pos[3] },
                }))

                -- North wall (+Z)
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = wallClass,
                    Material = biome.partWall,
                    Name = "Wall_N",
                    Size = { dims[1] + 2*wt, dims[2], wt },
                    Position = { pos[1], pos[2], pos[3] + dims[3]/2 + wt/2 },
                }))

                -- South wall (-Z)
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = wallClass,
                    Material = biome.partWall,
                    Name = "Wall_S",
                    Size = { dims[1] + 2*wt, dims[2], wt },
                    Position = { pos[1], pos[2], pos[3] - dims[3]/2 - wt/2 },
                }))

                -- East wall (+X)
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = wallClass,
                    Material = biome.partWall,
                    Name = "Wall_E",
                    Size = { wt, dims[2], dims[3] },
                    Position = { pos[1] + dims[1]/2 + wt/2, pos[2], pos[3] },
                }))

                -- West wall (-X)
                Dom.appendChild(roomModel, Dom.createElement("Part", {
                    class = wallClass,
                    Material = biome.partWall,
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

                -- Store geometry metadata for downstream nodes (MiniMap)
                Dom.setAttribute(roomModel, "ShellData", {
                    wallThickness = wt,
                    floor   = { size = {dims[1]+2*wt, wt, dims[3]+2*wt},      pos = {pos[1], pos[2]-dims[2]/2-wt/2, pos[3]} },
                    ceiling = { size = {dims[1]+2*wt, wt, dims[3]+2*wt},      pos = {pos[1], pos[2]+dims[2]/2+wt/2, pos[3]} },
                    walls = {
                        N = { size = {dims[1]+2*wt, dims[2], wt}, pos = {pos[1], pos[2], pos[3]+dims[3]/2+wt/2} },
                        S = { size = {dims[1]+2*wt, dims[2], wt}, pos = {pos[1], pos[2], pos[3]-dims[3]/2-wt/2} },
                        E = { size = {wt, dims[2], dims[3]},      pos = {pos[1]+dims[1]/2+wt/2, pos[2], pos[3]} },
                        W = { size = {wt, dims[2], dims[3]},      pos = {pos[1]-dims[1]/2-wt/2, pos[2], pos[3]} },
                    },
                })
            end

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
