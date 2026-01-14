--[[
    LibPureFiction Framework v2
    Projectile.lua - Projectile Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Projectile is a component that handles projectile movement, collision
    detection, and lifecycle. It supports multiple movement types and
    impact behaviors.

    Movement types:
    - "linear": Straight line, constant speed (default)
    - "ballistic": Arc/parabola with gravity (Phase 2)
    - "homing": Track and follow target (Phase 2)

    Impact behaviors:
    - "despawn": Remove projectile on hit (default)
    - "pierce": Continue through targets (Phase 5)
    - "bounce": Reflect off surfaces (Phase 5)
    - "explode": AoE damage on impact (Phase 5)

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ speed?, lifespan?, maxDistance?, damage?, movementType?,
                      collisionMode?, onHit?, gravity?, collisionFilter? })
            - Configure projectile behavior

        onLaunch({ origin: Vector3, direction: Vector3, speed?: number,
                   target?: Instance, damage?: number })
            - Launch the projectile
            - origin: Starting position
            - direction: Normalized direction vector
            - speed: Override configured speed
            - target: For homing projectiles
            - damage: Override configured damage

        onAbort()
            - Cancel the projectile mid-flight

    OUT (emits):
        launched({ origin, direction, speed, projectileId })
            - Fired when projectile begins flight

        hit({ target, position, normal, damage, projectileId })
            - Fired when projectile hits something

        expired({ position, traveled, reason, projectileId })
            - Fired when projectile expires without hitting
            - reason: "lifespan" | "maxDistance"

    Err (detour):
        noTarget({ reason, projectileId })
            - Homing projectile lost its target

        launchFailed({ reason, projectileId })
            - Launch failed (no model, already flying, etc.)

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Speed: number (default 50)
        Units (studs) per second

    Lifespan: number (default 5)
        Maximum seconds before expiration

    MaxDistance: number (default 500)
        Maximum studs traveled before expiration

    Damage: number (default 10)
        Damage value passed to hit signal

    MovementType: string (default "linear")
        "linear", "ballistic", "homing"

    CollisionMode: string (default "touch")
        "touch" - Use Touched event
        "raycast" - Use raycasting each frame
        "none" - No collision detection

    OnHit: string (default "despawn")
        "despawn", "pierce", "bounce", "explode"

    Gravity: number (default 196.2)
        Gravity for ballistic trajectory (studs/sec^2)

    HomingStrength: number (default 5)
        Turn rate for homing projectiles

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Create a projectile
    local projectile = Projectile:new({
        id = "Bullet_1",
        model = bulletModel,  -- A Part or Model
    })
    projectile.Sys.onInit(projectile)

    -- Configure
    projectile.In.onConfigure(projectile, {
        speed = 100,
        damage = 25,
        lifespan = 3,
    })

    -- Launch
    projectile.In.onLaunch(projectile, {
        origin = turretPosition,
        direction = aimDirection,
    })

    -- Handle hit
    projectile.Out:Connect("hit", function(data)
        applyDamage(data.target, data.damage)
    end)
    ```

--]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Node = require(script.Parent.Parent.Node)
local Registry = Node.Registry

local Projectile = Node.extend({
    name = "Projectile",
    domain = "server",

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Flight state
            self._flying = false
            self._startTime = 0
            self._startPosition = Vector3.new()
            self._direction = Vector3.new(0, 0, -1)
            self._velocity = Vector3.new()
            self._distanceTraveled = 0
            self._currentSpeed = 0

            -- Homing state
            self._target = nil

            -- Collision state
            self._hitTargets = {}  -- For pierce mode: { [instance] = true }
            self._bounceCount = 0

            -- Connections
            self._heartbeatConnection = nil
            self._touchedConnection = nil

            -- Collision filter
            self._collisionFilter = nil

            -- Default attributes
            if not self:getAttribute("Speed") then
                self:setAttribute("Speed", 50)
            end
            if not self:getAttribute("Lifespan") then
                self:setAttribute("Lifespan", 5)
            end
            if not self:getAttribute("MaxDistance") then
                self:setAttribute("MaxDistance", 500)
            end
            if not self:getAttribute("Damage") then
                self:setAttribute("Damage", 10)
            end
            if not self:getAttribute("MovementType") then
                self:setAttribute("MovementType", "linear")
            end
            if not self:getAttribute("CollisionMode") then
                self:setAttribute("CollisionMode", "touch")
            end
            if not self:getAttribute("OnHit") then
                self:setAttribute("OnHit", "despawn")
            end
            if not self:getAttribute("Gravity") then
                self:setAttribute("Gravity", 196.2)
            end
            if not self:getAttribute("HomingStrength") then
                self:setAttribute("HomingStrength", 5)
            end
            if not self:getAttribute("PierceCount") then
                self:setAttribute("PierceCount", 1)
            end
            if not self:getAttribute("BounceCount") then
                self:setAttribute("BounceCount", 1)
            end
            if not self:getAttribute("ExplosionRadius") then
                self:setAttribute("ExplosionRadius", 10)
            end
        end,

        onStart = function(self)
            -- Nothing on start - waits for onLaunch
        end,

        onStop = function(self)
            self:_stopFlight()
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

    In = {
        --[[
            Configure projectile behavior.
        --]]
        onConfigure = function(self, data)
            if not data then return end

            if data.speed then
                self:setAttribute("Speed", data.speed)
            end
            if data.lifespan then
                self:setAttribute("Lifespan", data.lifespan)
            end
            if data.maxDistance then
                self:setAttribute("MaxDistance", data.maxDistance)
            end
            if data.damage then
                self:setAttribute("Damage", data.damage)
            end
            if data.movementType then
                self:setAttribute("MovementType", data.movementType)
            end
            if data.collisionMode then
                self:setAttribute("CollisionMode", data.collisionMode)
            end
            if data.onHit then
                self:setAttribute("OnHit", data.onHit)
            end
            if data.gravity then
                self:setAttribute("Gravity", data.gravity)
            end
            if data.homingStrength then
                self:setAttribute("HomingStrength", data.homingStrength)
            end
            if data.pierceCount then
                self:setAttribute("PierceCount", data.pierceCount)
            end
            if data.bounceCount then
                self:setAttribute("BounceCount", data.bounceCount)
            end
            if data.explosionRadius then
                self:setAttribute("ExplosionRadius", data.explosionRadius)
            end
            if data.collisionFilter then
                self._collisionFilter = data.collisionFilter
            end
        end,

        --[[
            Launch the projectile.
        --]]
        onLaunch = function(self, data)
            if not data then
                self.Err:Fire({
                    reason = "launchFailed",
                    message = "Launch data required",
                    projectileId = self.id,
                })
                return
            end

            if self._flying then
                self.Err:Fire({
                    reason = "launchFailed",
                    message = "Projectile already flying",
                    projectileId = self.id,
                })
                return
            end

            local origin = data.origin
            local direction = data.direction

            if not origin or not direction then
                self.Err:Fire({
                    reason = "launchFailed",
                    message = "Origin and direction required",
                    projectileId = self.id,
                })
                return
            end

            -- Normalize direction
            if direction.Magnitude > 0 then
                direction = direction.Unit
            else
                direction = Vector3.new(0, 0, -1)
            end

            -- Override speed/damage if provided
            local speed = data.speed or self:getAttribute("Speed")
            local damage = data.damage or self:getAttribute("Damage")

            if data.speed then
                self._currentSpeed = data.speed
            else
                self._currentSpeed = self:getAttribute("Speed")
            end

            if data.damage then
                self:setAttribute("Damage", data.damage)
            end

            -- Set homing target if provided
            if data.target then
                self._target = data.target
            end

            -- Initialize flight state
            self._flying = true
            self._startTime = os.clock()
            self._startPosition = origin
            self._direction = direction
            self._distanceTraveled = 0
            self._hitTargets = {}
            self._bounceCount = 0

            -- Initialize velocity based on movement type
            local movementType = self:getAttribute("MovementType")
            if movementType == "linear" then
                self._velocity = direction * self._currentSpeed
            elseif movementType == "ballistic" then
                self._velocity = direction * self._currentSpeed
            elseif movementType == "homing" then
                self._velocity = direction * self._currentSpeed
            end

            -- Position the model
            self:_setPosition(origin)

            -- Start collision detection
            local collisionMode = self:getAttribute("CollisionMode")
            if collisionMode == "touch" then
                self:_enableTouchDetection()
            end

            -- Start movement update
            self:_startHeartbeat()

            -- Fire launched signal
            self.Out:Fire("launched", {
                origin = origin,
                direction = direction,
                speed = self._currentSpeed,
                projectileId = self.id,
            })
        end,

        --[[
            Abort the projectile mid-flight.
        --]]
        onAbort = function(self)
            if not self._flying then
                return
            end

            self:_stopFlight()

            self.Out:Fire("expired", {
                position = self:_getPosition(),
                traveled = self._distanceTraveled,
                reason = "aborted",
                projectileId = self.id,
            })
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA
    ----------------------------------------------------------------------------

    Out = {
        launched = {},  -- { origin, direction, speed, projectileId }
        hit = {},       -- { target, position, normal, damage, projectileId }
        expired = {},   -- { position, traveled, reason, projectileId }
    },

    ----------------------------------------------------------------------------
    -- PRIVATE: POSITION HELPERS
    ----------------------------------------------------------------------------

    --[[
        Get the projectile's current position.
    --]]
    _getPosition = function(self)
        if not self.model then
            return self._startPosition
        end

        if self.model:IsA("Model") then
            if self.model.PrimaryPart then
                return self.model.PrimaryPart.Position
            else
                local part = self.model:FindFirstChildWhichIsA("BasePart")
                return part and part.Position or self._startPosition
            end
        elseif self.model:IsA("BasePart") then
            return self.model.Position
        end

        return self._startPosition
    end,

    --[[
        Set the projectile's position.
    --]]
    _setPosition = function(self, position)
        if not self.model then
            return
        end

        if self.model:IsA("Model") then
            if self.model.PrimaryPart then
                local cf = CFrame.new(position, position + self._direction)
                self.model:SetPrimaryPartCFrame(cf)
            else
                local part = self.model:FindFirstChildWhichIsA("BasePart")
                if part then
                    part.CFrame = CFrame.new(position, position + self._direction)
                end
            end
        elseif self.model:IsA("BasePart") then
            self.model.CFrame = CFrame.new(position, position + self._direction)
        end
    end,

    --[[
        Get the projectile's primary part for collision.
    --]]
    _getPrimaryPart = function(self)
        if not self.model then
            return nil
        end

        if self.model:IsA("BasePart") then
            return self.model
        elseif self.model:IsA("Model") then
            return self.model.PrimaryPart or self.model:FindFirstChildWhichIsA("BasePart")
        end

        return nil
    end,

    ----------------------------------------------------------------------------
    -- PRIVATE: FLIGHT CONTROL
    ----------------------------------------------------------------------------

    --[[
        Start the heartbeat update loop.
    --]]
    _startHeartbeat = function(self)
        if self._heartbeatConnection then
            return
        end

        self._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
            self:_updateFlight(deltaTime)
        end)
    end,

    --[[
        Stop the heartbeat update loop.
    --]]
    _stopHeartbeat = function(self)
        if self._heartbeatConnection then
            self._heartbeatConnection:Disconnect()
            self._heartbeatConnection = nil
        end
    end,

    --[[
        Stop all flight systems.
    --]]
    _stopFlight = function(self)
        self._flying = false
        self:_stopHeartbeat()
        self:_disableTouchDetection()
    end,

    --[[
        Update flight each frame.
    --]]
    _updateFlight = function(self, deltaTime)
        if not self._flying then
            return
        end

        local movementType = self:getAttribute("MovementType")

        -- Update velocity based on movement type
        if movementType == "ballistic" then
            self:_updateBallistic(deltaTime)
        elseif movementType == "homing" then
            self:_updateHoming(deltaTime)
        end
        -- Linear uses constant velocity, no update needed

        -- Calculate new position
        local currentPos = self:_getPosition()
        local movement = self._velocity * deltaTime
        local newPos = currentPos + movement

        -- Raycast collision check (if using raycast mode)
        local collisionMode = self:getAttribute("CollisionMode")
        if collisionMode == "raycast" then
            local hit, hitPos, hitNormal, hitTarget = self:_raycastCheck(currentPos, newPos)
            if hit then
                self:_handleHit(hitTarget, hitPos, hitNormal)
                if not self._flying then
                    return  -- Projectile was stopped by hit
                end
            end
        end

        -- Update position
        self:_setPosition(newPos)

        -- Update distance traveled
        self._distanceTraveled = self._distanceTraveled + movement.Magnitude

        -- Update direction to match velocity (for ballistic/homing)
        if self._velocity.Magnitude > 0 then
            self._direction = self._velocity.Unit
        end

        -- Check expiration conditions
        local lifespan = self:getAttribute("Lifespan")
        local maxDistance = self:getAttribute("MaxDistance")
        local elapsed = os.clock() - self._startTime

        if elapsed >= lifespan then
            self:_expire("lifespan")
        elseif self._distanceTraveled >= maxDistance then
            self:_expire("maxDistance")
        end
    end,

    --[[
        Update ballistic (arc) trajectory.
    --]]
    _updateBallistic = function(self, deltaTime)
        local gravity = self:getAttribute("Gravity")
        -- Apply gravity to velocity
        self._velocity = self._velocity - Vector3.new(0, gravity * deltaTime, 0)
    end,

    --[[
        Update homing trajectory.
    --]]
    _updateHoming = function(self, deltaTime)
        if not self._target then
            return
        end

        -- Check if target still exists
        if not self._target.Parent then
            self._target = nil
            self.Err:Fire({
                reason = "noTarget",
                message = "Target destroyed",
                projectileId = self.id,
            })
            return
        end

        -- Get target position
        local targetPos
        if self._target:IsA("Model") then
            if self._target.PrimaryPart then
                targetPos = self._target.PrimaryPart.Position
            else
                local part = self._target:FindFirstChildWhichIsA("BasePart")
                targetPos = part and part.Position
            end
        elseif self._target:IsA("BasePart") then
            targetPos = self._target.Position
        end

        if not targetPos then
            return
        end

        -- Calculate desired direction
        local currentPos = self:_getPosition()
        local toTarget = (targetPos - currentPos)
        if toTarget.Magnitude == 0 then
            return
        end
        local desiredDirection = toTarget.Unit

        -- Lerp current direction toward target
        local homingStrength = self:getAttribute("HomingStrength")
        local turnAmount = math.min(1, homingStrength * deltaTime)
        local newDirection = self._direction:Lerp(desiredDirection, turnAmount).Unit

        -- Update velocity with new direction
        self._velocity = newDirection * self._currentSpeed
        self._direction = newDirection
    end,

    --[[
        Expire the projectile.
    --]]
    _expire = function(self, reason)
        local position = self:_getPosition()
        local traveled = self._distanceTraveled

        self:_stopFlight()

        self.Out:Fire("expired", {
            position = position,
            traveled = traveled,
            reason = reason,
            projectileId = self.id,
        })
    end,

    ----------------------------------------------------------------------------
    -- PRIVATE: COLLISION DETECTION
    ----------------------------------------------------------------------------

    --[[
        Enable touch-based collision detection.
    --]]
    _enableTouchDetection = function(self)
        local part = self:_getPrimaryPart()
        if not part then
            return
        end

        self._touchedConnection = part.Touched:Connect(function(otherPart)
            if not self._flying then
                return
            end

            -- Get the entity (Model or Part)
            local entity = otherPart:FindFirstAncestorOfClass("Model") or otherPart

            -- Skip if it's our own model
            if entity == self.model or otherPart == self.model then
                return
            end
            if self.model:IsA("Model") and otherPart:IsDescendantOf(self.model) then
                return
            end

            -- Apply collision filter
            if not self:_passesFilter(entity) then
                return
            end

            -- Get hit position and normal
            local hitPosition = otherPart.Position
            local hitNormal = (self:_getPosition() - hitPosition).Unit

            self:_handleHit(entity, hitPosition, hitNormal)
        end)
    end,

    --[[
        Disable touch-based collision detection.
    --]]
    _disableTouchDetection = function(self)
        if self._touchedConnection then
            self._touchedConnection:Disconnect()
            self._touchedConnection = nil
        end
    end,

    --[[
        Perform raycast collision check between two positions.
    --]]
    _raycastCheck = function(self, fromPos, toPos)
        local direction = toPos - fromPos
        local distance = direction.Magnitude

        if distance == 0 then
            return false
        end

        -- Set up raycast params
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude

        -- Exclude our own model
        local exclude = {}
        if self.model then
            if self.model:IsA("Model") then
                for _, part in ipairs(self.model:GetDescendants()) do
                    if part:IsA("BasePart") then
                        table.insert(exclude, part)
                    end
                end
            elseif self.model:IsA("BasePart") then
                table.insert(exclude, self.model)
            end
        end
        raycastParams.FilterDescendantsInstances = exclude

        -- Perform raycast
        local result = workspace:Raycast(fromPos, direction, raycastParams)

        if result then
            local entity = result.Instance:FindFirstAncestorOfClass("Model") or result.Instance

            -- Apply collision filter
            if self:_passesFilter(entity) then
                return true, result.Position, result.Normal, entity
            end
        end

        return false
    end,

    --[[
        Check if an entity passes the collision filter.
    --]]
    _passesFilter = function(self, entity)
        if not self._collisionFilter then
            return true
        end

        return Registry.matches(entity, self._collisionFilter)
    end,

    --[[
        Handle a hit.
    --]]
    _handleHit = function(self, target, position, normal)
        local onHit = self:getAttribute("OnHit")

        -- Check pierce mode - skip if already hit this target
        if onHit == "pierce" then
            if self._hitTargets[target] then
                return
            end
            self._hitTargets[target] = true
        end

        -- Fire hit signal
        self.Out:Fire("hit", {
            target = target,
            position = position,
            normal = normal,
            damage = self:getAttribute("Damage"),
            projectileId = self.id,
        })

        -- Handle based on onHit mode
        if onHit == "despawn" then
            self:_stopFlight()
        elseif onHit == "pierce" then
            local pierceCount = self:getAttribute("PierceCount")
            local hitCount = 0
            for _ in pairs(self._hitTargets) do
                hitCount = hitCount + 1
            end
            if hitCount >= pierceCount then
                self:_stopFlight()
            end
            -- Otherwise continue flying
        elseif onHit == "bounce" then
            local bounceCount = self:getAttribute("BounceCount")
            self._bounceCount = self._bounceCount + 1
            if self._bounceCount >= bounceCount then
                self:_stopFlight()
            else
                -- Reflect velocity
                self._velocity = self._velocity - 2 * self._velocity:Dot(normal) * normal
                self._direction = self._velocity.Unit
            end
        elseif onHit == "explode" then
            -- Explosion handling - fire additional signal or let handler deal with it
            -- The hit signal includes position, handler can create explosion zone
            self:_stopFlight()
        end
    end,
})

return Projectile
