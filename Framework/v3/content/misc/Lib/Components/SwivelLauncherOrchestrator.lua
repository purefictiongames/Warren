--[[
    LibPureFiction Framework v2
    SwivelLauncherOrchestrator.lua - Combined Swivel Turret + Launcher System

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    SwivelLauncherOrchestrator is a composite orchestrator that combines:
    - SwivelDemoOrchestrator: Controls yaw/pitch swivels
    - LauncherDemoOrchestrator: Controls launcher, magazine, and battery

    This follows the hierarchical orchestrator pattern:
    - Main orchestrator controls sub-orchestrators
    - Sub-orchestrators control their own primitives
    - Signals cascade down the tree

    Physical assembly:
    - Yaw swivel (base rotation)
    - Pitch swivel (mounted on yaw)
    - Launcher muzzle (welded to pitch)
    - Magazine + Battery (welded to muzzle, managed by LauncherDemoOrchestrator)

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        -- Swivel control (forwarded to SwivelDemoOrchestrator)
        onRotateYaw({ direction })
        onRotatePitch({ direction })
        onSetYawAngle({ degrees })    -- via onSetAngle
        onSetPitchAngle({ degrees })  -- via onSetAngle on pitch
        onStopYaw({})
        onStopPitch({})
        onStop({})

        -- Launcher control (forwarded to LauncherDemoOrchestrator)
        onFire({ targetPosition? })
        onTriggerDown({ targetPosition? })
        onTriggerUp({})
        onReload({})
        onConfigure({ fireMode?, cooldown?, yawSpeed?, pitchSpeed?, ... })
            - Swivel params forwarded to SwivelDemoOrchestrator
            - Launcher params forwarded to LauncherDemoOrchestrator

    OUT (emits):
        -- Swivel signals (from SwivelDemoOrchestrator)
        yawRotated({ angle })
        pitchRotated({ angle })
        yawLimitReached({ limit })
        pitchLimitReached({ limit })
        yawStopped({})
        pitchStopped({})

        -- Launcher signals (from LauncherDemoOrchestrator)
        fired, ready, ammoChanged, reloadStarted, reloadComplete, magazineEmpty
        beamStart, beamEnd, heatChanged, overheated, cooledDown
        powerChanged, powerDepleted, powerRestored

    ============================================================================
    ATTRIBUTES
    ============================================================================

    -- Required
    pitchModel: Part or Model
        The pitch part that mounts on the yaw swivel

    -- Swivel config (passed to SwivelDemoOrchestrator)
    yawConfig: { speed?, minAngle?, maxAngle? }
    pitchConfig: { speed?, minAngle?, maxAngle? }

    -- Launcher config (passed to LauncherDemoOrchestrator)
    fireMode, cooldown, projectileComponent, magazineCapacity, reloadTime
    beamComponent, beamMaxHeat, beamHeatRate, beamCoolRate
    batteryCapacity, batteryRechargeRate

    -- Visual
    launcherSize: Vector3 (default 1.5, 1.5, 3)

--]]

local Orchestrator = require(script.Parent.Orchestrator)

--------------------------------------------------------------------------------
-- SWIVEL LAUNCHER ORCHESTRATOR (Hierarchical Composition Pattern)
--------------------------------------------------------------------------------

