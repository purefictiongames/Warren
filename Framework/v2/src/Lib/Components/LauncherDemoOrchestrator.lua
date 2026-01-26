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
    - Beam heat/power management

    Uses parent Orchestrator's declarative wiring system for Launcher ↔ Magazine
    communication. The handshake pattern auto-discovers the external magazine.

    ============================================================================
    WIRING (declarative, handled by parent Orchestrator)
    ============================================================================

    Handshake:
        Launcher.discoverMagazine → Magazine.onDiscoverMagazine
        Magazine.magazinePresent  → Launcher.onMagazinePresent

    Runtime:
        Launcher.requestAmmo   → Magazine.onDispense
        Launcher.requestReload → Magazine.onRequestReload
        Magazine.spawned       → Launcher.onAmmoReceived

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

                        { from = "Magazine", signal = "ammoChanged", to = "Out" },
                        { from = "Magazine", signal = "reloadStarted", to = "Out" },
                        { from = "Magazine", signal = "depleted", to = "Out", handler = "magazineEmpty" },
                        { from = "Magazine", signal = "refilled", to = "Out", handler = "reloadComplete" },
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

            -- Error
            error = {},
        },
    }
end)

return LauncherDemoOrchestrator
