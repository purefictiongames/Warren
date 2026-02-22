--[[
    IGW v2 — DungeonOrchestrator
    Hub-and-spoke pipeline orchestrator. Calls each node sequentially
    via unique signals, waits for nodeComplete response before proceeding.

    Phase 1: Subtractive terrain (inventory → splines → blockout → paint → rocks)
    Phase 2: Mountain rooms (ice/outdoor biome — placeRooms → shells → doors → mount → paint → cut)

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
    -- Build pipeline sequence
    ------------------------------------------------------------------------

    _runBuild = function(self, payload)
        local Dom = self._System.Dom
        local Debug = self._System and self._System.Debug

        ----------------------------------------------------------------
        -- Phase 1: Subtractive terrain
        ----------------------------------------------------------------

        self:_syncCall("buildInventory", payload)
        self:_syncCall("planSplines", payload)
        self:_syncCall("buildBlockout", payload)
        self:_syncCall("paintTerrain", payload)
        self:_syncCall("scatterRocks", payload)

        -- Mount terrain DOM to workspace
        Dom.mount(payload.dom, workspace)
        payload.container = payload.dom._instance
        self._container = payload.container

        ----------------------------------------------------------------
        -- Phase 2: Mountain rooms (ice/outdoor biome override)
        ----------------------------------------------------------------

        local terrainDom = payload.dom
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
        payload.dom = Dom.createElement("Model", { Name = "Dungeon" })

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

        -- Restore biome + DOM for downstream (dungeonComplete, spawn, etc.)
        payload.biome = savedBiome
        payload.paletteClass = savedPaletteClass
        payload.dom = terrainDom

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
            local Dom = self._System.Dom
            local StyleBridge = self._System.StyleBridge
            local Styles = self._System.Styles
            local ClassResolver = self._System.ClassResolver
            local Debug = self._System and self._System.Debug

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

            -- Create DOM root
            local root = Dom.createElement("Model", {
                Name = "Region_" .. regionNum,
            })

            -- Build payload
            local payload = {
                dom = root,
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
