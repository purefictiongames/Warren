--[[
    LibPureFiction Framework v2
    Tracer.lua - Straight-Flying Projectile Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Tracer is a projectile that travels in a straight line at constant velocity.
    No gravity, no drop - pure ballistic tracer behavior.

    Features:
    - Constant velocity flight (no gravity)
    - Visual trail effect
    - Auto-destroy after lifetime or max distance
    - Hit detection via raycast

    If no model provided, creates a default glowing tracer part.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onLaunch({ direction: Vector3, velocity: number, position?: Vector3 })
            - Launch the tracer in a direction at velocity

        onConfigure({ lifetime?, maxDistance?, trailColor?, trailLength? })
            - Configure tracer properties

    OUT (emits):
        hit({ position: Vector3, normal: Vector3, instance: Instance })
            - Tracer hit something

        expired({ reason: "lifetime" | "distance" })
            - Tracer expired without hitting

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Velocity: number (default 200) - studs/second
    Lifetime: number (default 5) - seconds before auto-destroy
    MaxDistance: number (default 500) - studs before auto-destroy
    TrailColor: Color3 (default bright yellow)
    TrailLength: number (default 1) - trail lifetime in seconds

--]]

local Node = require(script.Parent.Parent.Node)
local RunService = game:GetService("RunService")

