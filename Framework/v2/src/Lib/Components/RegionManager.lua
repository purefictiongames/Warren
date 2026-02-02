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

--]]

local Players = game:GetService("Players")
local Node = require(script.Parent.Parent.Node)
local Layout = require(script.Parent.Layout)

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
                -- Teleport connections
                touchConnections = {},
                -- Player pad state (track who is on which pad, require exit before reactivation)
                playerPadState = {},
                -- Pending teleport (wait for build completion)
                pendingTeleport = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = getState(self)
        for _, conn in pairs(state.touchConnections) do
            conn:Disconnect()
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- LAYOUT GENERATION & INSTANTIATION
    ----------------------------------------------------------------------------

    local function generateSeed()
        return os.time() + math.random(1, 100000)
    end

    local function generateLayout(self, seed, regionNum)
        local state = getState(self)
        local config = state.config

        -- Offset each region to avoid geometry overlap during transitions
        local regionOffset = (regionNum - 1) * 2000
        local origin = config.origin or { 0, 20, 0 }
        local offsetOrigin = { origin[1] + regionOffset, origin[2], origin[3] }

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
            color = config.color,
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
    -- PAD TOUCH HANDLING
    ----------------------------------------------------------------------------

    local setupPadTouchHandler  -- Forward declaration

    local function setupAllPadHandlers(self, regionId)
        local state = getState(self)
        local region = state.regions[regionId]

        if not region or not region.pads then return end

        for padId, padData in pairs(region.pads) do
            setupPadTouchHandler(self, regionId, padId, padData.part)
        end
    end

    setupPadTouchHandler = function(self, regionId, padId, padPart)
        local state = getState(self)

        if not padPart then return end

        -- Create qualified pad ID (region + pad) to avoid cross-region conflicts
        local qualifiedPadId = regionId .. "_" .. padId

        -- Touch started - player enters pad
        local touchConnection = padPart.Touched:Connect(function(hit)
            local player = Players:GetPlayerFromCharacter(hit.Parent)
            if not player then return end

            local playerId = player.UserId
            local playerState = state.playerPadState[playerId]

            -- Initialize player state if needed
            if not playerState then
                state.playerPadState[playerId] = { onPad = nil, canActivate = true }
                playerState = state.playerPadState[playerId]
            end

            -- Track that player is on this pad (with region qualifier)
            playerState.onPad = qualifiedPadId

            -- Check if player can activate (must have exited pad since last teleport)
            if not playerState.canActivate then
                return
            end

            -- Debounce - prevent multiple triggers
            if padPart:GetAttribute("Teleporting") then return end
            padPart:SetAttribute("Teleporting", true)

            -- Mark player as unable to activate until they exit
            playerState.canActivate = false

            task.defer(function()
                handlePadTouch(self, regionId, padId, player)
                task.wait(0.5)
                if padPart and padPart.Parent then
                    padPart:SetAttribute("Teleporting", false)
                end
            end)
        end)

        -- Touch ended - player exits pad
        local touchEndConnection = padPart.TouchEnded:Connect(function(hit)
            local player = Players:GetPlayerFromCharacter(hit.Parent)
            if not player then return end

            local playerId = player.UserId
            local playerState = state.playerPadState[playerId]

            -- Only re-enable activation if player is exiting THIS specific pad
            if playerState and playerState.onPad == qualifiedPadId then
                playerState.onPad = nil
                playerState.canActivate = true
            end
        end)

        state.touchConnections[regionId .. "_" .. padId .. "_touch"] = touchConnection
        state.touchConnections[regionId .. "_" .. padId .. "_touchend"] = touchEndConnection
    end

    function handlePadTouch(self, regionId, padId, player)
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

        -- Setup pad touch handlers
        setupAllPadHandlers(self, newRegionId)

        -- Link first pad back to source
        local firstPadId = getFirstPadId(state.regions[newRegionId])
        if firstPadId and sourcePadId then
            linkPads(self, sourceRegionId, sourcePadId, newRegionId, firstPadId)
        end

        -- Prepare teleport (disable activation before moving)
        local playerId = player.UserId
        if not state.playerPadState[playerId] then
            state.playerPadState[playerId] = { onPad = nil, canActivate = false }
        else
            state.playerPadState[playerId].onPad = nil
            state.playerPadState[playerId].canActivate = false
        end

        -- Teleport to spawn in new region
        teleportPlayerToSpawn(self, newRegionId, player)

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

        -- Disconnect old touch handlers for this region
        local prefix = targetRegionId .. "_"
        local keysToRemove = {}
        for key, conn in pairs(state.touchConnections) do
            if string.sub(key, 1, #prefix) == prefix then
                conn:Disconnect()
                table.insert(keysToRemove, key)
            end
        end
        for _, key in ipairs(keysToRemove) do
            state.touchConnections[key] = nil
        end

        -- Reinstantiate from stored layout (no regeneration!)
        local result = instantiateLayout(self, targetRegionId, targetRegion.layout)

        -- Setup pad touch handlers
        setupAllPadHandlers(self, targetRegionId)

        -- Prepare teleport
        local playerId = player.UserId
        if not state.playerPadState[playerId] then
            state.playerPadState[playerId] = { onPad = nil, canActivate = false }
        else
            state.playerPadState[playerId].onPad = nil
            state.playerPadState[playerId].canActivate = false
        end

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

        -- Disconnect touch handlers for this region
        local prefix = regionId .. "_"
        local keysToRemove = {}
        for key, conn in pairs(state.touchConnections) do
            if string.sub(key, 1, #prefix) == prefix then
                conn:Disconnect()
                table.insert(keysToRemove, key)
            end
        end
        for _, key in ipairs(keysToRemove) do
            state.touchConnections[key] = nil
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

        -- Try runtime pad reference first
        if region and region.pads and region.pads[padId] then
            local pad = region.pads[padId]
            if pad.part and pad.part.Parent then
                hrp.CFrame = pad.part.CFrame + Vector3.new(0, 3, 0)
                return
            elseif pad.position then
                hrp.CFrame = CFrame.new(
                    pad.position[1],
                    pad.position[2] + 3,
                    pad.position[3]
                )
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
            instantiateLayout(self, regionId, layout)

            -- Setup pad touch handlers
            setupAllPadHandlers(self, regionId)

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
