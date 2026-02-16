--[[
    IGW v2 Pipeline — DoorPlanner
    Calculates door positions between connected rooms.
    Stores door specs in payload.doors for downstream use.
--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- DOOR POSITION CALCULATION
--------------------------------------------------------------------------------

local function calculateDoorPosition(roomA, roomB, config)
    local wt = config.wallThickness or 1
    local doorSize = config.doorSize or 12

    -- Find which axis they touch on
    local touchAxis = nil
    local touchDir = nil

    for axis = 1, 3 do
        local shellEdgeA = roomA.position[axis] + roomA.dims[axis] / 2 + wt
        local shellEdgeB = roomB.position[axis] - roomB.dims[axis] / 2 - wt
        if math.abs(shellEdgeA - shellEdgeB) < 0.1 then
            touchAxis = axis
            touchDir = 1
            break
        end

        shellEdgeA = roomA.position[axis] - roomA.dims[axis] / 2 - wt
        shellEdgeB = roomB.position[axis] + roomB.dims[axis] / 2 + wt
        if math.abs(shellEdgeA - shellEdgeB) < 0.1 then
            touchAxis = axis
            touchDir = -1
            break
        end
    end

    if not touchAxis then
        return nil
    end

    local center = { 0, 0, 0 }
    center[touchAxis] = roomA.position[touchAxis] +
        touchDir * (roomA.dims[touchAxis] / 2 + wt)

    local widthAxis, heightAxis
    if touchAxis == 2 then
        widthAxis = 1
        heightAxis = 3
    else
        heightAxis = 2
        if touchAxis == 1 then
            widthAxis = 3
        else
            widthAxis = 1
        end
    end

    -- Width axis overlap
    local minA = roomA.position[widthAxis] - roomA.dims[widthAxis] / 2
    local maxA = roomA.position[widthAxis] + roomA.dims[widthAxis] / 2
    local minB = roomB.position[widthAxis] - roomB.dims[widthAxis] / 2
    local maxB = roomB.position[widthAxis] + roomB.dims[widthAxis] / 2
    local overlapMin = math.max(minA, minB)
    local overlapMax = math.min(maxA, maxB)
    center[widthAxis] = (overlapMin + overlapMax) / 2
    local width = math.min(overlapMax - overlapMin - 4, doorSize)

    -- Height axis overlap
    minA = roomA.position[heightAxis] - roomA.dims[heightAxis] / 2
    maxA = roomA.position[heightAxis] + roomA.dims[heightAxis] / 2
    minB = roomB.position[heightAxis] - roomB.dims[heightAxis] / 2
    maxB = roomB.position[heightAxis] + roomB.dims[heightAxis] / 2
    overlapMin = math.max(minA, minB)
    overlapMax = math.min(maxA, maxB)
    local height = math.min(overlapMax - overlapMin - 4, doorSize)

    local doorBottom = nil
    if touchAxis ~= 2 then
        doorBottom = overlapMin + 1
        center[heightAxis] = doorBottom + height / 2
    else
        center[heightAxis] = (overlapMin + overlapMax) / 2
    end

    return {
        center = center,
        width = width,
        height = height,
        axis = touchAxis,
        widthAxis = widthAxis,
        bottom = doorBottom,
    }
end

--------------------------------------------------------------------------------
-- NODE
--------------------------------------------------------------------------------

local DoorPlanner = Node.extend({
    name = "DoorPlanner",
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
            local doors = {}
            local roomCount = 0
            for _ in pairs(rooms) do roomCount = roomCount + 1 end
            print(string.format("[DoorPlanner] Starting with %d rooms", roomCount))
            local doorId = 1

            for id, room in pairs(rooms) do
                if room.parentId then
                    local parentRoom = rooms[room.parentId]
                    if parentRoom then
                        local doorData = calculateDoorPosition(parentRoom, room, config)
                        if doorData then
                            table.insert(doors, {
                                id = doorId,
                                fromRoom = room.parentId,
                                toRoom = id,
                                center = doorData.center,
                                width = doorData.width,
                                height = doorData.height,
                                axis = doorData.axis,
                                widthAxis = doorData.widthAxis,
                                bottom = doorData.bottom,
                            })
                            doorId = doorId + 1
                        end
                    end
                end
            end

            payload.doors = doors

            print(string.format("[DoorPlanner] Planned %d doors", #doors))

            self.Out:Fire("buildPass", payload)
        end,
    },
})

return DoorPlanner