local Tracer = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                part = nil,
                partIsDefault = false,
                trail = nil,
                updateConnection = nil,
                direction = Vector3.new(0, 0, -1),
                velocity = 100,
                startPosition = Vector3.new(0, 0, 0),
                startTime = 0,
                launched = false,
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
            if state.partIsDefault and state.part then
                state.part:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    local function createDefaultPart(self)
        local state = getState(self)

        local part = Instance.new("Part")
        part.Name = self.id .. "_Tracer"
        part.Size = Vector3.new(0.3, 0.3, 1.5)
        part.Position = Vector3.new(0, 5, 0)
        part.Anchored = true
        part.CanCollide = false
        part.CastShadow = false
        part.BrickColor = BrickColor.new("Bright yellow")
        part.Material = Enum.Material.Neon
        part.Parent = workspace

        -- Glow effect
        local light = Instance.new("PointLight")
        light.Name = "Glow"
        light.Color = Color3.new(1, 0.9, 0.3)
        light.Brightness = 2
        light.Range = 8
        light.Parent = part

        state.part = part
        state.partIsDefault = true

        return part
    end

    local function createTrail(self)
        local state = getState(self)
        if not state.part then return end

        local trailColor = self:getAttribute("TrailColor") or Color3.new(1, 0.9, 0.3)
        local trailLength = self:getAttribute("TrailLength") or 1

        -- Trail attachments
        local frontAttach = Instance.new("Attachment")
        frontAttach.Name = "TrailFront"
        frontAttach.Position = Vector3.new(0, 0, -0.75)
        frontAttach.Parent = state.part

        local backAttach = Instance.new("Attachment")
        backAttach.Name = "TrailBack"
        backAttach.Position = Vector3.new(0, 0, 0.75)
        backAttach.Parent = state.part

        local trail = Instance.new("Trail")
        trail.Name = "TracerTrail"
        trail.Attachment0 = frontAttach
        trail.Attachment1 = backAttach
        trail.Lifetime = trailLength
        trail.MinLength = 0.05
        trail.FaceCamera = true
        trail.WidthScale = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0.6),
            NumberSequenceKeypoint.new(1, 0.1),
        })
        trail.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, trailColor),
            ColorSequenceKeypoint.new(0.5, trailColor),
            ColorSequenceKeypoint.new(1, Color3.new(trailColor.R * 0.5, trailColor.G * 0.3, 0)),
        })
        trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.7, 0.3),
            NumberSequenceKeypoint.new(1, 1),
        })
        trail.LightEmission = 1
        trail.LightInfluence = 0
        trail.Parent = state.part

        state.trail = trail
    end

    local function startFlying(self)
        local state = getState(self)
        if state.updateConnection then return end
        if not state.part then return end

        local lifetime = self:getAttribute("Lifetime") or 5
        local maxDistance = self:getAttribute("MaxDistance") or 500

        state.updateConnection = RunService.Heartbeat:Connect(function(dt)
            if not state.part or not state.part.Parent then
                cleanupState(self)
                return
            end

            -- Check lifetime
            local elapsed = os.clock() - state.startTime
            if elapsed >= lifetime then
                self.Out:Fire("expired", { reason = "lifetime" })
                state.part:Destroy()
                cleanupState(self)
                return
            end

            -- Check distance
            local traveled = (state.part.Position - state.startPosition).Magnitude
            if traveled >= maxDistance then
                self.Out:Fire("expired", { reason = "distance" })
                state.part:Destroy()
                cleanupState(self)
                return
            end

            -- Raycast for hit detection
            local rayLength = state.velocity * dt * 1.5  -- Slightly ahead
            local rayParams = RaycastParams.new()
            rayParams.FilterType = Enum.RaycastFilterType.Exclude
            rayParams.FilterDescendantsInstances = { state.part }

            local rayResult = workspace:Raycast(
                state.part.Position,
                state.direction * rayLength,
                rayParams
            )

            if rayResult then
                self.Out:Fire("hit", {
                    position = rayResult.Position,
                    normal = rayResult.Normal,
                    instance = rayResult.Instance,
                })
                state.part:Destroy()
                cleanupState(self)
                return
            end

            -- Move forward
            local movement = state.direction * state.velocity * dt
            state.part.CFrame = CFrame.new(
                state.part.Position + movement,
                state.part.Position + movement + state.direction
            )
        end)
    end

    return {
        name = "Tracer",
        domain = "server",

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Get part from model, or create default
                if self.model then
                    if self.model:IsA("BasePart") then
                        state.part = self.model
                    elseif self.model:IsA("Model") and self.model.PrimaryPart then
                        state.part = self.model.PrimaryPart
                    else
                        createDefaultPart(self)
                    end
                else
                    createDefaultPart(self)
                end

                -- Default attributes
                self:setAttribute("Velocity", self:getAttribute("Velocity") or 200)
                self:setAttribute("Lifetime", self:getAttribute("Lifetime") or 5)
                self:setAttribute("MaxDistance", self:getAttribute("MaxDistance") or 500)
                self:setAttribute("TrailColor", self:getAttribute("TrailColor") or Color3.new(1, 0.9, 0.3))
                self:setAttribute("TrailLength", self:getAttribute("TrailLength") or 1)

                -- Create trail
                createTrail(self)
            end,

            onStart = function(self)
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onConfigure = function(self, data)
                if not data then return end

                if data.velocity then
                    self:setAttribute("Velocity", math.max(1, data.velocity))
                end
                if data.lifetime then
                    self:setAttribute("Lifetime", math.max(0.1, data.lifetime))
                end
                if data.maxDistance then
                    self:setAttribute("MaxDistance", math.max(1, data.maxDistance))
                end
                if data.trailColor then
                    self:setAttribute("TrailColor", data.trailColor)
                end
                if data.trailLength then
                    self:setAttribute("TrailLength", math.max(0.1, data.trailLength))
                end
            end,

            onLaunch = function(self, data)
                data = data or {}
                local state = getState(self)

                if state.launched then return end  -- Already launched
                state.launched = true

                state.direction = data.direction and data.direction.Unit or Vector3.new(0, 0, -1)
                state.velocity = self:getAttribute("Velocity")

                -- Set initial position
                if data.position then
                    state.part.Position = data.position
                end
                state.startPosition = state.part.Position
                state.startTime = os.clock()

                -- Orient to direction
                state.part.CFrame = CFrame.new(
                    state.part.Position,
                    state.part.Position + state.direction
                )

                -- Start flying
                startFlying(self)
            end,
        },

        Out = {
            hit = {},     -- { position, normal, instance }
            expired = {}, -- { reason }
        },
    }
end)

return Tracer
