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

local Dropper = Node.extend({
    name = "Dropper",
    domain = "server",

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Internal state
            self._running = false
            self._loopConnection = nil
            self._spawnedAssetIds = {}  -- { [assetId] = true }
            self._spawnCounter = 0

            -- Pool state
            self._pool = nil           -- Array of template names
            self._poolIndex = 0        -- Current index for sequential mode
            self._capacity = nil       -- Total spawn limit (nil = unlimited)
            self._remaining = nil      -- Remaining spawns (nil = unlimited)

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
                self:_startLoop()
            end
        end,

        onStart = function(self)
            -- Nothing additional on start
        end,

        onStop = function(self)
            self:_stopLoop()
            -- Optionally despawn all on stop
            -- self:_despawnAll()
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

    In = {
        --[[
            Configure dropper settings.
        --]]
        onConfigure = function(self, data)
            if not data then return end

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
                self._spawnPosition = data.spawnPosition
            end

            if data.spawnOffset then
                self:setAttribute("SpawnOffset", data.spawnOffset)
            end

            -- Pool configuration
            if data.pool then
                self._pool = data.pool
                self._poolIndex = 0
            end

            if data.poolMode then
                self:setAttribute("PoolMode", data.poolMode)
            end

            -- Capacity configuration
            if data.capacity ~= nil then
                self._capacity = data.capacity
                self._remaining = data.capacity
                self:setAttribute("Capacity", data.capacity)
            end
        end,

        --[[
            Start the spawn loop.
        --]]
        onStart = function(self)
            self:_startLoop()
        end,

        --[[
            Stop the spawn loop.
        --]]
        onStop = function(self)
            self:_stopLoop()
        end,

        --[[
            Despawn a specific entity by assetId.
            Typically called when entity reaches end zone.
        --]]
        onReturn = function(self, data)
            if not data or not data.assetId then
                return
            end

            local assetId = data.assetId

            -- Only despawn if we spawned it
            if not self._spawnedAssetIds[assetId] then
                return
            end

            -- Get entity info before despawn
            local record = SpawnerCore.getRecord(assetId)
            local entityId = record and record.instance and record.instance:GetAttribute("NodeId")

            -- Despawn
            local success = SpawnerCore.despawn(assetId)
            if success then
                self._spawnedAssetIds[assetId] = nil

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
            self:_despawnAll()
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
                if not self:_canSpawn() then
                    break
                end

                -- Spawn with optional template override
                self:_spawn(templateOverride)
            end
        end,

        --[[
            Restore capacity.
            amount = nil: full refill to original capacity
            amount = number: add that amount (capped at capacity)
        --]]
        onRefill = function(self, data)
            data = data or {}

            if self._capacity == nil then
                -- Unlimited capacity, nothing to refill
                return
            end

            if data.amount then
                -- Partial refill
                self._remaining = math.min(
                    (self._remaining or 0) + data.amount,
                    self._capacity
                )
            else
                -- Full refill
                self._remaining = self._capacity
            end

            self:setAttribute("Remaining", self._remaining)
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA (documentation)
    ----------------------------------------------------------------------------

    Out = {
        spawned = {},    -- { assetId, instance, entityId, templateName, dropperId }
        despawned = {},  -- { assetId, entityId, dropperId }
        depleted = {},   -- { dropperId }
        loopStarted = {},
        loopStopped = {},
    },

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    --[[
        Get the spawn position.
    --]]
    _getSpawnPosition = function(self)
        -- Use configured position if set
        if self._spawnPosition then
            return self._spawnPosition
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
    end,

    --[[
        Get the current count of active spawned entities.
    --]]
    _getActiveCount = function(self)
        local count = 0
        for assetId in pairs(self._spawnedAssetIds) do
            -- Verify still exists
            if SpawnerCore.getInstance(assetId) then
                count = count + 1
            else
                -- Clean up stale reference
                self._spawnedAssetIds[assetId] = nil
            end
        end
        return count
    end,

    --[[
        Check if we can spawn (respects MaxActive and Capacity).
    --]]
    _canSpawn = function(self)
        -- Check capacity (total limit)
        if self._remaining ~= nil and self._remaining <= 0 then
            return false
        end

        -- Check maxActive (concurrent limit)
        local maxActive = self:getAttribute("MaxActive") or 0
        if maxActive > 0 and self:_getActiveCount() >= maxActive then
            return false
        end

        return true
    end,

    --[[
        Select template name based on pool mode.
        Returns template name string.
    --]]
    _selectTemplate = function(self, override)
        -- If override provided, use it
        if override then
            return override
        end

        -- If no pool, use single template
        local pool = self._pool
        if not pool or #pool == 0 then
            return self:getAttribute("TemplateName")
        end

        -- Select based on pool mode
        local mode = self:getAttribute("PoolMode") or "single"

        if mode == "sequential" then
            self._poolIndex = (self._poolIndex % #pool) + 1
            return pool[self._poolIndex]
        elseif mode == "random" then
            return pool[math.random(#pool)]
        else
            -- "single" mode - just use first item
            return pool[1]
        end
    end,

    --[[
        Spawn a single entity.
        templateOverride: optional template name to use instead of pool selection
    --]]
    _spawn = function(self, templateOverride)
        -- Select template (from pool, single, or override)
        local templateName = self:_selectTemplate(templateOverride)
        if not templateName or templateName == "" then
            self.Err:Fire({
                reason = "no_template",
                message = "TemplateName not configured",
                dropperId = self.id,
            })
            return nil
        end

        -- Check limits (capacity + maxActive)
        if not self:_canSpawn() then
            return nil
        end

        -- Generate entity ID
        self._spawnCounter = self._spawnCounter + 1
        local entityId = self.id .. "_entity_" .. self._spawnCounter

        -- Spawn via SpawnerCore
        local result, err = SpawnerCore.spawn({
            templateName = templateName,
            parent = workspace,
            position = self:_getSpawnPosition(),
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
        self._spawnedAssetIds[result.assetId] = true

        -- Decrement capacity if finite
        if self._remaining ~= nil then
            self._remaining = self._remaining - 1
            self:setAttribute("Remaining", self._remaining)

            -- Fire depleted if capacity exhausted
            if self._remaining <= 0 then
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
    end,

    --[[
        Start the spawn loop.
    --]]
    _startLoop = function(self)
        if self._running then
            return
        end

        self._running = true
        self.Out:Fire("loopStarted", { dropperId = self.id })

        -- Spawn loop
        task.spawn(function()
            while self._running do
                -- Spawn one entity
                self:_spawn()

                -- Wait for interval
                local interval = self:getAttribute("Interval") or 2
                task.wait(interval)
            end
        end)
    end,

    --[[
        Stop the spawn loop.
    --]]
    _stopLoop = function(self)
        if not self._running then
            return
        end

        self._running = false
        self.Out:Fire("loopStopped", { dropperId = self.id })
    end,

    --[[
        Despawn all entities spawned by this dropper.
    --]]
    _despawnAll = function(self)
        local toRemove = {}
        for assetId in pairs(self._spawnedAssetIds) do
            table.insert(toRemove, assetId)
        end

        for _, assetId in ipairs(toRemove) do
            SpawnerCore.despawn(assetId)
            self._spawnedAssetIds[assetId] = nil
        end
    end,
})

return Dropper
