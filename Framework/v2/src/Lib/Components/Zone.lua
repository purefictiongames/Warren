--[[
    LibPureFiction Framework v2
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

local Zone = Node.extend({
    name = "Zone",
    domain = "server",

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Internal state
            self._enabled = false
            self._entitiesInZone = {}  -- { [entity] = true }
            self._touchedConnection = nil
            self._touchEndedConnection = nil
            self._proximityConnection = nil

            -- Standard filter (uses Registry.matches)
            self._filter = nil

            -- Legacy filter settings (for backward compatibility)
            self._filterClass = nil
            self._filterTag = nil
            self._filterAttribute = nil
            self._filterAttributeValue = nil

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
                self:_enable()
            end
        end,

        onStart = function(self)
            -- Nothing additional on start
        end,

        onStop = function(self)
            self:_disable()
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

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

            if data.radius then
                self:setAttribute("Radius", data.radius)
            end

            if data.pollInterval then
                self:setAttribute("PollInterval", data.pollInterval)
            end

            if data.detectionMode then
                local wasEnabled = self._enabled
                if wasEnabled then
                    self:_disable()
                end
                self:setAttribute("DetectionMode", data.detectionMode)
                if wasEnabled then
                    self:_enable()
                end
            end

            if data.filter then
                -- Store the full filter for Registry.matches()
                self._filter = data.filter

                -- Also store individual fields for backward compatibility
                self._filterClass = data.filter.class
                self._filterTag = data.filter.tag
                if data.filter.attribute then
                    self._filterAttribute = data.filter.attribute.name
                    self._filterAttributeValue = data.filter.attribute.value
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
            self:_enable()
        end,

        --[[
            Disable detection.
        --]]
        onDisable = function(self)
            self:setAttribute("Enabled", false)
            self:_disable()
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA (documentation)
    ----------------------------------------------------------------------------

    Out = {
        entityEntered = {},  -- { entity, entityId, nodeClass, assetId, position }
        entityExited = {},   -- { entity, entityId }
    },

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    --[[
        Check if an entity passes the configured filters.

        Uses Registry.matches() for standardized filter checking.
        Falls back to legacy filter fields for backward compatibility.
    --]]
    _passesFilter = function(self, entity)
        if not entity then return false end

        -- Use Registry.matches() if a standard filter is configured
        if self._filter then
            return Registry.matches(entity, self._filter)
        end

        -- Legacy filter support (backward compatibility)
        -- Filter by NodeClass attribute
        local filterClass = self._filterClass or self:getAttribute("FilterClass")
        if filterClass and filterClass ~= "" then
            local entityClass = entity:GetAttribute("NodeClass")
            if entityClass ~= filterClass then
                return false
            end
        end

        -- Filter by CollectionService tag
        local filterTag = self._filterTag or self:getAttribute("FilterTag")
        if filterTag and filterTag ~= "" then
            if not CollectionService:HasTag(entity, filterTag) then
                return false
            end
        end

        -- Filter by custom attribute
        if self._filterAttribute then
            local attrValue = entity:GetAttribute(self._filterAttribute)
            if attrValue ~= self._filterAttributeValue then
                return false
            end
        end

        return true
    end,

    --[[
        Build entity data payload for signals.
    --]]
    _buildEntityData = function(self, entity)
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
    end,

    --[[
        Handle an entity entering the zone.
    --]]
    _handleEnter = function(self, entity)
        -- Skip if already in zone
        if self._entitiesInZone[entity] then
            return
        end

        -- Apply filters
        if not self:_passesFilter(entity) then
            return
        end

        -- Track entity
        self._entitiesInZone[entity] = true

        -- Fire signal
        local data = self:_buildEntityData(entity)
        self.Out:Fire("entityEntered", data)
    end,

    --[[
        Handle an entity exiting the zone.
    --]]
    _handleExit = function(self, entity)
        -- Skip if not in zone
        if not self._entitiesInZone[entity] then
            return
        end

        -- Untrack entity
        self._entitiesInZone[entity] = nil

        -- Fire signal
        self.Out:Fire("entityExited", {
            entity = entity,
            entityId = entity:GetAttribute("NodeId") or entity.Name,
            zoneId = self.id,
        })
    end,

    --[[
        Get the zone's detection part.
    --]]
    _getZonePart = function(self)
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
    end,

    --[[
        Get the zone's center position.
    --]]
    _getZoneCenter = function(self)
        local zonePart = self:_getZonePart()
        if zonePart then
            return zonePart.Position
        end
        return Vector3.new(0, 0, 0)
    end,

    --[[
        Enable detection based on mode.
    --]]
    _enable = function(self)
        if self._enabled then
            return
        end

        self._enabled = true
        local mode = self:getAttribute("DetectionMode")

        if mode == "collision" then
            self:_enableCollisionMode()
        elseif mode == "proximity" then
            self:_enableProximityMode()
        end
    end,

    --[[
        Disable detection.
    --]]
    _disable = function(self)
        if not self._enabled then
            return
        end

        self._enabled = false

        -- Disconnect collision events
        if self._touchedConnection then
            self._touchedConnection:Disconnect()
            self._touchedConnection = nil
        end
        if self._touchEndedConnection then
            self._touchEndedConnection:Disconnect()
            self._touchEndedConnection = nil
        end

        -- Disconnect proximity polling
        if self._proximityConnection then
            self._proximityConnection:Disconnect()
            self._proximityConnection = nil
        end

        -- Clear tracked entities
        self._entitiesInZone = {}
    end,

    --[[
        Enable collision-based detection.
    --]]
    _enableCollisionMode = function(self)
        local zonePart = self:_getZonePart()
        if not zonePart then
            self.Err:Fire({
                reason = "no_zone_part",
                message = "Zone has no model or detection part",
                zoneId = self.id,
            })
            return
        end

        -- Connect Touched event
        self._touchedConnection = zonePart.Touched:Connect(function(otherPart)
            if not self._enabled then return end

            -- Find the root model/entity
            local entity = otherPart:FindFirstAncestorOfClass("Model") or otherPart
            self:_handleEnter(entity)
        end)

        -- Connect TouchEnded event
        self._touchEndedConnection = zonePart.TouchEnded:Connect(function(otherPart)
            if not self._enabled then return end

            local entity = otherPart:FindFirstAncestorOfClass("Model") or otherPart
            self:_handleExit(entity)
        end)
    end,

    --[[
        Enable proximity-based detection.
    --]]
    _enableProximityMode = function(self)
        local radius = self:getAttribute("Radius") or 10
        local pollInterval = self:getAttribute("PollInterval") or 0.1
        local lastPoll = 0

        self._proximityConnection = RunService.Heartbeat:Connect(function()
            if not self._enabled then return end

            -- Throttle polling
            local now = os.clock()
            if now - lastPoll < pollInterval then
                return
            end
            lastPoll = now

            local center = self:_getZoneCenter()
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
                            if not self._entitiesInZone[descendant] then
                                self:_handleEnter(descendant)
                            end
                        end
                    end
                end
            end

            -- Handle exits for entities no longer in zone
            for entity in pairs(self._entitiesInZone) do
                if not currentInZone[entity] then
                    self:_handleExit(entity)
                end
            end
        end)
    end,
})

return Zone
