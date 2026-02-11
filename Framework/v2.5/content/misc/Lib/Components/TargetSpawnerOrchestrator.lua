--[[
    LibPureFiction Framework v2
    TargetSpawnerOrchestrator.lua - Target Drone Spawner System

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    TargetSpawnerOrchestrator manages spawning FlyingTarget drones.
    It tracks spawned targets, handles respawning when targets are destroyed,
    and manages the overall target population.

    Extends Orchestrator to use declarative node management and wiring.
    Uses Dropper internally in component mode to spawn FlyingTarget instances.

    Used for:
    - Shooting galleries
    - Turret testing
    - Combat practice scenarios

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onSpawn({})
            - Spawn a new target (if under max count)

        onSpawnWave({ count })
            - Spawn multiple targets at once

        onConfigure({ maxTargets?, respawnDelay?, health?, speed?, flyArea? })
            - Update spawner configuration

        onClear({})
            - Destroy all active targets

        onEnable({})
            - Enable auto-respawning

        onDisable({})
            - Disable auto-respawning

        -- Internal (wired from Spawner)
        onTargetSpawned({ component, entityId, ... })
            - Handle newly spawned target from Dropper

    OUT (emits):
        targetSpawned({ target, position })
            - New target was spawned

        targetDestroyed({ position })
            - A target was destroyed

        waveComplete({})
            - All targets from a wave have been destroyed

    ============================================================================
    ATTRIBUTES
    ============================================================================

    MaxTargets: number (default 5)
        Maximum number of active targets

    RespawnDelay: number (default 2)
        Seconds to wait before respawning a destroyed target

    AutoRespawn: boolean (default true)
        Whether to automatically respawn destroyed targets

    TargetHealth: number (default 100)
        Health of spawned targets

    TargetSpeed: number (default 20)
        Movement speed of spawned targets

    FlyAreaCenter: Vector3 (default 0, 20, -40)
        Center of the flying area

    FlyAreaSize: Vector3 (default 50, 20, 50)
        Size of the flying area box

--]]

local Orchestrator = require(script.Parent.Orchestrator)

--------------------------------------------------------------------------------
-- TARGET SPAWNER ORCHESTRATOR
--------------------------------------------------------------------------------

