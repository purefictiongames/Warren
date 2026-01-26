--[[
    LibPureFiction Framework v2
    Swivel.lua - Single-Axis Rotation Component (Physics-Based)

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Swivel provides single-axis rotation control using HingeConstraint servos.
    All motion is physics-driven for smooth interpolation - no frame-by-frame
    CFrame manipulation.

    Used for:
    - Turret yaw/pitch control
    - Searchlight sweep
    - Door hinges
    - Any single-axis rotation need

    ============================================================================
    SETUP REQUIREMENTS
    ============================================================================

    The Swivel requires either:
    1. An anchor part to hinge from (passed via config.anchor)
    2. Or the model's parent must be a valid anchor point

    The model (rotating part) will be unanchored automatically if needed.

    ============================================================================
    MODES
    ============================================================================

    continuous:
        Rotates while signal active using Motor mode, stops on onStop.
        Use for smooth tracking.

    stepped:
        Uses Servo mode - moves to target angle smoothly.
        Use for precise positioning.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onRotate({ direction: "forward" | "reverse" })
            - Continuous: starts rotating until onStop (uses Motor mode)
            - Stepped: rotates one StepSize increment (uses Servo mode)

        onSetAngle({ degrees: number })
            - Direct positioning using Servo mode
            - Clamps to MinAngle/MaxAngle

        onStop({})
            - Stops continuous rotation
            - No effect in stepped mode

        onConfigure({ axis?, mode?, speed?, stepSize?, minAngle?, maxAngle? })
            - Update configuration

    OUT (emits):
        rotated({ angle: number })
            - Current angle after movement

        limitReached({ limit: "min" | "max" })
            - Hit rotation boundary

        stopped({})
            - Emitted when rotation stops (servo reached target or motor stopped)

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Axis: string (default "Y")
        Rotation axis: "X", "Y", or "Z"

    Mode: string (default "continuous")
        "continuous" or "stepped"

    Speed: number (default 90)
        Degrees per second

    StepSize: number (default 5)
        Degrees per pulse (stepped mode)

    MinAngle: number (default -180)
        Lower rotation limit

    MaxAngle: number (default 180)
        Upper rotation limit

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Basic setup with anchor part
    local swivel = Swivel:new({
        model = workspace.TurretHead,
        anchor = workspace.TurretBase,  -- Part to hinge from
    })
    swivel.Sys.onInit(swivel)
    swivel.In.onConfigure(swivel, {
        axis = "Y",
        mode = "continuous",
        speed = 90,
        minAngle = -90,
        maxAngle = 90,
    })

    -- Start rotating (physics-driven, smooth)
    swivel.In.onRotate(swivel, { direction = "forward" })

    -- Later, stop
    swivel.In.onStop(swivel)

    -- Or set directly (servo smoothly moves to angle)
    swivel.In.onSetAngle(swivel, { degrees = 45 })
    ```

--]]

local RunService = game:GetService("RunService")
local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- SWIVEL NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Swivel = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                currentAngle = 0,
                targetAngle = 0,
                rotating = false,
                direction = 1,  -- 1 = forward, -1 = reverse
                hinge = nil,
                anchorAttachment = nil,
                modelAttachment = nil,
                monitorConnection = nil,
                createdAnchor = nil,
                createdModel = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Get attachment CFrame for the given axis.
        Rotates attachment so PrimaryAxis aligns with rotation axis.
    --]]
    local function getAttachmentCFrame(axis)
        if axis == "X" then
            -- PrimaryAxis (X) already points along X
            return CFrame.new()
        elseif axis == "Y" then
            -- Rotate so PrimaryAxis (X) points along Y
            return CFrame.Angles(0, 0, math.rad(90))
        else -- Z
            -- Rotate so PrimaryAxis (X) points along Z
            return CFrame.Angles(0, math.rad(90), 0)
        end
    end

    --[[
        Private: Update hinge axis orientation.
    --]]
    local function updateHingeAxis(self)
        local state = getState(self)
        if not state.anchorAttachment or not state.modelAttachment then
            return
        end

        local axis = self:getAttribute("Axis") or "Y"
        local attachmentCFrame = getAttachmentCFrame(axis)

        state.anchorAttachment.CFrame = attachmentCFrame
        state.modelAttachment.CFrame = attachmentCFrame
    end

    --[[
        Private: Stop rotation.
    --]]
    local function stopRotation(self)
        local state = getState(self)
        if not state.hinge then
            warn("[Swivel] " .. self.id .. " - stopRotation: NO HINGE!")
            return
        end

        local wasRotating = state.rotating
        state.rotating = false

        -- Switch back to Servo mode and hold current angle
        state.hinge.ActuatorType = Enum.ActuatorType.Servo
        state.hinge.TargetAngle = state.hinge.CurrentAngle
        state.targetAngle = state.hinge.CurrentAngle

        if wasRotating then
            print("[Swivel] " .. self.id .. " - stopRotation: stopped at angle " .. state.hinge.CurrentAngle)
            self.Out:Fire("stopped", {})
        end
    end

    --[[
        Private: Set target angle (uses Servo mode).
    --]]
    local function setTargetAngle(self, targetAngle)
        local state = getState(self)
        if not state.hinge then return end

        local minAngle = self:getAttribute("MinAngle") or -180
        local maxAngle = self:getAttribute("MaxAngle") or 180

        -- Clamp to limits
        local clampedAngle = math.clamp(targetAngle, minAngle, maxAngle)
        state.targetAngle = clampedAngle

        -- Check for limit
        local hitLimit = nil
        if targetAngle <= minAngle then
            hitLimit = "min"
        elseif targetAngle >= maxAngle then
            hitLimit = "max"
        end

        -- Switch to Servo mode and set target
        state.hinge.ActuatorType = Enum.ActuatorType.Servo
        state.hinge.TargetAngle = clampedAngle
        state.rotating = false

        -- Emit limit signal if hit
        if hitLimit then
            self.Out:Fire("limitReached", { limit = hitLimit })
        end
    end

    --[[
        Private: Start continuous rotation (uses Motor mode).
    --]]
    local function startContinuousRotation(self)
        local state = getState(self)
        if not state.hinge then
            warn("[Swivel] " .. self.id .. " - startContinuousRotation: NO HINGE!")
            return
        end
        if not state.hinge.Parent then
            warn("[Swivel] " .. self.id .. " - startContinuousRotation: HINGE HAS NO PARENT!")
            return
        end

        state.rotating = true
        local speed = self:getAttribute("Speed") or 90

        -- Switch to Motor mode for continuous rotation
        state.hinge.ActuatorType = Enum.ActuatorType.Motor
        state.hinge.AngularVelocity = math.rad(speed) * state.direction

        print("[Swivel] " .. self.id .. " - startContinuousRotation: direction=" .. state.direction .. ", speed=" .. speed)
    end

    --[[
        Private: Stop monitoring and cleanup physics objects.
    --]]
    local function stopMonitoring(self)
        local state = getState(self)

        if state.monitorConnection then
            state.monitorConnection:Disconnect()
            state.monitorConnection = nil
        end

        -- Cleanup created objects
        if state.hinge then
            state.hinge:Destroy()
            state.hinge = nil
        end
        if state.anchorAttachment then
            state.anchorAttachment:Destroy()
            state.anchorAttachment = nil
        end
        if state.modelAttachment then
            state.modelAttachment:Destroy()
            state.modelAttachment = nil
        end
        if state.createdAnchor then
            state.createdAnchor:Destroy()
            state.createdAnchor = nil
        end
        if state.createdModel then
            state.createdModel:Destroy()
            state.createdModel = nil
        end
    end

    --[[
        Private: Start monitoring hinge angle for signals.
    --]]
    local function startMonitoring(self)
        local state = getState(self)
        if state.monitorConnection then return end

        local lastAngle = state.currentAngle
        local lastLimitSignal = nil

        state.monitorConnection = RunService.Heartbeat:Connect(function()
            if not state.hinge then return end

            local currentAngle = state.hinge.CurrentAngle
            state.currentAngle = currentAngle

            -- Emit rotated signal if angle changed significantly
            if math.abs(currentAngle - lastAngle) > 0.1 then
                self.Out:Fire("rotated", { angle = currentAngle })
                lastAngle = currentAngle
            end

            -- Check for limits during continuous rotation
            -- Only stop if rotating TOWARD the limit, not away from it
            if state.rotating then
                local minAngle = self:getAttribute("MinAngle") or -180
                local maxAngle = self:getAttribute("MaxAngle") or 180
                local direction = state.direction or 1

                -- Only trigger min limit if rotating toward min (direction < 0)
                if currentAngle <= minAngle + 0.5 and direction < 0 and lastLimitSignal ~= "min" then
                    lastLimitSignal = "min"
                    print("[Swivel] " .. self.id .. " - HIT MIN LIMIT at " .. currentAngle)
                    self.Out:Fire("limitReached", { limit = "min" })
                    stopRotation(self)
                -- Only trigger max limit if rotating toward max (direction > 0)
                elseif currentAngle >= maxAngle - 0.5 and direction > 0 and lastLimitSignal ~= "max" then
                    lastLimitSignal = "max"
                    print("[Swivel] " .. self.id .. " - HIT MAX LIMIT at " .. currentAngle)
                    self.Out:Fire("limitReached", { limit = "max" })
                    stopRotation(self)
                else
                    lastLimitSignal = nil
                end
            end
        end)
    end

    --[[
        Private: Set up the HingeConstraint between anchor and model.
    --]]
    local function setupHinge(self)
        local state = getState(self)

        local modelPart = self.model
        if modelPart and modelPart:IsA("Model") then
            modelPart = modelPart.PrimaryPart
            if not modelPart then
                warn("[Swivel] Model has no PrimaryPart, creating default")
            end
        end

        -- Create default model part if none provided
        if not modelPart then
            modelPart = Instance.new("Part")
            modelPart.Name = self.id .. "_SwivelModel"
            modelPart.Size = Vector3.new(1, 1, 1)
            modelPart.CFrame = CFrame.new(0, 10, 0)  -- Above ground
            modelPart.Anchored = false
            modelPart.CanCollide = false
            modelPart.Transparency = 1
            modelPart.Parent = workspace
            state.createdModel = modelPart
        end

        -- Get or create anchor
        local anchorPart = self.anchor
        if not anchorPart then
            -- Try to use parent as anchor, or create invisible anchor
            if modelPart.Parent and modelPart.Parent:IsA("BasePart") then
                anchorPart = modelPart.Parent
            else
                -- Create invisible anchor at model position
                anchorPart = Instance.new("Part")
                anchorPart.Name = self.id .. "_SwivelAnchor"
                anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
                anchorPart.CFrame = modelPart.CFrame
                anchorPart.Anchored = true
                anchorPart.CanCollide = false
                anchorPart.Transparency = 1
                anchorPart.Parent = modelPart.Parent or workspace
                state.createdAnchor = anchorPart
            end
        end

        -- Ensure model is unanchored for physics
        if modelPart.Anchored then
            modelPart.Anchored = false
        end

        -- Create attachments
        local axis = self:getAttribute("Axis") or "Y"
        local attachmentCFrame = getAttachmentCFrame(axis)

        state.anchorAttachment = Instance.new("Attachment")
        state.anchorAttachment.Name = "SwivelAnchor"
        state.anchorAttachment.CFrame = attachmentCFrame
        state.anchorAttachment.Parent = anchorPart

        state.modelAttachment = Instance.new("Attachment")
        state.modelAttachment.Name = "SwivelModel"
        state.modelAttachment.CFrame = attachmentCFrame
        state.modelAttachment.Parent = modelPart

        -- Create HingeConstraint
        state.hinge = Instance.new("HingeConstraint")
        state.hinge.Name = "SwivelHinge"
        state.hinge.Attachment0 = state.anchorAttachment
        state.hinge.Attachment1 = state.modelAttachment
        state.hinge.ActuatorType = Enum.ActuatorType.Servo
        state.hinge.AngularSpeed = math.rad(self:getAttribute("Speed") or 90)
        state.hinge.ServoMaxTorque = 100000
        state.hinge.MotorMaxTorque = 100000
        state.hinge.TargetAngle = 0
        state.hinge.LimitsEnabled = true
        state.hinge.LowerAngle = self:getAttribute("MinAngle") or -180
        state.hinge.UpperAngle = self:getAttribute("MaxAngle") or 180
        state.hinge.Parent = anchorPart
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "Swivel",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Default attributes
                if not self:getAttribute("Axis") then
                    self:setAttribute("Axis", "Y")
                end
                if not self:getAttribute("Mode") then
                    self:setAttribute("Mode", "continuous")
                end
                if not self:getAttribute("Speed") then
                    self:setAttribute("Speed", 90)
                end
                if not self:getAttribute("StepSize") then
                    self:setAttribute("StepSize", 5)
                end
                if not self:getAttribute("MinAngle") then
                    self:setAttribute("MinAngle", -180)
                end
                if not self:getAttribute("MaxAngle") then
                    self:setAttribute("MaxAngle", 180)
                end

                -- Set up physics constraint
                setupHinge(self)
            end,

            onStart = function(self)
                -- Start monitoring hinge angle for signals
                startMonitoring(self)
            end,

            onStop = function(self)
                stopRotation(self)
                stopMonitoring(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Configure swivel settings.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.axis then
                    local axis = string.upper(data.axis)
                    if axis == "X" or axis == "Y" or axis == "Z" then
                        self:setAttribute("Axis", axis)
                        -- Reconfigure hinge axis
                        updateHingeAxis(self)
                    end
                end

                if data.mode then
                    local mode = string.lower(data.mode)
                    if mode == "continuous" or mode == "stepped" then
                        self:setAttribute("Mode", mode)
                    end
                end

                if data.speed then
                    self:setAttribute("Speed", math.abs(data.speed))
                    -- Update hinge speed
                    if state.hinge then
                        state.hinge.AngularSpeed = math.rad(data.speed)
                    end
                end

                if data.stepSize then
                    self:setAttribute("StepSize", math.abs(data.stepSize))
                end

                if data.minAngle then
                    self:setAttribute("MinAngle", data.minAngle)
                    if state.hinge then
                        state.hinge.LowerAngle = data.minAngle
                    end
                end

                if data.maxAngle then
                    self:setAttribute("MaxAngle", data.maxAngle)
                    if state.hinge then
                        state.hinge.UpperAngle = data.maxAngle
                    end
                end
            end,

            --[[
                Start rotating in a direction.
                Continuous mode: uses Motor actuator type
                Stepped mode: uses Servo to move one increment
            --]]
            onRotate = function(self, data)
                data = data or {}
                local state = getState(self)
                local direction = data.direction or "forward"
                state.direction = direction == "forward" and 1 or -1

                local mode = self:getAttribute("Mode") or "continuous"

                if mode == "continuous" then
                    startContinuousRotation(self)
                else
                    -- Stepped mode: rotate one increment using servo
                    local stepSize = self:getAttribute("StepSize") or 5
                    local targetAngle = state.currentAngle + (stepSize * state.direction)
                    setTargetAngle(self, targetAngle)
                end
            end,

            --[[
                Set angle directly using servo.
            --]]
            onSetAngle = function(self, data)
                if not data or data.degrees == nil then return end
                setTargetAngle(self, data.degrees)
            end,

            --[[
                Stop continuous rotation.
            --]]
            onStop = function(self)
                stopRotation(self)
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            rotated = {},      -- { angle: number }
            limitReached = {}, -- { limit: "min" | "max" }
            stopped = {},      -- {}
        },

    }
end)

return Swivel
