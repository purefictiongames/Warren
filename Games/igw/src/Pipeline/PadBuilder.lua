--[[
    IGW v2 Pipeline — PadBuilder
    Places teleport pads in safe floor positions (avoids doors, trusses).
--]]

--------------------------------------------------------------------------------
-- SAFE POSITION FINDING (inline from LayoutContext)
--------------------------------------------------------------------------------

local function positionConflictsWithDoor(pos, radius, doors)
    for _, door in ipairs(doors) do
        local dx = math.abs(pos[1] - door.center[1])
        local dy = math.abs(pos[2] - door.center[2])
        local dz = math.abs(pos[3] - door.center[3])

        local halfW = door.width / 2 + radius
        local halfH = door.height / 2 + radius

        if door.axis == 2 then
            if dx < halfW and dz < halfH then
                return true
            end
        elseif door.axis == 1 then
            if dz < halfW and dy < halfH and dx < radius then
                return true
            end
        else
            if dx < halfW and dy < halfH and dz < radius then
                return true
            end
        end
    end
    return false
end

local function positionConflictsWithObject(pos, radius, trusses, pads, lights)
    -- Check trusses
    for _, truss in ipairs(trusses) do
        local dx = math.abs(pos[1] - truss.position[1])
        local dy = math.abs(pos[2] - truss.position[2])
        local dz = math.abs(pos[3] - truss.position[3])

        if dx < truss.size[1]/2 + radius and
           dy < truss.size[2]/2 + radius and
           dz < truss.size[3]/2 + radius then
            return true
        end

        if truss.type == "ceiling" then
            local ceilingRadius = radius + 2
            if dx < truss.size[1]/2 + ceilingRadius and
               dz < truss.size[3]/2 + ceilingRadius then
                return true
            end
        end
    end

    -- Check existing pads
    for _, pad in ipairs(pads) do
        local dx = math.abs(pos[1] - pad.position[1])
        local dz = math.abs(pos[3] - pad.position[3])
        if dx < 3 + radius and dz < 3 + radius then
            return true
        end
    end

    -- Check lights
    for _, light in ipairs(lights) do
        local dx = math.abs(pos[1] - light.position[1])
        local dy = math.abs(pos[2] - light.position[2])
        local dz = math.abs(pos[3] - light.position[3])
        if dx < light.size[1]/2 + radius and
           dy < light.size[2]/2 + radius and
           dz < light.size[3]/2 + radius then
            return true
        end
    end

    return false
end

local function findSafeFloorPosition(room, doors, trusses, pads, lights)
    local floorY = room.position[2] - room.dims[2] / 2 + 0.5

    local candidates = {
        { room.position[1], floorY, room.position[3] },
        { room.position[1] - room.dims[1]/4, floorY, room.position[3] - room.dims[3]/4 },
        { room.position[1] + room.dims[1]/4, floorY, room.position[3] - room.dims[3]/4 },
        { room.position[1] - room.dims[1]/4, floorY, room.position[3] + room.dims[3]/4 },
        { room.position[1] + room.dims[1]/4, floorY, room.position[3] + room.dims[3]/4 },
        { room.position[1] - room.dims[1]/3, floorY, room.position[3] },
        { room.position[1] + room.dims[1]/3, floorY, room.position[3] },
        { room.position[1], floorY, room.position[3] - room.dims[3]/3 },
        { room.position[1], floorY, room.position[3] + room.dims[3]/3 },
        { room.position[1] - room.dims[1]/6, floorY, room.position[3] - room.dims[3]/6 },
        { room.position[1] + room.dims[1]/6, floorY, room.position[3] - room.dims[3]/6 },
        { room.position[1] - room.dims[1]/6, floorY, room.position[3] + room.dims[3]/6 },
        { room.position[1] + room.dims[1]/6, floorY, room.position[3] + room.dims[3]/6 },
    }

    local checkRadius = 4
    for _, pos in ipairs(candidates) do
        if not positionConflictsWithDoor(pos, checkRadius, doors) and
           not positionConflictsWithObject(pos, checkRadius, trusses, pads, lights) then
            return pos
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- NODE
--------------------------------------------------------------------------------

return {
    name = "PadBuilder",
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
            local trusses = payload.trusses or {}
            local lights = payload.lights or {}
            local paletteClass = payload.paletteClass or ""

            local roomCount = 0
            for _ in pairs(rooms) do roomCount = roomCount + 1 end

            local padCount = self:getAttribute("padCount") or 4
            local pads = {}
            local padNum = 1

            -- Find room DOM models by attribute
            local roomModels = {}
            for _, child in ipairs(Dom.getChildren(payload.dom)) do
                local rid = Dom.getAttribute(child, "RoomId")
                if rid then
                    roomModels[rid] = child
                end
            end

            -- Select rooms for pads (start from room 2, room 1 is spawn)
            local step = math.max(1, math.floor((roomCount - 1) / padCount))
            local roomId = 2

            for i = 1, padCount do
                if roomId > roomCount then break end

                local room = rooms[roomId]
                if room then
                    local safePos = findSafeFloorPosition(room, doors, trusses, pads, lights)

                    if not safePos and roomId + 1 <= roomCount then
                        roomId = roomId + 1
                        room = rooms[roomId]
                        if room then
                            safePos = findSafeFloorPosition(room, doors, trusses, pads, lights)
                        end
                    end

                    if safePos then
                        safePos[2] = safePos[2] + 0.1
                        local padId = "pad_" .. padNum
                        local padSize = {6, 1, 6}

                        local parent = roomModels[roomId] or payload.dom
                        local baseThickness = 1.5

                        -- Base
                        Dom.appendChild(parent, Dom.createElement("Part", {
                            class = "cave-pad-base " .. paletteClass,
                            Name = padId .. "_Base",
                            Size = { padSize[1], baseThickness, padSize[3] },
                            Position = {
                                safePos[1],
                                safePos[2] - (padSize[2] + baseThickness) / 2,
                                safePos[3],
                            },
                        }))

                        -- Pad surface
                        Dom.appendChild(parent, Dom.createElement("Part", {
                            class = "cave-pad",
                            Name = padId,
                            Size = padSize,
                            Position = safePos,
                            TeleportPad = true,
                            PadId = padId,
                            RoomId = roomId,
                        }))

                        table.insert(pads, {
                            id = padId,
                            roomId = roomId,
                            position = safePos,
                        })

                        padNum = padNum + 1
                    end
                end
                roomId = roomId + step
            end

            payload.pads = pads

            print(string.format("[PadBuilder] Placed %d pads", #pads))

            self.Out:Fire("buildPass", payload)
        end,
    },
}
