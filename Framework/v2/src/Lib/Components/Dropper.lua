--[[
    LibPureFiction Framework v2
    Dropper.lua - Interval-Based Spawner Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Dropper spawns entities at regular intervals and manages their lifecycle.
    It uses SpawnerCore internally for spawn/despawn/tracking operations.

    Key features:
    - Interval-based spawning (configurable rate)
    - Tracks all spawned entities
    - Despawns entities via onReturn signal (e.g., from Zone detection)
    - Optional max active limit

    Dropper is designed to work with other components via wiring:
    - PathFollower: Guide spawned entities along paths
    - Zone: Detect when entities reach destination, signal back to Dropper

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onStart()
            - Begin the spawn loop

        onStop()
            - Stop the spawn loop (does not despawn existing entities)

        onReturn({ assetId: string })
            - Despawn a specific entity by assetId
            - Typically wired from Zone.entityEntered

        onConfigure({ interval?, templateName?, maxActive?, spawnPosition? })
            - Configure dropper settings

        onDespawnAll()
            - Despawn all entities spawned by this dropper

    OUT (emits):
        spawned({ assetId: string, instance: Instance, entityId: string })
            - Fired when an entity is spawned
            - Wire to PathFollower.onControl to assign entity for navigation

        despawned({ assetId: string, entityId: string })
            - Fired when an entity is despawned

        loopStarted()
            - Fired when spawn loop begins

        loopStopped()
            - Fired when spawn loop ends

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Interval: number (default 2)
        Seconds between spawns

    TemplateName: string (default "")
        Name of template to spawn from ReplicatedStorage.Templates

    MaxActive: number (default 0)
        Maximum concurrent spawned entities (0 = unlimited)

    AutoStart: boolean (default false)
        If true, begins spawning on init

    SpawnOffset: Vector3 (default 0,0,0)
        Offset from dropper position for spawn location

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
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA (documentation)
    ----------------------------------------------------------------------------

    Out = {
        spawned = {},    -- { assetId, instance, entityId, dropperId }
        despawned = {},  -- { assetId, entityId, dropperId }
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
        Check if we can spawn (respects MaxActive).
    --]]
    _canSpawn = function(self)
        local maxActive = self:getAttribute("MaxActive") or 0
        if maxActive <= 0 then
            return true  -- Unlimited
        end
        return self:_getActiveCount() < maxActive
    end,

    --[[
        Spawn a single entity.
    --]]
    _spawn = function(self)
        local templateName = self:getAttribute("TemplateName")
        if not templateName or templateName == "" then
            self.Err:Fire({
                reason = "no_template",
                message = "TemplateName not configured",
                dropperId = self.id,
            })
            return nil
        end

        -- Check max active limit
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

        -- Fire spawned signal
        self.Out:Fire("spawned", {
            assetId = result.assetId,
            instance = result.instance,
            entityId = entityId,
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
