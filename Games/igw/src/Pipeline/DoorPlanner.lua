--[[
    IGW v2 Pipeline — DoorPlanner
    Two-phase door node:
    - Plan: calculates door positions between connected rooms
    - Apply: carves terrain doorways + disables collision on shell walls
--]]

--------------------------------------------------------------------------------
-- DOOR POSITION CALCULATION
--------------------------------------------------------------------------------

local function calculateDoorPosition(roomA, roomB, wt, doorSize)
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
        widthAxis = touchAxis == 1 and 3 or 1
    end

    local minA = roomA.position[widthAxis] - roomA.dims[widthAxis] / 2
    local maxA = roomA.position[widthAxis] + roomA.dims[widthAxis] / 2
    local minB = roomB.position[widthAxis] - roomB.dims[widthAxis] / 2
    local maxB = roomB.position[widthAxis] + roomB.dims[widthAxis] / 2
    local overlapMin = math.max(minA, minB)
    local overlapMax = math.min(maxA, maxB)
    center[widthAxis] = (overlapMin + overlapMax) / 2
    local width = math.min(overlapMax - overlapMin - 4, doorSize)

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

local function getCutterSize(door, wt)
    local depth = wt * 8
    if door.axis == 2 then
        return Vector3.new(door.width, depth, door.height)
    elseif door.widthAxis == 1 then
        return Vector3.new(door.width, door.height, depth)
    else
        return Vector3.new(depth, door.height, door.width)
    end
end

--------------------------------------------------------------------------------
-- NODE
--------------------------------------------------------------------------------

return {
    name = "DoorPlanner",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        --------------------------------------------------------------------
        -- Plan phase: compute door positions from room geometry
        --------------------------------------------------------------------
        onPlanDoors = function(self, payload)
            local rooms = payload.rooms or {}
            local wt = self:getAttribute("wallThickness") or 1
            local doorSize = self:getAttribute("doorSize") or 12
            local doors = {}
            local doorId = 1

            for id, room in pairs(rooms) do
                if room.parentId then
                    local parentRoom = rooms[room.parentId]
                    if parentRoom then
                        local doorData = calculateDoorPosition(parentRoom, room, wt, doorSize)
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
            payload.doorCount = #doors

            print(string.format("[DoorPlanner] Planned %d doors", #doors))
            self.Out:Fire("nodeComplete", payload)
        end,

        --------------------------------------------------------------------
        -- Apply phase: carve terrain + disable wall collision
        --------------------------------------------------------------------
        onApplyDoors = function(self, payload)
            local Dom = self._System.Dom
            local Canvas = Dom.Canvas
            local doors = payload.doors or {}
            local container = payload.container
            local wt = self:getAttribute("wallThickness") or 1

            if #doors == 0 or not container then
                print("[DoorPlanner] Apply: nothing to do")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            -- Carve terrain doorways
            local buf = payload.buffer
            for _, door in ipairs(doors) do
                local cutterSize = getCutterSize(door, wt)
                local cutterPos = CFrame.new(
                    door.center[1], door.center[2], door.center[3]
                )
                if buf then
                    buf:carveDoorway(cutterPos, cutterSize)
                else
                    Canvas.carveDoorway(cutterPos, cutterSize)
                end
            end

            -- Disable collision on shell walls at doorways
            local roomContainers = {}
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") and child.Name:match("^Room_") then
                    local idStr = child.Name:match("^Room_(%d+)")
                    if idStr then
                        roomContainers[tonumber(idStr)] = child
                    end
                end
            end

            local disabledCount = 0
            for _, door in ipairs(doors) do
                local cutterSize = getCutterSize(door, wt)
                local cutterPos = Vector3.new(
                    door.center[1], door.center[2], door.center[3]
                )

                for _, roomId in ipairs({ door.fromRoom, door.toRoom }) do
                    local rc = roomContainers[roomId]
                    if rc then
                        for _, part in ipairs(rc:GetChildren()) do
                            if part:IsA("BasePart") and (
                                part.Name:match("^Wall") or
                                part.Name == "Floor" or
                                part.Name == "Ceiling"
                            ) then
                                local pPos = part.Position
                                local pSize = part.Size
                                local hit = true
                                for axis = 1, 3 do
                                    local prop = axis == 1 and "X"
                                        or axis == 2 and "Y" or "Z"
                                    local wMin = pPos[prop] - pSize[prop] / 2
                                    local wMax = pPos[prop] + pSize[prop] / 2
                                    local cMin = cutterPos[prop] - cutterSize[prop] / 2
                                    local cMax = cutterPos[prop] + cutterSize[prop] / 2
                                    if wMax <= cMin or cMax <= wMin then
                                        hit = false
                                        break
                                    end
                                end
                                if hit then
                                    part.CanCollide = false
                                    disabledCount = disabledCount + 1
                                end
                            end
                        end
                    end
                end
            end

            print(string.format(
                "[DoorPlanner] Applied: carved %d doorways, disabled %d wall segments",
                #doors, disabledCount
            ))
            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
