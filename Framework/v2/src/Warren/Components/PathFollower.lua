--[[
    Warren Framework v2
    PathFollower.lua - Entity Navigation Component (PathedController)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    PathFollower (aka PathedController) navigates an entity through a sequence
    of waypoints. It supports both Humanoid-based movement (MoveTo) and
    non-Humanoid movement (TweenService/CFrame interpolation).

    Uses PathFollowerCore internally for path infrastructure.

    PathFollower is signal-driven: it waits for two signals before starting:
    - onControl: Provides the entity (Model) to control
    - onWaypoints: Provides the target waypoints (Part[])

    Once both signals are received, navigation begins automatically.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onControl({ entity: Model, entityId?: string })
            - Assigns the entity this PathFollower will move
            - entityId is optional, defaults to entity.Name

        onWaypoints({ targets: Part[] })
            - Provides ordered list of waypoint targets
            - Navigation begins when both onControl and onWaypoints received

        onPause()
            - Pauses navigation at current position

        onResume()
            - Resumes navigation from paused state

        onSetSpeed({ speed: number, segment?: number, segments?: table })
            - Changes movement speed
            - speed alone: sets default speed for all segments
            - segment + speed: sets speed for specific segment
            - segments: array of { segment, speed } for multiple

        onAck()
            - Acknowledgment signal for sync mode (WaitForAck = true)

    OUT (emits):
        waypointReached({ waypoint: Part, index: number, entityId: string })
            - Fired when entity reaches each waypoint

        pathComplete({ entityId: string })
            - Fired when entity reaches final waypoint

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Speed: number (default 16)
        Default movement speed in studs per second

    WaitForAck: boolean (default false)
        If true, pauses at each waypoint until onAck received

    AckTimeout: number (default 5)
        Seconds to wait for ack before firing error and aborting

    CollisionMode: string (default "ignore")
        "ignore" - Stay anchored, ignore collisions
        "physics" - Unanchor on collision, let physics take over

    OnInterrupt: string (default "stop")
        "stop" - Cancel navigation on collision
        "pause_and_resume" - Pause, wait ResumeDelay, continue
        "restart" - Go back to first waypoint after ResumeDelay

    ResumeDelay: number (default 1)
        Seconds to wait before resuming after collision

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Register the component
    local PathFollower = Lib.Components.PathFollower
    System.Asset.register(PathFollower)

    -- Create instance (via IPC or Asset.spawn)
    local pf = System.IPC.createInstance("PathFollower", {
        id = "PathFollower_Camper1",
        attributes = { Speed = 12, WaitForAck = false },
    })

    -- Send control signal (from adapter/spawner)
    System.IPC.sendTo("PathFollower_Camper1", "control", {
        entity = camperModel,
        entityId = "Camper_1",
    })

    -- Send waypoints (from waypoint builder)
    System.IPC.sendTo("PathFollower_Camper1", "waypoints", {
        targets = { seat1, seat2, seat3 },
    })

    -- Set per-segment speeds
    System.IPC.sendTo("PathFollower_Camper1", "setSpeed", {
        segments = {
            { segment = 1, speed = 20 },
            { segment = 2, speed = 10 },
        }
    })
    ```

--]]

local TweenService = game:GetService("TweenService")
local Node = require(script.Parent.Parent.Node)
local PathFollowerCore = require(script.Parent.Parent.Internal.PathFollowerCore)

--------------------------------------------------------------------------------
-- PATHFOLLOWER NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local PathFollower = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                path = nil,
                entity = nil,
                entityId = nil,
                paused = false,
                stopped = false,
                navigating = false,
                interrupted = false,
                collisionConnection = nil,
                resumeEvent = nil,
                originalAnchored = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Get the primary part of the entity (handles both Parts and Models).
    --]]
    local function getPrimaryPart(self)
        local state = getState(self)
        if not state.entity then
            return nil
        end

        if state.entity:IsA("BasePart") then
            return state.entity
        elseif state.entity:IsA("Model") then
            return state.entity.PrimaryPart or state.entity:FindFirstChildWhichIsA("BasePart")
        end

        return nil
    end

    --[[
        Private: Detect whether entity uses Humanoid or needs Tween-based movement.
    --]]
    local function detectMovementType(self)
        local state = getState(self)
        if not state.entity then
            return "tween", nil
        end

        local humanoid = state.entity:FindFirstChildOfClass("Humanoid")
        if humanoid then
            return "humanoid", humanoid
        else
            return "tween", nil
        end
    end

    --[[
        Private: Move entity to a waypoint target.
    --]]
    local function moveToWaypoint(self, target, segmentIndex)
        local state = getState(self)
        local movementType, humanoid = detectMovementType(self)
        local speed = state.path:getSegmentSpeed(segmentIndex or 1)

        if movementType == "humanoid" then
            humanoid:MoveTo(target.Position)
            humanoid.MoveToFinished:Wait()
        else
            local primaryPart = getPrimaryPart(self)
            if not primaryPart then
                self.Err:Fire({ reason = "no_primary_part", message = "Entity has no PrimaryPart for tween movement" })
                return
            end

            if state.originalAnchored == nil then
                state.originalAnchored = primaryPart.Anchored
            end
            primaryPart.Anchored = true

            local distance = (target.Position - primaryPart.Position).Magnitude
            local duration = distance / speed
            duration = math.max(duration, 0.1)

            local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
            local goal = { CFrame = CFrame.new(target.Position) }
            local tween = TweenService:Create(primaryPart, tweenInfo, goal)

            tween:Play()
            tween.Completed:Wait()
        end
    end

    -- Forward declarations for mutual recursion
    local startNavigation

    --[[
        Private: Handle a collision event based on configured behavior.
    --]]
    local function handleCollision(self, otherPart)
        local state = getState(self)

        if not state.navigating or state.interrupted then
            return
        end

        for i = 1, state.path:getWaypointCount() do
            local wp = state.path:getWaypoint(i)
            if otherPart == wp then
                return
            end
        end

        if otherPart:IsDescendantOf(state.entity) then
            return
        end

        local collisionMode = self:getAttribute("CollisionMode")
        local onInterrupt = self:getAttribute("OnInterrupt")

        self.Err:Fire({
            reason = "collision",
            entityId = state.entityId,
            collidedWith = otherPart,
            collidedWithName = otherPart.Name,
            waypointIndex = state.path:getCurrentIndex(),
            collisionMode = collisionMode,
            onInterrupt = onInterrupt,
        })

        if collisionMode == "physics" then
            local primaryPart = getPrimaryPart(self)
            if primaryPart then
                primaryPart.Anchored = false
            end
        end

        if onInterrupt == "stop" then
            state.stopped = true
            state.interrupted = true

        elseif onInterrupt == "pause_and_resume" then
            state.interrupted = true
            state.paused = true

            local resumeDelay = self:getAttribute("ResumeDelay") or 1
            task.spawn(function()
                task.wait(resumeDelay)

                if state.interrupted and not state.stopped then
                    state.interrupted = false
                    state.paused = false

                    if collisionMode == "physics" then
                        local primaryPart = getPrimaryPart(self)
                        if primaryPart then
                            primaryPart.Anchored = true
                        end
                    end

                    if state.resumeEvent then
                        state.resumeEvent:Fire()
                    end

                    self.Err:Fire({
                        reason = "collision_resumed",
                        entityId = state.entityId,
                        waypointIndex = state.path:getCurrentIndex(),
                    })
                end
            end)

        elseif onInterrupt == "restart" then
            state.interrupted = true

            if collisionMode == "physics" then
                local primaryPart = getPrimaryPart(self)
                if primaryPart then
                    primaryPart.Anchored = true
                end
            end

            task.spawn(function()
                local resumeDelay = self:getAttribute("ResumeDelay") or 1
                task.wait(resumeDelay)

                if not state.stopped then
                    state.interrupted = false
                    state.navigating = false
                    state.path:reset()

                    self.Err:Fire({
                        reason = "collision_restart",
                        entityId = state.entityId,
                    })

                    startNavigation(self)
                end
            end)
        end
    end

    --[[
        Private: Setup collision detection on the entity's primary part.
    --]]
    local function setupCollisionDetection(self)
        local state = getState(self)
        local collisionMode = self:getAttribute("CollisionMode")
        if collisionMode == "ignore" then
            return
        end

        local primaryPart = getPrimaryPart(self)
        if not primaryPart then
            return
        end

        if state.collisionConnection then
            state.collisionConnection:Disconnect()
        end

        state.collisionConnection = primaryPart.Touched:Connect(function(otherPart)
            handleCollision(self, otherPart)
        end)
    end

    --[[
        Private: Main navigation loop. Runs in a separate thread.
    --]]
    startNavigation = function(self)
        local state = getState(self)
        state.navigating = true
        state.path:reset()

        task.spawn(function()
            local waypointCount = state.path:getWaypointCount()

            for index = 1, waypointCount do
                if state.stopped then
                    break
                end

                while state.paused and not state.stopped do
                    if state.resumeEvent then
                        state.resumeEvent.Event:Wait()
                    else
                        task.wait(0.1)
                    end
                end

                if state.stopped then
                    break
                end

                state.path:setCurrentIndex(index)
                local target = state.path:getWaypoint(index)
                local segmentIndex = math.max(1, index - 1)
                moveToWaypoint(self, target, segmentIndex)

                if state.stopped then
                    break
                end

                self.Out:Fire("waypointReached", {
                    waypoint = target,
                    index = index,
                    entityId = state.entityId,
                })

                if self:getAttribute("WaitForAck") then
                    local ack = self:waitForSignal("onAck", self:getAttribute("AckTimeout") or 5)
                    if not ack then
                        self.Err:Fire({
                            reason = "ack_timeout",
                            waypoint = index,
                            entityId = state.entityId,
                        })
                        state.navigating = false
                        return
                    end
                end
            end

            if state.originalAnchored ~= nil and state.entity then
                local primaryPart = getPrimaryPart(self)
                if primaryPart then
                    primaryPart.Anchored = state.originalAnchored
                end
                state.originalAnchored = nil
            end

            state.navigating = false

            if not state.stopped then
                self.Out:Fire("pathComplete", {
                    entityId = state.entityId,
                })
            end
        end)
    end

    --[[
        Private: Try to start navigation if both entity and waypoints are ready.
    --]]
    local function tryStart(self)
        local state = getState(self)
        if state.entity and state.path:getWaypointCount() > 0 and not state.navigating then
            startNavigation(self)
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "PathFollower",
        domain = "shared",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                local defaultSpeed = self:getAttribute("Speed") or 16
                state.path = PathFollowerCore.new({ defaultSpeed = defaultSpeed })
                state.resumeEvent = Instance.new("BindableEvent")

                if not self:getAttribute("Speed") then
                    self:setAttribute("Speed", 16)
                end
                if self:getAttribute("WaitForAck") == nil then
                    self:setAttribute("WaitForAck", false)
                end
                if not self:getAttribute("AckTimeout") then
                    self:setAttribute("AckTimeout", 5)
                end
                if not self:getAttribute("CollisionMode") then
                    self:setAttribute("CollisionMode", "ignore")
                end
                if not self:getAttribute("OnInterrupt") then
                    self:setAttribute("OnInterrupt", "stop")
                end
                if not self:getAttribute("ResumeDelay") then
                    self:setAttribute("ResumeDelay", 1)
                end
            end,

            onStart = function(self)
                -- Nothing to do on start - we wait for signals
            end,

            onStop = function(self)
                local state = getState(self)
                state.stopped = true
                state.paused = false

                if state.collisionConnection then
                    state.collisionConnection:Disconnect()
                    state.collisionConnection = nil
                end

                if state.resumeEvent then
                    state.resumeEvent:Fire()
                    state.resumeEvent:Destroy()
                    state.resumeEvent = nil
                end

                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            onControl = function(self, data)
                if not data or not data.entity then
                    self.Err:Fire({ reason = "invalid_control", message = "Missing entity in onControl" })
                    return
                end

                local state = getState(self)
                state.entity = data.entity
                state.entityId = data.entityId or data.entity.Name

                setupCollisionDetection(self)
                tryStart(self)
            end,

            onWaypoints = function(self, data)
                if not data or not data.targets or #data.targets == 0 then
                    self.Err:Fire({ reason = "invalid_waypoints", message = "Missing or empty targets in onWaypoints" })
                    return
                end

                local state = getState(self)
                local success, err = state.path:setWaypoints(data.targets)
                if not success then
                    self.Err:Fire({ reason = "invalid_waypoints", message = err })
                    return
                end

                tryStart(self)
            end,

            onPause = function(self)
                local state = getState(self)
                if state.navigating and not state.paused then
                    state.paused = true
                end
            end,

            onResume = function(self)
                local state = getState(self)
                if state.navigating and state.paused then
                    state.paused = false
                    if state.resumeEvent then
                        state.resumeEvent:Fire()
                    end
                end
            end,

            onSetSpeed = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.segments and type(data.segments) == "table" then
                    state.path:setSegmentSpeeds(data.segments)
                elseif data.segment and data.speed then
                    state.path:setSegmentSpeed(data.segment, data.speed)
                elseif data.speed and type(data.speed) == "number" then
                    self:setAttribute("Speed", data.speed)
                    state.path:setDefaultSpeed(data.speed)
                end
            end,

            onAck = function(self, data)
                -- Handler exists for documentation.
                -- When WaitForAck is true, waitForSignal("onAck") captures this.
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            waypointReached = {},  -- { waypoint: Part, index: number, entityId: string }
            pathComplete = {},     -- { entityId: string }
        },

        -- Err (detour) signals documented in header
    }
end)

return PathFollower
