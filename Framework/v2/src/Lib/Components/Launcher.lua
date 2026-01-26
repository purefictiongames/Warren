--[[
    LibPureFiction Framework v2
    Launcher.lua - Projectile Launcher Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Launcher spawns and launches projectiles from a muzzle. It only handles
    spawning and initial velocity - projectiles are separate components that
    define their own flight behavior (straight, homing, gravity-affected, etc).

    If no model provided, creates a default muzzle part.
    If no projectile template, creates a default projectile/beam.

    ============================================================================
    FIRE MODES
    ============================================================================

    manual:
        Single shot per onFire signal. Respects magazine/reload.

    semi:
        One shot per trigger press. Respects magazine/reload.

    auto:
        Continuous fire while trigger held. Uses cooldown as fire rate.
        Respects magazine/reload.

    beam:
        Continuous beam while trigger held. Has intensity, heat, and power.
        Overheats if used too long. Power depletes and recharges.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onFire({ targetPosition?: Vector3 })
        onTriggerDown({ targetPosition?: Vector3 })
        onTriggerUp({})
        onReload({})
        onConfigure({ ... })

    OUT (emits):
        -- Projectile signals
        fired({ projectile, direction, ammo, maxAmmo })
        ready({})
        ammoChanged({ current, max })
        reloadStarted({ time })
        reloadComplete({})
        magazineEmpty({})

        -- Beam signals
        beamStart({ beam, intensity })
        beamEnd({})
        heatChanged({ current, max, percent })
        overheated({})
        cooledDown({})
        powerChanged({ current, max, percent })
        powerDepleted({})

    ============================================================================
    ATTRIBUTES
    ============================================================================

    -- General
    FireMode: string (default "manual")
    Cooldown: number (default 0.5) - seconds between shots

    -- Projectile
    ProjectileComponent: string (optional) - component name (e.g., "Tracer")
    ProjectileTemplate: string (optional) - SpawnerCore template fallback
    ProjectileVelocity: number (default 100) - studs/second
    MagazineCapacity: number (default -1, infinite)
    ReloadTime: number (default 1.5) - seconds

    -- Beam
    BeamComponent: string (optional) - component name (e.g., "PlasmaBeam")
    BeamIntensity: number (default 1.0)
    BeamMaxHeat: number (default 100)
    BeamHeatRate: number (default 25) - heat per second while firing
    BeamCoolRate: number (default 15) - cool per second while idle
    BeamPowerCapacity: number (default 100)
    BeamPowerDrainRate: number (default 20) - power per second while firing
    BeamPowerRechargeRate: number (default 10) - power per second while idle

--]]

local Node = require(script.Parent.Parent.Node)
local RunService = game:GetService("RunService")

