--[[
    Warren Framework v2
    PlasmaBeam.lua - Continuous Beam Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    PlasmaBeam is a continuous energy beam that fires from an origin point.
    Features pulsing visuals, hit detection, and damage potential.

    Features:
    - Continuous raycast hit detection
    - Pulsing intensity effect
    - Impact particles at hit point
    - Follows origin (muzzle) when active

    If no model provided, creates a default beam visual.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onActivate({ origin: BasePart, direction?: Vector3 })
            - Start firing the beam from origin

        onDeactivate({})
            - Stop the beam

        onConfigure({ color?, maxLength?, pulseSpeed?, width? })
            - Configure beam properties

    OUT (emits):
        activated({ beam: Instance })
            - Beam started firing

        deactivated({})
            - Beam stopped

        hitting({ position: Vector3, normal: Vector3, instance: Instance })
            - Beam is hitting something (continuous while active)

    ============================================================================
    ATTRIBUTES
    ============================================================================

    BeamColor: Color3 (default cyan)
    MaxLength: number (default 100) - max beam length in studs
    PulseSpeed: number (default 3) - pulses per second
    Width: number (default 0.3) - beam width

--]]

local Node = require(script.Parent.Parent.Node)
local RunService = game:GetService("RunService")

local PlasmaBeam = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                beamPart = nil,
                impactPart = nil,
                origin = nil,
                direction = Vector3.new(0, 0, -1),
                updateConnection = nil,
                active = false,
                startTime = 0,
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
            if state.beamPart then
                state.beamPart:Destroy()
            end
            if state.impactPart then
                state.impactPart:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    local function createBeamVisual(self)
        local state = getState(self)
        local color = self:getAttribute("BeamColor") or Color3.new(0, 0.8, 1)
        local width = self:getAttribute("Width") or 0.3

        -- Main beam part
        local beam = Instance.new("Part")
        beam.Name = self.id .. "_Beam"
        beam.Size = Vector3.new(width, width, 1)
        beam.Anchored = true
        beam.CanCollide = false
        beam.CastShadow = false
        beam.Color = color
        beam.Material = Enum.Material.Neon
        beam.Transparency = 0.2
        beam.Parent = workspace

        -- Inner glow
        local innerBeam = Instance.new("Part")
        innerBeam.Name = "InnerGlow"
        innerBeam.Size = Vector3.new(width * 0.4, width * 0.4, 1)
        innerBeam.Anchored = true
        innerBeam.CanCollide = false
        innerBeam.CastShadow = false
        innerBeam.Color = Color3.new(1, 1, 1)
        innerBeam.Material = Enum.Material.Neon
        innerBeam.Transparency = 0
        innerBeam.Parent = beam

        -- Light at origin
        local light = Instance.new("PointLight")
        light.Name = "BeamLight"
        light.Color = color
        light.Brightness = 3
        light.Range = 12
        light.Parent = beam

        state.beamPart = beam

        -- Impact effect
        local impact = Instance.new("Part")
        impact.Name = self.id .. "_Impact"
        impact.Size = Vector3.new(width * 3, width * 3, width * 3)
        impact.Shape = Enum.PartType.Ball
        impact.Anchored = true
        impact.CanCollide = false
        impact.CastShadow = false
        impact.Color = color
        impact.Material = Enum.Material.Neon
        impact.Transparency = 0.3
        impact.Parent = workspace

        -- Impact light
        local impactLight = Instance.new("PointLight")
        impactLight.Name = "ImpactLight"
        impactLight.Color = color
        impactLight.Brightness = 5
        impactLight.Range = 8
        impactLight.Parent = impact

        state.impactPart = impact
        state.impactPart.Transparency = 1  -- Start hidden

        return beam
    end

    local function updateBeam(self)
        local state = getState(self)
        if not state.active or not state.origin or not state.beamPart then
            return
        end

        local maxLength = self:getAttribute("MaxLength") or 100
        local pulseSpeed = self:getAttribute("PulseSpeed") or 3
        local width = self:getAttribute("Width") or 0.3

        -- Get origin position and direction
        local originPos = state.origin.Position
        local direction = state.origin.CFrame.LookVector

        -- Raycast to find hit
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = { state.beamPart, state.impactPart, state.origin }

        local rayResult = workspace:Raycast(originPos, direction * maxLength, rayParams)

        local endPos
        local hitSomething = false

        if rayResult then
            endPos = rayResult.Position
            hitSomething = true

            -- Fire hitting signal
            self.Out:Fire("hitting", {
                position = rayResult.Position,
                normal = rayResult.Normal,
                instance = rayResult.Instance,
            })
        else
            endPos = originPos + direction * maxLength
        end

        -- Calculate beam properties
        local beamLength = (endPos - originPos).Magnitude
        local midPoint = originPos + direction * (beamLength / 2)

        -- Pulse effect
        local elapsed = os.clock() - state.startTime
        local pulse = 0.8 + 0.2 * math.sin(elapsed * pulseSpeed * math.pi * 2)
        local pulseWidth = width * pulse

        -- Update beam part
        state.beamPart.Size = Vector3.new(pulseWidth, pulseWidth, beamLength)
        state.beamPart.CFrame = CFrame.new(midPoint, endPos)
        state.beamPart.Transparency = 0.2 + 0.1 * (1 - pulse)

        -- Update inner glow
        local innerGlow = state.beamPart:FindFirstChild("InnerGlow")
        if innerGlow then
            innerGlow.Size = Vector3.new(pulseWidth * 0.4, pulseWidth * 0.4, beamLength)
            innerGlow.CFrame = state.beamPart.CFrame
        end

        -- Update impact effect
        if hitSomething then
            state.impactPart.Transparency = 0.3
            state.impactPart.Position = endPos
            state.impactPart.Size = Vector3.new(pulseWidth * 3, pulseWidth * 3, pulseWidth * 3)
        else
            state.impactPart.Transparency = 1
        end
    end

    local function startBeam(self)
        local state = getState(self)
        if state.updateConnection then return end

        state.startTime = os.clock()

        state.updateConnection = RunService.Heartbeat:Connect(function(dt)
            if not state.active then
                return
            end
            updateBeam(self)
        end)
    end

    local function stopBeam(self)
        local state = getState(self)

        if state.updateConnection then
            state.updateConnection:Disconnect()
            state.updateConnection = nil
        end

        if state.beamPart then
            state.beamPart.Transparency = 1
        end
        if state.impactPart then
            state.impactPart.Transparency = 1
        end
    end

    return {
        name = "PlasmaBeam",
        domain = "server",

        Sys = {
            onInit = function(self)
                -- Default attributes
                self:setAttribute("BeamColor", self:getAttribute("BeamColor") or Color3.new(0, 0.8, 1))
                self:setAttribute("MaxLength", self:getAttribute("MaxLength") or 100)
                self:setAttribute("PulseSpeed", self:getAttribute("PulseSpeed") or 3)
                self:setAttribute("Width", self:getAttribute("Width") or 0.3)

                -- Create visual
                createBeamVisual(self)
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
                local state = getState(self)

                if data.color then
                    self:setAttribute("BeamColor", data.color)
                    if state.beamPart then
                        state.beamPart.Color = data.color
                        local light = state.beamPart:FindFirstChild("BeamLight")
                        if light then light.Color = data.color end
                    end
                    if state.impactPart then
                        state.impactPart.Color = data.color
                        local light = state.impactPart:FindFirstChild("ImpactLight")
                        if light then light.Color = data.color end
                    end
                end
                if data.maxLength then
                    self:setAttribute("MaxLength", math.max(1, data.maxLength))
                end
                if data.pulseSpeed then
                    self:setAttribute("PulseSpeed", math.max(0, data.pulseSpeed))
                end
                if data.width then
                    self:setAttribute("Width", math.max(0.1, data.width))
                end
            end,

            onActivate = function(self, data)
                data = data or {}
                local state = getState(self)

                if state.active then return end

                state.origin = data.origin
                if data.direction then
                    state.direction = data.direction.Unit
                end

                if not state.origin then
                    self.Err:Fire({ reason = "no_origin" })
                    return
                end

                state.active = true

                -- Show beam
                if state.beamPart then
                    state.beamPart.Transparency = 0.2
                end

                startBeam(self)
                self.Out:Fire("activated", { beam = state.beamPart })
            end,

            onDeactivate = function(self, data)
                local state = getState(self)

                if not state.active then return end

                state.active = false
                stopBeam(self)
                self.Out:Fire("deactivated", {})
            end,
        },

        Out = {
            activated = {},   -- { beam }
            deactivated = {}, -- {}
            hitting = {},     -- { position, normal, instance }
        },
    }
end)

return PlasmaBeam
