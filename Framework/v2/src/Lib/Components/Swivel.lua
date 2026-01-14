--[[
    LibPureFiction Framework v2
    Swivel.lua - Single-Axis Rotation Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Swivel provides single-axis rotation control. Like a servo motor, it rotates
    a Part or Model around one axis with configurable limits and speed.

    Used for:
    - Turret yaw/pitch control
    - Searchlight sweep
    - Door hinges
    - Any single-axis rotation need

    ============================================================================
    MODES
    ============================================================================

    continuous:
        Rotates while signal active, stops on onStop.
        Use for smooth tracking with natural play.

    stepped:
        Fixed increment per onRotate signal.
        Use for precise positioning.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onRotate({ direction: "forward" | "reverse" })
            - Continuous: starts rotating until onStop
            - Stepped: rotates one StepSize increment

        onSetAngle({ degrees: number })
            - Direct positioning (both modes)
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

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Axis: string (default "Y")
        Rotation axis: "X", "Y", or "Z"

    Mode: string (default "continuous")
        "continuous" or "stepped"

    Speed: number (default 90)
        Degrees per second (continuous mode)

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
    local swivel = Swivel:new({ model = workspace.TurretBase })
    swivel.Sys.onInit(swivel)
    swivel.In.onConfigure(swivel, {
        axis = "Y",
        mode = "continuous",
        speed = 90,
        minAngle = -90,
        maxAngle = 90,
    })

    -- Start rotating
    swivel.In.onRotate(swivel, { direction = "forward" })

    -- Later, stop
    swivel.In.onStop(swivel)

    -- Or set directly
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
            self._rotating = false
            self._direction = 1  -- 1 = forward, -1 = reverse
            self._heartbeatConnection = nil

            -- Store initial CFrame for rotation calculations
            self._initialCFrame = nil
            if self.model then
                if self.model:IsA("BasePart") then
                    self._initialCFrame = self.model.CFrame
                elseif self.model:IsA("Model") and self.model.PrimaryPart then
                    self._initialCFrame = self.model.PrimaryPart.CFrame
                end
            end

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
        end,

        onStart = function(self)
            -- Nothing additional on start
        end,

        onStop = function(self)
            -- Stop rotation on system stop
            self:_stopRotation()
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
            end

            if data.stepSize then
                self:setAttribute("StepSize", math.abs(data.stepSize))
            end

            if data.minAngle then
                self:setAttribute("MinAngle", data.minAngle)
            end

            if data.maxAngle then
                self:setAttribute("MaxAngle", data.maxAngle)
            end
        end,

        --[[
            Start rotating in a direction.
            Continuous mode: starts rotating until onStop
            Stepped mode: rotates one StepSize increment
        --]]
        onRotate = function(self, data)
            data = data or {}
            local direction = data.direction or "forward"
            self._direction = direction == "forward" and 1 or -1

            local mode = self:getAttribute("Mode") or "continuous"

            if mode == "continuous" then
                self:_startRotation()
            else
                -- Stepped mode: rotate one increment
                local stepSize = self:getAttribute("StepSize") or 5
                local targetAngle = self._currentAngle + (stepSize * self._direction)
                self:_setAngle(targetAngle)
            end
        end,

        --[[
            Set angle directly.
        --]]
        onSetAngle = function(self, data)
            if not data or data.degrees == nil then return end
            self:_setAngle(data.degrees)
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
    },

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    --[[
        Get the rotation CFrame for a given angle on the configured axis.
    --]]
    _getRotationCFrame = function(self, angleDegrees)
        local axis = self:getAttribute("Axis") or "Y"
        local angleRadians = math.rad(angleDegrees)

        if axis == "X" then
            return CFrame.Angles(angleRadians, 0, 0)
        elseif axis == "Y" then
            return CFrame.Angles(0, angleRadians, 0)
        else -- Z
            return CFrame.Angles(0, 0, angleRadians)
        end
    end,

    --[[
        Apply rotation to the model.
    --]]
    _applyRotation = function(self)
        if not self.model or not self._initialCFrame then
            return
        end

        local rotationCFrame = self:_getRotationCFrame(self._currentAngle)
        local newCFrame = self._initialCFrame * rotationCFrame

        if self.model:IsA("BasePart") then
            self.model.CFrame = newCFrame
        elseif self.model:IsA("Model") and self.model.PrimaryPart then
            self.model:SetPrimaryPartCFrame(newCFrame)
        end
    end,

    --[[
        Set angle with clamping and limit detection.
    --]]
    _setAngle = function(self, targetAngle)
        local minAngle = self:getAttribute("MinAngle") or -180
        local maxAngle = self:getAttribute("MaxAngle") or 180

        -- Clamp to limits
        local clampedAngle = math.clamp(targetAngle, minAngle, maxAngle)
        local hitLimit = nil

        if targetAngle <= minAngle then
            hitLimit = "min"
        elseif targetAngle >= maxAngle then
            hitLimit = "max"
        end

        -- Update angle
        local previousAngle = self._currentAngle
        self._currentAngle = clampedAngle

        -- Apply rotation to model
        self:_applyRotation()

        -- Emit rotated signal if angle changed
        if previousAngle ~= clampedAngle then
            self.Out:Fire("rotated", { angle = self._currentAngle })
        end

        -- Emit limitReached if hit boundary
        if hitLimit then
            self.Out:Fire("limitReached", { limit = hitLimit })
            -- Stop rotation if we hit a limit during continuous mode
            if self._rotating then
                self:_stopRotation()
            end
        end
    end,

    --[[
        Start continuous rotation.
    --]]
    _startRotation = function(self)
        if self._rotating then
            return
        end

        self._rotating = true

        -- Connect to Heartbeat for smooth rotation
        self._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
            if not self._rotating then
                return
            end

            local speed = self:getAttribute("Speed") or 90
            local deltaAngle = speed * deltaTime * self._direction
            local targetAngle = self._currentAngle + deltaAngle

            self:_setAngle(targetAngle)
        end)
    end,

    --[[
        Stop continuous rotation.
    --]]
    _stopRotation = function(self)
        if not self._rotating then
            return
        end

        self._rotating = false

        if self._heartbeatConnection then
            self._heartbeatConnection:Disconnect()
            self._heartbeatConnection = nil
        end
    end,

    --[[
        Get current angle (for external queries).
    --]]
    getCurrentAngle = function(self)
        return self._currentAngle
    end,

    --[[
        Check if currently rotating.
    --]]
    isRotating = function(self)
        return self._rotating
    end,
})

return Swivel
