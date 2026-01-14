--[[
    LibPureFiction Framework v2
    PathedConveyor.lua - Physics-Based Conveyor Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    PathedConveyor moves objects along a defined path using physics forces.
    Unlike PathFollower which actively controls a single entity, PathedConveyor
    passively affects all unanchored objects that touch it.

    Uses PathFollowerCore internally for path infrastructure.

    Key features:
    - Physics-based movement (applies forces/velocity)
    - Affects multiple objects simultaneously
    - Objects can resist or go with the flow
    - Per-segment speed configuration
    - Forward/reverse toggle
    - Filter support for selective effect

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ waypoints, speed?, filter?, affectsPlayers? })
            - Configure the conveyor path and settings

        onSetSpeed({ speed: number, segment?: number, segments?: table })
            - Changes conveyor speed
            - speed alone: sets speed for all segments
            - segment + speed: sets speed for specific segment
            - segments: array of { segment, speed } for multiple

        onReverse()
            - Toggle conveyor direction (forward/backward)

        onSetDirection({ forward: boolean })
            - Explicitly set direction

        onEnable()
            - Enable the conveyor (start applying forces)

        onDisable()
            - Disable the conveyor (stop applying forces)

    OUT (emits):
        entityEntered({ entity, entityId, segment })
            - Fired when an entity enters the conveyor zone

        entityExited({ entity, entityId })
            - Fired when an entity exits the conveyor zone

        segmentChanged({ entity, entityId, fromSegment, toSegment, waypoint, waypointIndex })
            - Fired when an entity transitions from one segment to another
            - waypoint: The waypoint Part/Vector3 at the transition point
            - waypointIndex: The index of the waypoint (toSegment index)

        directionChanged({ forward: boolean })
            - Fired when direction is toggled

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Speed: number (default 16)
        Default conveyor speed in studs per second

    ForceMode: string (default "velocity")
        How to apply movement:
        - "velocity": Set AssemblyLinearVelocity directly
        - "force": Apply continuous force via VectorForce
        - "surface": Use surface velocity (BasePart.AssemblyLinearVelocity)

    AffectsPlayers: boolean (default true)
        Whether the conveyor affects player characters

    DetectionRadius: number (default 2)
        Distance from path centerline to detect objects

    UpdateRate: number (default 0.1)
        Seconds between physics updates (lower = smoother, higher = cheaper)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local conveyor = PathedConveyor:new({ model = workspace.ConveyorPath })
    conveyor.Sys.onInit(conveyor)

    -- Configure with waypoints
    conveyor.In.onConfigure(conveyor, {
        waypoints = { part1, part2, part3, part4 },
        speed = 20,
        affectsPlayers = true,
    })

    -- Set per-segment speeds
    conveyor.In.onSetSpeed(conveyor, {
        segments = {
            { segment = 1, speed = 10 },  -- Slow start
            { segment = 2, speed = 30 },  -- Fast middle
            { segment = 3, speed = 10 },  -- Slow end
        }
    })

    -- Enable
    conveyor.In.onEnable(conveyor)

    -- Reverse direction
    conveyor.In.onReverse(conveyor)
    ```

--]]

local RunService = game:GetService("RunService")
local Node = require(script.Parent.Parent.Node)
local PathFollowerCore = require(script.Parent.Parent.Internal.PathFollowerCore)
local EntityUtils = require(script.Parent.Parent.Internal.EntityUtils)

local PathedConveyor = Node.extend({
    name = "PathedConveyor",
    domain = "server",

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Path infrastructure (shared with PathFollower)
            local defaultSpeed = self:getAttribute("Speed") or 16
            self._path = PathFollowerCore.new({ defaultSpeed = defaultSpeed })

            -- Conveyor state
            self._enabled = false
            self._updateConnection = nil

            -- Tracked entities currently on conveyor
            -- { [entity] = { segment, enterTime, lastUpdate } }
            self._trackedEntities = {}

            -- Filter configuration
            self._filter = nil

            -- Default attributes
            if not self:getAttribute("Speed") then
                self:setAttribute("Speed", 16)
            end
            if not self:getAttribute("ForceMode") then
                self:setAttribute("ForceMode", "velocity")
            end
            if self:getAttribute("AffectsPlayers") == nil then
                self:setAttribute("AffectsPlayers", true)
            end
            if not self:getAttribute("DetectionRadius") then
                self:setAttribute("DetectionRadius", 2)
            end
            if not self:getAttribute("UpdateRate") then
                self:setAttribute("UpdateRate", 0.1)
            end
        end,

        onStart = function(self)
            -- Nothing to do on start - we wait for enable signal
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
            Configure the conveyor path and settings.
        --]]
        onConfigure = function(self, data)
            if not data then return end

            -- Set waypoints
            if data.waypoints then
                local success, err = self._path:setWaypoints(data.waypoints)
                if not success then
                    self.Err:Fire({ reason = "invalid_waypoints", message = err })
                    return
                end
            end

            -- Set default speed
            if data.speed then
                self:setAttribute("Speed", data.speed)
                self._path:setDefaultSpeed(data.speed)
            end

            -- Set filter
            if data.filter then
                self._filter = data.filter
            end

            -- Set other attributes
            if data.affectsPlayers ~= nil then
                self:setAttribute("AffectsPlayers", data.affectsPlayers)
            end

            if data.forceMode then
                self:setAttribute("ForceMode", data.forceMode)
            end

            if data.detectionRadius then
                self:setAttribute("DetectionRadius", data.detectionRadius)
            end

            if data.updateRate then
                self:setAttribute("UpdateRate", data.updateRate)
            end
        end,

        --[[
            Change conveyor speed.
            - speed alone: sets default speed for all segments
            - segment + speed: sets speed for specific segment
            - segments: array of { segment, speed } for multiple
        --]]
        onSetSpeed = function(self, data)
            if not data then return end

            if data.segments and type(data.segments) == "table" then
                -- Set multiple segment speeds
                self._path:setSegmentSpeeds(data.segments)
            elseif data.segment and data.speed then
                -- Set single segment speed
                self._path:setSegmentSpeed(data.segment, data.speed)
            elseif data.speed and type(data.speed) == "number" then
                -- Set default speed for all
                self:setAttribute("Speed", data.speed)
                self._path:setDefaultSpeed(data.speed)
            end
        end,

        --[[
            Toggle conveyor direction.
        --]]
        onReverse = function(self)
            self._path:reverse()
            self.Out:Fire("directionChanged", {
                forward = self._path:isForward(),
            })
        end,

        --[[
            Explicitly set conveyor direction.
        --]]
        onSetDirection = function(self, data)
            if data and data.forward ~= nil then
                self._path:setDirection(data.forward)
                self.Out:Fire("directionChanged", {
                    forward = self._path:isForward(),
                })
            end
        end,

        --[[
            Enable the conveyor.
        --]]
        onEnable = function(self)
            self:_enable()
        end,

        --[[
            Disable the conveyor.
        --]]
        onDisable = function(self)
            self:_disable()
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA (documentation)
    ----------------------------------------------------------------------------

    Out = {
        entityEntered = {},    -- { entity, entityId, segment }
        entityExited = {},     -- { entity, entityId }
        segmentChanged = {},   -- { entity, entityId, fromSegment, toSegment, waypoint, waypointIndex }
        directionChanged = {}, -- { forward }
    },

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    --[[
        Enable the conveyor and start the update loop.
    --]]
    _enable = function(self)
        if self._enabled then return end
        if self._path:getWaypointCount() < 2 then
            self.Err:Fire({ reason = "no_path", message = "Conveyor requires at least 2 waypoints" })
            return
        end

        self._enabled = true
        self:_startUpdateLoop()
    end,

    --[[
        Disable the conveyor and stop the update loop.
    --]]
    _disable = function(self)
        if not self._enabled then return end

        self._enabled = false

        -- Stop update loop
        if self._updateConnection then
            self._updateConnection:Disconnect()
            self._updateConnection = nil
        end

        -- Clear tracked entities
        for entity, _ in pairs(self._trackedEntities) do
            self:_onEntityExit(entity)
        end
        self._trackedEntities = {}
    end,

    --[[
        Start the physics update loop.
    --]]
    _startUpdateLoop = function(self)
        local lastUpdate = 0
        local updateRate = self:getAttribute("UpdateRate") or 0.1

        self._updateConnection = RunService.Heartbeat:Connect(function(dt)
            lastUpdate = lastUpdate + dt
            if lastUpdate >= updateRate then
                lastUpdate = 0
                self:_updateConveyor()
            end
        end)
    end,

    --[[
        Main conveyor update - find entities and apply forces.
    --]]
    _updateConveyor = function(self)
        if not self._enabled then return end

        local detectionRadius = self:getAttribute("DetectionRadius") or 2
        local affectsPlayers = self:getAttribute("AffectsPlayers")

        -- Find all entities near the path
        local nearbyEntities = self:_findNearbyEntities(detectionRadius)

        -- Debug: show what we found (uncomment for debugging)
        -- if #nearbyEntities > 0 then
        --     print(string.format("[Conveyor] Found %d nearby entities", #nearbyEntities))
        --     for _, ed in ipairs(nearbyEntities) do
        --         local pos = EntityUtils.getPosition(ed.entity)
        --         print(string.format("  - %s: segment=%d, dist=%.2f, pos=%s",
        --             self:_getEntityId(ed.entity), ed.segment, ed.distance, tostring(pos)))
        --     end
        -- end

        -- Track new entities, update existing, remove gone
        local currentEntities = {}

        for _, entityData in ipairs(nearbyEntities) do
            local entity = entityData.entity
            currentEntities[entity] = true

            -- Check filter
            if not EntityUtils.passesFilter(entity, self._filter) then
                continue
            end

            -- Check if player and whether to affect
            if EntityUtils.isPlayer(entity) and not affectsPlayers then
                continue
            end

            -- Track or update
            if not self._trackedEntities[entity] then
                -- New entity
                self._trackedEntities[entity] = {
                    segment = entityData.segment,
                    enterTime = os.clock(),
                }
                self:_onEntityEnter(entity, entityData.segment)
            else
                -- Check for segment change (waypoint transition)
                local prevSegment = self._trackedEntities[entity].segment
                local newSegment = entityData.segment

                if prevSegment ~= newSegment then
                    -- Entity has transitioned to a new segment
                    self:_onSegmentChanged(entity, prevSegment, newSegment)
                    self._trackedEntities[entity].segment = newSegment
                end
            end

            -- Apply conveyor force
            self:_applyConveyorForce(entity, entityData.segment)
        end

        -- Remove entities that left
        for entity, _ in pairs(self._trackedEntities) do
            if not currentEntities[entity] then
                self:_onEntityExit(entity)
                self._trackedEntities[entity] = nil
            end
        end
    end,

    --[[
        Find all entities near the conveyor path.

        @return table - Array of { entity, segment, distance }
    --]]
    _findNearbyEntities = function(self, radius)
        local results = {}
        local seenEntities = {}

        -- Calculate bounding box for entire conveyor path
        local minPos = Vector3.new(math.huge, math.huge, math.huge)
        local maxPos = Vector3.new(-math.huge, -math.huge, -math.huge)

        for i = 1, self._path:getWaypointCount() do
            local pos = self._path:getWaypointPosition(i)
            if pos then
                minPos = Vector3.new(
                    math.min(minPos.X, pos.X),
                    math.min(minPos.Y, pos.Y),
                    math.min(minPos.Z, pos.Z)
                )
                maxPos = Vector3.new(
                    math.max(maxPos.X, pos.X),
                    math.max(maxPos.Y, pos.Y),
                    math.max(maxPos.Z, pos.Z)
                )
            end
        end

        -- Expand bounds by detection radius
        minPos = minPos - Vector3.new(radius, radius, radius)
        maxPos = maxPos + Vector3.new(radius, radius, radius)

        -- Query all parts in the bounding region
        local center = (minPos + maxPos) / 2
        local size = maxPos - minPos

        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = {}

        local parts = workspace:GetPartBoundsInBox(CFrame.new(center), size, overlapParams)

        -- Process each part
        for _, part in ipairs(parts) do
            local entity = EntityUtils.getEntityFromPart(part)

            if entity and not seenEntities[entity] and not self:_isWaypoint(part) then
                seenEntities[entity] = true

                -- Find which segment this entity is closest to
                local entityPos = EntityUtils.getPosition(entity)
                local closestSegment, closestPoint, distance = self._path:findClosestSegment(entityPos)

                if distance <= radius then
                    table.insert(results, {
                        entity = entity,
                        segment = closestSegment,
                        distance = distance,
                    })
                end
            end
        end

        return results
    end,

    --[[
        Apply conveyor force to an entity.

        @param entity Model|BasePart - The entity to move
        @param segment number - The segment the entity is on
    --]]
    _applyConveyorForce = function(self, entity, segment)
        local speed = self._path:getSegmentSpeed(segment)
        local direction = self._path:getTraversalDirection(segment)

        if not direction then
            warn("[PathedConveyor] No direction for segment", segment)
            return
        end

        local forceMode = self:getAttribute("ForceMode") or "velocity"
        local primaryPart = EntityUtils.getPrimaryPart(entity)

        if not primaryPart then
            warn("[PathedConveyor] No primary part for entity")
            return
        end

        -- Don't affect anchored parts
        if primaryPart.Anchored then
            return
        end

        local targetVelocity = direction * speed

        -- Check if this is a player character - needs special handling
        local isPlayerCharacter = EntityUtils.isPlayer(entity)

        if isPlayerCharacter then
            -- For players, use BodyVelocity for reliable movement
            self:_applyPlayerForce(entity, primaryPart, targetVelocity)
            return
        end

        -- For non-player entities, use BodyVelocity too (it's more reliable than
        -- setting AssemblyLinearVelocity directly, which gets counteracted by collision)
        if forceMode == "velocity" then
            local bodyVel = primaryPart:FindFirstChild("ConveyorBodyVelocity")

            if not bodyVel then
                bodyVel = Instance.new("BodyVelocity")
                bodyVel.Name = "ConveyorBodyVelocity"
                bodyVel.MaxForce = Vector3.new(10000, 0, 10000)  -- Horizontal only
                bodyVel.P = 1250  -- Responsiveness
                bodyVel.Parent = primaryPart
            end

            bodyVel.Velocity = Vector3.new(targetVelocity.X, 0, targetVelocity.Z)

        elseif forceMode == "force" then
            -- Apply force (more physics-realistic, objects can resist)
            local mass = primaryPart.AssemblyMass
            local force = direction * speed * mass * 2  -- Multiplier for responsiveness

            -- Use BodyForce or VectorForce
            local bodyForce = primaryPart:FindFirstChild("ConveyorForce")
            if not bodyForce then
                bodyForce = Instance.new("VectorForce")
                bodyForce.Name = "ConveyorForce"
                bodyForce.ApplyAtCenterOfMass = true
                bodyForce.RelativeTo = Enum.ActuatorRelativeTo.World

                local attachment = primaryPart:FindFirstChild("ConveyorAttachment")
                if not attachment then
                    attachment = Instance.new("Attachment")
                    attachment.Name = "ConveyorAttachment"
                    attachment.Parent = primaryPart
                end
                bodyForce.Attachment0 = attachment
                bodyForce.Parent = primaryPart
            end
            bodyForce.Force = force

        elseif forceMode == "surface" then
            -- Simulate surface velocity (like a real conveyor belt surface)
            -- This works by constantly nudging the object
            local nudge = targetVelocity * 0.1
            primaryPart.AssemblyLinearVelocity = primaryPart.AssemblyLinearVelocity + nudge
        end
    end,

    --[[
        Handle entity entering conveyor.
    --]]
    _onEntityEnter = function(self, entity, segment)
        local entityId = EntityUtils.getId(entity)

        self.Out:Fire("entityEntered", {
            entity = entity,
            entityId = entityId,
            segment = segment,
        })
    end,

    --[[
        Handle entity exiting conveyor.
    --]]
    _onEntityExit = function(self, entity)
        local entityId = EntityUtils.getId(entity)

        -- Clean up any physics constraints we created
        local primaryPart = EntityUtils.getPrimaryPart(entity)
        if primaryPart then
            -- Clean up VectorForce (used for "force" mode)
            local bodyForce = primaryPart:FindFirstChild("ConveyorForce")
            if bodyForce then
                bodyForce:Destroy()
            end

            -- Clean up VectorForce (used for players)
            local vectorForce = primaryPart:FindFirstChild("ConveyorVectorForce")
            if vectorForce then
                vectorForce:Destroy()
            end

            -- Clean up attachments
            local attachment = primaryPart:FindFirstChild("ConveyorAttachment")
            if attachment then
                attachment:Destroy()
            end

            -- Clean up BodyVelocity (for non-player entities in velocity mode)
            local bodyVel = primaryPart:FindFirstChild("ConveyorBodyVelocity")
            if bodyVel then
                bodyVel:Destroy()
            end
        end

        self.Out:Fire("entityExited", {
            entity = entity,
            entityId = entityId,
        })
    end,

    --[[
        Handle entity transitioning from one segment to another.
        This fires when an entity passes a waypoint.
    --]]
    _onSegmentChanged = function(self, entity, fromSegment, toSegment)
        local entityId = EntityUtils.getId(entity)

        -- The waypoint at the transition is the start of the new segment
        -- (or end of the old segment, depending on direction)
        local waypointIndex = toSegment
        local waypoint = self._path:getWaypoint(waypointIndex)

        self.Out:Fire("segmentChanged", {
            entity = entity,
            entityId = entityId,
            fromSegment = fromSegment,
            toSegment = toSegment,
            waypoint = waypoint,
            waypointIndex = waypointIndex,
        })
    end,

    --[[
        Check if a part is one of our waypoints.
    --]]
    _isWaypoint = function(self, part)
        for i = 1, self._path:getWaypointCount() do
            if self._path:getWaypoint(i) == part then
                return true
            end
        end
        return false
    end,

    --[[
        Apply conveyor movement to a player character.
        Players need special handling because Humanoid movement overrides velocity.

        @param entity Model - The player character
        @param rootPart BasePart - The HumanoidRootPart
        @param targetVelocity Vector3 - The desired velocity
    --]]
    _applyPlayerForce = function(self, entity, rootPart, targetVelocity)
        -- Use VectorForce for player movement - this ADDS to player movement rather than
        -- overriding it. This allows players to walk against the conveyor (slower) or
        -- with it (faster).
        local attachment = rootPart:FindFirstChild("ConveyorAttachment")
        if not attachment then
            attachment = Instance.new("Attachment")
            attachment.Name = "ConveyorAttachment"
            attachment.Parent = rootPart
        end

        local vectorForce = rootPart:FindFirstChild("ConveyorVectorForce")
        if not vectorForce then
            vectorForce = Instance.new("VectorForce")
            vectorForce.Name = "ConveyorVectorForce"
            vectorForce.ApplyAtCenterOfMass = true
            vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
            vectorForce.Attachment0 = attachment
            vectorForce.Parent = rootPart
        end

        -- Calculate force to achieve desired conveyor effect
        -- Force = mass * acceleration, but we want to push at a steady rate
        -- Use mass * targetSpeed * multiplier to get a force that feels like a conveyor
        local mass = rootPart.AssemblyMass
        local forceMultiplier = 8  -- Tuned for responsive feel without being too strong
        local force = Vector3.new(
            targetVelocity.X * mass * forceMultiplier,
            0,  -- No vertical force
            targetVelocity.Z * mass * forceMultiplier
        )

        vectorForce.Force = force
    end,

    --[[
        Clean up player conveyor constraints when they exit.
    --]]
    _cleanupPlayerForce = function(self, entity)
        local primaryPart = EntityUtils.getPrimaryPart(entity)
        if primaryPart then
            local vectorForce = primaryPart:FindFirstChild("ConveyorVectorForce")
            if vectorForce then
                vectorForce:Destroy()
            end
            local attachment = primaryPart:FindFirstChild("ConveyorAttachment")
            if attachment then
                attachment:Destroy()
            end
        end
    end,
})

return PathedConveyor
