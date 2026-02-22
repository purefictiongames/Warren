--[[
    IGW v2 Pipeline — DoorCutter
    Post-mount: cuts door openings in walls.
    Hides intersecting wall parts + carves air into terrain.
    No CSG — terrain air carving achieves the same doorway effect.

    Signals:
      onBuildPass — original pipeline path (fires buildComplete)
      onCutDoors — Phase 2 alias (fires nodeComplete)
--]]

return {
    name = "DoorCutter",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    _cutDoors = function(self, payload)
        local Dom = _G.Warren.Dom
        local Canvas = Dom.Canvas
        local doors = payload.doors or {}
        local wt = self:getAttribute("wallThickness") or 1

        local t0 = os.clock()
        print(string.format("[DoorCutter] Starting with %d doors", #doors))

        -- Build room model lookup from DOM
        local roomModels = {}
        for _, child in ipairs(Dom.getChildren(Dom.getRoot())) do
            local rid = Dom.getAttribute(child, "RoomId")
            if rid then
                roomModels[rid] = child
            end
        end

        local modelCount = 0
        for _ in pairs(roomModels) do modelCount = modelCount + 1 end
        print(string.format("[DoorCutter] Found %d room models in DOM", modelCount))

        local hideCount = 0

        for _, door in ipairs(doors) do
            local cutterDepth = wt * 8
            local cutterSize

            if door.axis == 2 then
                cutterSize = Vector3.new(door.width, cutterDepth, door.height)
            else
                if door.widthAxis == 1 then
                    cutterSize = Vector3.new(door.width, door.height, cutterDepth)
                else
                    cutterSize = Vector3.new(cutterDepth, door.height, door.width)
                end
            end

            local cutterPos = Vector3.new(door.center[1], door.center[2], door.center[3])

            -- Process walls in both rooms
            local roomsToCheck = { door.fromRoom, door.toRoom }
            for _, roomId in ipairs(roomsToCheck) do
                local roomNode = roomModels[roomId]
                if not roomNode then
                    warn(string.format("[DoorCutter] Room %s not found in DOM for door %d", tostring(roomId), door.id))
                elseif not roomNode._instance then
                    warn(string.format("[DoorCutter] Room %s has no _instance (not mounted?) for door %d", tostring(roomId), door.id))
                end
                if roomNode and roomNode._instance then
                    local roomContainer = roomNode._instance
                    for _, child in ipairs(roomContainer:GetChildren()) do
                        if child:IsA("BasePart") and (
                            child.Name:match("^Wall") or
                            child.Name == "Floor" or
                            child.Name == "Ceiling"
                        ) then
                            -- AABB intersection check
                            local wallPos = child.Position
                            local wallSize = child.Size
                            local intersects = true

                            for axis = 1, 3 do
                                local prop = axis == 1 and "X" or axis == 2 and "Y" or "Z"
                                local wMin = wallPos[prop] - wallSize[prop] / 2
                                local wMax = wallPos[prop] + wallSize[prop] / 2
                                local cMin = cutterPos[prop] - cutterSize[prop] / 2
                                local cMax = cutterPos[prop] + cutterSize[prop] / 2

                                if wMax <= cMin or cMax <= wMin then
                                    intersects = false
                                    break
                                end
                            end

                            if intersects then
                                -- Hide wall part; terrain air carve handles the opening
                                child.Transparency = 1
                                child.CanCollide = false
                                hideCount = hideCount + 1
                            end
                        end
                    end
                end
            end

            -- Carve terrain in doorway (always, regardless of style)
            local buf = payload.buffer
            if buf then
                buf:carveDoorway(CFrame.new(cutterPos), cutterSize)
            else
                Canvas.carveDoorway(CFrame.new(cutterPos), cutterSize)
            end

        end

        print(string.format("[DoorCutter] Hidden %d wall segments for %d doors — %.2fs",
            hideCount, #doors, os.clock() - t0))
    end,

    In = {
        onBuildPass = function(self, payload)
            self:_cutDoors(payload)
            self.Out:Fire("buildComplete", payload)
        end,

        onCutDoors = function(self, payload)
            self:_cutDoors(payload)
            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