local SwivelLauncherOrchestrator = Orchestrator.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                swivelOrchestrator = nil,
                launcherOrchestrator = nil,
                muzzlePart = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state and state.muzzlePart then
            state.muzzlePart:Destroy()
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "SwivelLauncherOrchestrator",
        domain = "server",

        Sys = {
            onInit = function(self)
                parent.Sys.onInit(self)

                local config = self._attributes or {}
                local state = getState(self)

                -- Import sub-orchestrators
                local SwivelDemoOrchestrator = require(script.Parent.SwivelDemoOrchestrator)
                local LauncherDemoOrchestrator = require(script.Parent.LauncherDemoOrchestrator)

                local pitchModel = config.pitchModel

                ----------------------------------------------------------------
                -- CREATE MUZZLE (welded to pitch swivel)
                ----------------------------------------------------------------

                local launcherSize = config.launcherSize or Vector3.new(1.5, 1.5, 3)
                local pitchPart = pitchModel
                if pitchModel and pitchModel:IsA("Model") then
                    pitchPart = pitchModel.PrimaryPart or pitchModel:FindFirstChildWhichIsA("BasePart")
                end

                local muzzle = Instance.new("Part")
                muzzle.Name = self.id .. "_Muzzle"
                muzzle.Size = launcherSize
                muzzle.CanCollide = false
                muzzle.BrickColor = BrickColor.new("Bright blue")
                muzzle.Material = Enum.Material.SmoothPlastic

                if pitchPart then
                    local offset = config.launcherOffset or CFrame.new(0, 0, -pitchPart.Size.Z / 2 - launcherSize.Z / 2)
                    muzzle.CFrame = pitchPart.CFrame * offset
                    muzzle.Anchored = false
                    muzzle.Parent = pitchPart.Parent or workspace

                    local weld = Instance.new("WeldConstraint")
                    weld.Part0 = pitchPart
                    weld.Part1 = muzzle
                    weld.Parent = muzzle
                else
                    muzzle.Position = Vector3.new(0, 5, 0)
                    muzzle.Anchored = true
                    muzzle.Parent = workspace
                end

                state.muzzlePart = muzzle

                ----------------------------------------------------------------
                -- CREATE SUB-ORCHESTRATOR: Swivel
                ----------------------------------------------------------------

                state.swivelOrchestrator = SwivelDemoOrchestrator:new({
                    id = self.id .. "_Swivel",
                    model = self.model,  -- yaw part
                    attributes = {
                        pitchModel = pitchModel,
                        yawConfig = config.yawConfig or {
                            speed = 60,
                            minAngle = -180,
                            maxAngle = 180,
                        },
                        pitchConfig = config.pitchConfig or {
                            speed = 45,
                            minAngle = -30,
                            maxAngle = 60,
                        },
                    },
                })
                state.swivelOrchestrator.Sys.onInit(state.swivelOrchestrator)

                ----------------------------------------------------------------
                -- CREATE SUB-ORCHESTRATOR: Launcher
                ----------------------------------------------------------------

                state.launcherOrchestrator = LauncherDemoOrchestrator:new({
                    id = self.id .. "_Launcher",
                    model = muzzle,
                    attributes = {
                        fireMode = config.fireMode or "auto",
                        cooldown = config.cooldown or 0.1,
                        projectileComponent = config.projectileComponent or "Tracer",
                        magazineCapacity = config.magazineCapacity or 30,
                        reloadTime = config.reloadTime or 1.5,
                        beamComponent = config.beamComponent or "PlasmaBeam",
                        beamIntensity = config.beamIntensity or 1.0,
                        beamMaxHeat = config.beamMaxHeat or 100,
                        beamHeatRate = config.beamHeatRate or 25,
                        beamCoolRate = config.beamCoolRate or 15,
                        beamPowerCapacity = config.beamPowerCapacity or 100,
                        beamPowerDrainRate = config.beamPowerDrainRate or 20,
                        beamPowerRechargeRate = config.beamPowerRechargeRate or 10,
                        batteryCapacity = config.batteryCapacity or 100,
                        batteryRechargeRate = config.batteryRechargeRate or 15,
                    },
                })
                state.launcherOrchestrator.Sys.onInit(state.launcherOrchestrator)

                ----------------------------------------------------------------
                -- SIGNAL FORWARDING: Sub-orchestrators -> Main Out
                ----------------------------------------------------------------

                -- Forward Swivel signals
                local swivelOriginalFire = state.swivelOrchestrator.Out.Fire
                state.swivelOrchestrator.Out.Fire = function(outSelf, signal, data)
                    -- Forward swivel signals to main orchestrator's Out
                    if signal == "yawRotated" or signal == "pitchRotated" or
                       signal == "yawLimitReached" or signal == "pitchLimitReached" or
                       signal == "yawStopped" or signal == "pitchStopped" then
                        self.Out:Fire(signal, data)
                    end
                    swivelOriginalFire(outSelf, signal, data)
                end

                -- Forward Launcher signals
                local launcherOriginalFire = state.launcherOrchestrator.Out.Fire
                state.launcherOrchestrator.Out.Fire = function(outSelf, signal, data)
                    -- Forward launcher signals to main orchestrator's Out
                    local forwardSignals = {
                        "fired", "ready", "ammoChanged", "reloadStarted", "reloadComplete",
                        "magazineEmpty", "beamStart", "beamEnd", "heatChanged", "overheated",
                        "cooledDown", "powerChanged", "powerDepleted", "powerRestored",
                        -- Targeter signals
                        "targetAcquired", "targetTracking", "targetLost",
                    }
                    for _, fwd in ipairs(forwardSignals) do
                        if signal == fwd then
                            self.Out:Fire(signal, data)
                            break
                        end
                    end
                    launcherOriginalFire(outSelf, signal, data)
                end
            end,

            onStart = function(self)
                parent.Sys.onStart(self)
                local state = getState(self)

                -- Start sub-orchestrators
                if state.swivelOrchestrator then
                    state.swivelOrchestrator.Sys.onStart(state.swivelOrchestrator)
                end
                if state.launcherOrchestrator then
                    state.launcherOrchestrator.Sys.onStart(state.launcherOrchestrator)
                end
            end,

            onStop = function(self)
                local state = getState(self)

                -- Stop sub-orchestrators (they handle their own primitives)
                if state.launcherOrchestrator then
                    state.launcherOrchestrator.Sys.onStop(state.launcherOrchestrator)
                end
                if state.swivelOrchestrator then
                    state.swivelOrchestrator.Sys.onStop(state.swivelOrchestrator)
                end

                cleanupState(self)
                parent.Sys.onStop(self)
            end,
        },

        In = {
            ----------------------------------------------------------------
            -- SWIVEL CONTROL (forwarded to SwivelDemoOrchestrator)
            ----------------------------------------------------------------

            onRotateYaw = function(self, data)
                local state = getState(self)
                if state.swivelOrchestrator then
                    state.swivelOrchestrator.In.onRotateYaw(state.swivelOrchestrator, data)
                end
            end,

            onRotatePitch = function(self, data)
                local state = getState(self)
                if state.swivelOrchestrator then
                    state.swivelOrchestrator.In.onRotatePitch(state.swivelOrchestrator, data)
                end
            end,

            onSetYawAngle = function(self, data)
                local state = getState(self)
                if state.swivelOrchestrator then
                    state.swivelOrchestrator.In.onSetYawAngle(state.swivelOrchestrator, data)
                end
            end,

            onSetPitchAngle = function(self, data)
                local state = getState(self)
                if state.swivelOrchestrator then
                    state.swivelOrchestrator.In.onSetPitchAngle(state.swivelOrchestrator, data)
                end
            end,

            onStopYaw = function(self, data)
                local state = getState(self)
                if state.swivelOrchestrator then
                    state.swivelOrchestrator.In.onStopYaw(state.swivelOrchestrator, data)
                end
            end,

            onStopPitch = function(self, data)
                local state = getState(self)
                if state.swivelOrchestrator then
                    state.swivelOrchestrator.In.onStopPitch(state.swivelOrchestrator, data)
                end
            end,

            onStop = function(self, data)
                local state = getState(self)
                if state.swivelOrchestrator then
                    state.swivelOrchestrator.In.onStop(state.swivelOrchestrator, data)
                end
            end,

            ----------------------------------------------------------------
            -- LAUNCHER CONTROL (forwarded to LauncherDemoOrchestrator)
            ----------------------------------------------------------------

            onFire = function(self, data)
                local state = getState(self)
                if state.launcherOrchestrator then
                    state.launcherOrchestrator.In.onFire(state.launcherOrchestrator, data)
                end
            end,

            onTriggerDown = function(self, data)
                local state = getState(self)
                if state.launcherOrchestrator then
                    state.launcherOrchestrator.In.onTriggerDown(state.launcherOrchestrator, data)
                end
            end,

            onTriggerUp = function(self, data)
                local state = getState(self)
                if state.launcherOrchestrator then
                    state.launcherOrchestrator.In.onTriggerUp(state.launcherOrchestrator, data)
                end
            end,

            onReload = function(self, data)
                local state = getState(self)
                if state.launcherOrchestrator then
                    state.launcherOrchestrator.In.onReload(state.launcherOrchestrator, data)
                end
            end,

            onConfigure = function(self, data)
                if not data then return end
                local state = getState(self)

                -- Forward swivel config (yawSpeed, pitchSpeed, angles)
                if state.swivelOrchestrator then
                    local swivelConfig = {}
                    if data.yawSpeed then swivelConfig.yawSpeed = data.yawSpeed end
                    if data.pitchSpeed then swivelConfig.pitchSpeed = data.pitchSpeed end
                    if data.yawMinAngle then swivelConfig.yawMinAngle = data.yawMinAngle end
                    if data.yawMaxAngle then swivelConfig.yawMaxAngle = data.yawMaxAngle end
                    if data.pitchMinAngle then swivelConfig.pitchMinAngle = data.pitchMinAngle end
                    if data.pitchMaxAngle then swivelConfig.pitchMaxAngle = data.pitchMaxAngle end
                    if next(swivelConfig) then
                        state.swivelOrchestrator.In.onConfigure(state.swivelOrchestrator, swivelConfig)
                    end
                end

                -- Forward launcher config (fireMode, cooldown, etc.)
                if state.launcherOrchestrator then
                    state.launcherOrchestrator.In.onConfigure(state.launcherOrchestrator, data)
                end
            end,
        },

        Out = {
            -- Swivel signals (from SwivelDemoOrchestrator)
            yawRotated = {},
            pitchRotated = {},
            yawLimitReached = {},
            pitchLimitReached = {},
            yawStopped = {},
            pitchStopped = {},

            -- Launcher projectile signals (from LauncherDemoOrchestrator)
            fired = {},
            ready = {},
            ammoChanged = {},
            reloadStarted = {},
            reloadComplete = {},
            magazineEmpty = {},

            -- Launcher beam signals (from LauncherDemoOrchestrator)
            beamStart = {},
            beamEnd = {},
            heatChanged = {},
            overheated = {},
            cooledDown = {},
            powerChanged = {},
            powerDepleted = {},
            powerRestored = {},

            -- Targeter signals (from LauncherDemoOrchestrator)
            targetAcquired = {},
            targetTracking = {},
            targetLost = {},

            -- Error
            error = {},
        },
    }
end)

return SwivelLauncherOrchestrator