--------------------------------------------------------------------------------
-- LAUNCHER NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Launcher = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Muzzle
                muzzle = nil,
                muzzleIsDefault = false,

                -- Firing state
                lastFireTime = 0,
                triggerHeld = false,
                autoFireConnection = nil,

                -- Magazine state
                currentAmmo = -1,  -- -1 = infinite
                isReloading = false,

                -- Beam state
                activeBeam = nil,
                activeBeamComponent = nil,
                beamHeat = 0,
                beamPower = 100,
                isOverheated = false,
                beamUpdateConnection = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            if state.autoFireConnection then
                state.autoFireConnection:Disconnect()
            end
            if state.beamUpdateConnection then
                state.beamUpdateConnection:Disconnect()
            end
            if state.activeBeam then
                state.activeBeam:Destroy()
            end
            if state.activeBeamComponent then
                state.activeBeamComponent.Sys.onStop(state.activeBeamComponent)
            end
            if state.muzzleIsDefault and state.muzzle then
                state.muzzle:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    local function getMuzzleInfo(self)
        local state = getState(self)
        if state.muzzle then
            return state.muzzle.Position, state.muzzle.CFrame.LookVector
        end
        return Vector3.new(0, 0, 0), Vector3.new(0, 0, -1)
    end

    local function createDefaultMuzzle(self)
        local state = getState(self)

        local muzzle = Instance.new("Part")
        muzzle.Name = self.id .. "_Muzzle"
        muzzle.Size = Vector3.new(1, 1, 2)
        muzzle.Position = Vector3.new(0, 5, 0)
        muzzle.Anchored = true
        muzzle.CanCollide = false
        muzzle.BrickColor = BrickColor.new("Bright blue")
        muzzle.Material = Enum.Material.SmoothPlastic
        muzzle.Parent = workspace

        state.muzzle = muzzle
        state.muzzleIsDefault = true
        return muzzle
    end

    local function createDefaultProjectile(muzzlePosition, direction)
        local projectile = Instance.new("Part")
        projectile.Name = "Projectile"
        projectile.Size = Vector3.new(0.4, 0.4, 1)
        projectile.CFrame = CFrame.new(muzzlePosition, muzzlePosition + direction)
        projectile.Anchored = false
        projectile.CanCollide = true
        projectile.BrickColor = BrickColor.new("Bright yellow")
        projectile.Material = Enum.Material.Neon
        projectile.Parent = workspace

        task.delay(5, function()
            if projectile and projectile.Parent then
                projectile:Destroy()
            end
        end)

        return projectile
    end

    local function createDefaultBeam(self, direction)
        local state = getState(self)
        local muzzlePosition = state.muzzle.Position
        local intensity = self:getAttribute("BeamIntensity") or 1.0

        if state.activeBeam then
            state.activeBeam:Destroy()
        end

        local beamLength = 50

        local beam = Instance.new("Part")
        beam.Name = "Beam"
        beam.Size = Vector3.new(0.2 * intensity, 0.2 * intensity, beamLength)
        beam.CFrame = CFrame.new(muzzlePosition + direction * (beamLength / 2), muzzlePosition + direction * beamLength)
        beam.Anchored = true
        beam.CanCollide = false
        beam.BrickColor = BrickColor.new("Bright red")
        beam.Material = Enum.Material.Neon
        beam.Transparency = math.max(0, 1 - intensity)
        beam.Parent = workspace

        state.activeBeam = beam
        return beam
    end

    local function destroyBeam(self)
        local state = getState(self)
        if state.activeBeam then
            state.activeBeam:Destroy()
            state.activeBeam = nil
        end
    end

    local function startBeamUpdate(self, direction)
        local state = getState(self)
        if state.beamUpdateConnection then return end

        local muzzlePosition, muzzleDirection = getMuzzleInfo(self)
        direction = direction or muzzleDirection

        state.beamUpdateConnection = RunService.Heartbeat:Connect(function(dt)
            if not state.triggerHeld or state.isOverheated then
                return
            end

            local maxHeat = self:getAttribute("BeamMaxHeat") or 100
            local heatRate = self:getAttribute("BeamHeatRate") or 25
            local powerCapacity = self:getAttribute("BeamPowerCapacity") or 100
            local drainRate = self:getAttribute("BeamPowerDrainRate") or 20

            -- Drain power
            state.beamPower = math.max(0, state.beamPower - drainRate * dt)
            self.Out:Fire("powerChanged", {
                current = state.beamPower,
                max = powerCapacity,
                percent = state.beamPower / powerCapacity,
            })

            -- Build heat
            state.beamHeat = math.min(maxHeat, state.beamHeat + heatRate * dt)
            self.Out:Fire("heatChanged", {
                current = state.beamHeat,
                max = maxHeat,
                percent = state.beamHeat / maxHeat,
            })

            -- Check power depleted
            if state.beamPower <= 0 then
                self.Out:Fire("powerDepleted", {})
                destroyBeam(self)
                self.Out:Fire("beamEnd", {})
                state.triggerHeld = false
                return
            end

            -- Check overheat
            if state.beamHeat >= maxHeat then
                state.isOverheated = true
                self.Out:Fire("overheated", {})
                destroyBeam(self)
                self.Out:Fire("beamEnd", {})
                return
            end

            -- Update beam position (follow muzzle)
            if state.activeBeam and state.muzzle then
                local pos = state.muzzle.Position
                local dir = state.muzzle.CFrame.LookVector
                local beamLength = state.activeBeam.Size.Z
                state.activeBeam.CFrame = CFrame.new(pos + dir * (beamLength / 2), pos + dir * beamLength)
            end
        end)
    end

    local function stopBeamUpdate(self)
        local state = getState(self)
        if state.beamUpdateConnection then
            state.beamUpdateConnection:Disconnect()
            state.beamUpdateConnection = nil
        end
    end

    local function startIdleCooldown(self)
        local state = getState(self)

        -- Already have a connection running
        if state.idleCoolConnection then return end

        state.idleCoolConnection = RunService.Heartbeat:Connect(function(dt)
            local maxHeat = self:getAttribute("BeamMaxHeat") or 100
            local coolRate = self:getAttribute("BeamCoolRate") or 15
            local powerCapacity = self:getAttribute("BeamPowerCapacity") or 100
            local rechargeRate = self:getAttribute("BeamPowerRechargeRate") or 10

            local wasOverheated = state.isOverheated
            local heatChanged = false
            local powerChanged = false

            -- Cool down
            if state.beamHeat > 0 then
                state.beamHeat = math.max(0, state.beamHeat - coolRate * dt)
                heatChanged = true
            end

            -- Recharge power
            if state.beamPower < powerCapacity then
                state.beamPower = math.min(powerCapacity, state.beamPower + rechargeRate * dt)
                powerChanged = true
            end

            -- Check if cooled down from overheat
            if wasOverheated and state.beamHeat <= 0 then
                state.isOverheated = false
                self.Out:Fire("cooledDown", {})
            end

            if heatChanged then
                self.Out:Fire("heatChanged", {
                    current = state.beamHeat,
                    max = maxHeat,
                    percent = state.beamHeat / maxHeat,
                })
            end

            if powerChanged then
                self.Out:Fire("powerChanged", {
                    current = state.beamPower,
                    max = powerCapacity,
                    percent = state.beamPower / powerCapacity,
                })
            end

            -- Stop if fully recovered
            if state.beamHeat <= 0 and state.beamPower >= powerCapacity then
                state.idleCoolConnection:Disconnect()
                state.idleCoolConnection = nil
            end
        end)
    end

    local function fireProjectile(self, data)
        data = data or {}
        local state = getState(self)

        -- Check if reloading
        if state.isReloading then
            self.Err:Fire({ reason = "reloading" })
            return false
        end

        -- Check cooldown
        local cooldown = self:getAttribute("Cooldown") or 0.5
        local currentTime = os.clock()
        local timeSinceFire = currentTime - state.lastFireTime

        if timeSinceFire < cooldown then
            self.Err:Fire({ reason = "cooldown", remaining = cooldown - timeSinceFire })
            return false
        end

        -- Check ammo
        local maxAmmo = self:getAttribute("MagazineCapacity") or -1
        if maxAmmo > 0 and state.currentAmmo <= 0 then
            self.Out:Fire("magazineEmpty", {})
            return false
        end

        -- Get muzzle info
        local muzzlePosition, muzzleDirection = getMuzzleInfo(self)
        local direction = data.targetPosition and (data.targetPosition - muzzlePosition).Unit or muzzleDirection

        -- Create projectile
        local projectile
        local projectileComponent = self:getAttribute("ProjectileComponent")
        local templateName = self:getAttribute("ProjectileTemplate")
        local velocity = self:getAttribute("ProjectileVelocity") or 100

        if projectileComponent and projectileComponent ~= "" then
            -- Use component-based projectile
            local Components = require(script.Parent)
            local ComponentClass = Components[projectileComponent]

            if ComponentClass then
                local comp = ComponentClass:new({
                    id = self.id .. "_Projectile_" .. tostring(os.clock()),
                })
                comp.Sys.onInit(comp)
                comp.Sys.onStart(comp)

                -- Launch the component
                comp.In.onLaunch(comp, {
                    position = muzzlePosition,
                    direction = direction,
                    velocity = velocity,
                })

                -- Get the visual part for the fired signal
                projectile = comp.model
            else
                self.Err:Fire({ reason = "component_not_found", component = projectileComponent })
                return false
            end

        elseif templateName and templateName ~= "" then
            -- Use SpawnerCore template
            local SpawnerCore = require(script.Parent.Parent.Internal.SpawnerCore)
            if not SpawnerCore.isInitialized() then
                SpawnerCore.init({
                    templates = game:GetService("ReplicatedStorage"):FindFirstChild("Templates"),
                })
            end

            local result = SpawnerCore.spawn({
                templateName = templateName,
                parent = workspace,
                cframe = CFrame.new(muzzlePosition, muzzlePosition + direction),
            })

            if result then
                projectile = result.instance
                if projectile:IsA("BasePart") then
                    projectile.Anchored = false
                elseif projectile:IsA("Model") and projectile.PrimaryPart then
                    projectile.PrimaryPart.Anchored = false
                end
            end

            -- Apply velocity for template-based projectiles
            if projectile then
                local physicsPart = projectile:IsA("BasePart") and projectile or
                    (projectile:IsA("Model") and projectile.PrimaryPart)
                if physicsPart then
                    physicsPart.AssemblyLinearVelocity = direction * velocity
                end
            end

        else
            -- Use default projectile
            projectile = createDefaultProjectile(muzzlePosition, direction)

            -- Apply velocity for default projectile
            local physicsPart = projectile:IsA("BasePart") and projectile or
                (projectile:IsA("Model") and projectile.PrimaryPart)
            if physicsPart then
                physicsPart.AssemblyLinearVelocity = direction * velocity
            end
        end

        if not projectile then
            self.Err:Fire({ reason = "spawn_failed" })
            return false
        end

        -- Consume ammo
        if maxAmmo > 0 then
            state.currentAmmo = state.currentAmmo - 1
            self.Out:Fire("ammoChanged", { current = state.currentAmmo, max = maxAmmo })
        end

        state.lastFireTime = currentTime

        self.Out:Fire("fired", {
            projectile = projectile,
            direction = direction,
            ammo = state.currentAmmo,
            maxAmmo = maxAmmo,
        })

        task.delay(cooldown, function()
            if state.lastFireTime == currentTime then
                self.Out:Fire("ready", {})
            end
        end)

        return true
    end

    local function startAutoFire(self, data)
        local state = getState(self)
        if state.autoFireConnection then return end

        fireProjectile(self, data)

        state.autoFireConnection = RunService.Heartbeat:Connect(function()
            if not state.triggerHeld then
                state.autoFireConnection:Disconnect()
                state.autoFireConnection = nil
                return
            end
            fireProjectile(self, data)
        end)
    end

    local function stopAutoFire(self)
        local state = getState(self)
        if state.autoFireConnection then
            state.autoFireConnection:Disconnect()
            state.autoFireConnection = nil
        end
    end

    local function doReload(self)
        local state = getState(self)
        local maxAmmo = self:getAttribute("MagazineCapacity") or -1

        if maxAmmo <= 0 then return end  -- Infinite ammo
        if state.isReloading then return end
        if state.currentAmmo >= maxAmmo then return end  -- Already full

        state.isReloading = true
        local reloadTime = self:getAttribute("ReloadTime") or 1.5

        self.Out:Fire("reloadStarted", { time = reloadTime })

        task.delay(reloadTime, function()
            state.currentAmmo = maxAmmo
            state.isReloading = false
            self.Out:Fire("reloadComplete", {})
            self.Out:Fire("ammoChanged", { current = state.currentAmmo, max = maxAmmo })
        end)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "Launcher",
        domain = "server",

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Get muzzle from model, or create default
                if self.model then
                    if self.model:IsA("BasePart") then
                        state.muzzle = self.model
                    elseif self.model:IsA("Model") and self.model.PrimaryPart then
                        state.muzzle = self.model.PrimaryPart
                    else
                        createDefaultMuzzle(self)
                    end
                else
                    createDefaultMuzzle(self)
                end

                -- Default attributes
                self:setAttribute("ProjectileComponent", self:getAttribute("ProjectileComponent") or "")
                self:setAttribute("ProjectileTemplate", self:getAttribute("ProjectileTemplate") or "")
                self:setAttribute("ProjectileVelocity", self:getAttribute("ProjectileVelocity") or 100)
                self:setAttribute("FireMode", self:getAttribute("FireMode") or "manual")
                self:setAttribute("Cooldown", self:getAttribute("Cooldown") or 0.5)
                self:setAttribute("MagazineCapacity", self:getAttribute("MagazineCapacity") or -1)
                self:setAttribute("ReloadTime", self:getAttribute("ReloadTime") or 1.5)

                self:setAttribute("BeamComponent", self:getAttribute("BeamComponent") or "")
                self:setAttribute("BeamIntensity", self:getAttribute("BeamIntensity") or 1.0)
                self:setAttribute("BeamMaxHeat", self:getAttribute("BeamMaxHeat") or 100)
                self:setAttribute("BeamHeatRate", self:getAttribute("BeamHeatRate") or 25)
                self:setAttribute("BeamCoolRate", self:getAttribute("BeamCoolRate") or 15)
                self:setAttribute("BeamPowerCapacity", self:getAttribute("BeamPowerCapacity") or 100)
                self:setAttribute("BeamPowerDrainRate", self:getAttribute("BeamPowerDrainRate") or 20)
                self:setAttribute("BeamPowerRechargeRate", self:getAttribute("BeamPowerRechargeRate") or 10)

                -- Initialize ammo
                local maxAmmo = self:getAttribute("MagazineCapacity")
                state.currentAmmo = maxAmmo > 0 and maxAmmo or -1

                -- Initialize beam power
                state.beamPower = self:getAttribute("BeamPowerCapacity")
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

                if data.projectileComponent ~= nil then
                    self:setAttribute("ProjectileComponent", data.projectileComponent)
                end
                if data.projectileTemplate ~= nil then
                    self:setAttribute("ProjectileTemplate", data.projectileTemplate)
                end
                if data.projectileVelocity then
                    self:setAttribute("ProjectileVelocity", math.abs(data.projectileVelocity))
                end
                if data.fireMode then
                    local mode = string.lower(data.fireMode)
                    if mode == "manual" or mode == "semi" or mode == "auto" or mode == "beam" then
                        self:setAttribute("FireMode", mode)
                    end
                end
                if data.cooldown then
                    self:setAttribute("Cooldown", math.max(0, data.cooldown))
                end
                if data.magazineCapacity then
                    self:setAttribute("MagazineCapacity", data.magazineCapacity)
                    if data.magazineCapacity > 0 then
                        state.currentAmmo = data.magazineCapacity
                        self.Out:Fire("ammoChanged", { current = state.currentAmmo, max = data.magazineCapacity })
                    end
                end
                if data.reloadTime then
                    self:setAttribute("ReloadTime", math.max(0, data.reloadTime))
                end

                -- Beam config
                if data.beamComponent ~= nil then
                    self:setAttribute("BeamComponent", data.beamComponent)
                end
                if data.beamIntensity then
                    self:setAttribute("BeamIntensity", math.max(0.1, data.beamIntensity))
                end
                if data.beamMaxHeat then
                    self:setAttribute("BeamMaxHeat", math.max(1, data.beamMaxHeat))
                end
                if data.beamHeatRate then
                    self:setAttribute("BeamHeatRate", math.max(0, data.beamHeatRate))
                end
                if data.beamCoolRate then
                    self:setAttribute("BeamCoolRate", math.max(0, data.beamCoolRate))
                end
                if data.beamPowerCapacity then
                    self:setAttribute("BeamPowerCapacity", math.max(1, data.beamPowerCapacity))
                    state.beamPower = data.beamPowerCapacity
                end
                if data.beamPowerDrainRate then
                    self:setAttribute("BeamPowerDrainRate", math.max(0, data.beamPowerDrainRate))
                end
                if data.beamPowerRechargeRate then
                    self:setAttribute("BeamPowerRechargeRate", math.max(0, data.beamPowerRechargeRate))
                end
            end,

            onFire = function(self, data)
                fireProjectile(self, data)
            end,

            onReload = function(self, data)
                doReload(self)
            end,

            onTriggerDown = function(self, data)
                local state = getState(self)
                local fireMode = self:getAttribute("FireMode") or "manual"

                state.triggerHeld = true

                if fireMode == "semi" then
                    fireProjectile(self, data)
                elseif fireMode == "auto" then
                    startAutoFire(self, data)
                elseif fireMode == "beam" then
                    if state.isOverheated then
                        self.Err:Fire({ reason = "overheated" })
                        return
                    end
                    if state.beamPower <= 0 then
                        self.Err:Fire({ reason = "no_power" })
                        return
                    end

                    local muzzlePosition, muzzleDirection = getMuzzleInfo(self)
                    local direction = data and data.targetPosition and
                        (data.targetPosition - muzzlePosition).Unit or muzzleDirection

                    local beamComponent = self:getAttribute("BeamComponent")
                    local intensity = self:getAttribute("BeamIntensity") or 1.0

                    if beamComponent and beamComponent ~= "" then
                        -- Use component-based beam
                        local Components = require(script.Parent)
                        local ComponentClass = Components[beamComponent]

                        if ComponentClass then
                            local comp = ComponentClass:new({
                                id = self.id .. "_Beam",
                            })
                            comp.Sys.onInit(comp)
                            comp.Sys.onStart(comp)

                            -- Activate the beam
                            comp.In.onActivate(comp, {
                                origin = state.muzzle,
                                direction = direction,
                            })

                            state.activeBeamComponent = comp
                            self.Out:Fire("beamStart", { beam = comp.model, intensity = intensity })
                        else
                            self.Err:Fire({ reason = "component_not_found", component = beamComponent })
                            return
                        end
                    else
                        -- Use default beam
                        local beam = createDefaultBeam(self, direction)
                        self.Out:Fire("beamStart", { beam = beam, intensity = intensity })
                    end

                    startBeamUpdate(self, direction)
                end
            end,

            onTriggerUp = function(self, data)
                local state = getState(self)
                local fireMode = self:getAttribute("FireMode") or "manual"

                state.triggerHeld = false

                if fireMode == "auto" then
                    stopAutoFire(self)
                elseif fireMode == "beam" then
                    stopBeamUpdate(self)

                    -- Deactivate beam component if used
                    if state.activeBeamComponent then
                        state.activeBeamComponent.In.onDeactivate(state.activeBeamComponent, {})
                        state.activeBeamComponent.Sys.onStop(state.activeBeamComponent)
                        state.activeBeamComponent = nil
                    else
                        destroyBeam(self)
                    end

                    self.Out:Fire("beamEnd", {})
                    startIdleCooldown(self)
                end
            end,
        },

        Out = {
            -- Projectile
            fired = {},          -- { projectile, direction, ammo, maxAmmo }
            ready = {},          -- {}
            ammoChanged = {},    -- { current, max }
            reloadStarted = {},  -- { time }
            reloadComplete = {}, -- {}
            magazineEmpty = {},  -- {}

            -- Beam
            beamStart = {},      -- { beam, intensity }
            beamEnd = {},        -- {}
            heatChanged = {},    -- { current, max, percent }
            overheated = {},     -- {}
            cooledDown = {},     -- {}
            powerChanged = {},   -- { current, max, percent }
            powerDepleted = {},  -- {}
        },
    }
end)

return Launcher
