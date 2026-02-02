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
    FUTURE: Persistent Layout Storage
    ============================================================================

    Layouts can be serialized and stored per-player in DataStore for persistence.
    This would allow players to return to previously explored regions.

    Size estimates (per layout, ~12 rooms):
    - Uncompressed JSON: ~4.5-5 KB
    - DataStore auto-compresses internally, so no manual gzip needed
    - 4MB DataStore limit = 800+ regions per player (more than enough)

    Proposed DataStore structure:
    ```lua
    {
        regions = {
            ["region_1"] = { version, seed, rooms, doors, trusses, lights, pads, spawn, config },
            ["region_2"] = { ... },
        },
        padLinks = {
            ["region_1_pad_1"] = { regionId = "region_2", padId = "pad_1" },
            ...
        },
        currentRegion = "region_5",
        regionCount = 5,
    }
    ```

    Implementation notes:
    - Store full layouts (not just seeds) to preserve exact geometry
    - This protects against algorithm changes breaking old saves
    - Enables future player modifications to their dungeons
    - Load existing layouts on player join, generate new as needed
    - Save on region creation and periodically

--]]

local Players = game:GetService("Players")
local Node = require(script.Parent.Parent.Node)
local Layout = require(script.Parent.Layout)
local JumpPad = require(script.Parent.JumpPad)

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
                    roomsPerPad = 25,
                    origin = { 0, 20, 0 },
                },
                -- Region tracking
                -- Each region stores: id, layout, padLinks, isActive, container, pads, spawnPoint
                regions = {},
                activeRegionId = nil,
                regionCount = 0,
                -- JumpPad instance IDs (for IPC.despawn)
                jumpPadIds = {},
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
    -- LAYOUT GENERATION & INSTANTIATION
    ----------------------------------------------------------------------------

    local function generateSeed()
        return os.time() + math.random(1, 100000)
    end

    -- Color palette for different regions (earthy/stone tones)
    local REGION_COLORS = {
        { 140, 110, 90 },   -- Warm brown (default)
        { 120, 130, 140 },  -- Cool grey-blue
        { 150, 120, 100 },  -- Terracotta
        { 100, 120, 100 },  -- Mossy green
        { 130, 100, 120 },  -- Dusty purple
        { 140, 140, 120 },  -- Sandstone
        { 110, 100, 90 },   -- Dark earth
        { 150, 140, 130 },  -- Light tan
        { 100, 110, 130 },  -- Slate blue
        { 130, 120, 110 },  -- Neutral stone
    }

    local function getRegionColor(regionNum)
        -- Cycle through palette, with slight random variation
        local baseColor = REGION_COLORS[((regionNum - 1) % #REGION_COLORS) + 1]
        -- Add small random variation (+/- 10) for uniqueness
        local variation = 10
        return {
            math.clamp(baseColor[1] + math.random(-variation, variation), 50, 200),
            math.clamp(baseColor[2] + math.random(-variation, variation), 50, 200),
            math.clamp(baseColor[3] + math.random(-variation, variation), 50, 200),
        }
    end

    local function generateLayout(self, seed, regionNum)
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
            roomsPerPad = config.roomsPerPad,
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

    function handleJumpRequest(self, regionId, padId, player)
        local state = getState(self)
        local region = state.regions[regionId]

        if not region then return end

        local padLinks = region.padLinks or {}
        local padLink = padLinks[padId]

        if padLink then
            -- Pad is linked - teleport to existing region
            teleportToRegion(self, padLink.regionId, padLink.padId, player)
        else
            -- Pad is unlinked - generate new region
            createNewRegion(self, regionId, padId, player)
        end
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

        -- Generate layout
        local layout = generateLayout(self, newSeed, regionNum)

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

        -- Link first pad back to source
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

        -- Destroy old JumpPads for this region
        destroyJumpPadsForRegion(self, targetRegionId)

        -- Reinstantiate from stored layout (no regeneration!)
        local result = instantiateLayout(self, targetRegionId, targetRegion.layout)

        -- Create JumpPad nodes for this region
        createJumpPadsForRegion(self, targetRegionId, result.container)

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
        },

        Out = {
            -- Reserved for future signals (e.g., regionLoaded, regionUnloaded)
        },

        -- Configuration
        configure = function(self, config)
            local state = getState(self)
            for key, value in pairs(config) do
                state.config[key] = value
            end
        end,

        -- Start the first region
        startFirstRegion = function(self)
            local state = getState(self)

            -- Delete baseplate
            local baseplate = workspace:FindFirstChild("Baseplate")
            if baseplate then
                baseplate:Destroy()
            end

            -- Create first region
            state.regionCount = 1
            local regionId = "region_1"
            local seed = generateSeed()

            -- Generate layout
            local layout = generateLayout(self, seed, 1)

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

            state.activeRegionId = regionId

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
    }
end)

return RegionManager
