--[[
    LibPureFiction Framework v2
    LauncherDemoOrchestrator.lua - Extended Orchestrator for Launcher Demo

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LauncherDemoOrchestrator manages a projectile launcher with all fire modes:
    - manual, semi, auto, beam
    - Magazine system with reload
    - Beam heat/power management

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onFire, onTriggerDown, onTriggerUp, onReload, onConfigure

    OUT (emits):
        Projectile: fired, ready, ammoChanged, reloadStarted, reloadComplete, magazineEmpty
        Beam: beamStart, beamEnd, heatChanged, overheated, cooledDown, powerChanged, powerDepleted
        error

--]]

local Orchestrator = require(script.Parent.Orchestrator)

local LauncherDemoOrchestrator = Orchestrator.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = { launcher = nil }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    local function setupSignalForwarding(self, launcher)
        local originalOutFire = launcher.Out.Fire
        launcher.Out.Fire = function(outSelf, signal, data)
            -- Forward all signals
            self.Out:Fire(signal, data)
            originalOutFire(outSelf, signal, data)
        end

        local originalErrFire = launcher.Err.Fire
        launcher.Err.Fire = function(errSelf, data)
            self.Out:Fire("error", data)
            originalErrFire(errSelf, data)
        end
    end

    return {
        name = "LauncherDemoOrchestrator",
        domain = "server",

        Sys = {
            onInit = function(self)
                parent.Sys.onInit(self)

                local config = self._attributes or {}
                local Launcher = require(script.Parent.Launcher)
                local state = getState(self)

                state.launcher = Launcher:new({
                    id = self.id .. "_Launcher",
                    model = self.model,
                })
                state.launcher.Sys.onInit(state.launcher)

                -- Configure from attributes
                state.launcher.In.onConfigure(state.launcher, {
                    -- General
                    fireMode = config.fireMode or "manual",
                    cooldown = config.cooldown or 0.5,

                    -- Projectile
                    projectileTemplate = config.projectileTemplate or "",
                    projectileVelocity = config.projectileVelocity or 100,
                    magazineCapacity = config.magazineCapacity or -1,
                    reloadTime = config.reloadTime or 1.5,

                    -- Beam
                    beamIntensity = config.beamIntensity or 1.0,
                    beamMaxHeat = config.beamMaxHeat or 100,
                    beamHeatRate = config.beamHeatRate or 25,
                    beamCoolRate = config.beamCoolRate or 15,
                    beamPowerCapacity = config.beamPowerCapacity or 100,
                    beamPowerDrainRate = config.beamPowerDrainRate or 20,
                    beamPowerRechargeRate = config.beamPowerRechargeRate or 10,
                })

                setupSignalForwarding(self, state.launcher)
            end,

            onStart = function(self)
                local state = getState(self)
                if state.launcher then
                    state.launcher.Sys.onStart(state.launcher)
                end
            end,

            onStop = function(self)
                local state = getState(self)
                if state.launcher then
                    state.launcher.Sys.onStop(state.launcher)
                end
                cleanupState(self)
            end,
        },

        In = {
            onFire = function(self, data)
                local state = getState(self)
                if state.launcher then
                    state.launcher.In.onFire(state.launcher, data)
                end
            end,

            onTriggerDown = function(self, data)
                local state = getState(self)
                if state.launcher then
                    state.launcher.In.onTriggerDown(state.launcher, data)
                end
            end,

            onTriggerUp = function(self, data)
                local state = getState(self)
                if state.launcher then
                    state.launcher.In.onTriggerUp(state.launcher, data)
                end
            end,

            onReload = function(self, data)
                local state = getState(self)
                if state.launcher then
                    state.launcher.In.onReload(state.launcher, data)
                end
            end,

            onConfigure = function(self, data)
                local state = getState(self)
                if state.launcher then
                    state.launcher.In.onConfigure(state.launcher, data)
                end
            end,
        },

        Out = {
            -- Projectile
            fired = {},
            ready = {},
            ammoChanged = {},
            reloadStarted = {},
            reloadComplete = {},
            magazineEmpty = {},

            -- Beam
            beamStart = {},
            beamEnd = {},
            heatChanged = {},
            overheated = {},
            cooledDown = {},
            powerChanged = {},
            powerDepleted = {},

            -- Error
            error = {},
        },
    }
end)

return LauncherDemoOrchestrator
