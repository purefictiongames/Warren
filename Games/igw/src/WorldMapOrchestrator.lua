--[[
    IGW v2 — WorldMapOrchestrator
    Top-level orchestrator. Owns the infinite dungeon loop:
    build region → explore → portal countdown → destroy → rebuild.

    Reads world map graph + biome configs from metadata (delivered as attributes).
    Manages player anchoring during transitions and late-joiner spawning.
--]]

return {
    name = "WorldMapOrchestrator",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._config = self:getAttribute("config") or {}
            self._currentBiome = nil
            self._regionNum = 0
            self._container = nil
            self._isTransitioning = false
            self._sourceBiome = nil
            self._dungeonReady = false
            self._spawnPos = nil

            -- Handle late joiners: anchor during build, position when ready
            local Players = game:GetService("Players")
            local selfRef = self

            Players.PlayerAdded:Connect(function(player)
                selfRef:_handlePlayerJoin(player)
            end)
            for _, player in ipairs(Players:GetPlayers()) do
                selfRef:_handlePlayerJoin(player)
            end
        end,

        onStart = function(self)
            local config = self._config
            local startBiome = config.startBiome or "desert"

            -- Defer so IPC.start() finishes setting isStarted = true
            local selfRef = self
            task.defer(function()
                selfRef:_buildDungeon(startBiome)
            end)
        end,

        onStop = function(self)
            if self._container and self._container.Parent then
                self._container:Destroy()
            end
        end,
    },

    _handlePlayerJoin = function(self, player)
        local selfRef = self
        player.CharacterAdded:Connect(function(character)
            task.spawn(function()
                local hrp = character:WaitForChild("HumanoidRootPart", 10)
                if not hrp then return end

                if selfRef._dungeonReady and selfRef._spawnPos then
                    -- Dungeon already built — position immediately
                    hrp.CFrame = CFrame.new(
                        selfRef._spawnPos[1],
                        selfRef._spawnPos[2],
                        selfRef._spawnPos[3]
                    )
                else
                    -- Dungeon still building — anchor until onDungeonComplete
                    hrp.Anchored = true
                end
            end)
        end)
    end,

    _buildDungeon = function(self, biomeName)
        local config = self._config
        local biomes = config.biomes or {}
        local worldMap = config.worldMap or {}
        local biome = biomes[biomeName]

        if not biome then
            warn("[WorldMapOrchestrator] Unknown biome: " .. tostring(biomeName))
            return
        end

        self._regionNum = self._regionNum + 1
        self._currentBiome = biomeName

        local seed = os.time() + math.random(1, 9999)

        print(string.format("[WorldMapOrchestrator] Building region %d — biome: %s (seed %d)",
            self._regionNum, biomeName, seed))

        self.Out:Fire("buildDungeon", {
            biome = biome,
            biomeName = biomeName,
            allBiomes = biomes,
            worldMap = worldMap,
            seed = seed,
            regionNum = self._regionNum,
            featureClasses = config.featureClasses,
        })
    end,

    _destroyCurrentRegion = function(self)
        if self._container and self._container.Parent then
            self._container:Destroy()
            self._container = nil
        end
        workspace.Terrain:Clear()

        -- Clean up minimap geometry
        local oldGeo = game:GetService("ReplicatedStorage"):FindFirstChild("MiniMapGeo")
        if oldGeo then oldGeo:Destroy() end
    end,

    _buildMiniMapGeo = function(self, container, mapCenter)
        if not container then return end

        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local MINIMAP_SCALE = 1 / 100

        -- Clean up previous
        local oldGeo = ReplicatedStorage:FindFirstChild("MiniMapGeo")
        if oldGeo then oldGeo:Destroy() end

        local geoFolder = Instance.new("Folder")
        geoFolder.Name = "MiniMapGeo"

        local mcX, mcY, mcZ = mapCenter[1], mapCenter[2], mapCenter[3]
        local cloneCount = 0

        for _, roomModel in ipairs(container:GetChildren()) do
            if not roomModel:IsA("Model") then continue end
            local roomId = roomModel:GetAttribute("RoomId")
            if not roomId then continue end

            local roomGeo = Instance.new("Model")
            roomGeo.Name = "Room_" .. roomId
            roomGeo:SetAttribute("RoomId", roomId)

            for _, part in ipairs(roomModel:GetChildren()) do
                if not part:IsA("BasePart") then continue end
                if part.Name:match("^RoomZone") then continue end
                local isFloor = (part.Name == "Floor")
                -- Only include floors + UnionOperations (CSG'd walls with door holes).
                -- Plain Wall_* Parts have no holes — skip them.
                if not isFloor and not part:IsA("UnionOperation") then continue end

                local clone = part:Clone()
                clone.Size = part.Size * MINIMAP_SCALE
                clone.CFrame = CFrame.new(
                    (part.Position.X - mcX) * MINIMAP_SCALE,
                    (part.Position.Y - mcY) * MINIMAP_SCALE,
                    (part.Position.Z - mcZ) * MINIMAP_SCALE
                )
                clone.Anchored = true
                clone.CanCollide = false
                clone.Material = Enum.Material.SmoothPlastic
                clone.Transparency = 1
                if clone:IsA("UnionOperation") then
                    clone.UsePartColor = true
                end
                clone:SetAttribute("IsFloor", isFloor)
                clone.Parent = roomGeo
                cloneCount = cloneCount + 1
            end

            roomGeo.Parent = geoFolder
        end

        -- Parent last so entire tree replicates atomically
        geoFolder.Parent = ReplicatedStorage
        print(string.format("[WorldMapOrchestrator] MiniMapGeo: %d parts at 1/100 scale", cloneCount))
    end,

    _anchorAllPlayers = function(self)
        local Players = game:GetService("Players")
        for _, player in ipairs(Players:GetPlayers()) do
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.Anchored = true
            end
        end
    end,

    _unanchorAllPlayers = function(self)
        local Players = game:GetService("Players")
        for _, player in ipairs(Players:GetPlayers()) do
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.Anchored = false
            end
        end
    end,

    _spawnAllPlayers = function(self, spawnPos)
        if not spawnPos then return end
        local Players = game:GetService("Players")
        for _, player in ipairs(Players:GetPlayers()) do
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(spawnPos[1], spawnPos[2], spawnPos[3])
            end
        end
    end,

    In = {
        onDungeonComplete = function(self, payload)
            print(string.format("[WorldMapOrchestrator] onDungeonComplete received (region %d)",
                self._regionNum))
            local Debug = self._System and self._System.Debug
            self._container = payload.container

            -- Build portal room list from assignments
            local portalRooms = {}
            local portalAssignments = payload.portalAssignments or {}
            local rooms = payload.rooms or {}
            for roomId, targetBiome in pairs(portalAssignments) do
                local room = rooms[roomId]
                if room then
                    table.insert(portalRooms, {
                        roomId = roomId,
                        targetBiome = targetBiome,
                        position = room.position,
                        dims = room.dims,
                    })
                end
            end

            if Debug then
                Debug.info("WorldMapOrchestrator",
                    "Region", self._regionNum, "complete.",
                    "Biome:", self._currentBiome,
                    "Portals:", #portalRooms)
            end

            print(string.format("[WorldMapOrchestrator] Region %d ready — %d portal rooms",
                self._regionNum, #portalRooms))

            -- Notify PortalTrigger about portal rooms
            if #portalRooms > 0 then
                self.Out:Fire("portalRoomsReady", {
                    portalRooms = portalRooms,
                    container = self._container,
                    countdownSeconds = self._config.portalCountdownSeconds or 5,
                })
            end

            -- Determine spawn position
            local spawnPos = payload.spawn and payload.spawn.position

            if self._isTransitioning and self._sourceBiome then
                -- Portal transition: spawn at the return portal room
                for roomId, targetBiome in pairs(portalAssignments) do
                    if targetBiome == self._sourceBiome then
                        local room = rooms[roomId]
                        if room then
                            local floorY = room.position[2] - room.dims[2] / 2 + 3
                            spawnPos = { room.position[1], floorY, room.position[3] }
                            print(string.format(
                                "[WorldMapOrchestrator] Spawning at return portal room %d → %s",
                                roomId, self._sourceBiome))
                            break
                        end
                    end
                end
            end

            -- Store spawn for late joiners + signal loading screen
            self._spawnPos = spawnPos
            self._dungeonReady = true
            shared.dungeonReady = {
                containerName = self._container and self._container.Name,
            }

            self:_spawnAllPlayers(spawnPos)
            self:_unanchorAllPlayers()

            -- Build door-face map for MiniMap: { [roomId] = { N=true, E=true, ... } }
            local doorFaces = {}
            for _, door in ipairs(payload.doors or {}) do
                local roomA = payload.rooms[door.fromRoom]
                local roomB = payload.rooms[door.toRoom]
                if not (roomA and roomB) then continue end

                if door.axis == 1 then
                    local aFace = roomA.position[1] < roomB.position[1] and "E" or "W"
                    local bFace = aFace == "E" and "W" or "E"
                    doorFaces[door.fromRoom] = doorFaces[door.fromRoom] or {}
                    doorFaces[door.fromRoom][aFace] = true
                    doorFaces[door.toRoom] = doorFaces[door.toRoom] or {}
                    doorFaces[door.toRoom][bFace] = true
                elseif door.axis == 3 then
                    local aFace = roomA.position[3] < roomB.position[3] and "N" or "S"
                    local bFace = aFace == "N" and "S" or "N"
                    doorFaces[door.fromRoom] = doorFaces[door.fromRoom] or {}
                    doorFaces[door.fromRoom][aFace] = true
                    doorFaces[door.toRoom] = doorFaces[door.toRoom] or {}
                    doorFaces[door.toRoom][bFace] = true
                elseif door.axis == 2 then
                    local aFace = roomA.position[2] < roomB.position[2] and "U" or "D"
                    local bFace = aFace == "U" and "D" or "U"
                    doorFaces[door.fromRoom] = doorFaces[door.fromRoom] or {}
                    doorFaces[door.fromRoom][aFace] = true
                    doorFaces[door.toRoom] = doorFaces[door.toRoom] or {}
                    doorFaces[door.toRoom][bFace] = true
                end
            end

            -- Build adjacency map for MiniMap fog-of-war
            local adjacency = {}
            for _, door in ipairs(payload.doors or {}) do
                adjacency[door.fromRoom] = adjacency[door.fromRoom] or {}
                table.insert(adjacency[door.fromRoom], door.toRoom)
                adjacency[door.toRoom] = adjacency[door.toRoom] or {}
                table.insert(adjacency[door.toRoom], door.fromRoom)
            end

            -- Strip room data for MiniMap (position + dims only)
            local miniMapRooms = {}
            for roomId, room in pairs(payload.rooms or {}) do
                miniMapRooms[roomId] = {
                    position = room.position,
                    dims = room.dims,
                }
            end

            -- Compute bounds for map center (used by both server geo + client)
            local minX, maxX = math.huge, -math.huge
            local minY, maxY = math.huge, -math.huge
            local minZ, maxZ = math.huge, -math.huge
            for _, room in pairs(miniMapRooms) do
                local p = room.position
                local d = room.dims
                minX = math.min(minX, p[1] - d[1]/2)
                maxX = math.max(maxX, p[1] + d[1]/2)
                minY = math.min(minY, p[2] - d[2]/2)
                maxY = math.max(maxY, p[2] + d[2]/2)
                minZ = math.min(minZ, p[3] - d[3]/2)
                maxZ = math.max(maxZ, p[3] + d[3]/2)
            end
            local mapCenter = {
                (minX + maxX) / 2,
                (minY + maxY) / 2,
                (minZ + maxZ) / 2,
            }

            -- Build minimap geometry server-side: clone CSG'd walls + floors at 1/100 scale
            self:_buildMiniMapGeo(payload.container, mapCenter)

            -- Send room data to MiniMap (client clones geometry from ReplicatedStorage)
            self.Out:Fire("buildMiniMap", {
                rooms = miniMapRooms,
                doorFaces = doorFaces,
                adjacency = adjacency,
                spawnPos = spawnPos,
                containerName = "Dungeon",
                mapCenter = mapCenter,
                wallThickness = self:getAttribute("wallThickness") or 2,
            })

            -- Enable map opening now that player is spawned
            self.Out:Fire("mapReady", {})

            -- If this was a portal transition, signal fade-in
            if self._isTransitioning then
                self._isTransitioning = false
                self._sourceBiome = nil
                self.Out:Fire("portalTransitionEnd", {
                    biomeName = self._currentBiome,
                })
            end
        end,

        onPortalActivated = function(self, data)
            if self._isTransitioning then return end

            local targetBiome = data.targetBiome
            local roomId = data.roomId
            local t0 = os.clock()

            print(string.format("[WorldMapOrchestrator] Portal activated! Room %d → %s",
                roomId or 0, targetBiome or "?"))

            self._isTransitioning = true
            self._sourceBiome = self._currentBiome

            -- Anchor all players
            self:_anchorAllPlayers()

            -- Signal client fade-out
            self.Out:Fire("portalTransitionStart", {
                targetBiome = targetBiome,
            })

            -- Wait for fade-out
            task.wait(1.0)
            print(string.format("[WorldMapOrchestrator] +%.1fs: fade done, destroying old region", os.clock() - t0))

            -- Destroy old region
            self:_destroyCurrentRegion()
            print(string.format("[WorldMapOrchestrator] +%.1fs: destroyed, building new region", os.clock() - t0))

            -- Build new region
            self:_buildDungeon(targetBiome)
            print(string.format("[WorldMapOrchestrator] +%.1fs: buildDungeon signal fired", os.clock() - t0))
        end,
    },
}
