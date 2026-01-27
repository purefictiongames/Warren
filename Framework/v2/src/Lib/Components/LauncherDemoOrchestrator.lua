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
    - External Magazine (Dropper) for ammo via IPC
    - External Battery for beam power via IPC
    - Beam heat management (internal to Launcher)

    Uses parent Orchestrator's declarative wiring system for Launcher ↔ Magazine
    and Launcher ↔ Battery communication. The handshake pattern auto-discovers
    external components.

    ============================================================================
    WIRING (declarative, handled by parent Orchestrator)
    ============================================================================

    Magazine Handshake:
        Launcher.discoverMagazine → Magazine.onDiscoverMagazine
        Magazine.magazinePresent  → Launcher.onMagazinePresent

    Magazine Runtime:
        Launcher.requestAmmo   → Magazine.onDispense
        Launcher.requestReload → Magazine.onRequestReload
        Magazine.spawned       → Launcher.onAmmoReceived

    Battery Handshake:
        Launcher.discoverBattery → Battery.onDiscoverBattery
        Battery.batteryPresent   → Launcher.onBatteryPresent

    Battery Runtime:
        Launcher.drawPower      → Battery.onDraw
        Battery.powerDrawn      → Launcher.onPowerDrawn
        Battery.powerDepleted   → Launcher.onBatteryDepleted
        Battery.powerRestored   → Launcher.onBatteryRestored

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
    return {
        name = "LauncherDemoOrchestrator",
        domain = "server",

        Sys = {
            onInit = function(self)
                parent.Sys.onInit(self)

                local config = self._attributes or {}

                -- Configure via parent Orchestrator's declarative system
                parent.In.onConfigure(self, {
                    -- Node instances
                    nodes = {
                        Launcher = {
                            class = "Launcher",
                            model = self.model,
                            config = {
                                fireMode = config.fireMode or "auto",
                                cooldown = config.cooldown or 0.1,
                                -- Beam settings
                                beamComponent = config.beamComponent or "",
                                beamIntensity = config.beamIntensity or 1.0,
                                beamMaxHeat = config.beamMaxHeat or 100,
                                beamHeatRate = config.beamHeatRate or 25,
                                beamCoolRate = config.beamCoolRate or 15,
                                beamPowerCapacity = config.beamPowerCapacity or 100,
                                beamPowerDrainRate = config.beamPowerDrainRate or 20,
                                beamPowerRechargeRate = config.beamPowerRechargeRate or 10,
                            },
                        },
                        Magazine = {
                            class = "Dropper",
                            config = {
                                componentName = config.projectileComponent or "Tracer",
                                capacity = config.magazineCapacity or 30,
                                reloadTime = config.reloadTime or 1.5,
                                -- Weld to the launcher's muzzle, offset to the left
                                WeldTo = self.model,
                                WeldOffset = CFrame.new(-1.5, 0, 0),  -- Left side of muzzle
                            },
                        },
                        Battery = {
                            class = "Battery",
                            config = {
                                capacity = config.batteryCapacity or 100,
                                rechargeRate = config.batteryRechargeRate or 15,
                                -- Weld to the launcher's muzzle, offset to the right
                                WeldTo = self.model,
                                WeldOffset = CFrame.new(1.5, 0, 0),  -- Right side of muzzle
                            },
                        },
                        Targeter = {
                            class = "Targeter",
                            config = {
                                -- Weld to the launcher's muzzle, offset on top
                                WeldTo = self.model,
                                WeldOffset = CFrame.new(0, 1, 0),  -- Top of muzzle
                                -- Targeter config
                                BeamMode = config.targeterBeamMode or "pinpoint",
                                Range = config.targeterRange or 100,
                                ScanMode = "continuous",
                                TrackingMode = "lock",
                                AutoStart = true,
                                BeamVisible = config.targeterBeamVisible ~= false,
                                BeamColor = config.targeterBeamColor or Color3.new(0, 1, 0),
                            },
                        },
                    },

                    -- Declarative wiring: Launcher ↔ Magazine
                    wiring = {
                        -- Handshake
                        { from = "Launcher", signal = "discoverMagazine", to = "Magazine", handler = "onDiscoverMagazine" },
                        { from = "Magazine", signal = "magazinePresent", to = "Launcher", handler = "onMagazinePresent" },

                        -- Runtime: Launcher → Magazine
                        { from = "Launcher", signal = "requestAmmo", to = "Magazine", handler = "onDispense" },
                        { from = "Launcher", signal = "requestReload", to = "Magazine", handler = "onRequestReload" },

                        -- Runtime: Magazine → Launcher
                        { from = "Magazine", signal = "spawned", to = "Launcher", handler = "onAmmoReceived" },

                        -- Battery handshake
                        { from = "Launcher", signal = "discoverBattery", to = "Battery", handler = "onDiscoverBattery" },
                        { from = "Battery", signal = "batteryPresent", to = "Launcher", handler = "onBatteryPresent" },

                        -- Runtime: Launcher → Battery
                        { from = "Launcher", signal = "drawPower", to = "Battery", handler = "onDraw" },

                        -- Runtime: Battery → Launcher
                        { from = "Battery", signal = "powerDrawn", to = "Launcher", handler = "onPowerDrawn" },
                        { from = "Battery", signal = "powerDepleted", to = "Launcher", handler = "onBatteryDepleted" },
                        { from = "Battery", signal = "powerRestored", to = "Launcher", handler = "onBatteryRestored" },

                        -- Targeter handshake
                        { from = "Launcher", signal = "discoverTargeter", to = "Targeter", handler = "onDiscoverTargeter" },
                        { from = "Targeter", signal = "targeterPresent", to = "Launcher", handler = "onTargeterPresent" },
                        { from = "Targeter", signal = "discoverLauncher", to = "Launcher", handler = "onDiscoverLauncher" },
                        { from = "Launcher", signal = "launcherPresent", to = "Targeter", handler = "onLauncherPresent" },

                        -- Runtime: Targeter → Launcher
                        { from = "Targeter", signal = "acquired", to = "Launcher", handler = "onTargetAcquired" },
                        { from = "Targeter", signal = "tracking", to = "Launcher", handler = "onTargetTracking" },
                        { from = "Targeter", signal = "lost", to = "Launcher", handler = "onTargetLost" },

                        -- Forward to orchestrator's Out (for HUD / external consumers)
                        { from = "Launcher", signal = "fired", to = "Out" },
                        { from = "Launcher", signal = "ready", to = "Out" },
                        { from = "Launcher", signal = "beamStart", to = "Out" },
                        { from = "Launcher", signal = "beamEnd", to = "Out" },
                        { from = "Launcher", signal = "heatChanged", to = "Out" },
                        { from = "Launcher", signal = "overheated", to = "Out" },
                        { from = "Launcher", signal = "cooledDown", to = "Out" },
                        { from = "Launcher", signal = "powerChanged", to = "Out" },
                        { from = "Launcher", signal = "powerDepleted", to = "Out" },
                        { from = "Launcher", signal = "powerRestored", to = "Out" },

                        { from = "Magazine", signal = "ammoChanged", to = "Out" },
                        { from = "Magazine", signal = "reloadStarted", to = "Out" },
                        { from = "Magazine", signal = "depleted", to = "Out", handler = "magazineEmpty" },
                        { from = "Magazine", signal = "refilled", to = "Out", handler = "reloadComplete" },

                        -- Forward Targeter signals to Out
                        { from = "Launcher", signal = "targetAcquired", to = "Out" },
                        { from = "Launcher", signal = "targetTracking", to = "Out" },
                        { from = "Launcher", signal = "targetLost", to = "Out" },
                    },
                })
            end,

            onStart = function(self)
                parent.Sys.onStart(self)
            end,

            onStop = function(self)
                parent.Sys.onStop(self)
            end,
        },

        In = {
            onFire = function(self, data)
                local launcher = self:getNode("Launcher")
                if launcher then
                    launcher.In.onFire(launcher, data)
                end
            end,

            onTriggerDown = function(self, data)
                local launcher = self:getNode("Launcher")
                if launcher then
                    launcher.In.onTriggerDown(launcher, data)
                end
            end,

            onTriggerUp = function(self, data)
                local launcher = self:getNode("Launcher")
                if launcher then
                    launcher.In.onTriggerUp(launcher, data)
                end
            end,

            onReload = function(self, data)
                local launcher = self:getNode("Launcher")
                if launcher then
                    launcher.In.onReload(launcher, data)
                end
            end,

            onConfigure = function(self, data)
                local launcher = self:getNode("Launcher")
                if launcher then
                    launcher.In.onConfigure(launcher, data)
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
            powerRestored = {},

            -- Targeter
            targetAcquired = {},
            targetTracking = {},
            targetLost = {},

            -- Error
            error = {},
        },
    }
end)

return LauncherDemoOrchestrator
