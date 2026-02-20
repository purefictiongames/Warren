--[[
    IGW v2 Pipeline — ChunkManager

    Manages terrain chunk loading/unloading based on player proximity.
    Receives topology data (polygon features) from the build pipeline,
    stores it, then streams terrain voxels by sending paint/clear signals
    to TopologyTerrainPainter for chunks within the load radius.

    v3.1: Region awareness — requests new regions from TopologyBuilder
    as the player approaches boundaries. Features from all loaded regions
    are merged into one array for chunk filtering.

    Initial load: all chunks around spawn, synchronous (blocks pipeline).
    Ongoing: heartbeat-driven, one chunk per tick, throttled.
--]]

return {
    name = "ChunkManager",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._features = {}
            self._groundFill = nil
            self._biome = nil
            self._spawn = nil
            self._peakElevation = 0

            self._loadedChunks = {}   -- { ["cx,cz"] = true }
            self._chunkSize = 512
            self._loadRadius = 1024
            self._unloadRadius = 1280
            self._checkInterval = 0.25

            self._heartbeatConn = nil
            self._lastCheck = 0
            self._chunkDone = false

            -- Water + sand levels
            self._waterLevel = nil   -- studs (Y), nil = no water
            self._sandLevel = nil    -- studs (Y), nil = no sand

            -- Region expansion
            self._regionSize = 4000
            self._loadedRegions = {}  -- { ["rx,rz"] = true }
            self._regionDone = false
            self._regionBuffer = nil
        end,

        onStart = function(self) end,

        onStop = function(self)
            if self._heartbeatConn then
                self._heartbeatConn:Disconnect()
                self._heartbeatConn = nil
            end
        end,
    },

    ------------------------------------------------------------------------
    -- Chunk coordinate helpers
    ------------------------------------------------------------------------

    _chunkKey = function(self, cx, cz)
        return cx .. "," .. cz
    end,

    _parseKey = function(self, key)
        local cx, cz = key:match("^(-?%d+),(-?%d+)$")
        return tonumber(cx), tonumber(cz)
    end,

    _chunkBounds = function(self, cx, cz)
        local s = self._chunkSize
        return {
            minX = cx * s,
            maxX = (cx + 1) * s,
            minZ = cz * s,
            maxZ = (cz + 1) * s,
        }
    end,

    ------------------------------------------------------------------------
    -- AABB intersection test for polygon features
    ------------------------------------------------------------------------

    _featureInChunk = function(self, feature, bounds)
        return feature.boundMaxX > bounds.minX
           and feature.boundMinX < bounds.maxX
           and feature.boundMaxZ > bounds.minZ
           and feature.boundMinZ < bounds.maxZ
    end,

    ------------------------------------------------------------------------
    -- Filter topology data for a chunk
    ------------------------------------------------------------------------

    _filterForChunk = function(self, bounds)
        local features = {}

        for _, feature in ipairs(self._features) do
            if self:_featureInChunk(feature, bounds) then
                table.insert(features, feature)
            end
        end

        return features
    end,

    ------------------------------------------------------------------------
    -- Region expansion — request new regions from TopologyManager
    ------------------------------------------------------------------------

    _checkRegions = function(self, px, pz)
        local rs = self._regionSize
        local prx = math.floor(px / rs + 0.5)
        local prz = math.floor(pz / rs + 0.5)

        for drx = -1, 1 do
            for drz = -1, 1 do
                local rx, rz = prx + drx, prz + drz
                local key = rx .. "," .. rz

                -- Clamp to Roblox terrain limits (~16384 studs per axis)
                if math.abs(rx * rs) + rs / 2 > 16000
                    or math.abs(rz * rs) + rs / 2 > 16000 then
                    continue
                end

                if not self._loadedRegions[key] then
                    self:_requestRegion(rx, rz)
                    return  -- one region per heartbeat tick
                end
            end
        end
    end,

    _requestRegion = function(self, rx, rz)
        self._regionDone = false
        self.Out:Fire("expandRegion", { _msgId = nil, rx = rx, rz = rz })
        while not self._regionDone do task.wait() end

        if self._regionBuffer then
            for _, f in ipairs(self._regionBuffer.features) do
                table.insert(self._features, f)
            end
            self._peakElevation = math.max(
                self._peakElevation,
                self._regionBuffer.peakElevation
            )
            self._regionBuffer = nil
        end

        self._loadedRegions[rx .. "," .. rz] = true
        print(string.format(
            "[ChunkManager] Region (%d,%d) merged — %d total features",
            rx, rz, #self._features
        ))
    end,

    ------------------------------------------------------------------------
    -- Load / unload a single chunk (synchronous via IPC flag)
    ------------------------------------------------------------------------

    _loadChunk = function(self, cx, cz)
        local key = self:_chunkKey(cx, cz)
        if self._loadedChunks[key] then return end

        local bounds = self:_chunkBounds(cx, cz)
        local features = self:_filterForChunk(bounds)

        -- Construct per-chunk groundFill (infinite ground plane)
        local groundFill = self._groundFill and {
            position = {
                (bounds.minX + bounds.maxX) / 2,
                self._groundFill.y,
                (bounds.minZ + bounds.maxZ) / 2,
            },
            size = {
                self._chunkSize,
                self._groundFill.height,
                self._chunkSize,
            },
        }

        self._chunkDone = false
        local msg = {
            _msgId = nil,
            action = "paint",
            bounds = bounds,
            features = features,
            groundFill = groundFill,
            biome = self._biome,
            peakElevation = self._peakElevation,
            waterLevel = self._waterLevel,
            sandLevel = self._sandLevel,
        }
        self.Out:Fire("paintChunk", msg)
        while not self._chunkDone do
            task.wait()
        end

        self._loadedChunks[key] = true
    end,

    _unloadChunk = function(self, cx, cz)
        local key = self:_chunkKey(cx, cz)
        if not self._loadedChunks[key] then return end

        local bounds = self:_chunkBounds(cx, cz)

        self._chunkDone = false
        local msg = {
            _msgId = nil,
            action = "clear",
            bounds = bounds,
            peakElevation = self._peakElevation,
        }
        self.Out:Fire("clearChunk", msg)
        while not self._chunkDone do
            task.wait()
        end

        self._loadedChunks[key] = nil
    end,

    ------------------------------------------------------------------------
    -- Player position (falls back to spawn)
    ------------------------------------------------------------------------

    _getPlayerPos = function(self)
        local Players = game:GetService("Players")
        for _, player in ipairs(Players:GetPlayers()) do
            local char = player.Character
            if char then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then
                    return root.Position.X, root.Position.Z
                end
            end
        end
        if self._spawn then
            return self._spawn[1], self._spawn[3]
        end
        return 0, 0
    end,

    ------------------------------------------------------------------------
    -- Determine which chunks should be loaded for a position
    ------------------------------------------------------------------------

    _chunksInRadius = function(self, px, pz, radius)
        local cs = self._chunkSize
        local minCX = math.floor((px - radius) / cs)
        local maxCX = math.floor((px + radius) / cs)
        local minCZ = math.floor((pz - radius) / cs)
        local maxCZ = math.floor((pz + radius) / cs)

        local result = {}
        for cx = minCX, maxCX do
            for cz = minCZ, maxCZ do
                local ccx = (cx + 0.5) * cs
                local ccz = (cz + 0.5) * cs
                local dist = math.sqrt(
                    (ccx - px) ^ 2 + (ccz - pz) ^ 2
                )
                if dist <= radius + cs * 0.71 then  -- 0.71 ~ sqrt(2)/2
                    table.insert(result, { cx = cx, cz = cz })
                end
            end
        end
        return result
    end,

    ------------------------------------------------------------------------
    -- Heartbeat: check regions, then load/unload one chunk per tick
    ------------------------------------------------------------------------

    _onHeartbeat = function(self)
        local now = os.clock()
        if now - self._lastCheck < self._checkInterval then return end
        self._lastCheck = now

        local px, pz = self:_getPlayerPos()
        local cs = self._chunkSize

        -- Expand regions around player (one per tick if needed)
        self:_checkRegions(px, pz)

        -- Check for one chunk to load
        local needed = self:_chunksInRadius(px, pz, self._loadRadius)
        for _, c in ipairs(needed) do
            local key = self:_chunkKey(c.cx, c.cz)
            if not self._loadedChunks[key] then
                self:_loadChunk(c.cx, c.cz)
                return  -- one per tick
            end
        end

        -- Check for one chunk to unload
        for key, _ in pairs(self._loadedChunks) do
            local cx, cz = self:_parseKey(key)
            local ccx = (cx + 0.5) * cs
            local ccz = (cz + 0.5) * cs
            local dist = math.sqrt(
                (ccx - px) ^ 2 + (ccz - pz) ^ 2
            )
            if dist > self._unloadRadius + cs * 0.71 then
                self:_unloadChunk(cx, cz)
                return  -- one per tick
            end
        end
    end,

    ------------------------------------------------------------------------
    -- Signals
    ------------------------------------------------------------------------

    In = {
        onInitChunks = function(self, payload)
            local t0 = os.clock()

            -- Store topology data
            self._features = payload.features or {}
            self._biome = payload.biome
            self._spawn = payload.spawn and payload.spawn.position
            self._waterLevel = payload.waterLevel  -- nil = no water
            self._sandLevel = payload.sandLevel    -- nil = no sand

            -- Store groundFill in simplified form (y + height only)
            local gf = payload.groundFill
            if gf then
                self._groundFill = {
                    y = gf.y or gf.position[2],
                    height = gf.height or gf.size[2],
                }
            end

            -- Find peak elevation from features
            self._peakElevation = 0
            for _, feature in ipairs(self._features) do
                if feature.peakY > self._peakElevation then
                    self._peakElevation = feature.peakY
                end
            end

            -- Config from attributes
            self._chunkSize =
                self:getAttribute("chunkSize") or 512
            self._loadRadius =
                self:getAttribute("loadRadius") or 1024
            self._unloadRadius =
                self:getAttribute("unloadRadius") or 1280
            self._checkInterval =
                self:getAttribute("checkInterval") or 0.25
            self._regionSize =
                self:getAttribute("regionSize") or 4000

            -- Mark origin region as loaded
            self._loadedRegions["0,0"] = true

            -- Initial load around spawn
            local sx, sz = 0, 0
            if self._spawn then
                sx, sz = self._spawn[1], self._spawn[3]
            end

            local initial = self:_chunksInRadius(
                sx, sz, self._loadRadius
            )
            for _, c in ipairs(initial) do
                self:_loadChunk(c.cx, c.cz)
                task.wait()  -- yield between chunks to avoid script timeout
            end

            print(string.format(
                "[ChunkManager] Initial: %d chunks"
                    .. " (size=%d, load=%d, unload=%d) — %.2fs",
                #initial, self._chunkSize,
                self._loadRadius, self._unloadRadius,
                os.clock() - t0
            ))

            -- Start heartbeat for ongoing chunk management
            local selfRef = self
            self._heartbeatConn = game:GetService("RunService")
                .Heartbeat:Connect(function()
                    selfRef:_onHeartbeat()
                end)

            payload._msgId = nil
            self.Out:Fire("nodeComplete", payload)
        end,

        onChunkDone = function(self)
            self._chunkDone = true
        end,

        onRegionReady = function(self, data)
            self._regionBuffer = data
            self._regionDone = true
        end,
    },
}
