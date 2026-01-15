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

local Swivel = Node.extend({
    name = "Swivel",
    domain = "server",

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Current state
            self._currentAngle = 0
            self._targetAngle = 0
            self._rotating = false
            self._direction = 1  -- 1 = forward, -1 = reverse

            -- Physics objects
            self._hinge = nil
            self._anchorAttachment = nil
            self._modelAttachment = nil
            self._monitorConnection = nil

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
            self:_setupHinge()
        end,

        onStart = function(self)
            -- Start monitoring hinge angle for signals
            self:_startMonitoring()
        end,

        onStop = function(self)
            self:_stopRotation()
            self:_stopMonitoring()
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

    In = {
        --[[
            Configure swivel settings.
        --]]
        onConfigure = function(self, data)
            if not data then return end

            if data.axis then
                local axis = string.upper(data.axis)
                if axis == "X" or axis == "Y" or axis == "Z" then
                    self:setAttribute("Axis", axis)
                    -- Reconfigure hinge axis
                    self:_updateHingeAxis()
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
                if self._hinge then
                    self._hinge.AngularSpeed = math.rad(data.speed)
                end
            end

            if data.stepSize then
                self:setAttribute("StepSize", math.abs(data.stepSize))
            end

            if data.minAngle then
                self:setAttribute("MinAngle", data.minAngle)
                if self._hinge then
                    self._hinge.LowerAngle = data.minAngle
                end
            end

            if data.maxAngle then
                self:setAttribute("MaxAngle", data.maxAngle)
                if self._hinge then
                    self._hinge.UpperAngle = data.maxAngle
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
            local direction = data.direction or "forward"
            self._direction = direction == "forward" and 1 or -1

            local mode = self:getAttribute("Mode") or "continuous"

            if mode == "continuous" then
                self:_startContinuousRotation()
            else
                -- Stepped mode: rotate one increment using servo
                local stepSize = self:getAttribute("StepSize") or 5
                local targetAngle = self._currentAngle + (stepSize * self._direction)
                self:_setTargetAngle(targetAngle)
            end
        end,

        --[[
            Set angle directly using servo.
        --]]
        onSetAngle = function(self, data)
            if not data or data.degrees == nil then return end
            self:_setTargetAngle(data.degrees)
        end,

        --[[
            Stop continuous rotation.
        --]]
        onStop = function(self)
            self:_stopRotation()
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA
    ----------------------------------------------------------------------------

    Out = {
        rotated = {},      -- { angle: number }
        limitReached = {}, -- { limit: "min" | "max" }
        stopped = {},      -- {}
    },

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    --[[
        Set up the HingeConstraint between anchor and model.
    --]]
    _setupHinge = function(self)
        if not self.model then
            warn("[Swivel] No model provided")
            return
        end

        local modelPart = self.model
        if self.model:IsA("Model") then
            modelPart = self.model.PrimaryPart
            if not modelPart then
                warn("[Swivel] Model has no PrimaryPart")
                return
            end
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
                self._createdAnchor = anchorPart
            end
        end

        -- Ensure model is unanchored for physics
        if modelPart.Anchored then
            modelPart.Anchored = false
        end

        -- Create attachments
        local axis = self:getAttribute("Axis") or "Y"
        local attachmentCFrame = self:_getAttachmentCFrame(axis)

        self._anchorAttachment = Instance.new("Attachment")
        self._anchorAttachment.Name = "SwivelAnchor"
        self._anchorAttachment.CFrame = attachmentCFrame
        self._anchorAttachment.Parent = anchorPart

        self._modelAttachment = Instance.new("Attachment")
        self._modelAttachment.Name = "SwivelModel"
        self._modelAttachment.CFrame = attachmentCFrame
        self._modelAttachment.Parent = modelPart

        -- Create HingeConstraint
        self._hinge = Instance.new("HingeConstraint")
        self._hinge.Name = "SwivelHinge"
        self._hinge.Attachment0 = self._anchorAttachment
        self._hinge.Attachment1 = self._modelAttachment
        self._hinge.ActuatorType = Enum.ActuatorType.Servo
        self._hinge.AngularSpeed = math.rad(self:getAttribute("Speed") or 90)
        self._hinge.ServoMaxTorque = 100000
        self._hinge.MotorMaxTorque = 100000
        self._hinge.TargetAngle = 0
        self._hinge.LimitsEnabled = true
        self._hinge.LowerAngle = self:getAttribute("MinAngle") or -180
        self._hinge.UpperAngle = self:getAttribute("MaxAngle") or 180
        self._hinge.Parent = anchorPart
    end,

    --[[
        Get attachment CFrame for the given axis.
        Rotates attachment so PrimaryAxis aligns with rotation axis.
    --]]
    _getAttachmentCFrame = function(self, axis)
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
    end,

    --[[
        Update hinge axis orientation.
    --]]
    _updateHingeAxis = function(self)
        if not self._anchorAttachment or not self._modelAttachment then
            return
        end

        local axis = self:getAttribute("Axis") or "Y"
        local attachmentCFrame = self:_getAttachmentCFrame(axis)

        self._anchorAttachment.CFrame = attachmentCFrame
        self._modelAttachment.CFrame = attachmentCFrame
    end,

    --[[
        Set target angle (uses Servo mode).
    --]]
    _setTargetAngle = function(self, targetAngle)
        if not self._hinge then return end

        local minAngle = self:getAttribute("MinAngle") or -180
        local maxAngle = self:getAttribute("MaxAngle") or 180

        -- Clamp to limits
        local clampedAngle = math.clamp(targetAngle, minAngle, maxAngle)
        self._targetAngle = clampedAngle

        -- Check for limit
        local hitLimit = nil
        if targetAngle <= minAngle then
            hitLimit = "min"
        elseif targetAngle >= maxAngle then
            hitLimit = "max"
        end

        -- Switch to Servo mode and set target
        self._hinge.ActuatorType = Enum.ActuatorType.Servo
        self._hinge.TargetAngle = clampedAngle
        self._rotating = false

        -- Emit limit signal if hit
        if hitLimit then
            self.Out:Fire("limitReached", { limit = hitLimit })
        end
    end,

    --[[
        Start continuous rotation (uses Motor mode).
    --]]
    _startContinuousRotation = function(self)
        if not self._hinge then return end

        self._rotating = true
        local speed = self:getAttribute("Speed") or 90

        -- Switch to Motor mode for continuous rotation
        self._hinge.ActuatorType = Enum.ActuatorType.Motor
        self._hinge.AngularVelocity = math.rad(speed) * self._direction
    end,

    --[[
        Stop rotation.
    --]]
    _stopRotation = function(self)
        if not self._hinge then return end

        local wasRotating = self._rotating
        self._rotating = false

        -- Switch back to Servo mode and hold current angle
        self._hinge.ActuatorType = Enum.ActuatorType.Servo
        self._hinge.TargetAngle = self._hinge.CurrentAngle
        self._targetAngle = self._hinge.CurrentAngle

        if wasRotating then
            self.Out:Fire("stopped", {})
        end
    end,

    --[[
        Start monitoring hinge angle for signals.
    --]]
    _startMonitoring = function(self)
        if self._monitorConnection then return end

        local lastAngle = self._currentAngle
        local lastLimitSignal = nil

        self._monitorConnection = RunService.Heartbeat:Connect(function()
            if not self._hinge then return end

            local currentAngle = self._hinge.CurrentAngle
            self._currentAngle = currentAngle

            -- Emit rotated signal if angle changed significantly
            if math.abs(currentAngle - lastAngle) > 0.1 then
                self.Out:Fire("rotated", { angle = currentAngle })
                lastAngle = currentAngle
            end

            -- Check for limits during continuous rotation
            if self._rotating then
                local minAngle = self:getAttribute("MinAngle") or -180
                local maxAngle = self:getAttribute("MaxAngle") or 180

                if currentAngle <= minAngle + 0.5 and lastLimitSignal ~= "min" then
                    lastLimitSignal = "min"
                    self.Out:Fire("limitReached", { limit = "min" })
                    self:_stopRotation()
                elseif currentAngle >= maxAngle - 0.5 and lastLimitSignal ~= "max" then
                    lastLimitSignal = "max"
                    self.Out:Fire("limitReached", { limit = "max" })
                    self:_stopRotation()
                else
                    lastLimitSignal = nil
                end
            end
        end)
    end,

    --[[
        Stop monitoring.
    --]]
    _stopMonitoring = function(self)
        if self._monitorConnection then
            self._monitorConnection:Disconnect()
            self._monitorConnection = nil
        end

        -- Cleanup created objects
        if self._hinge then
            self._hinge:Destroy()
            self._hinge = nil
        end
        if self._anchorAttachment then
            self._anchorAttachment:Destroy()
            self._anchorAttachment = nil
        end
        if self._modelAttachment then
            self._modelAttachment:Destroy()
            self._modelAttachment = nil
        end
        if self._createdAnchor then
            self._createdAnchor:Destroy()
            self._createdAnchor = nil
        end
    end,

    --[[
        Get current angle.
    --]]
    getCurrentAngle = function(self)
        if self._hinge then
            return self._hinge.CurrentAngle
        end
        return self._currentAngle
    end,

    --[[
        Check if currently rotating.
    --]]
    isRotating = function(self)
        return self._rotating
    end,

    --[[
        Check if servo has reached target (within tolerance).
    --]]
    isAtTarget = function(self)
        if not self._hinge then return true end
        return math.abs(self._hinge.CurrentAngle - self._targetAngle) < 1
    end,

    --[[
        Get the HingeConstraint (for advanced usage).
    --]]
    getHinge = function(self)
        return self._hinge
    end,
})

return Swivel
