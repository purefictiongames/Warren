--[[
    IGW v2 — DungeonOrchestrator
    Hub-and-spoke pipeline orchestrator. Calls each node sequentially
    via unique signals, waits for nodeComplete response before proceeding.

    Map generation (inventory, splines, rooms, doors) runs on the compute
    target configured via metadata `computeTarget`:
        "warren" — Warren server (Lune RPC on VPS, or localhost in Studio)
        "roblox" — Roblox game server (local pipeline nodes)

    Rendering (terrain voxels, shells, CSG, lights) always runs on Roblox.

    Receives buildDungeon from WorldMapOrchestrator.
    Sets up lighting, DOM root, then runs the build pipeline.
    Fires dungeonComplete when done.
--]]

return {
    name = "DungeonOrchestrator",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._gotResponse = false
            self._container = nil
            self._dungeonContainer = nil
        end,

        onStart = function(self) end,

        onStop = function(self)
            if self._dungeonContainer and self._dungeonContainer.Parent then
                self._dungeonContainer:Destroy()
            end
            if self._container and self._container.Parent then
                self._container:Destroy()
            end
        end,
    },

    ------------------------------------------------------------------------
    -- Synchronous call: fire signal, wait for nodeComplete flag
    -- IPC dispatch is synchronous — nodeComplete arrives during Fire(),
    -- before yield would be reached. Use a flag instead of coroutine.
    ------------------------------------------------------------------------

    _syncCall = function(self, signalName, payload)
        self._gotResponse = false
        payload._msgId = nil  -- fresh IPC message ID per call
        self.Out:Fire(signalName, payload)
        while not self._gotResponse do
            task.wait()
        end
    end,

    ------------------------------------------------------------------------
    -- Warren server compute: fetch pre-computed map data via RPC
    -- Studio: HttpService → localhost:8091 (local Lune server)
    -- Production: WarrenSDK → Registry → Lune server on VPS
    ------------------------------------------------------------------------

    _fetchFromWarren = function(self, payload)
        local RunService = game:GetService("RunService")
        local rpcPayload = {
            biomeName = payload.biomeName,
            seed      = payload.seed,
        }

        local ok, result

        if RunService:IsStudio() then
            -- Direct call to local Lune server (no SDK/Registry needed)
            local HttpService = game:GetService("HttpService")
            local body = HttpService:JSONEncode({
                action  = "mapgen.action.generate",
                payload = rpcPayload,
            })
            ok, result = pcall(HttpService.RequestAsync, HttpService, {
                Url     = "http://localhost:8091/rpc",
                Method  = "POST",
                Headers = {
                    ["Content-Type"]  = "application/json",
                    ["Authorization"] = "Bearer igw-dev-token",
                },
                Body = body,
            })
            if ok then
                if result.Success then
                    result = HttpService:JSONDecode(result.Body)
                else
                    error("[DungeonOrchestrator] Warren server returned HTTP " .. result.StatusCode)
                end
            else
                error("[DungeonOrchestrator] Warren server unreachable: " .. tostring(result)
                    .. "\n  → Studio: enable HTTP requests in Game Settings"
                    .. "\n  → Then start Lune server: lune run lune/server.lua")
            end
        else
            -- Production: WarrenSDK → Registry → Lune
            local WarrenSDK = require(game:GetService("ServerStorage").WarrenSDK)
            ok, result = pcall(WarrenSDK.MapGen.generate, rpcPayload)
            if not ok then
                error("[DungeonOrchestrator] Warren server failed: " .. tostring(result))
            end
        end

        if result and result.status == "ok" then
            return result.mapData
        end

        error("[DungeonOrchestrator] Warren server returned unexpected status: "
            .. tostring(result and result.status) .. " — "
            .. tostring(result and result.reason))
    end,

    ------------------------------------------------------------------------
    -- Build pipeline sequence
    ------------------------------------------------------------------------

    _runBuild = function(self, payload)
        local Dom = _G.Warren.Dom
        local Debug = _G.Warren.System.Debug
        local computeTarget = self:getAttribute("computeTarget") or "warren"

        ----------------------------------------------------------------
        -- Map generation: compute target determines WHERE it runs
        ----------------------------------------------------------------

        if computeTarget == "warren" then
            -- Warren server (VPS Lune) — fetch pre-computed data via RPC
            local mapData = self:_fetchFromWarren(payload)

            payload.biomeConfig = mapData.biomeConfig
            payload.inventory   = mapData.inventory
            payload.splines     = mapData.splines
            payload.rooms       = mapData.rooms
            payload.roomOrder   = mapData.roomOrder
            payload.doors       = mapData.doors
            payload.maxH        = mapData.maxH
            if mapData.spawn then
                payload.spawn = mapData.spawn
            end
            if mapData.seed then
                payload.seed = mapData.seed  -- Adopt pool map's seed for height field
            end

            local roomCount = 0
            if mapData.rooms then
                for _ in pairs(mapData.rooms) do roomCount = roomCount + 1 end
            end
            if Debug then
                Debug.info("DungeonOrchestrator", "Compute: warren |",
                    #(mapData.splines or {}), "splines,",
                    roomCount, "rooms,",
                    #(mapData.doors or {}), "doors")
            end
        elseif computeTarget == "roblox" then
            -- Roblox server — compute locally via pipeline nodes
            if Debug then
                Debug.info("DungeonOrchestrator", "Compute: roblox (local pipeline)")
            end
            self:_syncCall("buildInventory", payload)
            self:_syncCall("planSplines", payload)
            self:_syncCall("buildBlockout", payload)
        else
            error("[DungeonOrchestrator] Invalid computeTarget: " .. tostring(computeTarget)
                .. ' — must be "warren" or "roblox"')
        end

        ----------------------------------------------------------------
        -- Rendering: always on Roblox (terrain voxels or mesh)
        ----------------------------------------------------------------

        local terrainRenderer = self:getAttribute("terrainRenderer") or "voxel"
        if terrainRenderer == "mesh" then
            self:_syncCall("paintMeshTerrain", payload)
        else
            self:_syncCall("paintTerrain", payload)
            self:_syncCall("scatterRocks", payload)
        end

        -- Mount terrain DOM to workspace
        local terrainRoot = Dom.getRoot()
        Dom.mount(terrainRoot, workspace)
        payload.container = terrainRoot._instance
        self._container = payload.container

        ----------------------------------------------------------------
        -- Phase 2: Mountain rooms (ice/outdoor biome override)
        ----------------------------------------------------------------

        local savedBiome = payload.biome
        local savedPaletteClass = payload.paletteClass

        -- Override biome to ice/outdoor for room rendering
        payload.biome = {
            terrainStyle = "outdoor",
            paletteClass = "palette-glacier-ice",
            terrainWall = "Glacier",
            terrainWallMix = "Rock",
            terrainFloor = "Snow",
            partWall = "Ice",
            partFloor = "Glacier",
            doorWallClass = "ice-wall-solid",
            lightType = savedBiome.lightType or "PointLight",
            lightStyle = savedBiome.lightStyle or "cave-torch-light",
            lighting = savedBiome.lighting,
        }
        payload.paletteClass = "palette-glacier-ice"

        -- Swap DOM root for room phase
        Dom.setRoot(Dom.createElement("Model", { Name = "Dungeon" }))

        self:_syncCall("placeRooms", payload)          -- MountainRoomPlacer
        self:_syncCall("buildShells", payload)         -- ShellBuilder
        self:_syncCall("planDoors", payload)            -- DoorPlanner
        self:_syncCall("buildTrusses", payload)        -- TrussBuilder
        self:_syncCall("buildLights", payload)         -- LightBuilder (skips — skipLights)
        self:_syncCall("mount", payload)               -- Materializer
        self:_syncCall("paintMountainRooms", payload)  -- IceTerrainPainter alias
        self:_syncCall("applyDoors", payload)          -- DoorPlanner phase 2
        self:_syncCall("cutDoors", payload)            -- DoorCutter alias

        self._dungeonContainer = payload.container

        -- Restore biome + root for downstream (dungeonComplete, spawn, etc.)
        payload.biome = savedBiome
        payload.paletteClass = savedPaletteClass
        Dom.setRoot(terrainRoot)

        ----------------------------------------------------------------
        -- Done
        ----------------------------------------------------------------

        if Debug then
            local splineCount = payload.splines and #payload.splines or 0
            local roomCount = 0
            if payload.rooms then
                for _ in pairs(payload.rooms) do roomCount = roomCount + 1 end
            end
            local invParts = {}
            if payload.inventory then
                for k, v in pairs(payload.inventory) do
                    if v > 0 then
                        table.insert(invParts, k .. "=" .. v)
                    end
                end
                table.sort(invParts)
            end
            Debug.info("DungeonOrchestrator", "Build complete.",
                "Splines:", splineCount,
                "Rooms:", roomCount,
                "Inventory:", table.concat(invParts, " "))
        end

        payload._msgId = nil
        self.Out:Fire("dungeonComplete", payload)
    end,

    In = {
        onBuildDungeon = function(self, data)
            local Dom = _G.Warren.Dom
            local StyleBridge = _G.Warren.Dom.StyleBridge
            local Styles = _G.Warren.Styles
            local ClassResolver = _G.Warren.ClassResolver
            local Debug = _G.Warren.System.Debug

            local biome = data.biome or {}
            local biomeName = data.biomeName or "unknown"
            local allBiomes = data.allBiomes or {}
            local worldMap = data.worldMap or {}
            local seed = data.seed or (os.time() + math.random(1, 9999))
            local regionNum = data.regionNum or 1

            -- Apply biome lighting
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
            local resolver = StyleBridge.createResolver(Styles, ClassResolver)
            Dom.setStyleResolver(resolver)

            -- Palette from biome
            local paletteClass = biome.paletteClass or StyleBridge.getPaletteClass(regionNum)

            if Debug then
                Debug.info("DungeonOrchestrator", "Building:", biomeName,
                    "Seed:", seed, "Region:", regionNum, "Palette:", paletteClass)
            end

            -- Create DOM root (shared via Dom.getRoot(), not passed on payload)
            Dom.setRoot(Dom.createElement("Model", {
                Name = "Region_" .. regionNum,
            }))

            -- Build payload
            local payload = {
                seed = seed,
                regionNum = regionNum,
                paletteClass = paletteClass,
                biome = biome,
                biomeName = biomeName,
                allBiomes = allBiomes,
                worldMap = worldMap,
            }

            -- Run in background thread (task.wait in _syncCall needs yieldable context)
            local selfRef = self
            payload._msgId = nil  -- detach from buildDungeon's message chain
            task.spawn(function()
                selfRef:_runBuild(payload)
            end)
        end,

        onNodeComplete = function(self)
            self._gotResponse = true
        end,
    },
}
