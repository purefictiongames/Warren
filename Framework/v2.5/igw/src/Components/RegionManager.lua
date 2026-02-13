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
    - Stores seeds (not full layouts) for deterministic regeneration
    - Instantiates layouts into parts (via Layout.DomBuilder)
    - Manages two-way teleport links between pads
    - Swaps regions in/out of workspace (only one loaded at a time)

    Architecture:
    - Each region stores a seed + metadata (NOT the full layout)
    - Layouts are regenerated deterministically from seeds on load
    - This eliminates serialization issues and reduces save data size
    - Cross-region pad links stored separately (runtime connections)

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

        buildMiniMap({ player, layout })
            - Fired after region geometry is built, before loadingComplete
            - MiniMap should build geometry and signal miniMapReady

        visitedState({ player, visitedRooms, currentRoom, padLinks, stats })
            - Response to requestVisitedState from MiniMap
            - Contains visited state for color updates when map is opened

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

        onMiniMapReady({ player })
            - From MiniMap when geometry build is complete
            - Continues the load chain by firing loadingComplete

        onRequestVisitedState({ player })
            - From MiniMap when map is opened, needs current visited rooms

    ============================================================================
    PERSISTENCE (Seed-Based)
    ============================================================================

    Dungeon data is saved per-player in DataStore (DungeonData_v1).

    IMPORTANT: Layouts are NOT stored directly. Instead, we store seeds and
    regenerate layouts deterministically on load. This eliminates serialization
    issues and dramatically reduces save data size.

    Saved per region:
    - seed: number - Regenerates all geometry deterministically
    - regionNum: number - For color palette
    - padCount: number - Number of pads (1=spur, 2=corridor, 3-5=hub)
    - mapType: string - For branching decisions
    - padLinks: table - Runtime connections to other regions

    Also saved:
    - regionCount, activeRegionId, unlinkedPadCount, visitedRooms

    Size estimates:
    - ~100 bytes per region (vs 4-5KB for full layout)
    - 4MB DataStore limit = 40,000+ regions per player

