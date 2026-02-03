--[[
    LibPureFiction Framework v2
    RegionManager.lua - Infinite Dungeon Region Management

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    RegionManager handles the infinite dungeon system by managing map regions:
    - Generates layouts from seeds (via Layout.Builder)
    - Stores complete layouts (not just seeds) for reliable reload
    - Instantiates layouts into parts (via Layout.Instantiator)
    - Manages two-way teleport links between pads
    - Swaps regions in/out of workspace (only one loaded at a time)

    Architecture:
    - Each region stores a complete Layout table (source of truth)
    - Layout contains all geometry data: rooms, doors, trusses, lights, pads, spawn
    - Loading a region = instantiate from stored layout (no regeneration)
    - Cross-region pad links stored separately (not part of layout)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local RegionManager = Lib.Components.RegionManager
    local manager = RegionManager:new({ id = "InfiniteDungeon" })
    manager.Sys.onInit(manager)
    manager:configure({ mainPathLength = 8, spurCount = 4, ... })
    manager:startFirstRegion()
    ```

    ============================================================================
    SIGNALS
    ============================================================================

    OUT (sends):
        areaInfo({ player, regionNum, roomNum, visitedRooms })
            - Fired when player enters a room or on initial spawn
            - visitedRooms: Set of room IDs player has visited in this region

        mapData({ player, layout, visitedRooms, currentRoom })
            - Response to requestMapData from MiniMap
            - Contains layout and current state for map display

        transitionStart({ player, regionId, padId })
            - Fired when teleport begins (triggers client fade-out)

        loadingComplete({ player, container })
            - Fired after region is loaded (triggers client preload)

        transitionEnd({ player })
            - Fired when teleport completes (triggers client fade-in)

    IN (receives):
        onJumpRequested({ player, padId, regionId })
            - From JumpPad when player activates a teleport pad

        onFadeOutComplete({ player })
            - From ScreenTransition when fade-out finishes

        onTransitionComplete({ player })
            - From ScreenTransition when fade-in finishes

        onRequestMapData({ player })
            - From MiniMap when it needs current map data

    ============================================================================
    PERSISTENCE
    ============================================================================

    Dungeon data is saved per-player in DataStore (DungeonData_v1).
    - Saves: regions (layouts + padLinks), regionCount, activeRegionId,
      unlinkedPadCount, visitedRooms
    - Loads on startFirstRegion(player) - resumes from last active region
    - Saves automatically on new region creation

    Size estimates (per layout, ~12 rooms):
    - Uncompressed JSON: ~4.5-5 KB
    - DataStore auto-compresses internally
    - 4MB DataStore limit = 800+ regions per player

--]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Node = require(script.Parent.Parent.Node)
local Layout = require(script.Parent.Layout)
local JumpPad = require(script.Parent.JumpPad)

--------------------------------------------------------------------------------
-- DATA STORE
--------------------------------------------------------------------------------

local DATASTORE_NAME = "DungeonData_v1"
local dungeonStore = nil

-- Initialize DataStore (deferred to avoid errors in Studio without API access)
local function getDataStore()
    if not dungeonStore then
        local success, store = pcall(function()
            return DataStoreService:GetDataStore(DATASTORE_NAME)
        end)
        if success then
            dungeonStore = store
        else
            warn("[RegionManager] DataStore not available:", store)
        end
    end
    return dungeonStore
end

--------------------------------------------------------------------------------
-- REGION MANAGER NODE
--------------------------------------------------------------------------------

local RegionManager = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    -- Layout generation config
                    baseUnit = 5,
                    wallThickness = 1,
                    doorSize = 12,
                    floorThreshold = 5,
                    mainPathLength = 8,
                    spurCount = 4,
                    loopCount = 1,
                    verticalChance = 30,
                    minVerticalRatio = 0.2,
                    scaleRange = { min = 4, max = 12, minY = 4, maxY = 8 },
                    material = "Brick",
                    color = { 140, 110, 90 },
                    origin = { 0, 20, 0 },
                    -- Map type thresholds (based on unlinked pad count)
                    mapTypeThresholds = {
                        spurAllowed = 5,     -- Allow spurs if unlinked >= 5
                        forceHub = 2,        -- Force hub if unlinked <= 2
                    },
                    hubPadRange = { min = 3, max = 5 },
                },
                -- Region tracking
                -- Each region stores: id, layout, padLinks, isActive, container, pads, spawnPoint
                regions = {},
                activeRegionId = nil,
                regionCount = 0,
                -- JumpPad instance IDs (for IPC.despawn)
                jumpPadIds = {},
                -- Per-player current room tracking
                -- { [Player] = { regionNum, roomNum } }
                playerRooms = {},
                -- Per-player visited rooms tracking
                -- { [Player] = { [regionNum] = { [roomId] = true } } }
                visitedRooms = {},
                -- Per-player pending transitions (for async flow)
                -- { [Player] = { regionId, padId, isNewRegion, sourceRegionId, sourcePadId } }
                pendingTransitions = {},
                -- Global unlinked pad count for infinite expansion
                unlinkedPadCount = 0,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = getState(self)
        -- Despawn all JumpPad instances via IPC
        local IPC = self._System and self._System.IPC
        if IPC then
            for _, padId in ipairs(state.jumpPadIds) do
                IPC.despawn(padId)
            end
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- DATA PERSISTENCE
    ----------------------------------------------------------------------------

    --[[
        Saves dungeon data for a player to DataStore.
        Stores: regions (layouts + padLinks), regionCount, activeRegionId,
        unlinkedPadCount, and visitedRooms.
    --]]
    local function savePlayerData(self, player)
        local store = getDataStore()
        if not store then return false end

        local state = getState(self)
        local key = "player_" .. player.UserId

        -- Build save data (only persistent fields, no runtime refs)
        local regionsToSave = {}
        for regionId, region in pairs(state.regions) do
            regionsToSave[regionId] = {
                id = region.id,
                layout = region.layout,
                padLinks = region.padLinks,
            }
        end

        -- Get visited rooms for this player
        local playerVisited = state.visitedRooms[player] or {}

        local saveData = {
            version = 1,
            regions = regionsToSave,
            regionCount = state.regionCount,
            activeRegionId = state.activeRegionId,
            unlinkedPadCount = state.unlinkedPadCount,
            visitedRooms = playerVisited,
        }

        local success, err = pcall(function()
            store:SetAsync(key, saveData)
        end)

        if success then
            local System = self._System
            if System and System.Debug then
                System.Debug.info("RegionManager", "Saved data for", player.Name)
            end
        else
            warn("[RegionManager] Failed to save data for", player.Name, ":", err)
        end

        return success
    end

    --[[
        Loads dungeon data for a player from DataStore.
        Returns true if data was found and loaded, false otherwise.
    --]]
    local function loadPlayerData(self, player)
        local store = getDataStore()
        if not store then return false end

        local state = getState(self)
        local key = "player_" .. player.UserId

        local success, data = pcall(function()
            return store:GetAsync(key)
        end)

        if not success then
            warn("[RegionManager] Failed to load data for", player.Name, ":", data)
            return false
        end

        if not data then
            -- No saved data exists
            return false
        end

        -- Restore state from saved data
        state.regionCount = data.regionCount or 0
        state.activeRegionId = data.activeRegionId
        state.unlinkedPadCount = data.unlinkedPadCount or 0

        -- Restore regions
        state.regions = {}
        if data.regions then
            for regionId, savedRegion in pairs(data.regions) do
                state.regions[regionId] = {
                    id = savedRegion.id,
                    layout = savedRegion.layout,
                    padLinks = savedRegion.padLinks or {},
                    isActive = false,
                    container = nil,
                    pads = nil,
                    spawnPoint = nil,
                    spawnPosition = nil,
                }
            end
        end

        -- Restore visited rooms for this player
        if data.visitedRooms then
            state.visitedRooms[player] = data.visitedRooms
        end

        local System = self._System
        if System and System.Debug then
            System.Debug.info("RegionManager", "Loaded data for", player.Name,
                "- regions:", state.regionCount)
        end

        return true
    end

    ----------------------------------------------------------------------------
    -- PLAYER ANCHORING (for transition safety)
    ----------------------------------------------------------------------------

    local function anchorPlayer(player)
        local character = player.Character
        if not character then return end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.Anchored = true
        end
    end

    local function unanchorPlayer(player)
        local character = player.Character
        if not character then return end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.Anchored = false
        end
    end

    ----------------------------------------------------------------------------
    -- LAYOUT GENERATION & INSTANTIATION
    ----------------------------------------------------------------------------

    local function generateSeed()
        return os.time() + math.random(1, 100000)
    end

    -- Color palette for different regions (distinct, varied tones)
    local REGION_COLORS = {
        { 140, 100, 80 },   -- Warm brown
        { 80, 100, 140 },   -- Steel blue
        { 160, 90, 90 },    -- Brick red
        { 80, 130, 100 },   -- Forest green
        { 130, 100, 150 },  -- Violet
        { 170, 140, 90 },   -- Gold/tan
        { 100, 140, 140 },  -- Teal
        { 150, 120, 100 },  -- Terracotta
        { 90, 90, 120 },    -- Slate
        { 140, 130, 100 },  -- Sandstone
    }

    local function getRegionColor(regionNum)
        -- Cycle through palette (no randomization)
        return REGION_COLORS[((regionNum - 1) % #REGION_COLORS) + 1]
    end

    ----------------------------------------------------------------------------
    -- MAP TYPE DETERMINATION
    ----------------------------------------------------------------------------
    -- Map types: spur (1 pad), corridor (2 pads), hub (3-5 pads)
    -- Selection based on current unlinked pad count to ensure infinite expansion

    local MAP_TYPES = {
        SPUR = "spur",         -- 1 pad, dead end
        CORRIDOR = "corridor", -- 2 pads, linear progression
        HUB = "hub",           -- 3-5 pads, branch point
    }

    local function determineMapType(self, isFirstRegion)
        local state = getState(self)
        local config = state.config
        local unlinked = state.unlinkedPadCount
        local thresholds = config.mapTypeThresholds

        -- First region is always a corridor (need at least 1 pad for expansion)
        if isFirstRegion then
            return MAP_TYPES.CORRIDOR, 2
        end

        -- Safety: force hub if running low on unlinked pads
        if unlinked <= thresholds.forceHub then
            local hubRange = config.hubPadRange
            local padCount = math.random(hubRange.min, hubRange.max)
            return MAP_TYPES.HUB, padCount
        end

        -- Allow spurs only if we have plenty of unlinked pads
        if unlinked >= thresholds.spurAllowed then
            -- Weighted random: 20% spur, 50% corridor, 30% hub
            local roll = math.random(100)
            if roll <= 20 then
                return MAP_TYPES.SPUR, 1
            elseif roll <= 70 then
                return MAP_TYPES.CORRIDOR, 2
            else
                local hubRange = config.hubPadRange
                local padCount = math.random(hubRange.min, hubRange.max)
                return MAP_TYPES.HUB, padCount
            end
        end

        -- Default: corridor or hub (no spurs when unlinked is moderate)
        local roll = math.random(100)
        if roll <= 60 then
            return MAP_TYPES.CORRIDOR, 2
        else
            local hubRange = config.hubPadRange
            local padCount = math.random(hubRange.min, hubRange.max)
            return MAP_TYPES.HUB, padCount
        end
    end

    local function generateLayout(self, seed, regionNum, padCount)
        local state = getState(self)
        local config = state.config

        -- Offset each region to avoid geometry overlap during transitions
        local regionOffset = (regionNum - 1) * 2000
        local origin = config.origin or { 0, 20, 0 }
        local offsetOrigin = { origin[1] + regionOffset, origin[2], origin[3] }

        -- Get unique color for this region
        local regionColor = getRegionColor(regionNum)

        -- Generate layout using Layout.Builder
        local layout = Layout.generate({
            seed = seed,
            regionNum = regionNum,
            origin = offsetOrigin,
            baseUnit = config.baseUnit,
            wallThickness = config.wallThickness,
            doorSize = config.doorSize,
            floorThreshold = config.floorThreshold,
            verticalChance = config.verticalChance,
            minVerticalRatio = config.minVerticalRatio,
            mainPathLength = config.mainPathLength,
            spurCount = config.spurCount,
            loopCount = config.loopCount,
            scaleRange = config.scaleRange,
            material = config.material,
            color = regionColor,
            padCount = padCount,  -- Direct pad count instead of roomsPerPad
        })

        return layout
    end

    local function instantiateLayout(self, regionId, layout)
        local state = getState(self)
        local region = state.regions[regionId]

        -- Instantiate using Layout.Instantiator
        local result = Layout.instantiate(layout, {
            name = "Region_" .. regionId,
            regionId = regionId,
        })

        -- Store runtime references
        if region then
            region.container = result.container
            region.spawnPoint = result.spawnPoint
            region.spawnPosition = result.spawnPosition
            region.pads = result.pads
            region.roomCount = result.roomCount
            region.roomZones = result.roomZones
        end

        return result
    end

    ----------------------------------------------------------------------------
    -- JUMPPAD MANAGEMENT
    ----------------------------------------------------------------------------

    local function createJumpPadsForRegion(self, regionId, container)
        local state = getState(self)
        local region = state.regions[regionId]
        local IPC = self._System and self._System.IPC

        if not region or not region.layout or not region.layout.pads then return end
        if not IPC then
            warn("[RegionManager] IPC not available for JumpPad creation")
            return
        end

        -- Destroy any existing Parts created by LayoutInstantiator for pads
        -- (JumpPad will create its own geometry)
        if region.pads then
            for _, padData in pairs(region.pads) do
                if padData.part then
                    padData.part:Destroy()
                end
            end
        end

        region.jumpPadNodes = {}

        for _, padData in ipairs(region.layout.pads) do
            local qualifiedPadId = regionId .. "_" .. padData.id

            -- Create JumpPad via IPC (handles wiring automatically)
            local jumpPad = IPC.createInstance("JumpPad", {
                id = qualifiedPadId,
                attributes = {
                    PadId = padData.id,
                    RegionId = regionId,
                    PositionX = padData.position[1],
                    PositionY = padData.position[2],
                    PositionZ = padData.position[3],
                    Container = container,
                },
            })

            if jumpPad then
                -- Store references
                table.insert(state.jumpPadIds, qualifiedPadId)
                region.jumpPadNodes[padData.id] = jumpPad
            end
        end
    end

    local function destroyJumpPadsForRegion(self, regionId)
        local state = getState(self)
        local region = state.regions[regionId]
        local IPC = self._System and self._System.IPC

        if not IPC then return end

        -- Despawn JumpPads for this region via IPC
        local prefix = regionId .. "_"
        local indicesToRemove = {}

        for i, padId in ipairs(state.jumpPadIds) do
            if string.sub(padId, 1, #prefix) == prefix then
                IPC.despawn(padId)
                table.insert(indicesToRemove, 1, i)  -- Insert at front for reverse iteration
            end
        end

        -- Remove from list (iterate in reverse to preserve indices)
        for _, idx in ipairs(indicesToRemove) do
            table.remove(state.jumpPadIds, idx)
        end

        if region then
            region.jumpPadNodes = nil
        end
    end

    ----------------------------------------------------------------------------
    -- AREA INFO SIGNAL
    ----------------------------------------------------------------------------

    local function fireAreaInfo(self, player, regionNum, roomNum)
        local state = getState(self)

        -- Get visited rooms for this player/region (or empty table)
        local playerVisited = state.visitedRooms[player]
        local visitedRooms = playerVisited and playerVisited[regionNum] or {}

        self.Out:Fire("areaInfo", {
            _targetPlayer = player,
            player = player,
            regionNum = regionNum,
            roomNum = roomNum,
            visitedRooms = visitedRooms,
        })
    end

    ----------------------------------------------------------------------------
    -- ZONE MANAGEMENT (for room detection)
    ----------------------------------------------------------------------------

    local function createZonesForRegion(self, regionId, roomZones)
        local state = getState(self)
        local region = state.regions[regionId]

        if not roomZones then return end

        region.zoneConnections = {}

        for roomId, zonePart in pairs(roomZones) do
            -- Connect Touched event to detect players entering rooms
            local connection = zonePart.Touched:Connect(function(otherPart)
                -- Find if this is a player character
                local character = otherPart:FindFirstAncestorOfClass("Model")
                if not character then return end

                local player = Players:GetPlayerFromCharacter(character)
                if not player then return end

                -- Get region info
                local currentRegion = state.regions[regionId]
                if not currentRegion or not currentRegion.layout then return end

                local regionNum = currentRegion.layout.regionNum or 1

                -- Check if this is a new room for this player
                local currentRoom = state.playerRooms[player]
                if currentRoom and currentRoom.regionNum == regionNum and currentRoom.roomNum == roomId then
                    return  -- Already in this room
                end

                -- Update tracking
                state.playerRooms[player] = { regionNum = regionNum, roomNum = roomId }

                -- Mark room as visited
                if not state.visitedRooms[player] then
                    state.visitedRooms[player] = {}
                end
                if not state.visitedRooms[player][regionNum] then
                    state.visitedRooms[player][regionNum] = {}
                end
                state.visitedRooms[player][regionNum][roomId] = true

                -- Fire area info to client
                fireAreaInfo(self, player, regionNum, roomId)
            end)

            table.insert(region.zoneConnections, connection)
        end
    end

    local function destroyZonesForRegion(self, regionId)
        local state = getState(self)
        local region = state.regions[regionId]

        if not region then return end

        -- Disconnect all zone connections
        if region.zoneConnections then
            for _, connection in ipairs(region.zoneConnections) do
                connection:Disconnect()
            end
            region.zoneConnections = nil
        end
    end

    function handleJumpRequest(self, regionId, padId, player)
        local state = getState(self)
        local region = state.regions[regionId]

        if not region then return end

        -- Check if player already has a pending transition
        if state.pendingTransitions[player] then
            return
        end

        local padLinks = region.padLinks or {}
        local padLink = padLinks[padId]

        -- Determine target info
        local targetRegionId, targetPadId, isNewRegion
        if padLink then
            -- Pad is linked - will teleport to existing region
            targetRegionId = padLink.regionId
            targetPadId = padLink.padId
            isNewRegion = false
        else
            -- Pad is unlinked - will generate new region
            targetRegionId = nil  -- Will be generated later
            targetPadId = nil
            isNewRegion = true
        end

        -- Store pending transition data
        state.pendingTransitions[player] = {
            sourceRegionId = regionId,
            sourcePadId = padId,
            targetRegionId = targetRegionId,
            targetPadId = targetPadId,
            isNewRegion = isNewRegion,
        }

        -- Anchor player to prevent movement/physics during transition
        anchorPlayer(player)

        -- Fire transition start signal to client (routed via IPC wiring)
        self.Out:Fire("transitionStart", {
            _targetPlayer = player,
            player = player,
            regionId = targetRegionId or "new",
            padId = targetPadId,
        })
    end

    ----------------------------------------------------------------------------
    -- REGION MANAGEMENT
    ----------------------------------------------------------------------------

    local function linkPads(self, regionA, padA, regionB, padB)
        local state = getState(self)

        local regA = state.regions[regionA]
        local regB = state.regions[regionB]

        if regA then
            regA.padLinks = regA.padLinks or {}
            regA.padLinks[padA] = { regionId = regionB, padId = padB }
        end

        if regB then
            regB.padLinks = regB.padLinks or {}
            regB.padLinks[padB] = { regionId = regionA, padId = padA }
        end

        -- Both pads are now linked (no longer available for expansion)
        state.unlinkedPadCount = state.unlinkedPadCount - 2
    end

    local function getFirstPadId(region)
        if not region or not region.layout or not region.layout.pads then
            return nil
        end
        -- Return first pad from layout
        local firstPad = region.layout.pads[1]
        return firstPad and firstPad.id
    end

    function createNewRegion(self, sourceRegionId, sourcePadId, player)
        local state = getState(self)

        -- Generate new region
        state.regionCount = state.regionCount + 1
        local newRegionId = "region_" .. state.regionCount
        local newSeed = generateSeed()
        local regionNum = state.regionCount

        -- Determine map type based on current unlinked pad count
        local mapType, padCount = determineMapType(self, false)

        -- Generate layout with determined pad count
        local layout = generateLayout(self, newSeed, regionNum, padCount)

        -- Store region with layout
        state.regions[newRegionId] = {
            id = newRegionId,
            layout = layout,
            padLinks = {},
            isActive = false,
            -- Runtime refs (set after instantiation)
            container = nil,
            pads = nil,
            spawnPoint = nil,
            spawnPosition = nil,
        }

        -- Instantiate
        local result = instantiateLayout(self, newRegionId, layout)

        -- Create JumpPad nodes for this region
        createJumpPadsForRegion(self, newRegionId, result.container)

        -- Create Zone nodes for room detection
        createZonesForRegion(self, newRegionId, result.roomZones)

        -- Track new pads for infinite expansion
        local newPadCount = layout.pads and #layout.pads or 0
        state.unlinkedPadCount = state.unlinkedPadCount + newPadCount

        -- Link first pad back to source (decrements unlinkedPadCount by 2)
        local firstPadId = getFirstPadId(state.regions[newRegionId])
        if firstPadId and sourcePadId then
            linkPads(self, sourceRegionId, sourcePadId, newRegionId, firstPadId)
        end

        -- Teleport to first pad in new region (the entry point)
        if firstPadId then
            teleportPlayerToPad(self, newRegionId, firstPadId, player)
        else
            -- Fallback to spawn if no pad
            teleportPlayerToSpawn(self, newRegionId, player)
        end

        -- Set as active
        state.regions[newRegionId].isActive = true
        local oldActiveId = state.activeRegionId
        state.activeRegionId = newRegionId

        -- Unload old region
        if oldActiveId then
            task.defer(function()
                unloadRegion(self, oldActiveId)
            end)
        end

        return newRegionId
    end

    function teleportToRegion(self, targetRegionId, targetPadId, player)
        local state = getState(self)
        local targetRegion = state.regions[targetRegionId]

        if not targetRegion then return end

        -- Track old region for unloading
        local oldActiveId = state.activeRegionId

        -- Destroy any leftover container
        if targetRegion.container then
            targetRegion.container:Destroy()
            targetRegion.container = nil
        end
        local oldContainer = workspace:FindFirstChild("Region_" .. targetRegionId)
        if oldContainer then
            oldContainer:Destroy()
        end

        -- Destroy old JumpPads and Zones for this region
        destroyJumpPadsForRegion(self, targetRegionId)
        destroyZonesForRegion(self, targetRegionId)

        -- Reinstantiate from stored layout (no regeneration!)
        local result = instantiateLayout(self, targetRegionId, targetRegion.layout)

        -- Create JumpPad nodes for this region
        createJumpPadsForRegion(self, targetRegionId, result.container)

        -- Create Zone nodes for room detection
        createZonesForRegion(self, targetRegionId, result.roomZones)

        -- Teleport to target pad
        teleportPlayerToPad(self, targetRegionId, targetPadId, player)

        -- Set as active
        targetRegion.isActive = true
        state.activeRegionId = targetRegionId

        -- Unload old region
        if oldActiveId and oldActiveId ~= targetRegionId then
            task.defer(function()
                unloadRegion(self, oldActiveId)
            end)
        end
    end

    function unloadRegion(self, regionId)
        local state = getState(self)
        local region = state.regions[regionId]

        if not region then return end

        -- Destroy Zone nodes for this region
        destroyZonesForRegion(self, regionId)

        -- Destroy JumpPad nodes for this region
        destroyJumpPadsForRegion(self, regionId)

        -- Destroy container
        if region.container then
            region.container:Destroy()
            region.container = nil
        else
            local containerName = "Region_" .. regionId
            local container = workspace:FindFirstChild(containerName)
            if container then
                container:Destroy()
            end
        end

        -- Clear runtime refs (keep layout and padLinks for reload)
        region.isActive = false
        region.pads = nil
        region.spawnPoint = nil
    end

    ----------------------------------------------------------------------------
    -- ASYNC REGION OPERATIONS (for screen transition flow)
    ----------------------------------------------------------------------------

    --[[
        Create a new region without teleporting (async flow).
        Called after client fade out is complete.
        Returns the new region ID.
    --]]
    function createNewRegionAsync(self, sourceRegionId, sourcePadId, player)
        local state = getState(self)

        -- Generate new region
        state.regionCount = state.regionCount + 1
        local newRegionId = "region_" .. state.regionCount
        local newSeed = generateSeed()
        local regionNum = state.regionCount

        -- Determine map type based on current unlinked pad count
        local mapType, padCount = determineMapType(self, false)

        -- Generate layout with determined pad count
        local layout = generateLayout(self, newSeed, regionNum, padCount)

        -- Store region with layout
        state.regions[newRegionId] = {
            id = newRegionId,
            layout = layout,
            padLinks = {},
            isActive = false,
            container = nil,
            pads = nil,
            spawnPoint = nil,
            spawnPosition = nil,
        }

        -- Instantiate
        local result = instantiateLayout(self, newRegionId, layout)

        -- Create JumpPad nodes for this region
        createJumpPadsForRegion(self, newRegionId, result.container)

        -- Create Zone nodes for room detection
        createZonesForRegion(self, newRegionId, result.roomZones)

        -- Track new pads for infinite expansion
        local newPadCount = layout.pads and #layout.pads or 0
        state.unlinkedPadCount = state.unlinkedPadCount + newPadCount

        -- Link first pad back to source (decrements unlinkedPadCount by 2)
        local firstPadId = getFirstPadId(state.regions[newRegionId])
        if firstPadId and sourcePadId then
            linkPads(self, sourceRegionId, sourcePadId, newRegionId, firstPadId)
        end

        -- Teleport player to first pad (they're anchored so this just sets position)
        if firstPadId then
            teleportPlayerToPad(self, newRegionId, firstPadId, player)
        else
            teleportPlayerToSpawn(self, newRegionId, player)
        end

        -- Re-anchor at new position to ensure they stay put until transition completes
        anchorPlayer(player)

        -- Set as active
        state.regions[newRegionId].isActive = true
        local oldActiveId = state.activeRegionId
        state.activeRegionId = newRegionId

        -- Update pending transition with actual target info
        local pending = state.pendingTransitions[player]
        if pending then
            pending.targetRegionId = newRegionId
            pending.targetPadId = firstPadId
        end

        -- Unload old region
        if oldActiveId then
            task.defer(function()
                unloadRegion(self, oldActiveId)
            end)
        end

        -- Save after creating new region
        if player then
            task.defer(function()
                savePlayerData(self, player)
            end)
        end

        return newRegionId
    end

    --[[
        Teleport to existing region without player teleport call (async flow).
        Called after client fade out is complete.
    --]]
    function teleportToRegionAsync(self, targetRegionId, targetPadId, player)
        local state = getState(self)
        local targetRegion = state.regions[targetRegionId]

        if not targetRegion then return end

        -- Track old region for unloading
        local oldActiveId = state.activeRegionId

        -- Destroy any leftover container
        if targetRegion.container then
            targetRegion.container:Destroy()
            targetRegion.container = nil
        end
        local oldContainer = workspace:FindFirstChild("Region_" .. targetRegionId)
        if oldContainer then
            oldContainer:Destroy()
        end

        -- Destroy old JumpPads and Zones for this region
        destroyJumpPadsForRegion(self, targetRegionId)
        destroyZonesForRegion(self, targetRegionId)

        -- Reinstantiate from stored layout (no regeneration!)
        local result = instantiateLayout(self, targetRegionId, targetRegion.layout)

        -- Create JumpPad nodes for this region
        createJumpPadsForRegion(self, targetRegionId, result.container)

        -- Create Zone nodes for room detection
        createZonesForRegion(self, targetRegionId, result.roomZones)

        -- Teleport player to target pad (they're anchored so this just sets position)
        teleportPlayerToPad(self, targetRegionId, targetPadId, player)

        -- Re-anchor at new position to ensure they stay put until transition completes
        anchorPlayer(player)

        -- Set as active
        targetRegion.isActive = true
        state.activeRegionId = targetRegionId

        -- Unload old region
        if oldActiveId and oldActiveId ~= targetRegionId then
            task.defer(function()
                unloadRegion(self, oldActiveId)
            end)
        end
    end

    ----------------------------------------------------------------------------
    -- TELEPORTATION
    ----------------------------------------------------------------------------

    function teleportPlayerToSpawn(self, regionId, player)
        local state = getState(self)
        local region = state.regions[regionId]
        local character = player.Character
        if not character then return end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        -- Use stored spawn reference or position from layout
        if region and region.spawnPoint and region.spawnPoint.Parent then
            hrp.CFrame = region.spawnPoint.CFrame + Vector3.new(0, 3, 0)
        elseif region and region.spawnPosition then
            hrp.CFrame = CFrame.new(
                region.spawnPosition[1],
                region.spawnPosition[2] + 3,
                region.spawnPosition[3]
            )
        elseif region and region.layout and region.layout.spawn then
            -- Fallback to layout data
            local pos = region.layout.spawn.position
            hrp.CFrame = CFrame.new(pos[1], pos[2] + 3, pos[3])
        else
            warn("[RegionManager] No spawn point found for region: " .. tostring(regionId))
        end
    end

    function teleportPlayerToPad(self, regionId, padId, player)
        local state = getState(self)
        local region = state.regions[regionId]
        local character = player.Character
        if not character then return end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        -- Get JumpPad instance via IPC and set this player to spawnIn mode
        local qualifiedPadId = regionId .. "_" .. padId
        local IPC = self._System and self._System.IPC
        local jumpPad = IPC and IPC.getInstance(qualifiedPadId)

        if jumpPad then
            -- Set this player to spawnIn mode (won't fire until they walk off and back on)
            jumpPad:setModeForPlayer(player, "spawnIn")

            -- Try JumpPad node position first
            local position = jumpPad:getPosition()
            if position then
                hrp.CFrame = CFrame.new(position) + Vector3.new(0, 3, 0)
                return
            end
        end

        -- Fallback to layout data
        if region and region.layout then
            local layoutPad = Layout.Schema.getPad(region.layout, padId)
            if layoutPad then
                hrp.CFrame = CFrame.new(
                    layoutPad.position[1],
                    layoutPad.position[2] + 3,
                    layoutPad.position[3]
                )
                return
            end
        end

        -- Last resort: go to spawn
        teleportPlayerToSpawn(self, regionId, player)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "RegionManager",
        domain = "server",

        Sys = {
            onInit = function(self)
                local _ = getState(self)
            end,

            onStart = function(self) end,

            onStop = function(self)
                local state = getState(self)

                -- Unload all regions
                for regionId, region in pairs(state.regions) do
                    if region.container then
                        unloadRegion(self, regionId)
                    end
                end

                cleanupState(self)
            end,
        },

        In = {
            --[[
                Handle jump request from JumpPad (routed via IPC wiring).

                @param data table:
                    player: Player - The player who triggered the jump
                    padId: string - The pad ID (local to region)
                    regionId: string - The region ID
                    position: Vector3 - The pad position
            --]]
            onJumpRequested = function(self, data)
                if not data or not data.regionId or not data.padId or not data.player then
                    warn("[RegionManager] Invalid jumpRequested data")
                    return
                end
                handleJumpRequest(self, data.regionId, data.padId, data.player)
            end,

            --[[
                Handle fade out complete signal from client ScreenTransition.
                Screen is now black - safe to load/build and teleport.

                @param data table:
                    player: Player - The player who completed fade out
            --]]
            onFadeOutComplete = function(self, data)
                if not data or not data.player then
                    warn("[RegionManager] Invalid fadeOutComplete data")
                    return
                end

                local state = getState(self)
                local player = data.player
                local pending = state.pendingTransitions[player]

                if not pending then
                    warn("[RegionManager] No pending transition for player:", player.Name)
                    return
                end

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Fade complete for", player.Name, "- loading region")
                end

                local container
                if pending.isNewRegion then
                    -- Generate new region
                    local newRegionId = createNewRegionAsync(self, pending.sourceRegionId, pending.sourcePadId, player)
                    local newRegion = state.regions[newRegionId]
                    container = newRegion and newRegion.container
                else
                    -- Load existing region
                    teleportToRegionAsync(self, pending.targetRegionId, pending.targetPadId, player)
                    local targetRegion = state.regions[pending.targetRegionId]
                    container = targetRegion and targetRegion.container
                end

                -- Fire loading complete to client with container for preloading
                self.Out:Fire("loadingComplete", {
                    _targetPlayer = player,
                    player = player,
                    container = container,
                })
            end,

            --[[
                Handle transition complete signal from client ScreenTransition.
                Player can now move freely.

                @param data table:
                    player: Player - The player who completed the transition
            --]]
            onTransitionComplete = function(self, data)
                if not data or not data.player then
                    warn("[RegionManager] Invalid transitionComplete data")
                    return
                end

                local state = getState(self)
                local player = data.player
                local pending = state.pendingTransitions[player]

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Fade-in complete for", player.Name, "- ending transition")
                end

                -- Signal client to re-enable controls
                self.Out:Fire("transitionEnd", {
                    _targetPlayer = player,
                    player = player,
                })

                -- Fire area info for the destination
                if pending and pending.targetRegionId then
                    local targetRegion = state.regions[pending.targetRegionId]
                    if targetRegion and targetRegion.layout then
                        -- Get room from pad's roomId
                        local roomNum = 1
                        if pending.targetPadId then
                            local pad = Layout.Schema.getPad(targetRegion.layout, pending.targetPadId)
                            if pad then
                                roomNum = pad.roomId
                            end
                        end

                        local regionNum = targetRegion.layout.regionNum

                        -- Update tracking
                        state.playerRooms[player] = { regionNum = regionNum, roomNum = roomNum }

                        -- Mark room as visited
                        if not state.visitedRooms[player] then
                            state.visitedRooms[player] = {}
                        end
                        if not state.visitedRooms[player][regionNum] then
                            state.visitedRooms[player][regionNum] = {}
                        end
                        state.visitedRooms[player][regionNum][roomNum] = true

                        fireAreaInfo(self, player, regionNum, roomNum)
                    end
                end

                -- Unanchor player
                unanchorPlayer(player)

                -- Clear pending transition
                state.pendingTransitions[player] = nil

                if System and System.Debug then
                    System.Debug.info("RegionManager", "Transition complete for", player.Name)
                end
            end,

            --[[
                Handle map data request from MiniMap.
                Responds with current layout and visited rooms.

                @param data table:
                    player: Player - The requesting player
            --]]
            onRequestMapData = function(self, data)
                if not data or not data.player then return end

                local state = getState(self)
                local player = data.player
                local activeRegion = state.regions[state.activeRegionId]

                if not activeRegion or not activeRegion.layout then return end

                local layout = activeRegion.layout
                local regionNum = layout.regionNum or 1

                -- Get visited rooms for this player/region
                local playerVisited = state.visitedRooms[player]
                local visitedRooms = playerVisited and playerVisited[regionNum] or {}

                -- Get current room
                local playerRoom = state.playerRooms[player]
                local currentRoom = playerRoom and playerRoom.roomNum or 1

                -- Calculate stats
                local totalRooms = 0
                for _ in pairs(layout.rooms or {}) do
                    totalRooms = totalRooms + 1
                end

                local exploredRooms = 0
                for _ in pairs(visitedRooms) do
                    exploredRooms = exploredRooms + 1
                end

                local totalPortals = layout.pads and #layout.pads or 0

                local discoveredPortals = 0
                if layout.pads then
                    for _, pad in ipairs(layout.pads) do
                        if visitedRooms[pad.roomId] then
                            discoveredPortals = discoveredPortals + 1
                        end
                    end
                end

                local totalItems = totalRooms + totalPortals
                local discoveredItems = exploredRooms + discoveredPortals
                local completion = 0
                if totalItems > 0 then
                    completion = math.floor((discoveredItems / totalItems) * 100)
                end

                -- Send map data back to MiniMap
                self.Out:Fire("mapData", {
                    _targetPlayer = player,
                    player = player,
                    layout = layout,
                    visitedRooms = visitedRooms,
                    currentRoom = currentRoom,
                    padLinks = activeRegion.padLinks or {},
                    stats = {
                        totalRooms = totalRooms,
                        exploredRooms = exploredRooms,
                        totalPortals = totalPortals,
                        discoveredPortals = discoveredPortals,
                        completion = completion,
                    },
                })
            end,

        },

        Out = {
            transitionStart = {},
            loadingComplete = {},
            transitionEnd = {},
            areaInfo = {},
            mapData = {},
        },

        -- Configuration
        configure = function(self, config)
            local state = getState(self)
            for key, value in pairs(config) do
                state.config[key] = value
            end
        end,

        -- Start the dungeon for a player (loads existing or creates new)
        startFirstRegion = function(self, player)
            local state = getState(self)

            -- Delete baseplate
            local baseplate = workspace:FindFirstChild("Baseplate")
            if baseplate then
                baseplate:Destroy()
            end

            -- Try to load existing save data
            if player and loadPlayerData(self, player) and state.activeRegionId then
                -- Data loaded successfully - instantiate the active region
                local activeRegion = state.regions[state.activeRegionId]
                if activeRegion and activeRegion.layout then
                    local result = instantiateLayout(self, state.activeRegionId, activeRegion.layout)

                    -- Create JumpPad nodes for this region
                    createJumpPadsForRegion(self, state.activeRegionId, result.container)

                    -- Create Zone nodes for room detection
                    createZonesForRegion(self, state.activeRegionId, result.roomZones)

                    activeRegion.isActive = true

                    local System = self._System
                    if System and System.Debug then
                        System.Debug.info("RegionManager", "Resumed from save - region:",
                            state.activeRegionId, "total regions:", state.regionCount)
                    end

                    return state.activeRegionId
                end
            end

            -- No save data - create first region
            state.regionCount = 1
            local regionId = "region_1"
            local seed = generateSeed()

            -- First region is always a corridor (2 pads)
            local mapType, padCount = determineMapType(self, true)

            -- Generate layout
            local layout = generateLayout(self, seed, 1, padCount)

            -- Store region with layout
            state.regions[regionId] = {
                id = regionId,
                layout = layout,
                padLinks = {},
                isActive = true,
                container = nil,
                pads = nil,
                spawnPoint = nil,
                spawnPosition = nil,
            }

            -- Instantiate
            local result = instantiateLayout(self, regionId, layout)

            -- Create JumpPad nodes for this region
            createJumpPadsForRegion(self, regionId, result.container)

            -- Create Zone nodes for room detection
            createZonesForRegion(self, regionId, result.roomZones)

            -- Track initial pads for infinite expansion (no linking for first region)
            local initialPadCount = layout.pads and #layout.pads or 0
            state.unlinkedPadCount = initialPadCount

            state.activeRegionId = regionId

            -- Save initial state
            if player then
                task.defer(function()
                    savePlayerData(self, player)
                end)
            end

            return regionId
        end,

        -- Query methods
        getActiveRegion = function(self)
            local state = getState(self)
            return state.regions[state.activeRegionId]
        end,

        getRegion = function(self, regionId)
            return getState(self).regions[regionId]
        end,

        getAllRegions = function(self)
            return getState(self).regions
        end,

        getRegionCount = function(self)
            return getState(self).regionCount
        end,

        -- Get current unlinked pad count (for debugging/monitoring)
        getUnlinkedPadCount = function(self)
            return getState(self).unlinkedPadCount
        end,

        -- Get layout for a region (for serialization/debugging)
        getLayout = function(self, regionId)
            local region = getState(self).regions[regionId]
            return region and region.layout
        end,

        -- Load a region from a serialized layout
        loadRegionFromLayout = function(self, regionId, layout)
            local state = getState(self)

            state.regions[regionId] = {
                id = regionId,
                layout = layout,
                padLinks = {},
                isActive = false,
                container = nil,
                pads = nil,
                spawnPoint = nil,
                spawnPosition = nil,
            }

            return regionId
        end,

        -- Send initial area info for a player (e.g., on spawn)
        sendInitialAreaInfo = function(self, player, roomNum)
            local state = getState(self)
            local activeRegion = state.regions[state.activeRegionId]

            if activeRegion and activeRegion.layout then
                local layout = activeRegion.layout
                local regionNum = layout.regionNum or 1
                roomNum = roomNum or 1

                -- Update tracking
                state.playerRooms[player] = { regionNum = regionNum, roomNum = roomNum }

                -- Mark room as visited
                if not state.visitedRooms[player] then
                    state.visitedRooms[player] = {}
                end
                if not state.visitedRooms[player][regionNum] then
                    state.visitedRooms[player][regionNum] = {}
                end
                state.visitedRooms[player][regionNum][roomNum] = true

                -- Fire area info to client
                fireAreaInfo(self, player, regionNum, roomNum)
            end
        end,

        -- Manually save player data (e.g., on player leaving)
        saveData = function(self, player)
            return savePlayerData(self, player)
        end,

        -- Clear save data for a player (for testing/reset)
        clearSaveData = function(self, player)
            local store = getDataStore()
            if not store then return false end

            local key = "player_" .. player.UserId
            local success, err = pcall(function()
                store:RemoveAsync(key)
            end)

            if success then
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Cleared save data for", player.Name)
                end
            else
                warn("[RegionManager] Failed to clear data for", player.Name, ":", err)
            end

            return success
        end,
    }
end)

return RegionManager
