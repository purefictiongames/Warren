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

--------------------------------------------------------------------------------
-- PATHEDCONVEYOR NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local PathedConveyor = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                path = nil,             -- PathFollowerCore instance
                enabled = false,
                updateConnection = nil,
                trackedEntities = {},   -- { [entity] = { segment, enterTime } }
                filter = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    -- Forward declarations for mutual recursion
    local disable
    local onEntityExit

    --[[
        Private: Check if a part is one of our waypoints.
    --]]
    local function isWaypoint(self, part)
        local state = getState(self)
        for i = 1, state.path:getWaypointCount() do
            if state.path:getWaypoint(i) == part then
                return true
            end
        end
        return false
    end

    --[[
        Private: Handle entity entering conveyor.
    --]]
    local function onEntityEnter(self, entity, segment)
        local entityId = EntityUtils.getId(entity)

        self.Out:Fire("entityEntered", {
            entity = entity,
            entityId = entityId,
            segment = segment,
        })
    end

    --[[
        Private: Handle entity exiting conveyor.
    --]]
    onEntityExit = function(self, entity)
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
    end

    --[[
        Private: Handle entity transitioning from one segment to another.
        This fires when an entity passes a waypoint.
    --]]
    local function onSegmentChanged(self, entity, fromSegment, toSegment)
        local state = getState(self)
        local entityId = EntityUtils.getId(entity)

        -- The waypoint at the transition is the start of the new segment
        -- (or end of the old segment, depending on direction)
        local waypointIndex = toSegment
        local waypoint = state.path:getWaypoint(waypointIndex)

        self.Out:Fire("segmentChanged", {
            entity = entity,
            entityId = entityId,
            fromSegment = fromSegment,
            toSegment = toSegment,
            waypoint = waypoint,
            waypointIndex = waypointIndex,
        })
    end

    --[[
        Private: Apply conveyor movement to a player character.
        Players need special handling because Humanoid movement overrides velocity.
    --]]
    local function applyPlayerForce(self, entity, rootPart, targetVelocity)
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
    end

    --[[
        Private: Apply conveyor force to an entity.
    --]]
    local function applyConveyorForce(self, entity, segment)
        local state = getState(self)
        local speed = state.path:getSegmentSpeed(segment)
        local direction = state.path:getTraversalDirection(segment)

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
            applyPlayerForce(self, entity, primaryPart, targetVelocity)
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
    end

    --[[
        Private: Find all entities near the conveyor path.
    --]]
    local function findNearbyEntities(self, radius)
        local state = getState(self)
        local results = {}
        local seenEntities = {}

        -- Calculate bounding box for entire conveyor path
        local minPos = Vector3.new(math.huge, math.huge, math.huge)
        local maxPos = Vector3.new(-math.huge, -math.huge, -math.huge)

        for i = 1, state.path:getWaypointCount() do
            local pos = state.path:getWaypointPosition(i)
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

            if entity and not seenEntities[entity] and not isWaypoint(self, part) then
                seenEntities[entity] = true

                -- Find which segment this entity is closest to
                local entityPos = EntityUtils.getPosition(entity)
                local closestSegment, closestPoint, distance = state.path:findClosestSegment(entityPos)

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
    end

    --[[
        Private: Main conveyor update - find entities and apply forces.
    --]]
    local function updateConveyor(self)
        local state = getState(self)
        if not state.enabled then return end

        local detectionRadius = self:getAttribute("DetectionRadius") or 2
        local affectsPlayers = self:getAttribute("AffectsPlayers")

        -- Find all entities near the path
        local nearbyEntities = findNearbyEntities(self, detectionRadius)

        -- Track new entities, update existing, remove gone
        local currentEntities = {}

        for _, entityData in ipairs(nearbyEntities) do
            local entity = entityData.entity
            currentEntities[entity] = true

            -- Check filter
            if not EntityUtils.passesFilter(entity, state.filter) then
                continue
            end

            -- Check if player and whether to affect
            if EntityUtils.isPlayer(entity) and not affectsPlayers then
                continue
            end

            -- Track or update
            if not state.trackedEntities[entity] then
                -- New entity
                state.trackedEntities[entity] = {
                    segment = entityData.segment,
                    enterTime = os.clock(),
                }
                onEntityEnter(self, entity, entityData.segment)
            else
                -- Check for segment change (waypoint transition)
                local prevSegment = state.trackedEntities[entity].segment
                local newSegment = entityData.segment

                if prevSegment ~= newSegment then
                    -- Entity has transitioned to a new segment
                    onSegmentChanged(self, entity, prevSegment, newSegment)
                    state.trackedEntities[entity].segment = newSegment
                end
            end

            -- Apply conveyor force
            applyConveyorForce(self, entity, entityData.segment)
        end

        -- Remove entities that left
        for entity, _ in pairs(state.trackedEntities) do
            if not currentEntities[entity] then
                onEntityExit(self, entity)
                state.trackedEntities[entity] = nil
            end
        end
    end

    --[[
        Private: Start the physics update loop.
    --]]
    local function startUpdateLoop(self)
        local state = getState(self)
        local lastUpdate = 0
        local updateRate = self:getAttribute("UpdateRate") or 0.1

        state.updateConnection = RunService.Heartbeat:Connect(function(dt)
            lastUpdate = lastUpdate + dt
            if lastUpdate >= updateRate then
                lastUpdate = 0
                updateConveyor(self)
            end
        end)
    end

    --[[
        Private: Disable the conveyor and stop the update loop.
    --]]
    disable = function(self)
        local state = getState(self)
        if not state.enabled then return end

        state.enabled = false

        -- Stop update loop
        if state.updateConnection then
            state.updateConnection:Disconnect()
            state.updateConnection = nil
        end

        -- Clear tracked entities
        for entity, _ in pairs(state.trackedEntities) do
            onEntityExit(self, entity)
        end
        state.trackedEntities = {}
    end

    --[[
        Private: Enable the conveyor and start the update loop.
    --]]
    local function enable(self)
        local state = getState(self)
        if state.enabled then return end
        if state.path:getWaypointCount() < 2 then
            self.Err:Fire({ reason = "no_path", message = "Conveyor requires at least 2 waypoints" })
            return
        end

        state.enabled = true
        startUpdateLoop(self)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "PathedConveyor",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Path infrastructure (shared with PathFollower)
                local defaultSpeed = self:getAttribute("Speed") or 16
                state.path = PathFollowerCore.new({ defaultSpeed = defaultSpeed })

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
                disable(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Configure the conveyor path and settings.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)

                -- Set waypoints
                if data.waypoints then
                    local success, err = state.path:setWaypoints(data.waypoints)
                    if not success then
                        self.Err:Fire({ reason = "invalid_waypoints", message = err })
                        return
                    end
                end

                -- Set default speed
                if data.speed then
                    self:setAttribute("Speed", data.speed)
                    state.path:setDefaultSpeed(data.speed)
                end

                -- Set filter
                if data.filter then
                    state.filter = data.filter
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
            --]]
            onSetSpeed = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.segments and type(data.segments) == "table" then
                    -- Set multiple segment speeds
                    state.path:setSegmentSpeeds(data.segments)
                elseif data.segment and data.speed then
                    -- Set single segment speed
                    state.path:setSegmentSpeed(data.segment, data.speed)
                elseif data.speed and type(data.speed) == "number" then
                    -- Set default speed for all
                    self:setAttribute("Speed", data.speed)
                    state.path:setDefaultSpeed(data.speed)
                end
            end,

            --[[
                Toggle conveyor direction.
            --]]
            onReverse = function(self)
                local state = getState(self)
                state.path:reverse()
                self.Out:Fire("directionChanged", {
                    forward = state.path:isForward(),
                })
            end,

            --[[
                Explicitly set conveyor direction.
            --]]
            onSetDirection = function(self, data)
                local state = getState(self)
                if data and data.forward ~= nil then
                    state.path:setDirection(data.forward)
                    self.Out:Fire("directionChanged", {
                        forward = state.path:isForward(),
                    })
                end
            end,

            --[[
                Enable the conveyor.
            --]]
            onEnable = function(self)
                enable(self)
            end,

            --[[
                Disable the conveyor.
            --]]
            onDisable = function(self)
                disable(self)
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            entityEntered = {},    -- { entity, entityId, segment }
            entityExited = {},     -- { entity, entityId }
            segmentChanged = {},   -- { entity, entityId, fromSegment, toSegment, waypoint, waypointIndex }
            directionChanged = {}, -- { forward }
        },

        -- Err (detour) signals documented in header
    }
end)

return PathedConveyor
