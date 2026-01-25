--[[
    LibPureFiction Framework v2
    Dropper.lua - Versatile Spawner Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Dropper spawns entities via interval loop or on-demand signals.
    It uses SpawnerCore internally for spawn/despawn/tracking operations.

    Key features:
    - Interval-based spawning (timer loop)
    - On-demand spawning (onDispense signal)
    - Template pool with sequential/random selection
    - Optional capacity (total spawn limit) with refill
    - Optional maxActive (concurrent spawn limit)
    - Tracks all spawned entities

    Dropper is designed to work with other components via wiring:
    - PathFollower: Guide spawned entities along paths
    - Zone: Detect when entities reach destination, signal back to Dropper

    Use cases:
    - Tycoon dropper (interval loop, single template)
    - Tool dispenser (on-demand, pool of items, finite capacity)
    - NPC spawner (interval or on-demand, maxActive limit)

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onStart()
            - Begin the spawn loop

        onStop()
            - Stop the spawn loop (does not despawn existing entities)

        onDispense({ count?, templateName? })
            - One-shot spawn, bypasses interval loop
            - count: number of items to spawn (default 1)
            - templateName: override template for this dispense

        onReturn({ assetId: string })
            - Despawn a specific entity by assetId
            - Typically wired from Zone.entityEntered

        onConfigure({ interval?, templateName?, maxActive?, ... })
            - Configure dropper settings (see CONFIGURATION)

        onRefill({ amount? })
            - Restore capacity (nil = full refill)

        onDespawnAll()
            - Despawn all entities spawned by this dropper

    OUT (emits):
        spawned({ assetId, instance, entityId, templateName, dropperId })
            - Fired when an entity is spawned
            - Wire to PathFollower.onControl to assign entity for navigation

        despawned({ assetId, entityId, dropperId })
            - Fired when an entity is despawned

        depleted({ dropperId })
            - Fired when capacity is exhausted

        loopStarted({ dropperId })
            - Fired when spawn loop begins

        loopStopped({ dropperId })
            - Fired when spawn loop ends

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Interval: number (default 2)
        Seconds between spawns in loop mode

    TemplateName: string (default "")
        Name of template to spawn (single template mode)

    MaxActive: number (default 0)
        Maximum concurrent spawned entities (0 = unlimited)

    Capacity: number (default nil)
        Total spawn limit (nil = unlimited)

    PoolMode: string (default "single")
        Template selection mode: "single", "sequential", "random"

    AutoStart: boolean (default false)
        If true, begins spawning on init

    SpawnOffset: Vector3 (default 0,0,0)
        Offset from dropper position for spawn location

    ============================================================================
    CONFIGURATION
    ============================================================================

    onConfigure accepts:
        interval: number - Seconds between spawns
        templateName: string - Single template name
        pool: table - Array of template names for multi-template mode
        poolMode: string - "single", "sequential", "random"
        maxActive: number - Concurrent limit (0 = unlimited)
        capacity: number - Total limit (nil = unlimited)
        spawnOffset: Vector3 - Offset from model position
        spawnPosition: Vector3 - Absolute spawn position (overrides offset)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Create dropper with model (position source)
    local dropper = Dropper:new({ model = workspace.DropperPart })
    dropper.Sys.onInit(dropper)

    -- Configure
    dropper.In.onConfigure(dropper, {
        templateName = "Crate",
        interval = 2,
        maxActive = 10,
    })

    -- Wire spawned output to PathFollower
    dropper.Out = {
        Fire = function(self, signal, data)
            if signal == "spawned" then
                pathFollower.In.onControl(pathFollower, {
                    entity = data.instance,
                    entityId = data.entityId,
                })
            end
        end,
    }

    -- Wire Zone.entityEntered to dropper return
    zone.Out = {
        Fire = function(self, signal, data)
            if signal == "entityEntered" then
                dropper.In.onReturn(dropper, { assetId = data.assetId })
            end
        end,
    }

    -- Start spawning
    dropper.In.onStart(dropper)
    ```

--]]

local Node = require(script.Parent.Parent.Node)
local SpawnerCore = require(script.Parent.Parent.Internal.SpawnerCore)

--------------------------------------------------------------------------------
-- DROPPER NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Dropper = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                running = false,
                spawnedAssetIds = {},  -- { [assetId] = true }
                spawnCounter = 0,
                pool = nil,            -- Array of template names
                poolIndex = 0,         -- Current index for sequential mode
                capacity = nil,        -- Total spawn limit (nil = unlimited)
                remaining = nil,       -- Remaining spawns (nil = unlimited)
                spawnPosition = nil,   -- Override spawn position
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Get the spawn position.
    --]]
    local function getSpawnPosition(self)
        local state = getState(self)

        -- Use configured position if set
        if state.spawnPosition then
            return state.spawnPosition
        end

        -- Use model position + offset
        local basePosition = Vector3.new(0, 5, 0)

        if self.model then
            if self.model:IsA("BasePart") then
                basePosition = self.model.Position
            elseif self.model:IsA("Model") then
                if self.model.PrimaryPart then
                    basePosition = self.model.PrimaryPart.Position
                else
                    local part = self.model:FindFirstChildWhichIsA("BasePart")
                    if part then
                        basePosition = part.Position
                    end
                end
            end
        end

        -- Apply offset
        local offset = self:getAttribute("SpawnOffset")
        if offset then
            basePosition = basePosition + offset
        end

        return basePosition
    end

    --[[
        Private: Get the current count of active spawned entities.
    --]]
    local function getActiveCount(self)
        local state = getState(self)
        local count = 0
        for assetId in pairs(state.spawnedAssetIds) do
            -- Verify still exists
            if SpawnerCore.getInstance(assetId) then
                count = count + 1
            else
                -- Clean up stale reference
                state.spawnedAssetIds[assetId] = nil
            end
        end
        return count
    end

    --[[
        Private: Check if we can spawn (respects MaxActive and Capacity).
    --]]
    local function canSpawn(self)
        local state = getState(self)

        -- Check capacity (total limit)
        if state.remaining ~= nil and state.remaining <= 0 then
            return false
        end

        -- Check maxActive (concurrent limit)
        local maxActive = self:getAttribute("MaxActive") or 0
        if maxActive > 0 and getActiveCount(self) >= maxActive then
            return false
        end

        return true
    end

    --[[
        Private: Select template name based on pool mode.
        Returns template name string.
    --]]
    local function selectTemplate(self, override)
        local state = getState(self)

        -- If override provided, use it
        if override then
            return override
        end

        -- If no pool, use single template
        local pool = state.pool
        if not pool or #pool == 0 then
            return self:getAttribute("TemplateName")
        end

        -- Select based on pool mode
        local mode = self:getAttribute("PoolMode") or "single"

        if mode == "sequential" then
            state.poolIndex = (state.poolIndex % #pool) + 1
            return pool[state.poolIndex]
        elseif mode == "random" then
            return pool[math.random(#pool)]
        else
            -- "single" mode - just use first item
            return pool[1]
        end
    end

    --[[
        Private: Spawn a single entity.
        templateOverride: optional template name to use instead of pool selection
    --]]
    local function spawn(self, templateOverride)
        local state = getState(self)

        -- Select template (from pool, single, or override)
        local templateName = selectTemplate(self, templateOverride)
        if not templateName or templateName == "" then
            self.Err:Fire({
                reason = "no_template",
                message = "TemplateName not configured",
                dropperId = self.id,
            })
            return nil
        end

        -- Check limits (capacity + maxActive)
        if not canSpawn(self) then
            return nil
        end

        -- Generate entity ID
        state.spawnCounter = state.spawnCounter + 1
        local entityId = self.id .. "_entity_" .. state.spawnCounter

        -- Spawn via SpawnerCore
        local result, err = SpawnerCore.spawn({
            templateName = templateName,
            parent = workspace,
            position = getSpawnPosition(self),
            attributes = {
                NodeId = entityId,
                NodeClass = templateName,
                NodeSpawnSource = self.id,
            },
        })

        if not result then
            self.Err:Fire({
                reason = "spawn_failed",
                message = err or "Unknown spawn error",
                dropperId = self.id,
                templateName = templateName,
            })
            return nil
        end

        -- Track this spawn
        state.spawnedAssetIds[result.assetId] = true

        -- Decrement capacity if finite
        if state.remaining ~= nil then
            state.remaining = state.remaining - 1
            self:setAttribute("Remaining", state.remaining)

            -- Fire depleted if capacity exhausted
            if state.remaining <= 0 then
                self.Out:Fire("depleted", { dropperId = self.id })
            end
        end

        -- Fire spawned signal
        self.Out:Fire("spawned", {
            assetId = result.assetId,
            instance = result.instance,
            entityId = entityId,
            templateName = templateName,
            dropperId = self.id,
        })

        return result
    end

    -- Forward declaration for startLoop (used by onInit for AutoStart)
    local startLoop

    --[[
        Private: Stop the spawn loop.
    --]]
    local function stopLoop(self)
        local state = getState(self)

        if not state.running then
            return
        end

        state.running = false
        self.Out:Fire("loopStopped", { dropperId = self.id })
    end

    --[[
        Private: Start the spawn loop.
    --]]
    startLoop = function(self)
        local state = getState(self)

        if state.running then
            return
        end

        state.running = true
        self.Out:Fire("loopStarted", { dropperId = self.id })

        -- Spawn loop
        task.spawn(function()
            while state.running do
                -- Spawn one entity
                spawn(self)

                -- Wait for interval
                local interval = self:getAttribute("Interval") or 2
                task.wait(interval)
            end
        end)
    end

    --[[
        Private: Despawn all entities spawned by this dropper.
    --]]
    local function despawnAll(self)
        local state = getState(self)
        local toRemove = {}
        for assetId in pairs(state.spawnedAssetIds) do
            table.insert(toRemove, assetId)
        end

        for _, assetId in ipairs(toRemove) do
            SpawnerCore.despawn(assetId)
            state.spawnedAssetIds[assetId] = nil
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "Dropper",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Ensure SpawnerCore is initialized
                if not SpawnerCore.isInitialized() then
                    SpawnerCore.init({
                        templates = game:GetService("ReplicatedStorage"):FindFirstChild("Templates"),
                    })
                end

                -- Default attributes
                if not self:getAttribute("Interval") then
                    self:setAttribute("Interval", 2)
                end
                if not self:getAttribute("TemplateName") then
                    self:setAttribute("TemplateName", "")
                end
                if not self:getAttribute("MaxActive") then
                    self:setAttribute("MaxActive", 0)
                end
                if not self:getAttribute("PoolMode") then
                    self:setAttribute("PoolMode", "single")
                end
                if self:getAttribute("AutoStart") == nil then
                    self:setAttribute("AutoStart", false)
                end

                -- Auto-start if configured
                if self:getAttribute("AutoStart") then
                    startLoop(self)
                end
            end,

            onStart = function(self)
                -- Nothing additional on start
            end,

            onStop = function(self)
                stopLoop(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Configure dropper settings.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.interval then
                    self:setAttribute("Interval", data.interval)
                end

                if data.templateName then
                    self:setAttribute("TemplateName", data.templateName)
                end

                if data.maxActive then
                    self:setAttribute("MaxActive", data.maxActive)
                end

                if data.spawnPosition then
                    state.spawnPosition = data.spawnPosition
                end

                if data.spawnOffset then
                    self:setAttribute("SpawnOffset", data.spawnOffset)
                end

                -- Pool configuration
                if data.pool then
                    state.pool = data.pool
                    state.poolIndex = 0
                end

                if data.poolMode then
                    self:setAttribute("PoolMode", data.poolMode)
                end

                -- Capacity configuration
                if data.capacity ~= nil then
                    state.capacity = data.capacity
                    state.remaining = data.capacity
                    self:setAttribute("Capacity", data.capacity)
                end
            end,

            --[[
                Start the spawn loop.
            --]]
            onStart = function(self)
                startLoop(self)
            end,

            --[[
                Stop the spawn loop.
            --]]
            onStop = function(self)
                stopLoop(self)
            end,

            --[[
                Despawn a specific entity by assetId.
                Typically called when entity reaches end zone.
            --]]
            onReturn = function(self, data)
                if not data or not data.assetId then
                    return
                end

                local state = getState(self)
                local assetId = data.assetId

                -- Only despawn if we spawned it
                if not state.spawnedAssetIds[assetId] then
                    return
                end

                -- Get entity info before despawn
                local record = SpawnerCore.getRecord(assetId)
                local entityId = record and record.instance and record.instance:GetAttribute("NodeId")

                -- Despawn
                local success = SpawnerCore.despawn(assetId)
                if success then
                    state.spawnedAssetIds[assetId] = nil

                    -- Fire despawned signal
                    self.Out:Fire("despawned", {
                        assetId = assetId,
                        entityId = entityId,
                        dropperId = self.id,
                    })
                end
            end,

            --[[
                Despawn all entities spawned by this dropper.
            --]]
            onDespawnAll = function(self)
                despawnAll(self)
            end,

            --[[
                One-shot spawn - bypasses interval loop.
                Use for dispenser-style on-demand spawning.
            --]]
            onDispense = function(self, data)
                data = data or {}
                local count = data.count or 1
                local templateOverride = data.templateName

                for _ = 1, count do
                    -- Check if we can spawn (capacity + maxActive)
                    if not canSpawn(self) then
                        break
                    end

                    -- Spawn with optional template override
                    spawn(self, templateOverride)
                end
            end,

            --[[
                Restore capacity.
                amount = nil: full refill to original capacity
                amount = number: add that amount (capped at capacity)
            --]]
            onRefill = function(self, data)
                data = data or {}
                local state = getState(self)

                if state.capacity == nil then
                    -- Unlimited capacity, nothing to refill
                    return
                end

                if data.amount then
                    -- Partial refill
                    state.remaining = math.min(
                        (state.remaining or 0) + data.amount,
                        state.capacity
                    )
                else
                    -- Full refill
                    state.remaining = state.capacity
                end

                self:setAttribute("Remaining", state.remaining)
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            spawned = {},    -- { assetId, instance, entityId, templateName, dropperId }
            despawned = {},  -- { assetId, entityId, dropperId }
            depleted = {},   -- { dropperId }
            loopStarted = {},
            loopStopped = {},
        },

        -- Err (detour) signals documented in header
    }
end)

return Dropper
