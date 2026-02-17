--[[
    IGW v2 — DungeonOrchestrator
    Hub-and-spoke pipeline orchestrator. Calls each node sequentially
    via unique signals, waits for nodeComplete response before proceeding.

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
        end,

        onStart = function(self) end,

        onStop = function(self)
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
        local Canvas = Dom.Canvas
        local Debug = self._System and self._System.Debug

        -- Plan phase (DOM only, no Instances yet)
        self:_syncCall("buildMountain", payload)
        self:_syncCall("buildRooms", payload)
        self:_syncCall("buildShells", payload)
        self:_syncCall("planDoors", payload)
        self:_syncCall("buildTrusses", payload)
        self:_syncCall("buildLights", payload)

        -- Mount DOM to workspace
        Dom.mount(payload.dom, workspace)
        payload.container = payload.dom._instance

        -- Apply phase (needs mounted Instances + Canvas)
        self:_syncCall("paintTerrain", payload)

        -- Room operations: hide blockouts, air-carve, paint floors
        local rooms = payload.rooms or {}
        local biome = payload.biome or {}
        local floorMatName = biome.terrainFloor or "Grass"
        local floorMaterial = Enum.Material[floorMatName] or Enum.Material.Grass
        local container = payload.container

        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") then
                    for _, part in ipairs(child:GetChildren()) do
                        if part:IsA("BasePart") and part.Name:match("^RoomBlock_") then
                            part.Transparency = 1
                            part.CanCollide = false
                        end
                    end
                end
            end
        end

        local roomCount = 0
        for _, room in pairs(rooms) do
            Canvas.carveInterior(room.position, room.dims, 0)
            Canvas.paintFloor(room.position, room.dims, floorMaterial)
            roomCount = roomCount + 1
        end

        if Debug then
            Debug.info("DungeonOrchestrator",
                "Room terrain: carved + painted", roomCount, "rooms")
        end

        self:_syncCall("applyDoors", payload)

        -- Done
        self._container = payload.container

        if Debug then
            Debug.info("DungeonOrchestrator", "Build complete.",
                "Rooms:", payload.roomCount or "?",
                "Doors:", payload.doorCount or "?")
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
