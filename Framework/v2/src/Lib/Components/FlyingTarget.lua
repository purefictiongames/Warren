--[[
    LibPureFiction Framework v2
    FlyingTarget.lua - Flying Target Drone Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    FlyingTarget is a target drone that flies around with a randomized path.
    It has health (EntityStats) and can be shot down.

    Features:
    - Creates visual drone model with glowing core
    - Flies in random patterns within a defined area
    - Has EntityStats for health management
    - Emits signals when hit and when destroyed
    - Auto-starts flying in onStart (batteries included)

    Used for:
    - Shooting gallery targets
    - Turret testing
    - Combat practice

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ health?, speed?, flyArea?, ... })
            - Update configuration

        onHit({ damage?, position?, source? })
            - Apply damage to target (forwarded to EntityStats)

        onEnable({})
            - Start flying

        onDisable({})
            - Stop flying (hover in place)

    OUT (emits):
        hit({ damage, position, health, maxHealth })
            - Target was hit by something

        died({ position })
            - Target health reached zero

        destroyed({ position })
            - Target has been destroyed and removed

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Health: number (default 100)
        Starting health points

    Speed: number (default 20)
        Movement speed in studs/second

    FlyAreaCenter: Vector3 (default 0, 20, 0)
        Center of the flying area

    FlyAreaSize: Vector3 (default 50, 20, 50)
        Size of the flying area box

    AutoStart: boolean (default true)
        Whether to start flying automatically in onStart

    TargetClass: string (default "FlyingTarget")
        NodeClass attribute for target detection (used by Targeter filter)

--]]

