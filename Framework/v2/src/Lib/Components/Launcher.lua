--[[
    LibPureFiction Framework v2
    Launcher.lua - Physics-Based Projectile Firing Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Launcher provides physics-based projectile firing from a muzzle surface.
    Spawns projectiles using SpawnerCore and applies physics forces to launch
    them. After launch, physics handles the projectile's flight.

    Used for:
    - Turret guns
    - Cannons
    - Ball launchers
    - Any projectile-based weapon

    ============================================================================
    LAUNCH METHODS
    ============================================================================

    impulse:
        Sets AssemblyLinearVelocity directly.
        Quick, simple launch with immediate velocity.

    spring:
        Creates temporary SpringConstraint to fling projectile.
        More physical feel with acceleration.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onFire({ targetPosition?: Vector3 })
            - With targetPosition: calculate direction to target
            - Without: fire in muzzle LookVector direction (blind fire)

        onConfigure({ launchForce?, cooldown?, projectileTemplate?, ... })
            - Update configuration

    OUT (emits):
        fired({ projectile: Instance, direction: Vector3, assetId: string })
            - Projectile spawned and launched

    Err (detour):
        onCooldown({ remaining: number })
            - Fire attempted before cooldown expired

    ============================================================================
    ATTRIBUTES
    ============================================================================

    ProjectileTemplate: string (default nil)
        Template name for SpawnerCore

    LaunchForce: number (default 100)
        Impulse strength or spring force

    LaunchMethod: string (default "impulse")
        "impulse" or "spring"

    Cooldown: number (default 0.5)
        Min seconds between shots

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local launcher = Launcher:new({ model = workspace.TurretMuzzle })
    launcher.Sys.onInit(launcher)
    launcher.In.onConfigure(launcher, {
        projectileTemplate = "Bullet",
        launchForce = 150,
        cooldown = 0.2,
    })

    -- Fire at a target
    launcher.In.onFire(launcher, { targetPosition = enemy.Position })

    -- Or blind fire in muzzle direction
    launcher.In.onFire(launcher)

    -- Wire output to track projectiles
    launcher.Out = {
        Fire = function(self, signal, data)
            if signal == "fired" then
                print("Launched projectile:", data.assetId)
            end
        end,
    }
    ```

--]]

local Node = require(script.Parent.Parent.Node)
local SpawnerCore = require(script.Parent.Parent.Internal.SpawnerCore)

--------------------------------------------------------------------------------
-- LAUNCHER NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Launcher = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                lastFireTime = 0,
                muzzle = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Get muzzle position and direction.
    --]]
    local function getMuzzleInfo(self)
        local state = getState(self)
        if state.muzzle then
            return state.muzzle.Position, state.muzzle.CFrame.LookVector
        end
        return Vector3.new(0, 0, 0), Vector3.new(0, 0, -1)
    end

    --[[
        Private: Get the primary physics part of a projectile.
    --]]
    local function getPhysicsPart(projectile)
        if projectile:IsA("BasePart") then
            return projectile
        elseif projectile:IsA("Model") then
            return projectile.PrimaryPart or projectile:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end

    --[[
        Private: Prepare projectile for physics.
        Unanchor, enable collisions, setup mass.
    --]]
    local function prepareProjectile(projectile)
        local function preparePart(part)
            if part:IsA("BasePart") then
                part.Anchored = false
                part.CanCollide = true

                -- Add BodyForce to counteract gravity (tracer behavior)
                -- This is more compatible than AssemblyGravityModifier
                local mass = part:GetMass()
                local antiGravity = Instance.new("BodyForce")
                antiGravity.Name = "AntiGravity"
                antiGravity.Force = Vector3.new(0, mass * workspace.Gravity, 0)
                antiGravity.Parent = part
            end
        end

        if projectile:IsA("BasePart") then
            preparePart(projectile)
        elseif projectile:IsA("Model") then
            for _, desc in ipairs(projectile:GetDescendants()) do
                preparePart(desc)
            end
            -- Prepare PrimaryPart if it exists
            if projectile.PrimaryPart then
                preparePart(projectile.PrimaryPart)
            end
        end
    end

    --[[
        Private: Launch using direct velocity (impulse method).
    --]]
    local function launchImpulse(projectile, direction, force)
        local physicsPart = getPhysicsPart(projectile)
        if not physicsPart then
            return
        end

        -- Set velocity directly
        physicsPart.AssemblyLinearVelocity = direction * force
    end

    --[[
        Private: Launch using spring constraint (spring method).
    --]]
    local function launchSpring(projectile, direction, force)
        local physicsPart = getPhysicsPart(projectile)
        if not physicsPart then
            return
        end

        -- Create temporary attachment for spring
        local projectileAttachment = Instance.new("Attachment")
        projectileAttachment.Name = "LaunchAttachment"
        projectileAttachment.Parent = physicsPart

        -- Create anchor part behind projectile
        local anchorPosition = physicsPart.Position - direction * 2
        local anchorAttachment = Instance.new("Attachment")
        anchorAttachment.Name = "AnchorAttachment"
        anchorAttachment.WorldPosition = anchorPosition
        anchorAttachment.Parent = workspace.Terrain

        -- Create spring constraint
        local spring = Instance.new("SpringConstraint")
        spring.Name = "LaunchSpring"
        spring.Attachment0 = anchorAttachment
        spring.Attachment1 = projectileAttachment
        spring.Stiffness = force * 10  -- Convert to spring stiffness
        spring.Damping = 0
        spring.FreeLength = 0.1  -- Compressed
        spring.LimitsEnabled = false
        spring.Parent = physicsPart

        -- Release by destroying spring after brief moment
        task.delay(0.05, function()
            if spring and spring.Parent then
                spring:Destroy()
            end
            if projectileAttachment and projectileAttachment.Parent then
                projectileAttachment:Destroy()
            end
            if anchorAttachment and anchorAttachment.Parent then
                anchorAttachment:Destroy()
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "Launcher",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Get muzzle from model
                if self.model then
                    if self.model:IsA("BasePart") then
                        state.muzzle = self.model
                    elseif self.model:IsA("Model") and self.model.PrimaryPart then
                        state.muzzle = self.model.PrimaryPart
                    end
                end

                -- Ensure SpawnerCore is initialized
                if not SpawnerCore.isInitialized() then
                    SpawnerCore.init({
                        templates = game:GetService("ReplicatedStorage"):FindFirstChild("Templates"),
                    })
                end

                -- Default attributes
                if not self:getAttribute("ProjectileTemplate") then
                    self:setAttribute("ProjectileTemplate", "")
                end
                if not self:getAttribute("LaunchForce") then
                    self:setAttribute("LaunchForce", 100)
                end
                if not self:getAttribute("LaunchMethod") then
                    self:setAttribute("LaunchMethod", "impulse")
                end
                if not self:getAttribute("Cooldown") then
                    self:setAttribute("Cooldown", 0.5)
                end
            end,

            onStart = function(self)
                -- Nothing additional on start
            end,

            onStop = function(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Configure launcher settings.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                if data.projectileTemplate then
                    self:setAttribute("ProjectileTemplate", data.projectileTemplate)
                end

                if data.launchForce then
                    self:setAttribute("LaunchForce", math.abs(data.launchForce))
                end

                if data.launchMethod then
                    local method = string.lower(data.launchMethod)
                    if method == "impulse" or method == "spring" then
                        self:setAttribute("LaunchMethod", method)
                    end
                end

                if data.cooldown then
                    self:setAttribute("Cooldown", math.max(0, data.cooldown))
                end
            end,

            --[[
                Fire a projectile.
                With targetPosition: calculate direction to target.
                Without: fire in muzzle LookVector direction.
            --]]
            onFire = function(self, data)
                data = data or {}
                local state = getState(self)

                -- Check cooldown
                local cooldown = self:getAttribute("Cooldown") or 0.5
                local currentTime = os.clock()
                local timeSinceFire = currentTime - state.lastFireTime

                if timeSinceFire < cooldown then
                    self.Err:Fire({
                        reason = "cooldown",
                        message = "Fire attempted before cooldown expired",
                        remaining = cooldown - timeSinceFire,
                    })
                    return
                end

                -- Get template name
                local templateName = self:getAttribute("ProjectileTemplate")
                if not templateName or templateName == "" then
                    self.Err:Fire({
                        reason = "no_template",
                        message = "ProjectileTemplate not configured",
                        launcherId = self.id,
                    })
                    return
                end

                -- Get muzzle position and direction
                local muzzlePosition, muzzleDirection = getMuzzleInfo(self)

                -- Calculate direction
                local direction
                if data.targetPosition then
                    direction = (data.targetPosition - muzzlePosition).Unit
                else
                    direction = muzzleDirection
                end

                -- Spawn projectile
                local result, err = SpawnerCore.spawn({
                    templateName = templateName,
                    parent = workspace,
                    cframe = CFrame.new(muzzlePosition, muzzlePosition + direction),
                    attributes = {
                        NodeClass = templateName,
                        NodeSpawnSource = self.id,
                        LaunchTime = currentTime,
                    },
                })

                if not result then
                    self.Err:Fire({
                        reason = "spawn_failed",
                        message = err or "Unknown spawn error",
                        launcherId = self.id,
                        templateName = templateName,
                    })
                    return
                end

                local projectile = result.instance

                -- Make projectile physics-enabled
                prepareProjectile(projectile)

                -- Apply launch force
                local launchMethod = self:getAttribute("LaunchMethod") or "impulse"
                local launchForce = self:getAttribute("LaunchForce") or 100

                if launchMethod == "impulse" then
                    launchImpulse(projectile, direction, launchForce)
                else -- spring
                    launchSpring(projectile, direction, launchForce)
                end

                -- Update cooldown timer
                state.lastFireTime = currentTime

                -- Fire output signal
                self.Out:Fire("fired", {
                    projectile = projectile,
                    direction = direction,
                    assetId = result.assetId,
                    launcherId = self.id,
                })
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            fired = {},  -- { projectile: Instance, direction: Vector3, assetId: string }
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS (intentionally exposed)
        ------------------------------------------------------------------------

        --[[
            Check if ready to fire (cooldown elapsed).
        --]]
        isReady = function(self)
            local state = getState(self)
            local cooldown = self:getAttribute("Cooldown") or 0.5
            local timeSinceFire = os.clock() - state.lastFireTime
            return timeSinceFire >= cooldown
        end,

        --[[
            Get time remaining until ready to fire.
        --]]
        getCooldownRemaining = function(self)
            local state = getState(self)
            local cooldown = self:getAttribute("Cooldown") or 0.5
            local timeSinceFire = os.clock() - state.lastFireTime
            return math.max(0, cooldown - timeSinceFire)
        end,
    }
end)

return Launcher
