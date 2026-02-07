--[[
    Warren Framework v2
    Zone.lua - Trigger Zone Sensor Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Zone is a sensor component that detects when entities enter or exit an area.
    It fires signals but takes no action itself - downstream nodes handle actions.

    Detection modes:
    - "collision": Uses Touched/TouchEnded events on the zone's model
    - "proximity": Polls for entities within a radius (Heartbeat-based)

    Filtering:
    - By NodeClass: Only detect specific node classes (e.g., "Camper")
    - By Tag: Only detect entities with specific CollectionService tags
    - By Attribute: Only detect entities with specific attribute values

    Zone is a pure sensor - it reports what it sees. Actions like despawning,
    scoring, or redirecting are handled by other nodes via wiring.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ radius?, filter?, pollInterval? })
            - Configure zone settings
            - radius: Detection radius for proximity mode (default 10)
            - filter: { class?, tag?, attribute? } filtering options
            - pollInterval: Seconds between proximity checks (default 0.1)

        onEnable()
            - Start detection

        onDisable()
            - Stop detection

    OUT (emits):
        entityEntered({ entity: Instance, entityId: string, nodeClass: string,
                        assetId: string?, position: Vector3 })
            - Fired when an entity enters the zone

        entityExited({ entity: Instance, entityId: string })
            - Fired when an entity exits the zone (collision mode only)

    ============================================================================
    ATTRIBUTES
    ============================================================================

    DetectionMode: string (default "collision")
        "collision" - Use Touched/TouchEnded events
        "proximity" - Poll for entities within Radius

    Radius: number (default 10)
        Detection radius for proximity mode

    PollInterval: number (default 0.1)
        Seconds between proximity checks

    FilterClass: string (default "")
        Only detect entities of this NodeClass (empty = all)

    FilterTag: string (default "")
        Only detect entities with this CollectionService tag (empty = all)

    Enabled: boolean (default true)
        Whether detection is active

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Create a despawn zone at end of path
    local zone = Zone:new({ model = workspace.DespawnZone })
    zone.Sys.onInit(zone)

    -- Wire to despawn handler
    zone.Out.entityEntered:Connect(function(data)
        SpawnerCore.despawn(data.assetId)
    end)

    -- Or in wiring manifest:
    { from = "DespawnZone.entityEntered", to = "GameManager.onEntityReachedEnd" }
    ```

--]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Node = require(script.Parent.Parent.Node)
local Registry = Node.Registry

--------------------------------------------------------------------------------
-- ZONE NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Zone = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                enabled = false,
                entitiesInZone = {},           -- { [entity] = true }
                touchedConnection = nil,
                touchEndedConnection = nil,
                proximityConnection = nil,
                filter = nil,
                filterClass = nil,
                filterTag = nil,
                filterAttribute = nil,
                filterAttributeValue = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Get the zone's detection part.
    --]]
    local function getZonePart(self)
        if not self.model then
            return nil
        end

        if self.model:IsA("BasePart") then
            return self.model
        end

        -- Look for a part named "Zone" or "Trigger" or use PrimaryPart
        local zonePart = self.model:FindFirstChild("Zone")
            or self.model:FindFirstChild("Trigger")
            or self.model:FindFirstChild("Detection")
            or self.model.PrimaryPart
            or self.model:FindFirstChildWhichIsA("BasePart")

        return zonePart
    end

    --[[
        Private: Get the zone's center position.
    --]]
    local function getZoneCenter(self)
        local zonePart = getZonePart(self)
        if zonePart then
            return zonePart.Position
        end
        return Vector3.new(0, 0, 0)
    end

    --[[
        Private: Check if an entity passes the configured filters.
    --]]
    local function passesFilter(self, entity)
        if not entity then return false end

        local state = getState(self)

        -- Use Registry.matches() if a standard filter is configured
        if state.filter then
            return Registry.matches(entity, state.filter)
        end

        -- Legacy filter support (backward compatibility)
        -- Filter by NodeClass attribute
        local filterClass = state.filterClass or self:getAttribute("FilterClass")
        if filterClass and filterClass ~= "" then
            local entityClass = entity:GetAttribute("NodeClass")
            if entityClass ~= filterClass then
                return false
            end
        end

        -- Filter by CollectionService tag
        local filterTag = state.filterTag or self:getAttribute("FilterTag")
        if filterTag and filterTag ~= "" then
            if not CollectionService:HasTag(entity, filterTag) then
                return false
            end
        end

        -- Filter by custom attribute
        if state.filterAttribute then
            local attrValue = entity:GetAttribute(state.filterAttribute)
            if attrValue ~= state.filterAttributeValue then
                return false
            end
        end

        return true
    end

    --[[
        Private: Build entity data payload for signals.
    --]]
    local function buildEntityData(self, entity)
        local position
        if entity:IsA("Model") then
            if entity.PrimaryPart then
                position = entity.PrimaryPart.Position
            else
                local part = entity:FindFirstChildWhichIsA("BasePart")
                if part then
                    position = part.Position
                end
            end
        elseif entity:IsA("BasePart") then
            position = entity.Position
        end

        return {
            entity = entity,
            entityId = entity:GetAttribute("NodeId") or entity.Name,
            nodeClass = entity:GetAttribute("NodeClass") or "Unknown",
            assetId = entity:GetAttribute("AssetId"),
            position = position,
            zoneId = self.id,
        }
    end

    --[[
        Private: Handle an entity entering the zone.

        Child nodes can override onEntityEnter(self, data) to customize behavior.
        If not overridden, fires entityEntered signal.
    --]]
    local function handleEnter(self, entity)
        local state = getState(self)

        -- Skip if already in zone
        if state.entitiesInZone[entity] then
            return
        end

        -- Apply filters
        if not passesFilter(self, entity) then
            return
        end

        -- Track entity
        state.entitiesInZone[entity] = true

        -- Build data payload
        local data = buildEntityData(self, entity)

        -- Call hook if defined by child node, otherwise fire signal
        if self.onEntityEnter then
            self:onEntityEnter(data)
        else
            self.Out:Fire("entityEntered", data)
        end
    end

    --[[
        Private: Handle an entity exiting the zone.

        Child nodes can override onEntityExit(self, data) to customize behavior.
        If not overridden, fires entityExited signal.
    --]]
    local function handleExit(self, entity)
        local state = getState(self)

        -- Skip if not in zone
        if not state.entitiesInZone[entity] then
            return
        end

        -- Untrack entity
        state.entitiesInZone[entity] = nil

        -- Build data payload
        local data = {
            entity = entity,
            entityId = entity:GetAttribute("NodeId") or entity.Name,
            zoneId = self.id,
        }

        -- Call hook if defined by child node, otherwise fire signal
        if self.onEntityExit then
            self:onEntityExit(data)
        else
            self.Out:Fire("entityExited", data)
        end
    end

    --[[
        Private: Enable collision-based detection.
    --]]
    local function enableCollisionMode(self)
        local state = getState(self)
        local zonePart = getZonePart(self)

        if not zonePart then
            self.Err:Fire({
                reason = "no_zone_part",
                message = "Zone has no model or detection part",
                zoneId = self.id,
            })
            return
        end

        -- Connect Touched event
        state.touchedConnection = zonePart.Touched:Connect(function(otherPart)
            if not state.enabled then return end

            -- Find the root model/entity
            local entity = otherPart:FindFirstAncestorOfClass("Model") or otherPart
            handleEnter(self, entity)
        end)

        -- Connect TouchEnded event
        state.touchEndedConnection = zonePart.TouchEnded:Connect(function(otherPart)
            if not state.enabled then return end

            local entity = otherPart:FindFirstAncestorOfClass("Model") or otherPart
            handleExit(self, entity)
        end)
    end

    --[[
        Private: Enable proximity-based detection.
    --]]
    local function enableProximityMode(self)
        local state = getState(self)
        local radius = self:getAttribute("Radius") or 10
        local pollInterval = self:getAttribute("PollInterval") or 0.1
        local lastPoll = 0

        state.proximityConnection = RunService.Heartbeat:Connect(function()
            if not state.enabled then return end

            -- Throttle polling
            local now = os.clock()
            if now - lastPoll < pollInterval then
                return
            end
            lastPoll = now

            local center = getZoneCenter(self)
            local radiusSq = radius * radius

            -- Check all potentially relevant entities
            -- We check workspace descendants that have NodeId attribute
            local currentInZone = {}

            for _, descendant in ipairs(workspace:GetDescendants()) do
                if descendant:IsA("Model") and descendant:GetAttribute("NodeId") then
                    local position
                    if descendant.PrimaryPart then
                        position = descendant.PrimaryPart.Position
                    else
                        local part = descendant:FindFirstChildWhichIsA("BasePart")
                        if part then
                            position = part.Position
                        end
                    end

                    if position then
                        local distSq = (position - center).Magnitude ^ 2
                        if distSq <= radiusSq then
                            currentInZone[descendant] = true

                            -- Handle enter if new
                            if not state.entitiesInZone[descendant] then
                                handleEnter(self, descendant)
                            end
                        end
                    end
                end
            end

            -- Handle exits for entities no longer in zone
            for entity in pairs(state.entitiesInZone) do
                if not currentInZone[entity] then
                    handleExit(self, entity)
                end
            end
        end)
    end

    --[[
        Private: Enable detection based on mode.
    --]]
    local function enable(self)
        local state = getState(self)

        if state.enabled then
            return
        end

        state.enabled = true
        local mode = self:getAttribute("DetectionMode")

        if mode == "collision" then
            enableCollisionMode(self)
        elseif mode == "proximity" then
            enableProximityMode(self)
        end
    end

    --[[
        Private: Disable detection.
    --]]
    local function disable(self)
        local state = getState(self)

        if not state.enabled then
            return
        end

        state.enabled = false

        -- Disconnect collision events
        if state.touchedConnection then
            state.touchedConnection:Disconnect()
            state.touchedConnection = nil
        end
        if state.touchEndedConnection then
            state.touchEndedConnection:Disconnect()
            state.touchEndedConnection = nil
        end

        -- Disconnect proximity polling
        if state.proximityConnection then
            state.proximityConnection:Disconnect()
            state.proximityConnection = nil
        end

        -- Clear tracked entities
        state.entitiesInZone = {}
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "Zone",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Default attributes
                if not self:getAttribute("DetectionMode") then
                    self:setAttribute("DetectionMode", "collision")
                end
                if not self:getAttribute("Radius") then
                    self:setAttribute("Radius", 10)
                end
                if not self:getAttribute("PollInterval") then
                    self:setAttribute("PollInterval", 0.1)
                end
                if not self:getAttribute("FilterClass") then
                    self:setAttribute("FilterClass", "")
                end
                if not self:getAttribute("FilterTag") then
                    self:setAttribute("FilterTag", "")
                end
                if self:getAttribute("Enabled") == nil then
                    self:setAttribute("Enabled", true)
                end

                -- Auto-enable if Enabled attribute is true
                if self:getAttribute("Enabled") then
                    enable(self)
                end
            end,

            onStart = function(self)
                -- Nothing additional on start
            end,

            onStop = function(self)
                disable(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Configure zone settings.

                data.filter uses the Standard Filter Schema (see Node.Registry.matches):
                    class: string | string[]  - Match NodeClass
                    spawnSource: string       - Match NodeSpawnSource
                    status: string            - Match NodeStatus
                    tag: string               - Match CollectionService tag
                    assetId: string           - Match specific AssetId
                    nodeId: string            - Match specific NodeId
                    attribute: { name, value, operator? }
                    custom: function(entity, meta?) -> boolean
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.radius then
                    self:setAttribute("Radius", data.radius)
                end

                if data.pollInterval then
                    self:setAttribute("PollInterval", data.pollInterval)
                end

                if data.detectionMode then
                    local wasEnabled = state.enabled
                    if wasEnabled then
                        disable(self)
                    end
                    self:setAttribute("DetectionMode", data.detectionMode)
                    if wasEnabled then
                        enable(self)
                    end
                end

                if data.filter then
                    -- Store the full filter for Registry.matches()
                    state.filter = data.filter

                    -- Also store individual fields for backward compatibility
                    state.filterClass = data.filter.class
                    state.filterTag = data.filter.tag
                    if data.filter.attribute then
                        state.filterAttribute = data.filter.attribute.name
                        state.filterAttributeValue = data.filter.attribute.value
                    end

                    -- Store in attributes for inspection
                    if type(data.filter.class) == "string" then
                        self:setAttribute("FilterClass", data.filter.class)
                    end
                    if data.filter.tag then
                        self:setAttribute("FilterTag", data.filter.tag)
                    end
                end
            end,

            --[[
                Enable detection.
            --]]
            onEnable = function(self)
                self:setAttribute("Enabled", true)
                enable(self)
            end,

            --[[
                Disable detection.
            --]]
            onDisable = function(self)
                self:setAttribute("Enabled", false)
                disable(self)
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            entityEntered = {},  -- { entity, entityId, nodeClass, assetId, position }
            entityExited = {},   -- { entity, entityId }
        },
    }
end)

return Zone
