--[[
    IGW v2 Pipeline — DoorCutter
    Post-mount: uses CSG SubtractAsync to cut door openings in walls.

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
        local Dom = self._System.Dom
        local Canvas = Dom.Canvas
        local doors = payload.doors or {}
        local biome = payload.biome or {}
        local isOutdoor = biome.terrainStyle == "outdoor"
        local wt = self:getAttribute("wallThickness") or 1

        local t0 = os.clock()
        print(string.format("[DoorCutter] Starting with %d doors (outdoor=%s)", #doors, tostring(isOutdoor)))

        -- Build room model lookup from DOM
        local roomModels = {}
        for _, child in ipairs(Dom.getChildren(payload.dom)) do
            local rid = Dom.getAttribute(child, "RoomId")
            if rid then
                roomModels[rid] = child
            end
        end

        local modelCount = 0
        for _ in pairs(roomModels) do modelCount = modelCount + 1 end
        print(string.format("[DoorCutter] Found %d room models in DOM", modelCount))

        local cutCount = 0
        local failCount = 0
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

            -- Outdoor horizontal doors: CSG first, THEN hide.
            -- CSG geometry preserved in workspace for minimap cloning.
            local hideAfterCsg = isOutdoor and door.axis ~= 2

            -- Always create cutter for CSG
            local cutter = Instance.new("Part")
            cutter.Size = cutterSize
            cutter.Position = cutterPos
            cutter.Anchored = true
            cutter.CanCollide = false
            cutter.Transparency = 1

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
                                -- Always CSG cut
                                local success, result = pcall(function()
                                    return child:SubtractAsync({cutter})
                                end)

                                if success and result then
                                    result.Name = child.Name
                                    result.Parent = roomContainer

                                    -- Update DomNode _instance reference
                                    local children = Dom.getChildren(roomNode)
                                    for _, domChild in ipairs(children) do
                                        if domChild and domChild._instance == child then
                                            domChild._instance = result
                                            break
                                        end
                                    end

                                    child:Destroy()
                                    cutCount = cutCount + 1

                                    -- Outdoor horizontal: hide AFTER CSG
                                    -- (geometry preserved for minimap cloning)
                                    if hideAfterCsg then
                                        result.Transparency = 1
                                        result.CanCollide = false
                                        hideCount = hideCount + 1
                                    end
                                else
                                    failCount = failCount + 1
                                    -- Fallback: hide if outdoor horizontal
                                    if hideAfterCsg then
                                        child.Transparency = 1
                                        child.CanCollide = false
                                        hideCount = hideCount + 1
                                    end
                                    warn(string.format(
                                        "[DoorCutter] SubtractAsync FAILED on %s (room %s): %s",
                                        child.Name, tostring(roomId),
                                        tostring(result)
                                    ))
                                end
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

            cutter:Destroy()
        end

        print(string.format("[DoorCutter] Cut %d, hidden %d wall segments for %d doors (%d CSG failures) — %.2fs",
            cutCount, hideCount, #doors, failCount, os.clock() - t0))
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