local RunService = game:GetService("RunService")
local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- FLYING TARGET NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local FlyingTarget = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Visual
                part = nil,
                partIsDefault = false,
                glowPart = nil,
                trail = nil,
                hitEvent = nil,
                hitConnection = nil,
                -- Movement
                targetPosition = nil,
                updateConnection = nil,
                enabled = false,
                -- EntityStats
                entityStats = nil,
                -- Hit flash
                hitFlashTime = 0,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            if state.updateConnection then
                state.updateConnection:Disconnect()
            end
            if state.hitConnection then
                state.hitConnection:Disconnect()
            end
            if state.entityStats then
                state.entityStats.Sys.onStop(state.entityStats)
            end
            if state.partIsDefault and state.part then
                state.part:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    --[[
        Private: Create the visual drone model.
    --]]
    local function createDronePart(self)
        local state = getState(self)

        -- Main body - larger size for easier targeting
        local part = Instance.new("Part")
        part.Name = self.id .. "_Drone"
        part.Size = Vector3.new(6, 6, 6)
        part.Shape = Enum.PartType.Ball
        part.Position = Vector3.new(0, 20, 0)
        part.Anchored = true
        part.CanCollide = true
        part.BrickColor = BrickColor.new("Bright red")
        part.Material = Enum.Material.SmoothPlastic

        -- Set NodeClass for Targeter detection
        local targetClass = self:getAttribute("TargetClass") or "FlyingTarget"
        part:SetAttribute("NodeClass", targetClass)

        part.Parent = workspace

        -- Glowing core
        local glow = Instance.new("Part")
        glow.Name = "Core"
        glow.Size = Vector3.new(2, 2, 2)
        glow.Shape = Enum.PartType.Ball
        glow.Anchored = false
        glow.CanCollide = false
        glow.CastShadow = false
        glow.BrickColor = BrickColor.new("Bright orange")
        glow.Material = Enum.Material.Neon
        glow.Parent = part

        -- Weld core to body
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = part
        weld.Part1 = glow
        weld.Parent = glow

        -- Light
        local light = Instance.new("PointLight")
        light.Color = Color3.new(1, 0.5, 0)
        light.Brightness = 2
        light.Range = 8
        light.Parent = glow

        -- Trail for movement
        local attachment0 = Instance.new("Attachment")
        attachment0.Position = Vector3.new(0, 0, -3)
        attachment0.Parent = part

        local attachment1 = Instance.new("Attachment")
        attachment1.Position = Vector3.new(0, 0, 3)
        attachment1.Parent = part

        local trail = Instance.new("Trail")
        trail.Attachment0 = attachment0
        trail.Attachment1 = attachment1
        trail.Lifetime = 0.5
        trail.MinLength = 0.1
        trail.FaceCamera = true
        trail.Color = ColorSequence.new(Color3.new(1, 0.5, 0), Color3.new(1, 0.2, 0))
        trail.Transparency = NumberSequence.new(0.3, 1)
        trail.LightEmission = 0.5

        -- BindableEvent for receiving external hits (from projectiles)
        local hitEvent = Instance.new("BindableEvent")
        hitEvent.Name = "HitEvent"
        hitEvent.Parent = part

        state.hitEvent = hitEvent

        -- Wire hit event to self
        state.hitConnection = hitEvent.Event:Connect(function(data)
            self.In.onHit(self, data)
        end)
        trail.Parent = part

        state.part = part
        state.partIsDefault = true
        state.glowPart = glow
        state.trail = trail

        return part
    end

    --[[
        Private: Pick a new random target position within the fly area.
    --]]
    local function pickNewTarget(self)
        local state = getState(self)
        local center = self:getAttribute("FlyAreaCenter") or Vector3.new(0, 20, 0)
        local size = self:getAttribute("FlyAreaSize") or Vector3.new(50, 20, 50)

        -- Random position within box
        local x = center.X + (math.random() - 0.5) * size.X
        local y = center.Y + (math.random() - 0.5) * size.Y
        local z = center.Z + (math.random() - 0.5) * size.Z

        state.targetPosition = Vector3.new(x, y, z)
    end

    --[[
        Private: Start the flying loop.
    --]]
    local function startFlying(self)
        local state = getState(self)
        if state.updateConnection then return end
        if not state.part then return end

        state.enabled = true
        pickNewTarget(self)

        state.updateConnection = RunService.Heartbeat:Connect(function(dt)
            if not state.part or not state.part.Parent then
                cleanupState(self)
                return
            end

            if not state.enabled then
                return
            end

            -- Handle hit flash
            if state.hitFlashTime > 0 then
                state.hitFlashTime = state.hitFlashTime - dt
                if state.hitFlashTime <= 0 then
                    state.part.BrickColor = BrickColor.new("Bright red")
                end
            end

            -- Move towards target
            local speed = self:getAttribute("Speed") or 20
            local currentPos = state.part.Position
            local targetPos = state.targetPosition

            if not targetPos then
                pickNewTarget(self)
                return
            end

            local distance = (targetPos - currentPos).Magnitude

            -- Pick new target if close enough
            if distance < 5 then
                pickNewTarget(self)
                return
            end

            -- Move towards target with smooth turning
            local desiredDirection = (targetPos - currentPos).Unit

            -- Get current facing direction
            local currentDirection = state.part.CFrame.LookVector

            -- Smoothly interpolate direction (max turn rate ~90 deg/sec)
            local turnRate = 1.5 * dt  -- How fast we can turn
            local smoothedDirection = currentDirection:Lerp(desiredDirection, math.min(turnRate, 1))
            if smoothedDirection.Magnitude > 0.001 then
                smoothedDirection = smoothedDirection.Unit
            else
                smoothedDirection = desiredDirection
            end

            local moveAmount = math.min(speed * dt, distance)
            local newPos = currentPos + smoothedDirection * moveAmount

            -- Orient towards movement direction
            state.part.CFrame = CFrame.new(newPos, newPos + smoothedDirection)
        end)
    end

    --[[
        Private: Stop the flying loop.
    --]]
    local function stopFlying(self)
        local state = getState(self)
        state.enabled = false
    end

    --[[
        Private: Handle death - play explosion effect and destroy.
    --]]
    local function handleDeath(self)
        local state = getState(self)
        if not state.part then return end

        local position = state.part.Position

        -- Create explosion effect
        local explosion = Instance.new("Part")
        explosion.Name = "Explosion"
        explosion.Size = Vector3.new(1, 1, 1)
        explosion.Position = position
        explosion.Anchored = true
        explosion.CanCollide = false
        explosion.BrickColor = BrickColor.new("Bright orange")
        explosion.Material = Enum.Material.Neon
        explosion.Parent = workspace

        -- Expand and fade
        local startSize = 1
        local endSize = 8
        local duration = 0.3

        task.spawn(function()
            local elapsed = 0
            while elapsed < duration do
                elapsed = elapsed + task.wait()
                local t = elapsed / duration
                local size = startSize + (endSize - startSize) * t
                explosion.Size = Vector3.new(size, size, size)
                explosion.Transparency = t
            end
            explosion:Destroy()
        end)

        -- Emit destroyed signal
        self.Out:Fire("destroyed", { position = position })

        -- Destroy the drone
        if state.part then
            state.part:Destroy()
            state.part = nil
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "FlyingTarget",
        domain = "server",

        Sys = {
            onInit = function(self)
                local state = getState(self)
                local EntityStats = require(script.Parent.EntityStats)

                -- Create visual if no model provided
                if self.model then
                    if self.model:IsA("BasePart") then
                        state.part = self.model
                    elseif self.model:IsA("Model") and self.model.PrimaryPart then
                        state.part = self.model.PrimaryPart
                    else
                        createDronePart(self)
                    end
                else
                    createDronePart(self)
                end

                -- Default attributes
                if self:getAttribute("Health") == nil then
                    self:setAttribute("Health", 100)
                end
                if self:getAttribute("Speed") == nil then
                    self:setAttribute("Speed", 20)
                end
                if self:getAttribute("FlyAreaCenter") == nil then
                    self:setAttribute("FlyAreaCenter", Vector3.new(0, 20, 0))
                end
                if self:getAttribute("FlyAreaSize") == nil then
                    self:setAttribute("FlyAreaSize", Vector3.new(50, 20, 50))
                end
                if self:getAttribute("AutoStart") == nil then
                    self:setAttribute("AutoStart", true)
                end
                if self:getAttribute("TargetClass") == nil then
                    self:setAttribute("TargetClass", "FlyingTarget")
                end

                -- Create EntityStats for health management
                local maxHealth = self:getAttribute("Health")
                state.entityStats = EntityStats:new({
                    id = self.id .. "_Stats",
                    model = state.part,
                    attributes = {
                        stats = {
                            health = { base = maxHealth, current = maxHealth, min = 0, max = maxHealth },
                        },
                    },
                })
                state.entityStats.Sys.onInit(state.entityStats)

                -- Wire EntityStats signals
                local statsOriginalFire = state.entityStats.Out.Fire
                state.entityStats.Out.Fire = function(outSelf, signal, data)
                    data = data or {}

                    if signal == "statChanged" and data.name == "health" then
                        -- Forward health changes as hit signal
                        if data.previous and data.current and data.current < data.previous then
                            local damage = data.previous - data.current
                            self.Out:Fire("hit", {
                                damage = damage,
                                position = state.part and state.part.Position or Vector3.zero,
                                health = data.current,
                                maxHealth = data.max or maxHealth,
                            })

                            -- Flash white on hit
                            if state.part then
                                state.part.BrickColor = BrickColor.new("White")
                                state.hitFlashTime = 0.1
                            end
                        end

                    elseif signal == "died" then
                        -- Forward death signal
                        self.Out:Fire("died", {
                            position = state.part and state.part.Position or Vector3.zero,
                        })
                        handleDeath(self)
                    end

                    statsOriginalFire(outSelf, signal, data)
                end
            end,

            onStart = function(self)
                local state = getState(self)

                -- Start EntityStats
                if state.entityStats then
                    state.entityStats.Sys.onStart(state.entityStats)
                end

                -- Auto-start flying if configured (default: true)
                if self:getAttribute("AutoStart") then
                    startFlying(self)
                end
            end,

            onStop = function(self)
                stopFlying(self)
                cleanupState(self)
            end,
        },

        In = {
            --[[
                Configure target settings.
            --]]
            onConfigure = function(self, data)
                if not data then return end
                local state = getState(self)

                if data.health then
                    self:setAttribute("Health", math.max(1, data.health))
                    -- Reset EntityStats health
                    if state.entityStats then
                        state.entityStats.In.onSetStat(state.entityStats, {
                            name = "health",
                            base = data.health,
                            current = data.health,
                            max = data.health,
                        })
                    end
                end

                if data.speed then
                    self:setAttribute("Speed", math.max(1, data.speed))
                end

                if data.flyAreaCenter then
                    self:setAttribute("FlyAreaCenter", data.flyAreaCenter)
                end

                if data.flyAreaSize then
                    self:setAttribute("FlyAreaSize", data.flyAreaSize)
                end

                if data.targetClass then
                    self:setAttribute("TargetClass", data.targetClass)
                    if state.part then
                        state.part:SetAttribute("NodeClass", data.targetClass)
                    end
                end
            end,

            --[[
                Apply damage to target.
            --]]
            onHit = function(self, data)
                data = data or {}
                local state = getState(self)

                local damage = data.damage or 10

                -- Apply damage via EntityStats
                if state.entityStats then
                    state.entityStats.In.onApplyModifier(state.entityStats, {
                        name = "health",
                        operation = "subtract",
                        value = damage,
                    })
                end
            end,

            --[[
                Enable flying.
            --]]
            onEnable = function(self)
                startFlying(self)
            end,

            --[[
                Disable flying.
            --]]
            onDisable = function(self)
                stopFlying(self)
            end,
        },

        Out = {
            hit = {},       -- { damage, position, health, maxHealth }
            died = {},      -- { position }
            destroyed = {}, -- { position }
        },
    }
end)

return FlyingTarget
