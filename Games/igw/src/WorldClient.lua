--[[
    IGW v2 — WorldClient (Chunked World Manager)

    Roblox-side chunk manager. Creates worlds on VPS, receives global data +
    worldId, then loads/unloads spatial chunks as the player moves.

    Replaces WorldMapOrchestrator's monolithic buildDungeon → DungeonOrchestrator
    path with: buildWorld → WorldClient → per-chunk DungeonOrchestrator dispatch.

    Responsibilities:
        - onBuildWorld: create world on VPS → compute height field → load initial chunks
        - Player position tracking (1s poll via Heartbeat)
        - Chunk loading: fetch from VPS → filter payload → _syncCall to DungeonOrchestrator
        - Chunk unloading: destroy room containers + FillRegion(Air) for terrain tile
        - Border door queue: build cross-chunk doors when both sides loaded

    Signal: onBuildWorld(data) → fires worldReady
    Signal: onDestroyWorld() → fires worldDestroyed
--]]

local VOXEL = 4
local floor = math.floor
local max   = math.max
local min   = math.min

return {
    name = "WorldClient",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._worldId = nil
            self._global = nil
            self._chunkGrid = nil
            self._loadedChunks = {}      -- "cx,cz" → { container, tileKey }
            self._pendingBorderDoors = {} -- "cx,cz" → array of door data
            self._heightField = nil
            self._gotResponse = false
            self._pollConnection = nil
            self._lastPlayerChunk = nil
            self._dungeonContainer = nil
        end,

        onStart = function(self) end,

        onStop = function(self)
            self:_stopBackgroundLoading()
            self:_stopTracking()
            self:_unloadAllChunks()
        end,
    },

    ------------------------------------------------------------------------
    -- Synchronous call (same pattern as DungeonOrchestrator)
    ------------------------------------------------------------------------

    _syncCall = function(self, signalName, payload)
        self._gotResponse = false
        payload._msgId = nil
        self.Out:Fire(signalName, payload)
        while not self._gotResponse do
            task.wait()
        end
    end,

    ------------------------------------------------------------------------
    -- VPS RPC helpers
    ------------------------------------------------------------------------

    _callVPS = function(self, action, rpcPayload)
        local RunService = game:GetService("RunService")
        local result

        if RunService:IsStudio() then
            local HttpService = game:GetService("HttpService")
            local body = HttpService:JSONEncode({
                action  = action,
                payload = rpcPayload,
            })
            local ok, response = pcall(HttpService.RequestAsync, HttpService, {
                Url     = "http://localhost:8091/rpc",
                Method  = "POST",
                Headers = {
                    ["Content-Type"]  = "application/json",
                    ["Authorization"] = "Bearer igw-dev-token",
                },
                Body = body,
            })
            if not ok then
                error("[WorldClient] VPS unreachable: " .. tostring(response))
            end
            if not response.Success then
                error("[WorldClient] VPS returned HTTP " .. response.StatusCode)
            end
            result = HttpService:JSONDecode(response.Body)
        else
            local WarrenSDK = require(game:GetService("ServerStorage").WarrenSDK)
            local ok, res = pcall(WarrenSDK.World.create, rpcPayload)
            if not ok then
                error("[WorldClient] SDK call failed: " .. tostring(res))
            end
            result = res
        end

        return result
    end,

    ------------------------------------------------------------------------
    -- Chunk coord helpers
    ------------------------------------------------------------------------

    _worldToChunk = function(self, worldX, worldZ)
        local grid = self._chunkGrid
        if not grid then return 0, 0 end
        local cx = floor((worldX - grid.mapMinX) / grid.chunkSize)
        local cz = floor((worldZ - grid.mapMinZ) / grid.chunkSize)
        cx = max(0, min(grid.sizeX - 1, cx))
        cz = max(0, min(grid.sizeZ - 1, cz))
        return cx, cz
    end,

    _getChunksInRadius = function(self, centerCX, centerCZ, radius)
        local grid = self._chunkGrid
        if not grid then return {} end
        local coords = {}
        for dx = -radius, radius do
            for dz = -radius, radius do
                local cx = centerCX + dx
                local cz = centerCZ + dz
                if cx >= 0 and cx < grid.sizeX and cz >= 0 and cz < grid.sizeZ then
                    table.insert(coords, { cx = cx, cz = cz })
                end
            end
        end
        return coords
    end,

    ------------------------------------------------------------------------
    -- Chunk loading
    ------------------------------------------------------------------------

    _loadChunks = function(self, coordsList)
        if not self._worldId then return end

        -- Filter out already-loaded chunks
        local toFetch = {}
        for _, coord in ipairs(coordsList) do
            local key = coord.cx .. "," .. coord.cz
            if not self._loadedChunks[key] then
                table.insert(toFetch, key)
            end
        end

        if #toFetch == 0 then return end

        local Debug = _G.Warren.System.Debug
        if Debug then
            Debug.info("WorldClient", "Loading", #toFetch, "chunks:", table.concat(toFetch, " "))
        end

        -- Fetch chunk data from VPS
        local result = self:_callVPS("world.action.getChunks", {
            worldId = self._worldId,
            coords  = toFetch,
        })

        if not result or result.status ~= "ok" then
            warn("[WorldClient] getChunks failed: " .. tostring(result and result.reason))
            return
        end

        local chunks = result.chunks or {}

        -- Build each chunk via DungeonOrchestrator
        for key, chunkData in pairs(chunks) do
            self:_buildChunk(key, chunkData)
        end

        -- Process border doors for newly-loaded chunks
        self:_processBorderDoors()
    end,

    _buildChunk = function(self, key, chunkData)
        if self._loadedChunks[key] then return end

        local global = self._global
        local biome = self._buildBiome
        local grid  = self._chunkGrid

        -- Build terrain tile filter: chunk coord maps to tile index
        local cx = chunkData.cx
        local cz = chunkData.cz
        local tileKey = cx .. "," .. cz

        -- Filter payload: only rooms/doors for this chunk
        local payload = {
            seed        = global.seed,
            biomeConfig = global.biomeConfig,
            inventory   = global.inventory,
            splines     = global.splines,
            maxH        = global.maxH,
            rooms       = chunkData.rooms,
            doors       = chunkData.doors,
            roomOrder   = global.roomOrder,
            spawn       = global.spawn,
            biome       = biome,
            biomeName   = self._biomeName,
            -- Chunk filter for terrain tiles
            chunkFilter = { [tileKey] = true },
            -- Chunk bounds for rock scatter
            chunkBounds = {
                minX = chunkData.worldMinX,
                minZ = chunkData.worldMinZ,
                maxX = chunkData.worldMinX + grid.chunkSize,
                maxZ = chunkData.worldMinZ + grid.chunkSize,
            },
            -- Flag: this is a chunk build (DungeonOrchestrator uses this)
            isChunkBuild = true,
            chunkKey = key,
        }

        -- Height field stored from initial compute
        payload.heightField      = self._heightField
        payload.heightFieldGridW = self._hfGridW
        payload.heightFieldGridD = self._hfGridD
        payload.heightFieldMinX  = self._hfMinX
        payload.heightFieldMinZ  = self._hfMinZ

        -- Pre-register entry so onChunkBuildComplete can update container ref
        self._loadedChunks[key] = {
            container = nil,
            tileKey = tileKey,
            chunkData = chunkData,
        }

        -- Dispatch to DungeonOrchestrator (onChunkBuildComplete sets loaded.container)
        self:_syncCall("buildChunk", payload)

        -- Stash border doors for later processing
        if chunkData.borderDoors and #chunkData.borderDoors > 0 then
            self._pendingBorderDoors[key] = chunkData.borderDoors
        end
    end,

    _processBorderDoors = function(self)
        -- Build border doors when both adjacent chunks are loaded
        for key, doors in pairs(self._pendingBorderDoors) do
            local allLoaded = true
            for _, door in ipairs(doors) do
                local roomAChunk = self:_findRoomChunk(door.fromRoom)
                local roomBChunk = self:_findRoomChunk(door.toRoom)
                if not (roomAChunk and self._loadedChunks[roomAChunk]
                    and roomBChunk and self._loadedChunks[roomBChunk]) then
                    allLoaded = false
                    break
                end
            end

            if allLoaded then
                -- All rooms for these border doors are loaded — build them
                self.Out:Fire("buildBorderDoors", {
                    doors = doors,
                    chunkKey = key,
                })
                self._pendingBorderDoors[key] = nil
            end
        end
    end,

    _findRoomChunk = function(self, roomId)
        for key, loaded in pairs(self._loadedChunks) do
            if loaded.chunkData and loaded.chunkData.rooms
                and loaded.chunkData.rooms[roomId] then
                return key
            end
        end
        return nil
    end,

    ------------------------------------------------------------------------
    -- Chunk unloading
    ------------------------------------------------------------------------

    _unloadChunksOutsideRadius = function(self, centerCX, centerCZ, radius)
        local grid = self._chunkGrid
        if not grid then return end

        local toUnload = {}

        for key, loaded in pairs(self._loadedChunks) do
            local parts = string.split(key, ",")
            local cx = tonumber(parts[1]) or 0
            local cz = tonumber(parts[2]) or 0

            local dx = math.abs(cx - centerCX)
            local dz = math.abs(cz - centerCZ)

            if dx > radius or dz > radius then
                table.insert(toUnload, key)
            end
        end

        for _, key in ipairs(toUnload) do
            self:_unloadChunk(key)
        end
    end,

    _unloadChunk = function(self, key)
        local loaded = self._loadedChunks[key]
        if not loaded then return end

        -- Destroy room container
        if loaded.container and loaded.container.Parent then
            loaded.container:Destroy()
        end

        -- Clear terrain tile with FillRegion(Air)
        if loaded.chunkData and self._chunkGrid then
            local grid = self._chunkGrid
            local cd = loaded.chunkData
            local tileMinX = cd.worldMinX
            local tileMinZ = cd.worldMinZ
            local tileMaxX = tileMinX + grid.chunkSize
            local tileMaxZ = tileMinZ + grid.chunkSize
            local maxH = self._global and self._global.maxH or 500

            local region = Region3.new(
                Vector3.new(tileMinX, -VOXEL, tileMinZ),
                Vector3.new(tileMaxX, maxH + VOXEL, tileMaxZ)
            )
            workspace.Terrain:FillRegion(region:ExpandToGrid(VOXEL), VOXEL, Enum.Material.Air)
        end

        -- Remove border doors for this chunk
        self._pendingBorderDoors[key] = nil

        self._loadedChunks[key] = nil

        local Debug = _G.Warren.System.Debug
        if Debug then
            Debug.info("WorldClient", "Unloaded chunk:", key)
        end
    end,

    _unloadAllChunks = function(self)
        for key in pairs(self._loadedChunks) do
            self:_unloadChunk(key)
        end
    end,

    ------------------------------------------------------------------------
    -- Player position tracking
    ------------------------------------------------------------------------

    _startTracking = function(self)
        if self._pollConnection then return end

        local loadRadius   = self:getAttribute("loadRadius") or 2
        local unloadRadius = self:getAttribute("unloadRadius") or 4
        local pollInterval = self:getAttribute("pollInterval") or 1.0
        local elapsed = 0

        self._pollConnection = game:GetService("RunService").Heartbeat:Connect(function(dt)
            elapsed = elapsed + dt
            if elapsed < pollInterval then return end
            elapsed = 0

            local Players = game:GetService("Players")
            -- Use first player's position (Phase 1: single-player chunk set)
            local player = Players:GetPlayers()[1]
            if not player then return end

            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            local pos = hrp.Position
            local cx, cz = self:_worldToChunk(pos.X, pos.Z)
            local chunkKey = cx .. "," .. cz

            if chunkKey == self._lastPlayerChunk then return end
            self._lastPlayerChunk = chunkKey

            -- Load chunks in load radius
            local needed = self:_getChunksInRadius(cx, cz, loadRadius)
            task.spawn(function()
                self:_loadChunks(needed)
            end)

            -- Unload chunks outside unload radius
            task.spawn(function()
                self:_unloadChunksOutsideRadius(cx, cz, unloadRadius)
            end)
        end)
    end,

    _stopTracking = function(self)
        if self._pollConnection then
            self._pollConnection:Disconnect()
            self._pollConnection = nil
        end
    end,

    ------------------------------------------------------------------------
    -- Background loading — load remaining chunks outward from spawn
    ------------------------------------------------------------------------

    _startBackgroundLoading = function(self)
        if self._bgLoadRunning then return end
        self._bgLoadRunning = true

        local selfRef = self
        task.spawn(function()
            local grid = selfRef._chunkGrid
            if not grid then return end

            -- Build spiral order outward from spawn chunk
            local spawnCX = selfRef._spawnCX or 0
            local spawnCZ = selfRef._spawnCZ or 0
            local maxR = math.max(grid.sizeX, grid.sizeZ)

            for r = 0, maxR do
                if not selfRef._bgLoadRunning then break end

                local coords = selfRef:_getChunksInRadius(spawnCX, spawnCZ, r)
                local toLoad = {}
                for _, coord in ipairs(coords) do
                    local key = coord.cx .. "," .. coord.cz
                    if not selfRef._loadedChunks[key] then
                        table.insert(toLoad, coord)
                    end
                end

                if #toLoad > 0 then
                    selfRef:_loadChunks(toLoad)
                    -- Yield between rings to avoid blocking gameplay
                    task.wait()
                end
            end

            local loadedCount = 0
            for _ in pairs(selfRef._loadedChunks) do loadedCount = loadedCount + 1 end
            print(string.format("[WorldClient] Background loading complete: %d chunks", loadedCount))
            selfRef._bgLoadRunning = false
        end)
    end,

    _stopBackgroundLoading = function(self)
        self._bgLoadRunning = false
    end,

    ------------------------------------------------------------------------
    -- Signal handlers
    ------------------------------------------------------------------------

    In = {
        onBuildWorld = function(self, data)
            local selfRef = self
            task.spawn(function()
                local Dom = _G.Warren.Dom
                local Debug = _G.Warren.System.Debug
                local startTime = os.clock()

                local biome = data.biome or {}
                local biomeName = data.biomeName or "mountain"
                local computeTarget = selfRef:getAttribute("computeTarget") or "warren"

                selfRef._biomeName = biomeName
                selfRef._buildBiome = biome

                if Debug then
                    Debug.info("WorldClient", "Building world:", biomeName, "compute:", computeTarget)
                end

                --------------------------------------------------------
                -- Step 1: Create world on VPS → get global + worldId
                --------------------------------------------------------

                local createResult = selfRef:_callVPS("world.action.create", {
                    biomeName = biomeName,
                })

                if not createResult or createResult.status ~= "ok" then
                    warn("[WorldClient] world.create failed: " .. tostring(createResult and createResult.reason))
                    return
                end

                selfRef._worldId = createResult.worldId
                selfRef._global  = createResult.global
                selfRef._chunkGrid = createResult.global.chunkGrid

                local global = createResult.global

                if Debug then
                    Debug.info("WorldClient", "World created:", selfRef._worldId,
                        "seed:", global.seed,
                        "grid:", global.chunkGrid.sizeX .. "x" .. global.chunkGrid.sizeZ)
                end

                --------------------------------------------------------
                -- Step 2: Compute height field locally (deterministic)
                --------------------------------------------------------

                -- Apply biome lighting (same as DungeonOrchestrator)
                local lc = biome.lighting
                if lc then
                    local Lighting = game:GetService("Lighting")
                    Lighting.ClockTime = lc.ClockTime or 0
                    Lighting.Brightness = lc.Brightness or 0
                    Lighting.OutdoorAmbient = Color3.fromRGB(
                        lc.OutdoorAmbient[1] or 0,
                        lc.OutdoorAmbient[2] or 0,
                        lc.OutdoorAmbient[3] or 0
                    )
                    Lighting.Ambient = Color3.fromRGB(
                        lc.Ambient[1] or 20,
                        lc.Ambient[2] or 20,
                        lc.Ambient[3] or 25
                    )
                    Lighting.FogEnd = lc.FogEnd or 1000
                    Lighting.FogColor = Color3.fromRGB(
                        lc.FogColor[1] or 0,
                        lc.FogColor[2] or 0,
                        lc.FogColor[3] or 0
                    )
                    Lighting.GlobalShadows = lc.GlobalShadows or false
                end

                -- Set up style resolver
                local StyleBridge = Dom.StyleBridge
                local Styles = _G.Warren.Styles
                local ClassResolver = _G.Warren.ClassResolver
                local resolver = StyleBridge.createResolver(Styles, ClassResolver)
                Dom.setStyleResolver(resolver)

                -- TerrainPainterNode.computeHeightField is called via _syncCall
                -- We pre-store the seed so DungeonOrchestrator uses it
                local heightFieldPayload = {
                    seed        = global.seed,
                    biomeConfig = global.biomeConfig,
                    splines     = global.splines,
                    maxH        = global.maxH,
                }

                -- Compute height field via TerrainPainterNode (reused for all chunks)
                -- Actually — height field is computed inside TerrainPainterNode.onPaintTerrain.
                -- We need the height field for room building. Let's compute it directly.
                local TerrainPainterNode = nil
                -- Access the computeHeightField function from the node module
                -- It's a module-level function exposed on the return table
                for _, child in ipairs(game:GetService("ServerStorage"):GetChildren()) do
                    if child.Name == "TerrainPainterNode" then
                        TerrainPainterNode = require(child)
                        break
                    end
                end

                -- Fall back: compute inline (the function is pure math)
                local mapWidth = selfRef:getAttribute("mapWidth") or 4000
                local mapDepth = selfRef:getAttribute("mapDepth") or 4000
                local groundY  = selfRef:getAttribute("groundY") or 0

                -- We can't require the node module from here directly (it's loaded
                -- by Bootstrap). Instead, fire paintTerrain for just the initial chunks
                -- and let it compute + cache the height field on the payload.

                -- For Phase 1, the height field IS computed by TerrainPainterNode
                -- on each chunk build. Since height field is deterministic and
                -- identical across all chunks, the first chunk build computes it
                -- and we cache it for subsequent builds.

                --------------------------------------------------------
                -- Step 3: Create parent container for room geometry
                -- MiniMap's _connectZones searches workspace.Dungeon
                -- for RoomZone_ parts. Chunk room containers are
                -- re-parented here so zone detection works.
                --------------------------------------------------------

                local dungeonContainer = Instance.new("Model")
                dungeonContainer.Name = "Dungeon"
                dungeonContainer.Parent = workspace
                selfRef._dungeonContainer = dungeonContainer

                --------------------------------------------------------
                -- Step 4: Load initial chunks around spawn
                --------------------------------------------------------

                local spawn = global.spawn
                local spawnX = spawn and spawn.position and spawn.position[1] or 0
                local spawnZ = spawn and spawn.position and spawn.position[3] or 0

                local spawnCX, spawnCZ = selfRef:_worldToChunk(spawnX, spawnZ)
                local loadRadius = selfRef:getAttribute("loadRadius") or 2
                local initialCoords = selfRef:_getChunksInRadius(spawnCX, spawnCZ, loadRadius)

                if Debug then
                    Debug.info("WorldClient", "Loading initial chunks around spawn",
                        "cx:", spawnCX, "cz:", spawnCZ, "count:", #initialCoords)
                end

                selfRef:_loadChunks(initialCoords)

                --------------------------------------------------------
                -- Step 4: Start player tracking
                --------------------------------------------------------

                selfRef._spawnCX = spawnCX
                selfRef._spawnCZ = spawnCZ
                selfRef._lastPlayerChunk = spawnCX .. "," .. spawnCZ
                selfRef:_startTracking()

                --------------------------------------------------------
                -- Done — fire worldReady, then start background loading
                --------------------------------------------------------

                local elapsed = os.clock() - startTime
                local loadedCount = 0
                for _ in pairs(selfRef._loadedChunks) do loadedCount = loadedCount + 1 end

                print(string.format(
                    "[WorldClient] World ready: %s | %d chunks loaded (%.2fs)",
                    selfRef._worldId, loadedCount, elapsed
                ))

                selfRef.Out:Fire("worldReady", {
                    worldId = selfRef._worldId,
                    global  = global,
                    spawn   = global.spawn,
                    biome   = biome,
                    biomeName = biomeName,
                })

                -- Load remaining chunks in the background (outward from spawn)
                selfRef:_startBackgroundLoading()
            end)
        end,

        onDestroyWorld = function(self)
            self:_stopBackgroundLoading()
            self:_stopTracking()
            self:_unloadAllChunks()
            workspace.Terrain:Clear()

            -- Clean up mesh terrain
            local meshTerrain = workspace:FindFirstChild("MeshTerrain")
            if meshTerrain then meshTerrain:Destroy() end

            -- Destroy world on VPS
            if self._worldId then
                pcall(function()
                    self:_callVPS("world.action.destroy", {
                        worldId = self._worldId,
                    })
                end)
            end

            -- Destroy Dungeon container (room geometry parent)
            if self._dungeonContainer then
                self._dungeonContainer:Destroy()
                self._dungeonContainer = nil
            end

            self._worldId = nil
            self._global = nil
            self._chunkGrid = nil
            self._loadedChunks = {}
            self._pendingBorderDoors = {}
            self._heightField = nil
            self._lastPlayerChunk = nil

            self.Out:Fire("worldDestroyed", {})
        end,

        onChunkBuildComplete = function(self, payload)
            -- Cache height field from first chunk build
            if not self._heightField and payload.heightField then
                self._heightField = payload.heightField
                self._hfGridW = payload.heightFieldGridW
                self._hfGridD = payload.heightFieldGridD
                self._hfMinX  = payload.heightFieldMinX
                self._hfMinZ  = payload.heightFieldMinZ
            end

            -- Store container reference + re-parent room containers under Dungeon
            if payload.chunkKey and payload.container then
                local loaded = self._loadedChunks[payload.chunkKey]
                if loaded then
                    loaded.container = payload.container
                end
                -- Room containers ("Chunk_*") go under Dungeon for MiniMap zone detection
                if self._dungeonContainer
                    and not payload.container.Name:match("^ChunkTerrain") then
                    payload.container.Parent = self._dungeonContainer
                end
            end

            self._gotResponse = true
        end,

        onNodeComplete = function(self)
            self._gotResponse = true
        end,
    },
}
