--[[
    LibPureFiction Framework v2
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

local PathFollower = Node.extend({
    name = "PathFollower",
    domain = "shared",  -- "shared" allows testing from Command Bar; use "server" in production

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Path infrastructure (shared with PathedConveyor)
            local defaultSpeed = self:getAttribute("Speed") or 16
            self._path = PathFollowerCore.new({ defaultSpeed = defaultSpeed })

            -- Entity state
            self._entity = nil
            self._entityId = nil

            -- Navigation state
            self._paused = false
            self._stopped = false
            self._navigating = false
            self._interrupted = false
            self._collisionConnection = nil

            -- Pause/resume event
            self._resumeEvent = Instance.new("BindableEvent")

            -- Default attributes
            if not self:getAttribute("Speed") then
                self:setAttribute("Speed", 16)
            end
            if self:getAttribute("WaitForAck") == nil then
                self:setAttribute("WaitForAck", false)
            end
            if not self:getAttribute("AckTimeout") then
                self:setAttribute("AckTimeout", 5)
            end
            -- Collision handling defaults
            if not self:getAttribute("CollisionMode") then
                self:setAttribute("CollisionMode", "ignore")  -- "ignore", "physics"
            end
            if not self:getAttribute("OnInterrupt") then
                self:setAttribute("OnInterrupt", "stop")  -- "stop", "pause_and_resume", "restart"
            end
            if not self:getAttribute("ResumeDelay") then
                self:setAttribute("ResumeDelay", 1)
            end
        end,

        onStart = function(self)
            -- Nothing to do on start - we wait for signals
        end,

        onStop = function(self)
            self._stopped = true
            self._paused = false

            -- Clean up collision connection
            if self._collisionConnection then
                self._collisionConnection:Disconnect()
                self._collisionConnection = nil
            end

            -- Clean up resume event
            if self._resumeEvent then
                self._resumeEvent:Fire()  -- Unblock any waiting
                self._resumeEvent:Destroy()
                self._resumeEvent = nil
            end
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

    In = {
        --[[
            Receive entity to control.
        --]]
        onControl = function(self, data)
            if not data or not data.entity then
                self.Err:Fire({ reason = "invalid_control", message = "Missing entity in onControl" })
                return
            end

            self._entity = data.entity
            self._entityId = data.entityId or data.entity.Name

            -- Setup collision detection if not in "ignore" mode
            self:_setupCollisionDetection()

            self:_tryStart()
        end,

        --[[
            Receive waypoint targets.
        --]]
        onWaypoints = function(self, data)
            if not data or not data.targets or #data.targets == 0 then
                self.Err:Fire({ reason = "invalid_waypoints", message = "Missing or empty targets in onWaypoints" })
                return
            end

            -- Store in PathFollowerCore
            local success, err = self._path:setWaypoints(data.targets)
            if not success then
                self.Err:Fire({ reason = "invalid_waypoints", message = err })
                return
            end

            self:_tryStart()
        end,

        --[[
            Pause navigation.
        --]]
        onPause = function(self)
            if self._navigating and not self._paused then
                self._paused = true
            end
        end,

        --[[
            Resume navigation.
        --]]
        onResume = function(self)
            if self._navigating and self._paused then
                self._paused = false
                if self._resumeEvent then
                    self._resumeEvent:Fire()
                end
            end
        end,

        --[[
            Change movement speed.
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
            Acknowledgment for sync mode.
            This is handled by waitForSignal() when WaitForAck is true.
        --]]
        onAck = function(self, data)
            -- This handler exists for documentation.
            -- When WaitForAck is true, waitForSignal("onAck") installs
            -- a temporary handler that captures this signal.
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA (documentation)
    ----------------------------------------------------------------------------

    Out = {
        waypointReached = {},  -- { waypoint: Part, index: number, entityId: string }
        pathComplete = {},     -- { entityId: string }
    },

    -- Err (detour) signals:
    -- { reason = "collision", entityId, collidedWith, collidedWithName, waypointIndex, collisionMode, onInterrupt }
    -- { reason = "collision_resumed", entityId, waypointIndex }
    -- { reason = "collision_restart", entityId }
    -- { reason = "ack_timeout", waypoint, entityId }
    -- { reason = "invalid_control", message }
    -- { reason = "invalid_waypoints", message }
    -- { reason = "no_primary_part", message }

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    --[[
        Try to start navigation if both entity and waypoints are ready.
    --]]
    _tryStart = function(self)
        if self._entity and self._path:getWaypointCount() > 0 and not self._navigating then
            self:_startNavigation()
        end
    end,

    --[[
        Setup collision detection on the entity's primary part.
        Only active when CollisionMode ~= "ignore".
    --]]
    _setupCollisionDetection = function(self)
        local collisionMode = self:getAttribute("CollisionMode")
        if collisionMode == "ignore" then
            return  -- No collision handling needed
        end

        local primaryPart = self._entity.PrimaryPart or self._entity:FindFirstChildWhichIsA("BasePart")
        if not primaryPart then
            return
        end

        -- Disconnect existing connection if any
        if self._collisionConnection then
            self._collisionConnection:Disconnect()
        end

        -- Listen for collisions
        self._collisionConnection = primaryPart.Touched:Connect(function(otherPart)
            self:_handleCollision(otherPart)
        end)
    end,

    --[[
        Handle a collision event based on configured behavior.

        @param otherPart BasePart - The part we collided with
    --]]
    _handleCollision = function(self, otherPart)
        -- Ignore if not navigating or already interrupted
        if not self._navigating or self._interrupted then
            return
        end

        -- Ignore collisions with waypoints themselves
        for i = 1, self._path:getWaypointCount() do
            local wp = self._path:getWaypoint(i)
            if otherPart == wp then
                return
            end
        end

        -- Ignore collisions with self (other parts of the entity)
        if otherPart:IsDescendantOf(self._entity) then
            return
        end

        local collisionMode = self:getAttribute("CollisionMode")
        local onInterrupt = self:getAttribute("OnInterrupt")

        -- Fire detour signal with collision info
        self.Err:Fire({
            reason = "collision",
            entityId = self._entityId,
            collidedWith = otherPart,
            collidedWithName = otherPart.Name,
            waypointIndex = self._path:getCurrentIndex(),
            collisionMode = collisionMode,
            onInterrupt = onInterrupt,
        })

        -- Handle based on CollisionMode
        if collisionMode == "physics" then
            -- Unanchor to let physics take over
            local primaryPart = self._entity.PrimaryPart or self._entity:FindFirstChildWhichIsA("BasePart")
            if primaryPart then
                primaryPart.Anchored = false
            end
        end

        -- Handle based on OnInterrupt
        if onInterrupt == "stop" then
            self._stopped = true
            self._interrupted = true

        elseif onInterrupt == "pause_and_resume" then
            self._interrupted = true
            self._paused = true

            -- Schedule resume after delay
            local resumeDelay = self:getAttribute("ResumeDelay") or 1
            task.spawn(function()
                task.wait(resumeDelay)

                -- Only resume if still in interrupted state
                if self._interrupted and not self._stopped then
                    self._interrupted = false
                    self._paused = false

                    -- Re-anchor if we unanchored
                    if collisionMode == "physics" then
                        local primaryPart = self._entity.PrimaryPart or self._entity:FindFirstChildWhichIsA("BasePart")
                        if primaryPart then
                            primaryPart.Anchored = true
                        end
                    end

                    -- Fire resume event
                    if self._resumeEvent then
                        self._resumeEvent:Fire()
                    end

                    -- Fire detour signal indicating resume
                    self.Err:Fire({
                        reason = "collision_resumed",
                        entityId = self._entityId,
                        waypointIndex = self._path:getCurrentIndex(),
                    })
                end
            end)

        elseif onInterrupt == "restart" then
            self._interrupted = true

            -- Re-anchor if we unanchored
            if collisionMode == "physics" then
                local primaryPart = self._entity.PrimaryPart or self._entity:FindFirstChildWhichIsA("BasePart")
                if primaryPart then
                    primaryPart.Anchored = true
                end
            end

            -- Restart navigation from beginning
            task.spawn(function()
                local resumeDelay = self:getAttribute("ResumeDelay") or 1
                task.wait(resumeDelay)

                if not self._stopped then
                    self._interrupted = false
                    self._navigating = false
                    self._path:reset()

                    -- Fire detour signal indicating restart
                    self.Err:Fire({
                        reason = "collision_restart",
                        entityId = self._entityId,
                    })

                    -- Restart
                    self:_startNavigation()
                end
            end)
        end
    end,

    --[[
        Detect whether entity uses Humanoid or needs Tween-based movement.

        @return string, Humanoid|nil - Movement type and humanoid if found
    --]]
    _detectMovementType = function(self)
        if not self._entity then
            return "tween", nil
        end

        local humanoid = self._entity:FindFirstChildOfClass("Humanoid")
        if humanoid then
            return "humanoid", humanoid
        else
            return "tween", nil
        end
    end,

    --[[
        Move entity to a waypoint target.

        @param target Part - The waypoint to move to
        @param segmentIndex number - The segment being traversed (for speed lookup)
    --]]
    _moveToWaypoint = function(self, target, segmentIndex)
        local movementType, humanoid = self:_detectMovementType()
        -- Get segment-specific speed, or fall back to default
        local speed = self._path:getSegmentSpeed(segmentIndex or 1)

        if movementType == "humanoid" then
            -- Use Humanoid:MoveTo()
            humanoid:MoveTo(target.Position)
            humanoid.MoveToFinished:Wait()
        else
            -- Use TweenService for non-Humanoid entities
            local primaryPart = self._entity.PrimaryPart or self._entity:FindFirstChildWhichIsA("BasePart")
            if not primaryPart then
                self.Err:Fire({ reason = "no_primary_part", message = "Entity has no PrimaryPart for tween movement" })
                return
            end

            -- Anchor during tween to prevent gravity interference
            -- Store original state on first move (restored at path end)
            if self._originalAnchored == nil then
                self._originalAnchored = primaryPart.Anchored
            end
            primaryPart.Anchored = true

            -- Calculate duration based on distance and speed
            local distance = (target.Position - primaryPart.Position).Magnitude
            local duration = distance / speed

            -- Ensure minimum duration to avoid instant jumps
            duration = math.max(duration, 0.1)

            -- Create and play tween
            local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
            local goal = { CFrame = CFrame.new(target.Position) }
            local tween = TweenService:Create(primaryPart, tweenInfo, goal)

            tween:Play()
            tween.Completed:Wait()

            -- Restore original anchored state (keep anchored for non-physics entities)
            -- For tween-based movement, we keep it anchored to prevent falling
            -- primaryPart.Anchored = wasAnchored
        end
    end,

    --[[
        Main navigation loop. Runs in a separate thread.
    --]]
    _startNavigation = function(self)
        self._navigating = true
        self._path:reset()

        task.spawn(function()
            local waypointCount = self._path:getWaypointCount()

            for index = 1, waypointCount do
                -- Check if stopped
                if self._stopped then
                    break
                end

                -- Handle pause
                while self._paused and not self._stopped do
                    if self._resumeEvent then
                        self._resumeEvent.Event:Wait()
                    else
                        task.wait(0.1)
                    end
                end

                if self._stopped then
                    break
                end

                -- Update current index in Core
                self._path:setCurrentIndex(index)

                -- Get target waypoint
                local target = self._path:getWaypoint(index)

                -- Move to waypoint (segment index is index-1 for segment before this waypoint,
                -- but for speed we want the segment we're traversing TO this waypoint)
                local segmentIndex = math.max(1, index - 1)
                self:_moveToWaypoint(target, segmentIndex)

                -- Check if stopped during movement
                if self._stopped then
                    break
                end

                -- Fire waypoint reached
                self.Out:Fire("waypointReached", {
                    waypoint = target,
                    index = index,
                    entityId = self._entityId,
                })

                -- Optional: wait for acknowledgment
                if self:getAttribute("WaitForAck") then
                    local ack = self:waitForSignal("onAck", self:getAttribute("AckTimeout") or 5)
                    if not ack then
                        self.Err:Fire({
                            reason = "ack_timeout",
                            waypoint = index,
                            entityId = self._entityId,
                        })
                        self._navigating = false
                        return
                    end
                end
            end

            -- Restore original anchor state for tween-based entities
            -- (Do this BEFORE firing pathComplete, as listeners may reset our state)
            if self._originalAnchored ~= nil and self._entity then
                local primaryPart = self._entity.PrimaryPart or self._entity:FindFirstChildWhichIsA("BasePart")
                if primaryPart then
                    primaryPart.Anchored = self._originalAnchored
                end
                self._originalAnchored = nil
            end

            self._navigating = false

            -- Path complete (only if not stopped early)
            -- Fire this LAST as listeners (like NodePool) may reset our state
            if not self._stopped then
                self.Out:Fire("pathComplete", {
                    entityId = self._entityId,
                })
            end
        end)
    end,
})

return PathFollower
