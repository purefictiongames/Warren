--[[
    LibPureFiction Framework v2
    SwivelDemoOrchestrator.lua - Extended Orchestrator for Swivel Demo

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    SwivelDemoOrchestrator manages a turret-style dual-swivel system:
    - Yaw swivel: Rotates left/right (Y-axis)
    - Pitch swivel: Rotates up/down (X-axis), mounted on yaw swivel

    The pitch swivel is anchored to the yaw swivel's model, so it follows
    the yaw rotation while independently controlling pitch.

    This follows the proper architecture:
    - Extends Orchestrator (not ad-hoc configuration)
    - All control via In signals (no public methods)
    - All state broadcast via Out signals (no query methods)
    - Managed Swivels are encapsulated (external code never sees them)

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onRotateYaw({ direction: "forward" | "reverse" })
            - Rotate left/right

        onRotatePitch({ direction: "forward" | "reverse" })
            - Rotate up/down (forward = up, reverse = down)

        onStopYaw({})
            - Stop yaw rotation

        onStopPitch({})
            - Stop pitch rotation

        onStop({})
            - Stop both rotations

        onConfigure({ yawSpeed?, pitchSpeed?, yawMinAngle?, yawMaxAngle?, pitchMinAngle?, pitchMaxAngle? })
            - Update swivel speeds and angle limits at runtime

    OUT (emits):
        yawRotated({ angle: number })
        pitchRotated({ angle: number })
        yawLimitReached({ limit: "min" | "max" })
        pitchLimitReached({ limit: "min" | "max" })
        yawStopped({})
        pitchStopped({})

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local orchestrator = SwivelDemoOrchestrator:new({
        id = "Demo_Orchestrator",
        model = yawPart,          -- The yaw (base) rotating part
        attributes = {
            pitchModel = pitchPart,  -- The pitch part (sits on yaw)
            yawConfig = { speed = 45, minAngle = -90, maxAngle = 90 },
            pitchConfig = { speed = 30, minAngle = -30, maxAngle = 60 },
        },
    })
    ```

--]]

local Orchestrator = require(script.Parent.Orchestrator)

--------------------------------------------------------------------------------
-- SWIVEL DEMO ORCHESTRATOR (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local SwivelDemoOrchestrator = Orchestrator.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                yawSwivel = nil,
                pitchSwivel = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    local function setupSignalForwarding(self, swivel, prefix)
        local originalFire = swivel.Out.Fire
        local orchestrator = self

        swivel.Out.Fire = function(outSelf, signal, data)
            -- Forward with prefix (e.g., "rotated" -> "yawRotated")
            if signal == "rotated" then
                orchestrator.Out:Fire(prefix .. "Rotated", data)
            elseif signal == "limitReached" then
                orchestrator.Out:Fire(prefix .. "LimitReached", data)
            elseif signal == "stopped" then
                orchestrator.Out:Fire(prefix .. "Stopped", data)
            end
            originalFire(outSelf, signal, data)
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "SwivelDemoOrchestrator",
        domain = "server",

        Sys = {
            onInit = function(self)
                parent.Sys.onInit(self)

                local yawConfig = self:getAttribute("yawConfig") or {}
                local pitchConfig = self:getAttribute("pitchConfig") or {}
                local pitchModel = self:getAttribute("pitchModel")

                local Swivel = require(script.Parent.Swivel)
                local state = getState(self)

                -- Create Yaw Swivel (Y-axis, left/right)
                -- No anchor provided - creates invisible anchor
                state.yawSwivel = Swivel:new({
                    id = self.id .. "_YawSwivel",
                    model = self.model,
                })
                state.yawSwivel.Sys.onInit(state.yawSwivel)
                state.yawSwivel.In.onConfigure(state.yawSwivel, {
                    axis = "Y",
                    mode = "continuous",
                    speed = yawConfig.speed or 45,
                    minAngle = yawConfig.minAngle or -90,
                    maxAngle = yawConfig.maxAngle or 90,
                })

                -- Create Pitch Swivel (X-axis, up/down)
                -- Anchored to yaw model - follows yaw rotation
                if pitchModel then
                    state.pitchSwivel = Swivel:new({
                        id = self.id .. "_PitchSwivel",
                        model = pitchModel,
                    })
                    -- CRITICAL: Anchor pitch to yaw's model
                    state.pitchSwivel.anchor = self.model

                    state.pitchSwivel.Sys.onInit(state.pitchSwivel)
                    state.pitchSwivel.In.onConfigure(state.pitchSwivel, {
                        axis = "X",
                        mode = "continuous",
                        speed = pitchConfig.speed or 30,
                        minAngle = pitchConfig.minAngle or -30,
                        maxAngle = pitchConfig.maxAngle or 60,
                    })
                end

                -- Set up signal forwarding
                setupSignalForwarding(self, state.yawSwivel, "yaw")
                if state.pitchSwivel then
                    setupSignalForwarding(self, state.pitchSwivel, "pitch")
                end
            end,

            onStart = function(self)
                local state = getState(self)
                if state.yawSwivel then
                    state.yawSwivel.Sys.onStart(state.yawSwivel)
                end
                if state.pitchSwivel then
                    state.pitchSwivel.Sys.onStart(state.pitchSwivel)
                end
            end,

            onStop = function(self)
                local state = getState(self)
                if state.yawSwivel then
                    state.yawSwivel.Sys.onStop(state.yawSwivel)
                end
                if state.pitchSwivel then
                    state.pitchSwivel.Sys.onStop(state.pitchSwivel)
                end
                cleanupState(self)
            end,
        },

        In = {
            onRotateYaw = function(self, data)
                local state = getState(self)
                if state.yawSwivel then
                    state.yawSwivel.In.onRotate(state.yawSwivel, data)
                end
            end,

            onRotatePitch = function(self, data)
                local state = getState(self)
                if state.pitchSwivel then
                    state.pitchSwivel.In.onRotate(state.pitchSwivel, data)
                end
            end,

            onStopYaw = function(self, data)
                local state = getState(self)
                if state.yawSwivel then
                    state.yawSwivel.In.onStop(state.yawSwivel)
                end
            end,

            onStopPitch = function(self, data)
                local state = getState(self)
                if state.pitchSwivel then
                    state.pitchSwivel.In.onStop(state.pitchSwivel)
                end
            end,

            onStop = function(self, data)
                local state = getState(self)
                if state.yawSwivel then
                    state.yawSwivel.In.onStop(state.yawSwivel)
                end
                if state.pitchSwivel then
                    state.pitchSwivel.In.onStop(state.pitchSwivel)
                end
            end,

            -- Direct angle control
            onSetYawAngle = function(self, data)
                local state = getState(self)
                if state.yawSwivel then
                    state.yawSwivel.In.onSetAngle(state.yawSwivel, data)
                end
            end,

            onSetPitchAngle = function(self, data)
                local state = getState(self)
                if state.pitchSwivel then
                    state.pitchSwivel.In.onSetAngle(state.pitchSwivel, data)
                end
            end,

            -- Keep old handlers for backwards compatibility with single-swivel
            onRotate = function(self, data)
                local state = getState(self)
                if state.yawSwivel then
                    state.yawSwivel.In.onRotate(state.yawSwivel, data)
                end
            end,

            onSetAngle = function(self, data)
                local state = getState(self)
                if state.yawSwivel then
                    state.yawSwivel.In.onSetAngle(state.yawSwivel, data)
                end
            end,

            --[[
                Configure swivel settings at runtime.
                Supports: yawSpeed, pitchSpeed, yawMinAngle, yawMaxAngle, pitchMinAngle, pitchMaxAngle
            --]]
            onConfigure = function(self, data)
                if not data then return end
                local state = getState(self)

                -- Forward yaw config
                if state.yawSwivel then
                    local yawConfig = {}
                    if data.yawSpeed then yawConfig.speed = data.yawSpeed end
                    if data.yawMinAngle then yawConfig.minAngle = data.yawMinAngle end
                    if data.yawMaxAngle then yawConfig.maxAngle = data.yawMaxAngle end
                    if next(yawConfig) then
                        state.yawSwivel.In.onConfigure(state.yawSwivel, yawConfig)
                    end
                end

                -- Forward pitch config
                if state.pitchSwivel then
                    local pitchConfig = {}
                    if data.pitchSpeed then pitchConfig.speed = data.pitchSpeed end
                    if data.pitchMinAngle then pitchConfig.minAngle = data.pitchMinAngle end
                    if data.pitchMaxAngle then pitchConfig.maxAngle = data.pitchMaxAngle end
                    if next(pitchConfig) then
                        state.pitchSwivel.In.onConfigure(state.pitchSwivel, pitchConfig)
                    end
                end
            end,
        },

        Out = {
            yawRotated = {},
            pitchRotated = {},
            yawLimitReached = {},
            pitchLimitReached = {},
            yawStopped = {},
            pitchStopped = {},
            -- Keep old signals for backwards compatibility
            rotated = {},
            limitReached = {},
            stopped = {},
        },
    }
end)

return SwivelDemoOrchestrator
