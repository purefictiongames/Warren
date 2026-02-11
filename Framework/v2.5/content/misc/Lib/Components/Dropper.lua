--[[
    LibPureFiction Framework v2
    Dropper.lua - Versatile Spawner Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Dropper spawns entities via interval loop or on-demand signals.
    Supports two spawning modes:
    - Template mode: Uses SpawnerCore to spawn physical templates
    - Component mode: Spawns Node component instances (e.g., Tracer projectiles)

    Key features:
    - Interval-based spawning (timer loop)
    - On-demand spawning (onDispense signal)
    - Template/component pool with sequential/random selection
    - Optional capacity (total spawn limit) with refill
    - Optional maxActive (concurrent spawn limit)
    - Tracks all spawned entities

    Dropper is designed to work with other components via wiring:
    - PathFollower: Guide spawned entities along paths
    - Zone: Detect when entities reach destination, signal back to Dropper
    - Launcher: Use Dropper as ammo magazine, dispenses projectile components

    Use cases:
    - Tycoon dropper (interval loop, single template)
    - Tool dispenser (on-demand, pool of items, finite capacity)
    - NPC spawner (interval or on-demand, maxActive limit)
    - Ammo magazine (component mode, finite capacity, dispenses Tracer/etc)

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
        spawned({ ... })
            - Template mode: { assetId, instance, entityId, templateName, dropperId }
            - Component mode: { component, instance, entityId, componentName, dropperId }
            - Wire to PathFollower.onControl or Launcher for projectile handling

        despawned({ assetId?, entityId, dropperId })
            - Fired when an entity is despawned

        depleted({ dropperId })
            - Fired when capacity is exhausted

        refilled({ current, max, dropperId })
            - Fired when capacity is restored (magazine reloaded)

        ammoChanged({ current, max, dropperId })
            - Fired when capacity changes (for HUD/UI updates)

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

    Visible: boolean (default true)
        Whether the dropper visual part is visible

    Size: Vector3 (default 1, 1.5, 1)
        Size of default dropper part (if no model provided)

    WeldTo: BasePart (default nil)
        If provided, welds the default dropper part to this part

    WeldOffset: CFrame (default CFrame.new(-2, 0, 0))
        Offset from WeldTo part (only used if WeldTo is set)

    Position: Vector3 (default 0, 5, 0)
        Absolute position for default part (only used if WeldTo is nil)

    ============================================================================
    CONFIGURATION
    ============================================================================

    onConfigure accepts:
        interval: number - Seconds between spawns
        templateName: string - Single template name (template mode)
        componentName: string - Single component name (component mode, e.g., "Tracer")
        pool: table - Array of template/component names for multi-item mode
        poolMode: string - "single", "sequential", "random"
        maxActive: number - Concurrent limit (0 = unlimited)
        capacity: number - Total limit (nil = unlimited)
        reloadTime: number - Time to refill (for magazine use case)
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
                spawnedAssetIds = {},      -- { [assetId] = true } for SpawnerCore spawns
                spawnedComponents = {},    -- { [entityId] = component } for Component spawns
                spawnCounter = 0,
                pool = nil,                -- Array of template/component names
                poolIndex = 0,             -- Current index for sequential mode
                capacity = nil,            -- Total spawn limit (nil = unlimited)
                remaining = nil,           -- Remaining spawns (nil = unlimited)
                spawnPosition = nil,       -- Override spawn position
                componentMode = false,     -- If true, spawn Components instead of templates
                -- Visual
                part = nil,
                partIsDefault = false,
                weld = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            -- Destroy weld if we created it
            if state.weld then
                state.weld:Destroy()
            end
            -- Destroy default part if we created it
            if state.partIsDefault and state.part then
                state.part:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    --[[
        Private: Update part color based on ammo level.
        Green (full) → Yellow (mid) → Red (empty)
    --]]
    local function updatePartColor(self)
        local state = getState(self)
        if not state.part then return end

        -- If no capacity (unlimited), stay green
        if state.capacity == nil or state.capacity <= 0 then
            state.part.Color = Color3.new(0, 1, 0)  -- Green
            return
        end

        local percent = (state.remaining or 0) / state.capacity

        -- Color gradient: Red (0%) → Yellow (50%) → Green (100%)
        local color
        if percent > 0.5 then
            -- Green to Yellow (100% to 50%)
            local t = (percent - 0.5) * 2  -- 0 to 1
            color = Color3.new(1 - t, 1, 0)  -- Yellow to Green
        else
            -- Yellow to Red (50% to 0%)
            local t = percent * 2  -- 0 to 1
            color = Color3.new(1, t, 0)  -- Red to Yellow
        end

        state.part.Color = color
    end

    --[[
        Private: Update part visibility based on attribute.
    --]]
    local function updateVisibility(self)
        local state = getState(self)
        local visible = self:getAttribute("Visible")
        if visible == nil then visible = true end

        if state.part then
            state.part.Transparency = visible and 0 or 1
        end
    end

    --[[
        Private: Create a default dropper/magazine part.
        If weldTo is provided, welds the part to that reference with an offset.
    --]]
    local function createDefaultPart(self, weldTo)
        local state = getState(self)

        local size = self:getAttribute("Size") or Vector3.new(1, 1.5, 1)
        local visible = self:getAttribute("Visible")
        if visible == nil then visible = true end

        local part = Instance.new("Part")
        part.Name = self.id .. "_Magazine"
        part.Size = size
        part.CanCollide = false
        part.Color = Color3.new(0, 1, 0)  -- Start green (full)
        part.Material = Enum.Material.Neon
        part.Transparency = visible and 0 or 1

        -- Position and weld to reference part if provided
        if weldTo and weldTo:IsA("BasePart") then
            -- Get offset from config or use default (to the left side)
            local offset = self:getAttribute("WeldOffset") or CFrame.new(-2, 0, 0)

            part.CFrame = weldTo.CFrame * offset
            part.Anchored = false
            part.Parent = weldTo.Parent or workspace

            -- Create weld
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = weldTo
            weld.Part1 = part
            weld.Parent = part
            state.weld = weld
        else
            -- No reference, use absolute position
            local position = self:getAttribute("Position") or Vector3.new(0, 5, 0)
            part.Position = position
            part.Anchored = true
            part.Parent = workspace
        end

        state.part = part
        state.partIsDefault = true

        return part
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

        -- Count SpawnerCore spawns
        for assetId in pairs(state.spawnedAssetIds) do
            -- Verify still exists
            if SpawnerCore.getInstance(assetId) then
                count = count + 1
            else
                -- Clean up stale reference
                state.spawnedAssetIds[assetId] = nil
            end
        end

        -- Count component spawns
        for entityId, comp in pairs(state.spawnedComponents) do
            -- Components are tracked until explicitly returned/despawned
            count = count + 1
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
        Private: Spawn a single entity (template or component).
        nameOverride: optional template/component name to use instead of pool selection
        passthrough: optional data to include in spawned signal (for IPC correlation)
    --]]
    local function spawn(self, nameOverride, passthrough)
        local state = getState(self)

        -- Select template/component name (from pool, single, or override)
        local name = selectTemplate(self, nameOverride)
        if not name or name == "" then
            self.Err:Fire({
                reason = "no_template",
                message = "TemplateName/ComponentName not configured",
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

        local result

        if state.componentMode then
            -- Component-based spawning
            local Components = require(script.Parent)
            local ComponentClass = Components[name]

            if not ComponentClass then
                self.Err:Fire({
                    reason = "component_not_found",
                    message = "Component not found: " .. name,
                    dropperId = self.id,
                    componentName = name,
                })
                return nil
            end

            -- Create and initialize component
            local comp = ComponentClass:new({
                id = entityId,
            })
            comp.Sys.onInit(comp)
            comp.Sys.onStart(comp)

            -- Track this component
            state.spawnedComponents[entityId] = comp

            result = {
                component = comp,
                instance = comp.model,  -- May be nil if component has no model
                entityId = entityId,
            }

            -- Fire spawned signal with component reference
            self.Out:Fire("spawned", {
                component = comp,
                instance = comp.model,
                entityId = entityId,
                componentName = name,
                dropperId = self.id,
                _passthrough = passthrough,
            })
        else
            -- Template-based spawning via SpawnerCore
            local spawnResult, err = SpawnerCore.spawn({
                templateName = name,
                parent = workspace,
                position = getSpawnPosition(self),
                attributes = {
                    NodeId = entityId,
                    NodeClass = name,
                    NodeSpawnSource = self.id,
                },
            })

            if not spawnResult then
                self.Err:Fire({
                    reason = "spawn_failed",
                    message = err or "Unknown spawn error",
                    dropperId = self.id,
                    templateName = name,
                })
                return nil
            end

            -- Track this spawn
            state.spawnedAssetIds[spawnResult.assetId] = true

            result = spawnResult

            -- Fire spawned signal
            self.Out:Fire("spawned", {
                assetId = spawnResult.assetId,
                instance = spawnResult.instance,
                entityId = entityId,
                templateName = name,
                dropperId = self.id,
                _passthrough = passthrough,
            })
        end

        -- Decrement capacity if finite
        if state.remaining ~= nil then
            state.remaining = state.remaining - 1
            self:setAttribute("Remaining", state.remaining)

            -- Fire ammoChanged for HUD/UI updates
            self.Out:Fire("ammoChanged", {
                current = state.remaining,
                max = state.capacity,
                dropperId = self.id,
            })

            -- Update visual color
            updatePartColor(self)

            -- Fire depleted if capacity exhausted
            if state.remaining <= 0 then
                self.Out:Fire("depleted", { dropperId = self.id })
            end
        end

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

        -- Despawn SpawnerCore entities
        local toRemove = {}
        for assetId in pairs(state.spawnedAssetIds) do
            table.insert(toRemove, assetId)
        end
        for _, assetId in ipairs(toRemove) do
            SpawnerCore.despawn(assetId)
            state.spawnedAssetIds[assetId] = nil
        end

        -- Stop and cleanup component entities
        local compsToRemove = {}
        for entityId, comp in pairs(state.spawnedComponents) do
            table.insert(compsToRemove, { entityId = entityId, comp = comp })
        end
        for _, item in ipairs(compsToRemove) do
            item.comp.Sys.onStop(item.comp)
            state.spawnedComponents[item.entityId] = nil
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
                if self:getAttribute("Visible") == nil then
                    self:setAttribute("Visible", true)
                end

                -- Set up visual part
                if self.model then
                    -- Use provided model
                    if self.model:IsA("BasePart") then
                        state.part = self.model
                    elseif self.model:IsA("Model") and self.model.PrimaryPart then
                        state.part = self.model.PrimaryPart
                    end
                    state.partIsDefault = false
                else
                    -- Create default part, optionally welded to a reference part
                    local weldTo = self:getAttribute("WeldTo")
                    createDefaultPart(self, weldTo)
                end

                -- Apply initial visibility and color
                updateVisibility(self)
                updatePartColor(self)

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
                Magazine handshake: respond to discovery from Launcher.
                This tells the Launcher that an external magazine is wired.
            --]]
            onDiscoverMagazine = function(self, data)
                local state = getState(self)
                -- Respond immediately (sync) to confirm we're here
                self.Out:Fire("magazinePresent", {
                    magazineId = self.id,
                    capacity = state.capacity,
                    current = state.remaining,
                })
            end,

            --[[
                Reload request from Launcher.
            --]]
            onRequestReload = function(self, data)
                local state = getState(self)
                local reloadTime = self:getAttribute("ReloadTime") or 1.5

                -- Fire reload started
                self.Out:Fire("reloadStarted", {
                    time = reloadTime,
                    dropperId = self.id,
                })

                -- Delay refill by reload time
                task.delay(reloadTime, function()
                    state.remaining = state.capacity
                    self:setAttribute("Remaining", state.remaining)

                    self.Out:Fire("ammoChanged", {
                        current = state.remaining,
                        max = state.capacity,
                        dropperId = self.id,
                    })

                    -- Update visual color
                    updatePartColor(self)

                    self.Out:Fire("refilled", {
                        current = state.remaining,
                        max = state.capacity,
                        dropperId = self.id,
                    })
                end)
            end,

            --[[
                Configure dropper settings.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.interval then
                    self:setAttribute("Interval", data.interval)
                end

                -- Template mode (SpawnerCore)
                if data.templateName then
                    self:setAttribute("TemplateName", data.templateName)
                    state.componentMode = false
                end

                -- Component mode (Node components like Tracer)
                if data.componentName then
                    self:setAttribute("TemplateName", data.componentName)  -- Reuse attribute
                    self:setAttribute("ComponentName", data.componentName)
                    state.componentMode = true
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

                -- Pool configuration (works for both templates and components)
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
                    self:setAttribute("Remaining", data.capacity)

                    -- Fire initial ammoChanged so HUD gets current state
                    self.Out:Fire("ammoChanged", {
                        current = state.remaining,
                        max = state.capacity,
                        dropperId = self.id,
                    })

                    -- Update visual color
                    updatePartColor(self)
                end

                -- Reload time (for magazine use case)
                if data.reloadTime then
                    self:setAttribute("ReloadTime", data.reloadTime)
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
                Despawn a specific entity by assetId or entityId.
                Typically called when entity reaches end zone or projectile expires.
            --]]
            onReturn = function(self, data)
                if not data then return end

                local state = getState(self)

                -- Handle component return (by entityId)
                if data.entityId and state.spawnedComponents[data.entityId] then
                    local comp = state.spawnedComponents[data.entityId]
                    comp.Sys.onStop(comp)
                    state.spawnedComponents[data.entityId] = nil

                    self.Out:Fire("despawned", {
                        entityId = data.entityId,
                        dropperId = self.id,
                    })
                    return
                end

                -- Handle SpawnerCore return (by assetId)
                if not data.assetId then
                    return
                end

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

                data._passthrough: any data to include in spawned signal (for IPC correlation)
            --]]
            onDispense = function(self, data)
                data = data or {}
                local count = data.count or 1
                local templateOverride = data.templateName or data.componentName
                local passthrough = data._passthrough

                for _ = 1, count do
                    -- Check if we can spawn (capacity + maxActive)
                    if not canSpawn(self) then
                        break
                    end

                    -- Spawn with optional template override and passthrough data
                    spawn(self, templateOverride, passthrough)
                end
            end,

            --[[
                Restore capacity (reload magazine).
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

                -- Update visual color
                updatePartColor(self)

                -- Fire refilled signal
                self.Out:Fire("refilled", {
                    current = state.remaining,
                    max = state.capacity,
                    dropperId = self.id,
                })
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            -- Template mode: { assetId, instance, entityId, templateName, dropperId }
            -- Component mode: { component, instance, entityId, componentName, dropperId }
            spawned = {},
            despawned = {},       -- { assetId?, entityId, dropperId }
            depleted = {},        -- { dropperId }
            refilled = {},        -- { current, max, dropperId }
            ammoChanged = {},     -- { current, max, dropperId }
            reloadStarted = {},   -- { time, dropperId }
            loopStarted = {},
            loopStopped = {},

            -- Magazine handshake (for Launcher integration)
            magazinePresent = {}, -- { magazineId, capacity, current }
        },

        -- Err (detour) signals documented in header
    }
end)

return Dropper