--]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node
local Layout = require(script.Parent.Layout)
local JumpPad = require(script.Parent.JumpPad)
local PlaceGraph = require(script.Parent.PlaceGraph)

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
                    -- Map type distribution (deterministic pattern)
                    hubInterval = 4,         -- Guarantee a hub every N regions
                    hubPadRange = { min = 3, max = 4 },  -- Pads in hub regions
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
                -- Per-player pending minimap builds (waiting for miniMapReady)
                -- { [Player] = { container } }
                pendingMiniMapBuild = {},
                -- Per-player skip data load flags (after clearing saved data)
                skipDataLoad = {},
                -- Global unlinked pad count for infinite expansion
                unlinkedPadCount = 0,
                -- Title diorama state
                diorama = {
                    layout = nil,
                    container = nil,
                    domTree = nil,
                    isLoaded = false,
                },
                -- Lobby state
                lobby = {
                    layout = nil,
                    container = nil,
                    domTree = nil,
                    isLoaded = false,
                    pads = {},
                    padDomNodes = nil,
                },
                -- View state is now managed by System.Player subsystem
                -- (per-player view tracking with ref-counted geometry)
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
        Recursively normalizes numeric array keys that may have become strings
        after DataStore deserialization. Handles Vec3 arrays like position/dims.
    --]]
    local function normalizeArrayKeys(tbl)
        if type(tbl) ~= "table" then return tbl end

        local normalized = {}
        local hasStringNumericKeys = false

        for key, value in pairs(tbl) do
            local numKey = tonumber(key)
            if numKey and type(key) == "string" then
                hasStringNumericKeys = true
            end

            local newKey = numKey or key
            local newValue = normalizeArrayKeys(value)  -- Recurse
            normalized[newKey] = newValue
        end

        return normalized
    end

    --[[
        Normalizes a layout after loading from DataStore.
        DataStore serialization can convert numeric table keys to strings.
        This recursively converts them back for consistent lookups.
    --]]
    local function normalizeLayout(layout)
        if not layout then return layout end

        -- Recursively normalize the entire layout structure
        -- This handles rooms table keys AND position/dims Vec3 arrays
        return normalizeArrayKeys(layout)
    end

    --[[
        Validates a layout and logs any issues found.
        Call after loading to diagnose missing room problems.
    --]]
    local function validateLayout(layout, regionId)
        if not layout then
            warn("[RegionManager] Layout is nil for", regionId)
            return false
        end

        local issues = {}

        -- Check rooms
        if not layout.rooms then
            table.insert(issues, "No rooms table")
        else
            local roomCount = 0
            for roomId, room in pairs(layout.rooms) do
                roomCount = roomCount + 1

                -- Check position array
                if not room.position then
                    table.insert(issues, "Room " .. tostring(roomId) .. ": missing position")
                elseif not room.position[1] or not room.position[2] or not room.position[3] then
                    table.insert(issues, "Room " .. tostring(roomId) .. ": invalid position array, keys: " ..
                        table.concat({next(room.position)}, ","))
                end

                -- Check dims array
                if not room.dims then
                    table.insert(issues, "Room " .. tostring(roomId) .. ": missing dims")
                elseif not room.dims[1] or not room.dims[2] or not room.dims[3] then
                    table.insert(issues, "Room " .. tostring(roomId) .. ": invalid dims array")
                end
            end

            if roomCount == 0 then
                table.insert(issues, "Rooms table is empty")
            end
        end

        -- Check doors reference valid rooms
        if layout.doors then
            for i, door in ipairs(layout.doors) do
                if layout.rooms and not layout.rooms[door.fromRoom] then
                    table.insert(issues, "Door " .. i .. ": fromRoom " .. tostring(door.fromRoom) .. " not found")
                end
                if layout.rooms and not layout.rooms[door.toRoom] then
                    table.insert(issues, "Door " .. i .. ": toRoom " .. tostring(door.toRoom) .. " not found")
                end
            end
        end

        if #issues > 0 then
            warn("[RegionManager] Layout validation issues for", regionId .. ":")
            for _, issue in ipairs(issues) do
                warn("  -", issue)
            end
            return false
        end

        return true
    end

    --[[
        Normalizes visited rooms data after loading from DataStore.
        Converts string keys back to numbers.
    --]]
    local function normalizeVisitedRooms(visitedData)
        if not visitedData then return {} end

        local normalized = {}
        for regionKey, roomSet in pairs(visitedData) do
            local numRegionKey = tonumber(regionKey) or regionKey
            normalized[numRegionKey] = {}
            for roomKey, value in pairs(roomSet) do
                local numRoomKey = tonumber(roomKey) or roomKey
                normalized[numRegionKey][numRoomKey] = value
            end
        end
        return normalized
    end

    ----------------------------------------------------------------------------
    -- LAYOUT GENERATION (must be defined before loadPlayerData)
    ----------------------------------------------------------------------------

    local function generateSeed()
        return os.time() + math.random(1, 100000)
    end

    -- Palette colors now live in Styles.lua as palette classes (palette-classic-lava, etc.)
    -- StyleBridge.getPaletteClass(regionNum) maps regionNum to the correct class.
    -- REGION_COLORS removed — palette resolution happens at render time via DOM styles.

    local function generateLayout(self, seed, regionNum, padCount)
        local state = getState(self)
        local config = state.config

        -- Offset each region to avoid geometry overlap during transitions
        local regionOffset = (regionNum - 1) * 2000
        local origin = config.origin or { 0, 20, 0 }
        local offsetOrigin = { origin[1] + regionOffset, origin[2], origin[3] }

        -- Generate layout using Layout.Builder
        -- Palette/color now resolved at instantiation time by DomBuilder
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
            padCount = padCount,  -- Direct pad count instead of roomsPerPad
        })

        return layout
    end

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

        -- Build save data (seed-based - store seeds, not full layouts)
        -- Layouts are regenerated deterministically from seeds on load
        local regionsToSave = {}
        for regionId, region in pairs(state.regions) do
            local layout = region.layout
            regionsToSave[regionId] = {
                id = region.id,
                -- Seeds & params to regenerate layout (NOT the full layout)
                seed = layout and layout.seed,
                seeds = layout and layout.seeds,  -- Domain-specific seeds
                regionNum = layout and layout.regionNum,
                padCount = layout and layout.pads and #layout.pads or 2,
                mapType = region.mapType,
                -- Runtime connections (can't be regenerated)
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

        -- Restore regions (regenerate layouts from seeds - no serialization issues!)
        state.regions = {}
        if data.regions then
            for regionId, savedRegion in pairs(data.regions) do
                local layout = nil

                -- Regenerate layout from seed (deterministic)
                if savedRegion.seed and savedRegion.regionNum then
                    layout = generateLayout(
                        self,
                        savedRegion.seed,
                        savedRegion.regionNum,
                        savedRegion.padCount or 2
                    )

                    local System = self._System
                    if System and System.Debug then
                        System.Debug.info("RegionManager", "Regenerated", regionId,
                            "from seed", savedRegion.seed)
                    end
                else
                    -- Legacy: try to use stored layout (old save format)
                    if savedRegion.layout then
                        layout = normalizeLayout(savedRegion.layout)
                        validateLayout(layout, regionId)
                        warn("[RegionManager] Using legacy layout for", regionId,
                            "- consider clearing save data")
                    end
                end

                state.regions[regionId] = {
                    id = savedRegion.id,
                    layout = layout,
                    mapType = savedRegion.mapType,
                    padLinks = savedRegion.padLinks or {},
                    isActive = false,
                    container = nil,
                    pads = nil,
                    spawnPoint = nil,
                    spawnPosition = nil,
                }
            end
        end

        -- Restore visited rooms for this player (normalize keys)
        if data.visitedRooms then
            state.visitedRooms[player] = normalizeVisitedRooms(data.visitedRooms)
        end

        local System = self._System
        if System and System.Debug then
            System.Debug.info("RegionManager", "Loaded data for", player.Name,
                "- regions:", state.regionCount)
        end

        return true
    end

    -- Player anchoring is now handled by System.Player subsystem
    -- (anchorPlayer/unanchorPlayer moved to System.Player.anchorPlayer/unanchorPlayer)

    ----------------------------------------------------------------------------
    -- MAP TYPE DETERMINATION
    ----------------------------------------------------------------------------
    -- Map types: spur (1 pad), corridor (2 pads), hub (3-5 pads)
    --
    -- Deterministic pattern ensures variety:
    -- - Hubs guaranteed every N regions (hubInterval config)
    -- - Spurs only spawn from hubs (never block main path)
    -- - Corridors fill the gaps
    --
    -- Pad roles:
    -- - pad_1 is ALWAYS the back-link to parent region
    -- - Remaining pads are forward links to new regions
    -- - Spurs have only pad_1 (dead end)

    local MAP_TYPES = {
        SPUR = "spur",         -- 1 pad, dead end (back-link only)
        CORRIDOR = "corridor", -- 2 pads (1 back + 1 forward)
        HUB = "hub",           -- 3-5 pads (1 back + 2-4 forward)
    }

    --[[
        Determines map type for a new region.

        @param self: RegionManager instance
        @param isFirstRegion: boolean - true if this is region 1
        @param sourceMapType: string - type of the source region (nil for first)
        @return mapType, padCount
    --]]
    local function determineMapType(self, isFirstRegion, sourceMapType)
        local state = getState(self)
        local config = state.config
        local regionNum = state.regionCount + 1  -- The region we're about to create

        -- First region is always a corridor
        if isFirstRegion then
            return MAP_TYPES.CORRIDOR, 2
        end

        -- Hub interval: guarantee a hub every N regions
        local hubInterval = config.hubInterval or 4

        -- Check if this should be a guaranteed hub
        if regionNum % hubInterval == 0 then
            local hubRange = config.hubPadRange or { min = 3, max = 4 }
            local padCount = math.random(hubRange.min, hubRange.max)
            return MAP_TYPES.HUB, padCount
        end

        -- Spurs can ONLY spawn from hubs (to avoid blocking main path)
        if sourceMapType == MAP_TYPES.HUB then
            -- From a hub: 25% chance of spur, 50% corridor, 25% hub
            local roll = math.random(100)
            if roll <= 25 then
                return MAP_TYPES.SPUR, 1
            elseif roll <= 75 then
                return MAP_TYPES.CORRIDOR, 2
            else
                local hubRange = config.hubPadRange or { min = 3, max = 4 }
                local padCount = math.random(hubRange.min, hubRange.max)
                return MAP_TYPES.HUB, padCount
            end
        end

        -- From a corridor: 70% corridor, 30% hub (no spurs)
        local roll = math.random(100)
        if roll <= 70 then
            return MAP_TYPES.CORRIDOR, 2
        else
            local hubRange = config.hubPadRange or { min = 3, max = 4 }
            local padCount = math.random(hubRange.min, hubRange.max)
            return MAP_TYPES.HUB, padCount
        end
    end

    local function instantiateLayout(self, regionId, layout)
        local state = getState(self)
        local region = state.regions[regionId]

        -- Instantiate using DomBuilder (DOM-based, style-resolved)
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
            region.domTree = result.domTree
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

        -- Destroy any existing Parts created by DomBuilder for pads
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
        self._System.Player.anchorPlayer(player)

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

        -- Clear terrain for this region's rooms (zone-scoped, not global)
        if region.layout then
            Layout.clearTerrain(region.layout)
        end

        -- Destroy Zone nodes for this region
        destroyZonesForRegion(self, regionId)

        -- Destroy JumpPad nodes for this region
        destroyJumpPadsForRegion(self, regionId)

        -- Unmount DOM tree (cleans up node refs before destroying Instances)
        if region.domTree and region.domTree.root then
            local Warren = require(game.ReplicatedStorage.Warren)
            Warren.Dom.unmount(region.domTree.root)
            region.domTree = nil
        end

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
    -- TITLE DIORAMA
    ----------------------------------------------------------------------------

    local DIORAMA_SEED = 42
    local DIORAMA_PAD_COUNT = 2  -- Same as first gameplay region (corridor)

    local function buildDiorama(self)
        local state = getState(self)
        local Players = game:GetService("Players")

        -- Generate layout using the exact same pipeline as gameplay
        local layout = generateLayout(self, DIORAMA_SEED, 1, DIORAMA_PAD_COUNT)

        -- Instantiate using the exact same pipeline as gameplay
        local result = Layout.instantiate(layout, {
            name = "TitleDiorama",
            regionId = "diorama",
        })

        state.diorama.layout = layout
        state.diorama.container = result.container
        state.diorama.domTree = result.domTree
        state.diorama.isLoaded = true

        -- Player anchoring during title screen is handled by System.Player
        -- (anchor=true in view def + CharacterAdded re-anchoring)

        local System = self._System
        if System and System.Debug then
            System.Debug.info("RegionManager", "Title diorama built")
        end

    end

    local function destroyDiorama(self)
        local state = getState(self)
        if not state.diorama.isLoaded then return end

        -- CharacterAdded anchoring connections are managed by System.Player

        -- Clear terrain for this view's rooms (zone-scoped, not global)
        if state.diorama.layout then
            Layout.clearTerrain(state.diorama.layout)
        end

        -- Unmount DOM tree
        if state.diorama.domTree and state.diorama.domTree.root then
            Warren.Dom.unmount(state.diorama.domTree.root)
        end

        -- Destroy container
        if state.diorama.container then
            state.diorama.container:Destroy()
        end

        state.diorama = {
            layout = nil,
            container = nil,
            domTree = nil,
            isLoaded = false,
        }

        local System = self._System
        if System and System.Debug then
            System.Debug.info("RegionManager", "Title diorama destroyed")
        end
    end

    ----------------------------------------------------------------------------
    -- LOBBY
    ----------------------------------------------------------------------------

    local LOBBY_PAD_TOTAL = 10
    local LOBBY_PAD_SPACING = 30  -- Studs between pads along X
    local LOBBY_PAD_SIZE = 10     -- Studs per pad side

    -- Lobby hall dimensions: one large room
    local LOBBY_HALL_WIDTH = 200   -- X axis (long)
    local LOBBY_HALL_HEIGHT = 30   -- Y axis
    local LOBBY_HALL_DEPTH = 60    -- Z axis

    --[[
        Build lobby by swapping in a single predefined hall room, then running
        the rest of the standard build chain (lights, instantiate).
    --]]
    local function buildLobby(self)
        local state = getState(self)
        local config = state.config
        local origin = config.origin or { 0, 20, 0 }

        -- 1. Build layout via the standard pipeline, but replace room massing
        --    with a single predefined hall room.
        local LayoutContext = Layout.Context

        local cfg = {
            seed = 0,  -- Predefined, no RNG
            seeds = { rooms = 0, doors = 10000, trusses = 20000, lights = 30000 },
            regionNum = 0,
            origin = origin,
            baseUnit = config.baseUnit,
            wallThickness = config.wallThickness,
            doorSize = config.doorSize,
            floorThreshold = config.floorThreshold or 5,
            material = config.material or "Brick",
            color = config.color or { 140, 110, 90 },
            gap = 2 * config.wallThickness,
            cutterDepth = config.wallThickness * 8,
            padCount = 0,  -- No layout pads — portal pads are placed manually
        }

        local ctx = LayoutContext.new(cfg)

        -- Swap in the custom hall room (replaces planRooms)
        ctx:setRooms({
            [1] = {
                id = 1,
                position = { origin[1], origin[2], origin[3] },
                dims = { LOBBY_HALL_WIDTH, LOBBY_HALL_HEIGHT, LOBBY_HALL_DEPTH },
                parentId = nil,
                attachFace = nil,
            },
        })

        -- Run rest of build chain: doors (none for single room), lights
        ctx:setDoors({})    -- Single room = no doors
        ctx:setTrusses({})  -- No doors = no trusses
        -- Let planLights run for the hall (gives it wall-mounted lighting)
        local room1 = ctx:getRoom(1)
        if room1 then
            local lights = {}
            -- Place lights on each wall for the hall
            local wallDefs = {
                { name = "N", axis = 3, dir = 1,  sizeAxis = 1 },
                { name = "S", axis = 3, dir = -1, sizeAxis = 1 },
                { name = "E", axis = 1, dir = 1,  sizeAxis = 3 },
                { name = "W", axis = 1, dir = -1, sizeAxis = 3 },
            }
            for i, wall in ipairs(wallDefs) do
                local wallWidth = room1.dims[wall.sizeAxis]
                local stripWidth = math.clamp(wallWidth * 0.5, 4, 12)
                local lightPos = { room1.position[1], room1.position[2] + room1.dims[2] / 2 - 2, room1.position[3] }
                lightPos[wall.axis] = room1.position[wall.axis] + wall.dir * (room1.dims[wall.axis] / 2 - 0.1)
                local lightSize
                if wall.sizeAxis == 1 then
                    lightSize = { stripWidth, 1, 0.3 }
                else
                    lightSize = { 0.3, 1, stripWidth }
                end
                table.insert(lights, {
                    id = i,
                    roomId = 1,
                    position = lightPos,
                    size = lightSize,
                    wall = wall.name,
                })
            end
            ctx:setLights(lights)
        end

        ctx:setPads({})  -- No layout pads

        -- Set spawn at entrance end of hall (negative X)
        local floorY = origin[2] - LOBBY_HALL_HEIGHT / 2 + 3
        ctx:setSpawn({
            position = { origin[1] - LOBBY_HALL_WIDTH / 2 + 15, floorY, origin[3] },
            roomId = 1,
        })

        -- 2. Export layout and instantiate via standard pipeline
        local layout = ctx:toLayout()

        local result = Layout.instantiate(layout, {
            name = "LobbyHall",
            regionId = "lobby",
        })

        state.lobby.layout = layout
        state.lobby.container = result.container
        state.lobby.domTree = result.domTree
        state.lobby.isLoaded = true

        -- 3. Place 10 portal pads inside the hall (2 rows of 5) via DOM
        local Dom = Warren.Dom
        local hallCenterX = origin[1]
        local hallCenterZ = origin[3]
        local floorTopY = origin[2] - LOBBY_HALL_HEIGHT / 2  -- Top of the floor Part
        local baseThickness = 2  -- Thick base to clear cracked lava terrain
        local padHeight = 1
        local baseCenterY = floorTopY + baseThickness / 2
        local padCenterY = floorTopY + baseThickness + padHeight / 2

        local pads = {}
        local padDomNodes = {}
        for i = 1, LOBBY_PAD_TOTAL do
            local row = i <= 5 and 0 or 1
            local col = ((i - 1) % 5)

            -- 2 rows along Z, 5 columns along X
            local xOffset = (col - 2) * LOBBY_PAD_SPACING
            local zOffset = (row == 0) and -15 or 15
            local padX = hallCenterX + xOffset
            local padZ = hallCenterZ + zOffset

            -- Base shim under pad (clears terrain texture)
            local baseNode = Dom.createElement("Part", {
                class = "lobby-pad-base",
                Name = "LobbyPadBase_" .. i,
                Size = { LOBBY_PAD_SIZE, baseThickness, LOBBY_PAD_SIZE },
                Position = { padX, baseCenterY, padZ },
            })
            Dom.mount(baseNode, result.container)
            table.insert(padDomNodes, baseNode)

            -- Pad surface on top of base
            local padNode = Dom.createElement("Part", {
                class = "lobby-pad",
                Name = "LobbyPad_" .. i,
                Size = { LOBBY_PAD_SIZE, padHeight, LOBBY_PAD_SIZE },
                Position = { padX, padCenterY, padZ },
            })
            Dom.mount(padNode, result.container)
            table.insert(padDomNodes, padNode)

            table.insert(pads, {
                id = "lobby_pad_" .. i,
                part = padNode._instance,
                index = i,
            })
        end

        state.lobby.pads = pads
        state.lobby.padDomNodes = padDomNodes

        local System = self._System
        if System and System.Debug then
            System.Debug.info("RegionManager", "Lobby built: single hall "
                .. LOBBY_HALL_WIDTH .. "x" .. LOBBY_HALL_HEIGHT .. "x" .. LOBBY_HALL_DEPTH
                .. " with " .. LOBBY_PAD_TOTAL .. " portal pads")
        end

        return pads
    end

    local function destroyLobby(self)
        local state = getState(self)
        if not state.lobby.isLoaded then return end

        -- Signal LobbyManager to cleanup
        self.Out:Fire("unloadLobby", {})

        -- Clear terrain for this view's rooms (zone-scoped, not global)
        if state.lobby.layout then
            Layout.clearTerrain(state.lobby.layout)
        end

        -- Unmount pad DOM nodes
        if state.lobby.padDomNodes then
            for _, padNode in ipairs(state.lobby.padDomNodes) do
                Warren.Dom.unmount(padNode)
            end
        end

        -- Unmount DOM tree
        if state.lobby.domTree and state.lobby.domTree.root then
            Warren.Dom.unmount(state.lobby.domTree.root)
        end

        -- Destroy container
        if state.lobby.container then
            state.lobby.container:Destroy()
        end

        state.lobby = {
            layout = nil,
            container = nil,
            domTree = nil,
            isLoaded = false,
            pads = {},
            padDomNodes = nil,
        }

        local System = self._System
        if System and System.Debug then
            System.Debug.info("RegionManager", "Lobby destroyed")
        end
    end

    ----------------------------------------------------------------------------
    -- VIEW REGISTRATION (System.Player integration)
    ----------------------------------------------------------------------------
    -- Views are registered with System.Player subsystem for per-player tracking.
    -- registerViews() is called from Bootstrap.server.lua before activation.
    -- View transitions are handled by System.Player.transitionTo().

    local function registerViews(self)
        local state = getState(self)
        local System = self._System

        System.Player.registerView("title", {
            anchor = true,
            build = function(options)
                buildDiorama(self)
            end,
            destroy = function()
                destroyDiorama(self)
            end,
            getSpawn = function()
                local layout = state.diorama and state.diorama.layout
                return layout and layout.spawn and layout.spawn.position
            end,
            onEnter = function(player, buildResult)
                if player then
                    self.Out:Fire("showTitle", { _targetPlayer = player, player = player })
                end
                self.Out:Fire("dioramaReady", {})
            end,
            onLeave = function(player)
                if player then
                    self.Out:Fire("hideTitle", { _targetPlayer = player, player = player })
                end
            end,
        })

        System.Player.registerView("lobby", {
            anchor = false,
            build = function(options)
                return buildLobby(self)
            end,
            destroy = function()
                destroyLobby(self)
            end,
            getSpawn = function()
                local layout = state.lobby and state.lobby.layout
                return layout and layout.spawn and layout.spawn.position
            end,
            onEnter = function(player, buildResult)
                if buildResult then
                    self.Out:Fire("padsReady", { pads = buildResult })
                end
            end,
            onLeave = function(player) end,
        })

        System.Player.registerView("gameplay", {
            anchor = false,
            build = function(options)
                return self:startFirstRegion(options and options.player)
            end,
            destroy = function()
                for regionId, region in pairs(state.regions) do
                    if region.container then
                        unloadRegion(self, regionId)
                    end
                end
                state.activeRegionId = nil
            end,
            getSpawn = nil,
            onEnter = function(player, buildResult) end,
            onLeave = function(player) end,
        })
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

        -- Get source region's map type for deterministic type selection
        local sourceRegion = state.regions[sourceRegionId]
        local sourceMapType = sourceRegion and sourceRegion.mapType or nil

        -- Generate new region
        state.regionCount = state.regionCount + 1
        local newRegionId = "region_" .. state.regionCount
        local newSeed = generateSeed()
        local regionNum = state.regionCount

        -- Determine map type based on source and position in tree
        local mapType, padCount = determineMapType(self, false, sourceMapType)

        -- Generate layout with determined pad count
        local layout = generateLayout(self, newSeed, regionNum, padCount)

        -- Store region with layout and map type
        state.regions[newRegionId] = {
            id = newRegionId,
            layout = layout,
            mapType = mapType,  -- Store for future branching decisions
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
        self._System.Player.anchorPlayer(player)

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
        self._System.Player.anchorPlayer(player)

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
                Handle start pressed signal from TitleScreen.
                Starts the dungeon for the player and hides the title screen.

                @param data table:
                    player: Player - The player who pressed start
            --]]
            onStartPressed = function(self, data)
                if not data or not data.player then
                    warn("[RegionManager] Invalid startPressed data")
                    return
                end

                local state = getState(self)
                local player = data.player
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Start pressed by", player.Name)
                end

                -- Transition title → gameplay via System.Player
                -- (hideTitle fired by onLeave, build calls startFirstRegion)
                System.Player.transitionTo(player, "gameplay", {
                    player = player,
                })

                -- Gameplay-specific: log layout, build minimap, delayed transitionEnd
                local region = state.regions[state.activeRegionId]
                if region and region.layout then
                    local layout = region.layout
                    local roomCount = 0
                    for _ in pairs(layout.rooms) do roomCount = roomCount + 1 end

                    if System and System.Debug then
                        System.Debug.info("RegionManager", string.format(
                            "Layout: %d rooms, %d doors, %d trusses, %d lights, %d pads",
                            roomCount,
                            #layout.doors,
                            #layout.trusses,
                            #layout.lights,
                            #layout.pads
                        ))
                    end

                    -- Fire buildMiniMap to client (builds while title fades out)
                    self.Out:Fire("buildMiniMap", {
                        _targetPlayer = player,
                        player = player,
                        layout = layout,
                    })
                end

                -- TODO: Replace task.delay with proper transition callback (Phase 2)
                task.delay(0.6, function()
                    self.Out:Fire("transitionEnd", {
                        _targetPlayer = player,
                        player = player,
                    })
                end)

                -- Handle character respawn (safety net for out-of-bounds spawn)
                local function onCharacterAdded(character)
                    task.wait(0.5)

                    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
                    if not humanoidRootPart then return end

                    local activeRegion = state.regions[state.activeRegionId]
                    local layout = activeRegion and activeRegion.layout

                    local pos = humanoidRootPart.Position

                    local isInside = false
                    if layout then
                        for _, room in pairs(layout.rooms) do
                            local minX = room.position[1] - room.dims[1] / 2
                            local maxX = room.position[1] + room.dims[1] / 2
                            local minY = room.position[2] - room.dims[2] / 2
                            local maxY = room.position[2] + room.dims[2] / 2
                            local minZ = room.position[3] - room.dims[3] / 2
                            local maxZ = room.position[3] + room.dims[3] / 2

                            if pos.X >= minX and pos.X <= maxX and
                               pos.Y >= minY and pos.Y <= maxY and
                               pos.Z >= minZ and pos.Z <= maxZ then
                                isInside = true
                                break
                            end
                        end
                    end

                    if not isInside and layout then
                        local room1 = layout.rooms[1]
                        if room1 then
                            local targetPos = Vector3.new(
                                room1.position[1],
                                room1.position[2] - room1.dims[2] / 2 + 3,
                                room1.position[3]
                            )
                            humanoidRootPart.CFrame = CFrame.new(targetPos)
                        end
                    end

                    self:sendInitialAreaInfo(player, 1)
                end

                if player.Character then
                    onCharacterAdded(player.Character)
                end
                player.CharacterAdded:Connect(onCharacterAdded)

                if System and System.Debug then
                    System.Debug.info("RegionManager", "Dungeon ready for", player.Name)
                end
            end,

            --[[
                Handle clear saved data request from TitleScreen Options menu.
                Clears all dungeon data for the player from DataStore.

                @param data table:
                    player: Player - The player requesting data clear
            --]]
            onClearSavedData = function(self, data)
                if not data or not data.player then
                    warn("[RegionManager] Invalid clearSavedData data")
                    return
                end

                local player = data.player
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Clearing saved data for", player.Name)
                end

                -- Clear the data
                local success = self:clearSaveData(player)

                -- Signal back to client with result
                self.Out:Fire("savedDataCleared", {
                    _targetPlayer = player,
                    player = player,
                    success = success,
                })
            end,

            --[[
                Handle lobby pressed signal from TitleScreen.
                Transitions from title diorama to multiplayer lobby.

                @param data table:
                    player: Player - The player who pressed lobby
            --]]
            onLobbyPressed = function(self, data)
                if not data or not data.player then
                    warn("[RegionManager] Invalid lobbyPressed data")
                    return
                end

                local player = data.player
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Lobby pressed by", player.Name)
                end

                System.Player.transitionTo(player, "lobby")

                -- TODO: Replace task.delay with proper transition callback (Phase 2)
                task.delay(0.6, function()
                    self.Out:Fire("transitionEnd", {
                        _targetPlayer = player,
                        player = player,
                    })
                end)

                if System and System.Debug then
                    System.Debug.info("RegionManager", "Lobby ready for", player.Name)
                end
            end,

            --[[
                Handle exit from lobby back to title screen.

                @param data table:
                    player: Player - The player who wants to leave the lobby
            --]]
            onExitLobbyToTitle = function(self, data)
                if not data or not data.player then
                    warn("[RegionManager] Invalid exitLobbyToTitle data")
                    return
                end

                local player = data.player
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Exit lobby to title by", player.Name)
                end

                System.Player.transitionTo(player, "title")
            end,

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

                -- Handle exit-to-title transition
                if pending.isExitToTitle then
                    if System and System.Debug then
                        System.Debug.info("RegionManager", "Fade complete for", player.Name, "- returning to title")
                    end

                    state.pendingTransitions[player] = nil

                    -- Signal client to close exit screen (before view transition)
                    self.Out:Fire("returnToTitle", {
                        _targetPlayer = player,
                        player = player,
                    })

                    -- gameplay → title via System.Player
                    System.Player.transitionTo(player, "title")

                    if System and System.Debug then
                        System.Debug.info("RegionManager", "Returned to title for", player.Name)
                    end

                    return
                end

                -- Normal teleport transition
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Fade complete for", player.Name, "- loading region")
                end

                local container, layout
                if pending.isNewRegion then
                    -- Generate new region
                    local newRegionId = createNewRegionAsync(self, pending.sourceRegionId, pending.sourcePadId, player)
                    local newRegion = state.regions[newRegionId]
                    container = newRegion and newRegion.container
                    layout = newRegion and newRegion.layout
                else
                    -- Load existing region
                    teleportToRegionAsync(self, pending.targetRegionId, pending.targetPadId, player)
                    local targetRegion = state.regions[pending.targetRegionId]
                    container = targetRegion and targetRegion.container
                    layout = targetRegion and targetRegion.layout
                end

                -- Store pending minimap build (will fire loadingComplete when ready)
                state.pendingMiniMapBuild[player] = {
                    container = container,
                }

                -- Fire buildMiniMap to client - client will signal miniMapReady when done
                -- Note: domTree NOT sent — cyclic refs can't cross IPC boundary
                self.Out:Fire("buildMiniMap", {
                    _targetPlayer = player,
                    player = player,
                    layout = layout,
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
                self._System.Player.unanchorPlayer(player)

                -- Clear pending transition
                state.pendingTransitions[player] = nil

                if System and System.Debug then
                    System.Debug.info("RegionManager", "Transition complete for", player.Name)
                end
            end,

            --[[
                Handle visited state request from MiniMap (when map is opened).
                Sends current visited rooms, current room, and stats (no layout).

                @param data table:
                    player: Player - The requesting player
                    regionNum: number? - Region number to look up (avoids stale activeRegionId)
            --]]
            onRequestVisitedState = function(self, data)
                if not data or not data.player then return end

                local state = getState(self)
                local player = data.player

                -- Use regionNum from request if provided (avoids stale activeRegionId)
                local regionNum = data.regionNum
                local targetRegion = nil

                if regionNum then
                    -- Find region with matching regionNum
                    for _, region in pairs(state.regions) do
                        if region.layout and region.layout.regionNum == regionNum then
                            targetRegion = region
                            break
                        end
                    end
                end

                -- Fall back to activeRegion if no match found
                if not targetRegion then
                    targetRegion = state.regions[state.activeRegionId]
                end

                if not targetRegion or not targetRegion.layout then return end

                local layout = targetRegion.layout
                regionNum = regionNum or layout.regionNum or 1

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

                -- Send visited state back to MiniMap
                self.Out:Fire("visitedState", {
                    _targetPlayer = player,
                    player = player,
                    visitedRooms = visitedRooms,
                    currentRoom = currentRoom,
                    padLinks = targetRegion.padLinks or {},
                    stats = {
                        totalRooms = totalRooms,
                        exploredRooms = exploredRooms,
                        totalPortals = totalPortals,
                        discoveredPortals = discoveredPortals,
                        completion = completion,
                    },
                })
            end,

            --[[
                Handle minimap ready signal from MiniMap.
                Continues the region load chain after minimap geometry is built.
            --]]
            onMiniMapReady = function(self, data)
                if not data or not data.player then return end

                local state = getState(self)
                local player = data.player
                local pending = state.pendingMiniMapBuild and state.pendingMiniMapBuild[player]

                if not pending then return end

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "MiniMap ready for", player.Name)
                end

                -- Clear pending state
                state.pendingMiniMapBuild[player] = nil

                -- Fire loading complete to client with container for preloading
                self.Out:Fire("loadingComplete", {
                    _targetPlayer = player,
                    player = player,
                    container = pending.container,
                })
            end,

            --[[
                Handle exit to title request from ExitScreen.
                Initiates fade-to-black transition, then unloads dungeon and shows title screen.

                @param data table:
                    player: Player - The player who requested exit
            --]]
            onExitToTitle = function(self, data)
                if not data or not data.player then
                    warn("[RegionManager] Invalid exitToTitle data")
                    return
                end

                local state = getState(self)
                local player = data.player

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Exit to title requested by", player.Name)
                end

                -- On gameplay server, teleport back to start Place
                if PlaceGraph.isGameplayServer() then
                    if System and System.Debug then
                        System.Debug.info("RegionManager", "Gameplay server - teleporting", player.Name, "to start Place (title)")
                    end
                    PlaceGraph.navigateTo("start", player, { destination = "title" })
                    return
                end

                -- Store pending exit-to-title transition
                state.pendingTransitions[player] = {
                    isExitToTitle = true,
                }

                -- Signal client to fade to black
                self.Out:Fire("transitionStart", {
                    _targetPlayer = player,
                    player = player,
                })
            end,

            --[[
                Handle exit to lobby request from ExitScreen (on reserved servers).
                Teleports the player back to the main Place with lobby destination.

                @param data table:
                    player: Player - The player who requested exit to lobby
            --]]
            onExitToLobby = function(self, data)
                if not data or not data.player then
                    warn("[RegionManager] Invalid exitToLobby data")
                    return
                end

                local state = getState(self)
                local player = data.player

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Exit to lobby requested by", player.Name)
                end

                -- Teleport back to start Place with lobby destination
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Teleporting", player.Name, "to start Place (lobby)")
                end
                PlaceGraph.navigateTo("start", player, { destination = "lobby" })
            end,

        },

        Out = {
            hideTitle = {},
            showTitle = {},
            returnToTitle = {},
            dioramaReady = {},
            transitionStart = {},
            loadingComplete = {},
            transitionEnd = {},
            areaInfo = {},
            buildMiniMap = {},
            visitedState = {},
            savedDataCleared = {},
            padsReady = {},
            unloadLobby = {},
        },

        -- Configuration
        configure = function(self, config)
            local state = getState(self)
            for key, value in pairs(config) do
                state.config[key] = value
            end
        end,

        -- Build the title diorama (called from Bootstrap after configure)
        -- DEPRECATED: Use System.Player.preload("title") instead
        buildTitleDiorama = function(self)
            self._System.Player.preload("title")
        end,

        -- Enter lobby directly (for TeleportData re-entry)
        -- DEPRECATED: Use System.Player.transitionTo(player, "lobby") instead
        enterLobbyDirectly = function(self, player)
            self._System.Player.transitionTo(player, "lobby")
        end,

        -- Start the dungeon for a player (loads existing or creates new)
        startFirstRegion = function(self, player)
            local state = getState(self)

            -- Delete baseplate
            local baseplate = workspace:FindFirstChild("Baseplate")
            if baseplate then
                baseplate:Destroy()
            end

            -- Check if we should skip DataStore load (e.g., user just cleared data)
            local skipLoad = state.skipDataLoad and state.skipDataLoad[player]
            if skipLoad then
                state.skipDataLoad[player] = nil  -- Clear the flag
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Skipping DataStore load for", player.Name, "(data was cleared)")
                end
            end

            -- Try to load existing save data (unless skipLoad is set)
            if not skipLoad and player and loadPlayerData(self, player) and state.activeRegionId then
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

            -- Store region with layout and map type
            state.regions[regionId] = {
                id = regionId,
                layout = layout,
                mapType = mapType,  -- Store for future branching decisions
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

        -- Register view definitions with System.Player subsystem.
        -- Called from Bootstrap.server.lua before System.Player.activate().
        registerViews = function(self)
            registerViews(self)
        end,

        -- Clear save data for a player (for testing/reset)
        clearSaveData = function(self, player)
            local store = getDataStore()
            if not store then return false end

            local state = getState(self)
            local key = "player_" .. player.UserId
            local success, err = pcall(function()
                store:RemoveAsync(key)
            end)

            if success then
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("RegionManager", "Cleared save data for", player.Name)
                end

                -- Also clear in-memory state so next Start creates fresh data
                -- Clear region data
                for regionId, region in pairs(state.regions) do
                    -- Destroy any instantiated models
                    if region.model then
                        region.model:Destroy()
                    end
                end
                state.regions = {}
                state.activeRegionId = nil
                state.regionCount = 0
                state.unlinkedPadCount = 0

                -- Clear player-specific state
                state.visitedRooms[player] = nil
                state.playerRooms[player] = nil
                state.pendingTransitions[player] = nil

                -- Set flag to skip DataStore load on next Start (avoids cache issues)
                if not state.skipDataLoad then
                    state.skipDataLoad = {}
                end
                state.skipDataLoad[player] = true

                if System and System.Debug then
                    System.Debug.info("RegionManager", "Reset in-memory state for", player.Name)
                end
            else
                warn("[RegionManager] Failed to clear data for", player.Name, ":", err)
            end

            return success
        end,

        -- TODO: These admin functions are currently accessed via _G.RegionManager in
        -- Studio CLI. This is hacky but works for development testing. Later, integrate
        -- into a proper system:
        -- - Options screen UI for players to manage their save data
        -- - Multiple save slots (RPG-style)
        -- - Admin panel for moderators/devs
        -- See: Bootstrap.server.lua where _G.RegionManager is assigned

        -- Admin: Clear save data (for Studio CLI)
        -- Usage:
        --   regionManager:adminClearSaveData()           -- current player
        --   regionManager:adminClearSaveData("Username") -- by username
        --   regionManager:adminClearSaveData(12345678)   -- by UserId
        adminClearSaveData = function(self, playerOrId)
            local store = getDataStore()
            if not store then
                warn("[RegionManager] DataStore not available")
                return false
            end

            -- Resolve to UserId
            local userId
            if playerOrId == nil then
                -- No arg: use first player in game
                local players = Players:GetPlayers()
                if #players == 0 then
                    warn("[RegionManager] No players in game")
                    return false
                end
                userId = players[1].UserId
            elseif type(playerOrId) == "number" then
                -- Direct UserId
                userId = playerOrId
            elseif type(playerOrId) == "string" then
                -- Username lookup
                local player = Players:FindFirstChild(playerOrId)
                if player then
                    userId = player.UserId
                else
                    warn("[RegionManager] Player not found:", playerOrId)
                    return false
                end
            elseif typeof(playerOrId) == "Instance" and playerOrId:IsA("Player") then
                -- Player object
                userId = playerOrId.UserId
            else
                warn("[RegionManager] Invalid argument type")
                return false
            end

            local key = "player_" .. tostring(userId)
            local success, err = pcall(function()
                store:RemoveAsync(key)
            end)

            if success then
                print("[RegionManager] Admin: Cleared save data for UserId:", userId)
            else
                warn("[RegionManager] Admin: Failed to clear data for UserId:", userId, "-", err)
            end

            return success
        end,

        -- Admin: Dump raw save data to output (for debugging serialization issues)
        -- Usage:
        --   regionManager:adminDumpRawData()           -- current player
        --   regionManager:adminDumpRawData("Username") -- by username
        --   regionManager:adminDumpRawData(12345678)   -- by UserId
        adminDumpRawData = function(self, playerOrId)
            local store = getDataStore()
            if not store then
                warn("[RegionManager] DataStore not available")
                return nil
            end

            -- Resolve to UserId
            local userId
            if playerOrId == nil then
                local players = Players:GetPlayers()
                if #players == 0 then
                    warn("[RegionManager] No players in game")
                    return nil
                end
                userId = players[1].UserId
            elseif type(playerOrId) == "number" then
                userId = playerOrId
            elseif type(playerOrId) == "string" then
                local player = Players:FindFirstChild(playerOrId)
                if player then
                    userId = player.UserId
                else
                    warn("[RegionManager] Player not found:", playerOrId)
                    return nil
                end
            elseif typeof(playerOrId) == "Instance" and playerOrId:IsA("Player") then
                userId = playerOrId.UserId
            else
                warn("[RegionManager] Invalid argument type")
                return nil
            end

            local key = "player_" .. tostring(userId)
            local success, data = pcall(function()
                return store:GetAsync(key)
            end)

            if success and data then
                -- Dump structure to help diagnose issues
                print("[RegionManager] === RAW DATA DUMP for UserId", userId, "===")

                if data.regions then
                    for regionId, region in pairs(data.regions) do
                        print("Region:", regionId)
                        if region.layout and region.layout.rooms then
                            print("  Rooms table type:", type(region.layout.rooms))
                            for roomKey, room in pairs(region.layout.rooms) do
                                local keyType = type(roomKey)
                                local posType = room.position and type(room.position) or "nil"
                                local pos1Type = room.position and room.position[1] and "num" or
                                    (room.position and room.position["1"] and "str" or "missing")
                                print(string.format("    Room key=%s(%s) pos=%s pos[1]=%s",
                                    tostring(roomKey), keyType, posType, pos1Type))
                            end
                        end
                    end
                end

                print("[RegionManager] === END RAW DATA DUMP ===")
                return data
            else
                warn("[RegionManager] Failed to get data:", data)
                return nil
            end
        end,

        -- Admin: View save data (for debugging)
        -- Usage:
        --   regionManager:adminViewSaveData()           -- current player
        --   regionManager:adminViewSaveData("Username") -- by username
        --   regionManager:adminViewSaveData(12345678)   -- by UserId
        adminViewSaveData = function(self, playerOrId)
            local store = getDataStore()
            if not store then
                warn("[RegionManager] DataStore not available")
                return nil
            end

            -- Resolve to UserId
            local userId
            if playerOrId == nil then
                local players = Players:GetPlayers()
                if #players == 0 then
                    warn("[RegionManager] No players in game")
                    return nil
                end
                userId = players[1].UserId
            elseif type(playerOrId) == "number" then
                userId = playerOrId
            elseif type(playerOrId) == "string" then
                local player = Players:FindFirstChild(playerOrId)
                if player then
                    userId = player.UserId
                else
                    warn("[RegionManager] Player not found:", playerOrId)
                    return nil
                end
            elseif typeof(playerOrId) == "Instance" and playerOrId:IsA("Player") then
                userId = playerOrId.UserId
            else
                warn("[RegionManager] Invalid argument type")
                return nil
            end

            local key = "player_" .. tostring(userId)
            local success, data = pcall(function()
                return store:GetAsync(key)
            end)

            if success then
                if data then
                    print("[RegionManager] Admin: Save data for UserId", userId)
                    print("  - Version:", data.version)
                    print("  - Region count:", data.regionCount)
                    print("  - Active region:", data.activeRegionId)
                    print("  - Unlinked pads:", data.unlinkedPadCount)
                    if data.regions then
                        for regionId, region in pairs(data.regions) do
                            -- New seed-based format
                            if region.seed then
                                print(string.format("  - %s: seed=%d, padCount=%d, type=%s",
                                    regionId,
                                    region.seed,
                                    region.padCount or 0,
                                    region.mapType or "unknown"))
                            -- Legacy full-layout format
                            elseif region.layout then
                                local roomCount = 0
                                if region.layout.rooms then
                                    for _ in pairs(region.layout.rooms) do
                                        roomCount = roomCount + 1
                                    end
                                end
                                print("  - " .. regionId .. ": (legacy) " .. roomCount .. " rooms")
                            end
                        end
                    end
                else
                    print("[RegionManager] Admin: No save data for UserId:", userId)
                end
                return data
            else
                warn("[RegionManager] Admin: Failed to read data for UserId:", userId, "-", data)
                return nil
            end
        end,
    }
end)

return RegionManager