local TargetSpawnerOrchestrator = Orchestrator.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                activeTargets = {},  -- { [id] = target component }
                targetCounter = 0,
                enabled = true,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "TargetSpawnerOrchestrator",
        domain = "server",

        Sys = {
            onInit = function(self)
                -- Call parent onInit first
                parent.Sys.onInit(self)

                local config = self._attributes or {}

                -- Default attributes
                self:setAttribute("MaxTargets", config.MaxTargets or 5)
                self:setAttribute("RespawnDelay", config.RespawnDelay or 2)
                self:setAttribute("AutoRespawn", config.AutoRespawn ~= false)
                self:setAttribute("TargetHealth", config.TargetHealth or 100)
                self:setAttribute("TargetSpeed", config.TargetSpeed or 20)
                self:setAttribute("FlyAreaCenter", config.FlyAreaCenter or Vector3.new(0, 20, -40))
                self:setAttribute("FlyAreaSize", config.FlyAreaSize or Vector3.new(50, 20, 50))

                -- Configure orchestrator with Dropper node using declarative pattern
                parent.In.onConfigure(self, {
                    nodes = {
                        Spawner = {
                            class = "Dropper",
                            config = {
                                componentName = "FlyingTarget",
                                Visible = false,
                                AutoStart = false,
                            },
                        },
                    },
                    wiring = {
                        -- Route spawned signal to Self for internal handling
                        { from = "Spawner", signal = "spawned", to = "Self", handler = "onTargetSpawned" },
                    },
                })
            end,

            onStart = function(self)
                -- Parent onStart enables routing and starts all nodes
                parent.Sys.onStart(self)
            end,

            onStop = function(self)
                -- Clear all targets before stopping
                self.In.onClear(self)
                cleanupState(self)
                parent.Sys.onStop(self)
            end,
        },

        In = {
            --[[
                Internal handler: Dropper spawned a FlyingTarget component.
                Configure it, track it, and wire its destroyed signal.
            --]]
            onTargetSpawned = function(self, data)
                if not data or not data.component then return end

                local state = getState(self)
                local target = data.component

                -- Get fly area config
                local health = self:getAttribute("TargetHealth") or 100
                local speed = self:getAttribute("TargetSpeed") or 20
                local center = self:getAttribute("FlyAreaCenter") or Vector3.new(0, 20, -40)
                local size = self:getAttribute("FlyAreaSize") or Vector3.new(50, 20, 50)

                -- Configure the target
                target.In.onConfigure(target, {
                    health = health,
                    speed = speed,
                    flyAreaCenter = center,
                    flyAreaSize = size,
                })

                -- Track the target
                state.activeTargets[target.id] = target

                -- Wire target's destroyed signal to handle respawn
                local originalFire = target.Out.Fire
                target.Out.Fire = function(outSelf, signal, signalData)
                    signalData = signalData or {}

                    if signal == "destroyed" then
                        -- Remove from tracking
                        state.activeTargets[target.id] = nil

                        -- Forward to our Out
                        self.Out:Fire("targetDestroyed", signalData)

                        -- Auto-respawn if enabled
                        if state.enabled and self:getAttribute("AutoRespawn") then
                            local delay = self:getAttribute("RespawnDelay") or 2
                            task.delay(delay, function()
                                if state.enabled then
                                    self.In.onSpawn(self)
                                end
                            end)
                        end

                        -- Check if wave complete
                        local count = 0
                        for _ in pairs(state.activeTargets) do
                            count = count + 1
                        end
                        if count == 0 then
                            self.Out:Fire("waveComplete", {})
                        end
                    end

                    originalFire(outSelf, signal, signalData)
                end

                -- Position at random point in fly area
                local x = center.X + (math.random() - 0.5) * size.X
                local y = center.Y + (math.random() - 0.5) * size.Y
                local z = center.Z + (math.random() - 0.5) * size.Z
                local spawnPos = Vector3.new(x, y, z)

                -- Find the drone part and position it
                task.defer(function()
                    for _, p in ipairs(workspace:GetDescendants()) do
                        if p.Name == target.id .. "_Drone" then
                            p.Position = spawnPos
                            break
                        end
                    end
                end)

                -- Emit spawned signal
                self.Out:Fire("targetSpawned", {
                    target = target,
                    position = spawnPos,
                })
            end,

            --[[
                Spawn a single target (if under max count).
            --]]
            onSpawn = function(self, data)
                local state = getState(self)

                -- Check max targets
                local maxTargets = self:getAttribute("MaxTargets") or 5
                local count = 0
                for _ in pairs(state.activeTargets) do
                    count = count + 1
                end

                if count >= maxTargets then
                    return  -- At max capacity
                end

                -- Request spawn from Dropper via orchestrator's node management
                local spawner = self:getNode("Spawner")
                if spawner then
                    state.targetCounter = state.targetCounter + 1
                    spawner.In.onDispense(spawner, {
                        _passthrough = { targetId = state.targetCounter },
                    })
                end
            end,

            --[[
                Spawn a wave of targets.
            --]]
            onSpawnWave = function(self, data)
                data = data or {}
                local count = data.count or self:getAttribute("MaxTargets") or 5

                for i = 1, count do
                    self.In.onSpawn(self)
                end
            end,

            --[[
                Configure spawner settings.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                if data.maxTargets then
                    self:setAttribute("MaxTargets", math.max(1, data.maxTargets))
                end
                if data.respawnDelay then
                    self:setAttribute("RespawnDelay", math.max(0, data.respawnDelay))
                end
                if data.autoRespawn ~= nil then
                    self:setAttribute("AutoRespawn", data.autoRespawn)
                end
                if data.health then
                    self:setAttribute("TargetHealth", math.max(1, data.health))
                end
                if data.speed then
                    self:setAttribute("TargetSpeed", math.max(1, data.speed))
                end
                if data.flyAreaCenter then
                    self:setAttribute("FlyAreaCenter", data.flyAreaCenter)
                end
                if data.flyAreaSize then
                    self:setAttribute("FlyAreaSize", data.flyAreaSize)
                end
            end,

            --[[
                Clear all active targets.
            --]]
            onClear = function(self, data)
                local state = getState(self)

                for id, target in pairs(state.activeTargets) do
                    target.Sys.onStop(target)
                end
                state.activeTargets = {}
            end,

            --[[
                Enable auto-respawning.
            --]]
            onEnable = function(self, data)
                local state = getState(self)
                state.enabled = true
            end,

            --[[
                Disable auto-respawning.
            --]]
            onDisable = function(self, data)
                local state = getState(self)
                state.enabled = false
            end,
        },

        Out = {
            targetSpawned = {},    -- { target, position }
            targetDestroyed = {},  -- { position }
            waveComplete = {},     -- {}
        },
    }
end)

return TargetSpawnerOrchestrator
