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
            self._miniMapRunning = false

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
                    -- Dungeon still building — anchor until ready
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

        -- Chunked path: WorldBridge handles VPS creation + incremental chunk loading
        self.Out:Fire("buildWorld", {
            biome = biome,
            biomeName = biomeName,
            allBiomes = biomes,
            worldMap = worldMap,
            seed = seed,
            regionNum = self._regionNum,
            featureClasses = config.featureClasses,
        })
    end,

    _buildDungeonMonolithic = function(self, biomeName)
        -- Legacy monolithic path (kept for computeTarget = "roblox" fallback)
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

        -- Clean up mesh terrain (EditableMesh renderer)
        local meshTerrain = workspace:FindFirstChild("MeshTerrain")
        if meshTerrain then meshTerrain:Destroy() end

        -- Clean up minimap geometry
        self._miniMapRunning = false
        local mmGeo = game:GetService("ReplicatedStorage"):FindFirstChild("MiniMapGeo")
        if mmGeo then mmGeo:Destroy() end
        local mmBuild = workspace:FindFirstChild("_MiniMapBuild")
        if mmBuild then mmBuild:Destroy() end
    end,

    ------------------------------------------------------------------------
    -- MINIMAP GEOMETRY — server-side CSG, results to ReplicatedStorage
    --
    -- For each room in workspace.Dungeon: clone Floor + door-intersecting
    -- walls, CSG door holes at full scale, scale to 1/100, parent to
    -- ReplicatedStorage.MiniMapGeo. Client clones from there.
    -- Runs in background, processes rooms as they appear (DescendantAdded).
    --
    -- BUG (2026-02-24): Some rooms occasionally produce no minimap geometry.
    -- The room Model exists in workspace.Dungeon and gets processed, but
    -- either SubtractAsync fails silently, children haven't replicated when
    -- processRoom runs, or the room container has no Floor/Wall_ children
    -- at the moment of processing. The proximity gate (chunkGrid path) may
    -- exacerbate this if DescendantAdded fires before the room's children
    -- are fully parented. Workaround: rooms without geometry simply don't
    -- appear on the minimap. No crash, just missing tiles.
    ------------------------------------------------------------------------

    _buildMiniMapGeo = function(self, doors, mapCenter, wallThickness, chunkGrid, allRooms)
        local RS = game:GetService("ReplicatedStorage")
        local Players = game:GetService("Players")
        local wt = wallThickness or 2
        local SCALE = 1 / 100
        local floor = math.floor
        local max = math.max
        local min = math.min
        local abs = math.abs

        -- Clean up previous
        local oldGeo = RS:FindFirstChild("MiniMapGeo")
        if oldGeo then oldGeo:Destroy() end
        local geoFolder = Instance.new("Folder")
        geoFolder.Name = "MiniMapGeo"
        geoFolder.Parent = RS

        local tempFolder = Instance.new("Folder")
        tempFolder.Name = "_MiniMapBuild"
        tempFolder.Parent = workspace

        -- Index doors by room
        local doorsByRoom = {}
        for _, door in ipairs(doors) do
            local fromId = tonumber(door.fromRoom) or door.fromRoom
            local toId = tonumber(door.toRoom) or door.toRoom
            doorsByRoom[fromId] = doorsByRoom[fromId] or {}
            table.insert(doorsByRoom[fromId], door)
            doorsByRoom[toId] = doorsByRoom[toId] or {}
            table.insert(doorsByRoom[toId], door)
        end

        local mc = mapCenter
        local processed = {}

        -- Inline chunk coord helper (mirrors WorldBridge._worldToChunk)
        local function worldToChunk(worldX, worldZ)
            if not chunkGrid then return 0, 0 end
            local cx = floor((worldX - chunkGrid.mapMinX) / chunkGrid.chunkSize)
            local cz = floor((worldZ - chunkGrid.mapMinZ) / chunkGrid.chunkSize)
            cx = max(0, min(chunkGrid.sizeX - 1, cx))
            cz = max(0, min(chunkGrid.sizeZ - 1, cz))
            return cx, cz
        end

        local function processRoom(roomContainer)
            if not self._miniMapRunning then return end
            local idStr = roomContainer.Name:match("^Room_(%d+)")
            if not idStr then return end
            local roomId = tonumber(idStr)
            if processed[roomId] then return end
            processed[roomId] = true

            local roomModel = Instance.new("Model")
            roomModel.Name = "Room_" .. roomId
            roomModel:SetAttribute("RoomId", roomId)

            -- Collect all CSG candidates: Wall_* + Floor + Ceiling
            local csgCandidates = {}
            local floorPart = nil
            for _, child in ipairs(roomContainer:GetChildren()) do
                if child:IsA("BasePart") then
                    if child.Name == "Floor" then
                        floorPart = child
                        csgCandidates[child.Name] = child
                    elseif child.Name:match("^Wall_") or child.Name == "Ceiling" then
                        csgCandidates[child.Name] = child
                    end
                end
            end

            -- For each door touching this room, find intersecting parts → CSG
            local partsToCSG = {} -- { [partName] = { part, cutters = {{size,pos},...} } }
            local roomDoors = doorsByRoom[roomId] or {}

            for _, door in ipairs(roomDoors) do
                if not door.center then continue end

                local cutterDepth = wt * 8
                local cutterSize
                if door.axis == 2 then
                    -- Ceiling/floor hole: opening spans X and Z
                    cutterSize = Vector3.new(door.width, cutterDepth, door.height)
                else
                    if door.widthAxis == 1 then
                        cutterSize = Vector3.new(door.width, door.height, cutterDepth)
                    else
                        cutterSize = Vector3.new(cutterDepth, door.height, door.width)
                    end
                end
                local cutterPos = Vector3.new(door.center[1], door.center[2], door.center[3])

                for partName, partInstance in pairs(csgCandidates) do
                    local wPos = partInstance.Position
                    local wSize = partInstance.Size
                    local intersects = true
                    for axis = 1, 3 do
                        local prop = axis == 1 and "X" or axis == 2 and "Y" or "Z"
                        local wMin = wPos[prop] - wSize[prop] / 2
                        local wMax = wPos[prop] + wSize[prop] / 2
                        local cMin = cutterPos[prop] - cutterSize[prop] / 2
                        local cMax = cutterPos[prop] + cutterSize[prop] / 2
                        if wMax <= cMin or cMax <= wMin then
                            intersects = false
                            break
                        end
                    end
                    if intersects then
                        if not partsToCSG[partName] then
                            partsToCSG[partName] = { part = partInstance, cutters = {} }
                        end
                        table.insert(partsToCSG[partName].cutters, {
                            size = cutterSize, pos = cutterPos,
                        })
                    end
                end
            end

            -- CSG each intersecting part at full scale, then scale to 1/100
            for partName, entry in pairs(partsToCSG) do
                local wall = entry.part:Clone()
                wall.Transparency = 0
                wall.Anchored = true
                wall.CanCollide = false
                wall.Parent = tempFolder

                local result = wall
                for _, cut in ipairs(entry.cutters) do
                    local cutter = Instance.new("Part")
                    cutter.Size = cut.size
                    cutter.CFrame = CFrame.new(cut.pos)
                    cutter.Anchored = true
                    cutter.CanCollide = false
                    cutter.Parent = tempFolder

                    local ok, union = pcall(function()
                        return result:SubtractAsync({ cutter })
                    end)
                    if ok and union then
                        result.Parent = nil
                        result:Destroy()
                        union.Anchored = true
                        union.CanCollide = false
                        union.Parent = tempFolder
                        result = union
                    end
                    cutter:Destroy()
                end

                -- Scale + reposition
                local wp = result.Position
                result.Size = result.Size * SCALE
                result.CFrame = CFrame.new(
                    (wp.X - mc[1]) * SCALE,
                    (wp.Y - mc[2]) * SCALE,
                    (wp.Z - mc[3]) * SCALE
                )
                result.Material = Enum.Material.SmoothPlastic
                if result:IsA("UnionOperation") then
                    result.UsePartColor = true
                end
                result.Parent = nil
                result:SetAttribute("IsFloor", partName == "Floor")
                result.Parent = roomModel
            end

            -- Floor always shown: if it wasn't CSG'd, add a plain clone
            if floorPart and not partsToCSG["Floor"] then
                local f = floorPart:Clone()
                local wp = f.Position
                f.Size = f.Size * SCALE
                f.CFrame = CFrame.new(
                    (wp.X - mc[1]) * SCALE,
                    (wp.Y - mc[2]) * SCALE,
                    (wp.Z - mc[3]) * SCALE
                )
                f.Transparency = 0  -- DoorCutter/_cutBorderDoors may have hidden the original
                f.Anchored = true
                f.CanCollide = false
                f.Material = Enum.Material.SmoothPlastic
                f:SetAttribute("IsFloor", true)
                f.Parent = roomModel
            end

            -- Only add if we produced something
            if #roomModel:GetChildren() > 0 then
                roomModel.Parent = geoFolder
            else
                roomModel:Destroy()
            end
        end

        -- Queue for rooms awaiting proximity check
        local queue = {}

        -- Enqueue rooms already in Dungeon
        local dungeon = workspace:FindFirstChild("Dungeon")
        if dungeon then
            for _, child in ipairs(dungeon:GetDescendants()) do
                if child:IsA("Model") and child.Name:match("^Room_") then
                    table.insert(queue, child)
                end
            end

            -- Watch for new rooms as chunks load in background
            local conn
            conn = dungeon.DescendantAdded:Connect(function(desc)
                if not self._miniMapRunning then
                    conn:Disconnect()
                    return
                end
                if desc:IsA("Model") and desc.Name:match("^Room_") then
                    if chunkGrid then
                        -- Chunked path: enqueue for proximity check
                        table.insert(queue, desc)
                    else
                        -- Monolithic path: process immediately
                        task.defer(function()
                            processRoom(desc)
                        end)
                    end
                end
            end)
        end

        if not chunkGrid then
            -- Monolithic path: process all queued rooms immediately, done
            for _, roomContainer in ipairs(queue) do
                processRoom(roomContainer)
            end
            return
        end

        -- Chunked path: poll loop — process rooms within miniMapCsgRadius of player
        local radius = self:getAttribute("miniMapCsgRadius") or 3

        while self._miniMapRunning do
            -- Get first player's position
            local playerList = Players:GetPlayers()
            local hrp = nil
            for _, player in ipairs(playerList) do
                local char = player.Character
                hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then break end
            end

            if hrp then
                local pCX, pCZ = worldToChunk(hrp.Position.X, hrp.Position.Z)

                -- Drain queue: process rooms in range, keep the rest
                local remaining = {}
                for _, roomContainer in ipairs(queue) do
                    if not roomContainer.Parent then
                        -- Room was destroyed (chunk unloaded), skip
                        continue
                    end

                    local idStr = roomContainer.Name:match("^Room_(%d+)")
                    local roomId = idStr and tonumber(idStr)
                    if not roomId or processed[roomId] then
                        continue
                    end

                    -- Get room's world position from allRooms data
                    local roomData = allRooms and allRooms[roomId]
                    if roomData and roomData.position then
                        local rCX, rCZ = worldToChunk(roomData.position[1], roomData.position[3])
                        local dist = max(abs(pCX - rCX), abs(pCZ - rCZ))  -- Chebyshev
                        if dist <= radius then
                            processRoom(roomContainer)
                        else
                            table.insert(remaining, roomContainer)
                        end
                    else
                        -- No room data — process anyway (safety fallback)
                        processRoom(roomContainer)
                    end
                end
                queue = remaining
            end

            task.wait(1)
        end

        -- Temp folder cleaned up by _destroyCurrentRegion on next transition
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
        --------------------------------------------------------------------
        -- Chunked path: WorldBridge reports world is ready with initial chunks loaded
        --------------------------------------------------------------------
        onWorldReady = function(self, data)
            print(string.format("[WorldMapOrchestrator] onWorldReady: %s (region %d)",
                data.worldId or "?", self._regionNum))

            self._worldId = data.worldId

            -- Store spawn for late joiners
            local spawnPos = data.spawn and data.spawn.position
            self._spawnPos = spawnPos
            self._dungeonReady = true
            shared.dungeonReady = {
                worldId = data.worldId,
                containerName = "Dungeon",
            }

            -- Signal Bootstrap's loading screen protocol
            local drEvent = game:GetService("ServerStorage"):FindFirstChild("DungeonReady")
            if drEvent then drEvent:Fire() end

            self:_spawnAllPlayers(spawnPos)
            self:_unanchorAllPlayers()

            -- Send room/door DATA to MiniMap — client builds geometry incrementally
            local global = data.global or {}
            local doors = global.doors or {}

            -- Normalize room keys (JSON round-trip may stringify numeric keys)
            local rooms = nil
            if global.rooms then
                rooms = {}
                for id, room in pairs(global.rooms) do
                    rooms[tonumber(id) or id] = room
                end
            end

            if rooms then
                local roomCount = 0
                for _ in pairs(rooms) do roomCount = roomCount + 1 end
                print(string.format("[WorldMapOrchestrator] Sending minimap data: %d rooms, %d doors",
                    roomCount, #doors))

                -- Adjacency map for fog-of-war
                local adjacency = {}
                for _, door in ipairs(doors) do
                    adjacency[door.fromRoom] = adjacency[door.fromRoom] or {}
                    table.insert(adjacency[door.fromRoom], door.toRoom)
                    adjacency[door.toRoom] = adjacency[door.toRoom] or {}
                    table.insert(adjacency[door.toRoom], door.fromRoom)
                end

                -- Strip room data (position + dims only)
                local miniMapRooms = {}
                for roomId, room in pairs(rooms) do
                    miniMapRooms[roomId] = {
                        position = room.position,
                        dims = room.dims,
                    }
                end

                -- Compute map center from bounds
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

                -- Send all data to client (client builds geometry as chunks load)
                self.Out:Fire("buildMiniMap", {
                    rooms = miniMapRooms,
                    doors = doors,
                    adjacency = adjacency,
                    spawnPos = spawnPos,
                    containerName = "Dungeon",
                    mapCenter = mapCenter,
                    wallThickness = self:getAttribute("wallThickness") or 2,
                })
                print("[WorldMapOrchestrator] buildMiniMap fired (data only)")

                -- Start background CSG for minimap walls (server-side only)
                self._miniMapRunning = true
                local selfRef = self
                local wt = selfRef:getAttribute("wallThickness") or 2
                task.spawn(function()
                    selfRef:_buildMiniMapGeo(doors, mapCenter, wt, global.chunkGrid, rooms)
                end)
            end

            -- Enable map opening
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

        --------------------------------------------------------------------
        -- Monolithic path: DungeonOrchestrator reports dungeon complete
        --------------------------------------------------------------------
        onDungeonComplete = function(self, payload)
            print(string.format("[WorldMapOrchestrator] onDungeonComplete received (region %d)",
                self._regionNum))
            local Debug = _G.Warren.System.Debug
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
                worldId = nil,
                containerName = self._container and self._container.Name or "Dungeon",
            }

            -- Signal Bootstrap's loading screen protocol
            local drEvent = game:GetService("ServerStorage"):FindFirstChild("DungeonReady")
            if drEvent then drEvent:Fire() end

            self:_spawnAllPlayers(spawnPos)
            self:_unanchorAllPlayers()

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

            -- Compute bounds for map center
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

            -- Send all data to MiniMap (client builds geometry)
            local monolithicWt = self:getAttribute("wallThickness") or 2
            self.Out:Fire("buildMiniMap", {
                rooms = miniMapRooms,
                doors = payload.doors or {},
                adjacency = adjacency,
                spawnPos = spawnPos,
                containerName = self._container and self._container.Name or "Dungeon",
                mapCenter = mapCenter,
                wallThickness = monolithicWt,
            })

            -- Start background CSG for minimap walls (server-side only)
            self._miniMapRunning = true
            local selfRef = self
            local monolithicDoors = payload.doors or {}
            task.spawn(function()
                selfRef:_buildMiniMapGeo(monolithicDoors, mapCenter, monolithicWt, nil, nil)
            end)

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

            -- Destroy via WorldBridge (chunked path) or direct (monolithic)
            if self._worldId then
                self.Out:Fire("destroyWorld", {})
                self._worldId = nil
            else
                self:_destroyCurrentRegion()
            end
            print(string.format("[WorldMapOrchestrator] +%.1fs: destroyed, building new region", os.clock() - t0))

            -- Build new region
            self:_buildDungeon(targetBiome)
            print(string.format("[WorldMapOrchestrator] +%.1fs: buildWorld signal fired", os.clock() - t0))
        end,
    },
}
