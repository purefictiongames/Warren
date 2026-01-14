--[[
    LibPureFiction Framework v2
    Launcher Component Demo

    Demonstrates physics-based projectile firing with visual feedback.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar:

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    local demo = Demos.Launcher.run()

    -- Controls:
    demo.fire()                    -- Fire in muzzle direction
    demo.fireAt(position)          -- Fire at target position
    demo.setForce(200)             -- Change launch force
    demo.setMethod("spring")       -- Change launch method
    demo.setCooldown(0.2)          -- Change cooldown
    demo.cleanup()                 -- Remove demo objects
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Launcher = Lib.Components.Launcher

-- Internal access for template setup
local SpawnerCore = require(ReplicatedStorage.Lib.Internal.SpawnerCore)

local Demo = {}

function Demo.run(config)
    config = config or {}
    local position = config.position or Vector3.new(0, 10, 0)

    ---------------------------------------------------------------------------
    -- CLEANUP EXISTING DEMO (handles Studio persistence between runs)
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("Launcher_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end

    ---------------------------------------------------------------------------
    -- CREATE PROJECTILE TEMPLATE
    ---------------------------------------------------------------------------

    local templateFolder = ReplicatedStorage:FindFirstChild("Templates")
    if not templateFolder then
        templateFolder = Instance.new("Folder")
        templateFolder.Name = "Templates"
        templateFolder.Parent = ReplicatedStorage
    end

    -- Remove old template if exists (we want the upgraded tracer)
    local oldTemplate = templateFolder:FindFirstChild("DemoBullet")
    if oldTemplate then
        oldTemplate:Destroy()
    end

    -- Create highly visible tracer round
    local bulletTemplate = Instance.new("Part")
    bulletTemplate.Name = "DemoBullet"
    bulletTemplate.Size = Vector3.new(0.6, 0.6, 2.5)  -- Larger, elongated bullet
    bulletTemplate.BrickColor = BrickColor.new("Bright yellow")
    bulletTemplate.Color = Color3.new(1, 0.9, 0.2)  -- Bright yellow-orange
    bulletTemplate.Material = Enum.Material.Neon
    bulletTemplate.Anchored = true  -- Will be unanchored on spawn
    bulletTemplate.CanCollide = false
    bulletTemplate.CastShadow = false
    bulletTemplate.Parent = templateFolder

    -- Add glowing point light for visibility
    local glow = Instance.new("PointLight")
    glow.Name = "TracerGlow"
    glow.Color = Color3.new(1, 0.6, 0)
    glow.Brightness = 3
    glow.Range = 12
    glow.Parent = bulletTemplate

    -- Trail attachments - positioned at front and back of bullet
    local attachment0 = Instance.new("Attachment")
    attachment0.Name = "TrailFront"
    attachment0.Position = Vector3.new(0, 0, -1.25)  -- Front of bullet
    attachment0.Parent = bulletTemplate

    local attachment1 = Instance.new("Attachment")
    attachment1.Name = "TrailBack"
    attachment1.Position = Vector3.new(0, 0, 1.25)   -- Back of bullet
    attachment1.Parent = bulletTemplate

    -- Main tracer trail - bright and long
    local trail = Instance.new("Trail")
    trail.Name = "TracerTrail"
    trail.Attachment0 = attachment0
    trail.Attachment1 = attachment1
    trail.Lifetime = 1.5  -- Long trail for visibility
    trail.MinLength = 0.05
    trail.FaceCamera = true
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.3, 0.8),
        NumberSequenceKeypoint.new(1, 0.1),
    })
    trail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 0.8)),      -- White-yellow at head
        ColorSequenceKeypoint.new(0.2, Color3.new(1, 0.7, 0.1)),  -- Orange
        ColorSequenceKeypoint.new(1, Color3.new(1, 0.3, 0)),      -- Red at tail
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.LightEmission = 1  -- Glowing trail
    trail.LightInfluence = 0
    trail.Parent = bulletTemplate

    -- Initialize SpawnerCore
    if not SpawnerCore.isInitialized() then
        SpawnerCore.init({ templates = templateFolder })
    end

    ---------------------------------------------------------------------------
    -- CREATE VISUAL SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "Launcher_Demo"
    demoFolder.Parent = workspace

    -- Launcher base
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(4, 2, 4)
    base.Position = position - Vector3.new(0, 1, 0)
    base.Anchored = true
    base.BrickColor = BrickColor.new("Dark stone grey")
    base.Material = Enum.Material.Metal
    base.Parent = demoFolder

    -- Muzzle (the firing point)
    local muzzle = Instance.new("Part")
    muzzle.Name = "Muzzle"
    muzzle.Size = Vector3.new(1.5, 1.5, 4)
    muzzle.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, 0)
    muzzle.Anchored = true
    muzzle.BrickColor = BrickColor.new("Bright blue")
    muzzle.Material = Enum.Material.SmoothPlastic
    muzzle.Parent = demoFolder

    -- Muzzle flash indicator
    local muzzleFlash = Instance.new("Part")
    muzzleFlash.Name = "MuzzleFlash"
    muzzleFlash.Size = Vector3.new(0.8, 0.8, 0.2)
    muzzleFlash.CFrame = muzzle.CFrame * CFrame.new(0, 0, -2.1)
    muzzleFlash.Anchored = true
    muzzleFlash.CanCollide = false
    muzzleFlash.BrickColor = BrickColor.new("Bright orange")
    muzzleFlash.Material = Enum.Material.Neon
    muzzleFlash.Transparency = 1
    muzzleFlash.Parent = demoFolder

    -- Target ring (for aiming visualization)
    local targetRing = Instance.new("Part")
    targetRing.Name = "TargetRing"
    targetRing.Size = Vector3.new(6, 0.2, 6)
    targetRing.Position = position + Vector3.new(0, -5, -30)
    targetRing.Anchored = true
    targetRing.BrickColor = BrickColor.new("Bright red")
    targetRing.Material = Enum.Material.Neon
    targetRing.Transparency = 0.5
    targetRing.Shape = Enum.PartType.Cylinder
    targetRing.Orientation = Vector3.new(0, 0, 90)
    targetRing.Parent = demoFolder

    -- Status display
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 200, 0, 80)
    billboardGui.StudsOffset = Vector3.new(0, 4, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = muzzle

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundTransparency = 0.3
    statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    statusLabel.TextColor3 = Color3.new(0, 1, 0)
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.Code
    statusLabel.Text = "LAUNCHER: READY\nShots: 0"
    statusLabel.Parent = billboardGui

    -- Projectile tracking
    local projectileFolder = Instance.new("Folder")
    projectileFolder.Name = "Projectiles"
    projectileFolder.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- CREATE LAUNCHER COMPONENT
    ---------------------------------------------------------------------------

    local launcher = Launcher:new({
        id = "Demo_Launcher",
        model = muzzle,
    })
    launcher.Sys.onInit(launcher)

    -- Configure launcher
    launcher.In.onConfigure(launcher, {
        projectileTemplate = "DemoBullet",
        launchForce = 80,  -- Slower for visible tracer flight
        launchMethod = "impulse",
        cooldown = 0.3,
    })

    -- Track stats
    local shotsFired = 0

    -- Wire output
    launcher.Out = {
        Fire = function(self, signal, data)
            if signal == "fired" then
                shotsFired = shotsFired + 1
                statusLabel.Text = string.format("FIRED!\nShots: %d", shotsFired)
                statusLabel.TextColor3 = Color3.new(1, 0.5, 0)

                -- Muzzle flash effect
                muzzleFlash.Transparency = 0
                task.delay(0.05, function()
                    if muzzleFlash.Parent then
                        muzzleFlash.Transparency = 1
                    end
                end)

                -- Parent projectile to folder for tracking
                if data.projectile and data.projectile.Parent then
                    data.projectile.Parent = projectileFolder
                end

                -- Reset status after short delay
                task.delay(0.2, function()
                    if statusLabel.Parent then
                        statusLabel.Text = string.format("LAUNCHER: READY\nShots: %d", shotsFired)
                        statusLabel.TextColor3 = Color3.new(0, 1, 0)
                    end
                end)
            end
        end,
    }

    -- Wire error output
    launcher.Err = {
        Fire = function(self, data)
            if data.reason == "cooldown" then
                statusLabel.Text = string.format("COOLDOWN: %.1fs\nShots: %d",
                    data.remaining, shotsFired)
                statusLabel.TextColor3 = Color3.new(1, 0, 0)
            end
        end,
    }

    -- Update muzzle flash position
    local updateConnection = RunService.Heartbeat:Connect(function()
        if muzzle.Parent and muzzleFlash.Parent then
            muzzleFlash.CFrame = muzzle.CFrame * CFrame.new(0, 0, -2.1)
        end
    end)

    -- Auto-cleanup old projectiles
    local cleanupConnection = RunService.Heartbeat:Connect(function()
        for _, proj in ipairs(projectileFolder:GetChildren()) do
            -- Remove projectiles that fall below certain height or go too far
            if proj:IsA("BasePart") then
                if proj.Position.Y < -50 or proj.Position.Magnitude > 500 then
                    proj:Destroy()
                end
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- DEMO CONTROLS
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.fire()
        launcher.In.onFire(launcher)
    end

    function controls.fireAt(targetPosition)
        targetPosition = targetPosition or targetRing.Position
        launcher.In.onFire(launcher, { targetPosition = targetPosition })
    end

    function controls.setForce(force)
        launcher.In.onConfigure(launcher, { launchForce = force })
        print("Launch force set to:", force)
    end

    function controls.setMethod(method)
        launcher.In.onConfigure(launcher, { launchMethod = method })
        print("Launch method set to:", method)
    end

    function controls.setCooldown(cooldown)
        launcher.In.onConfigure(launcher, { cooldown = cooldown })
        print("Cooldown set to:", cooldown)
    end

    function controls.aimAt(direction)
        muzzle.CFrame = CFrame.new(muzzle.Position, muzzle.Position + direction)
    end

    function controls.setMuzzleAngle(pitch, yaw)
        pitch = math.rad(pitch or 0)
        yaw = math.rad(yaw or 0)
        muzzle.CFrame = CFrame.new(muzzle.Position) * CFrame.Angles(pitch, yaw, 0)
    end

    function controls.moveTarget(newPosition)
        targetRing.Position = newPosition
    end

    function controls.clearProjectiles()
        projectileFolder:ClearAllChildren()
    end

    function controls.isReady()
        return launcher:isReady()
    end

    function controls.getCooldownRemaining()
        return launcher:getCooldownRemaining()
    end

    function controls.cleanup()
        updateConnection:Disconnect()
        cleanupConnection:Disconnect()
        launcher.Sys.onStop(launcher)
        demoFolder:Destroy()
    end

    function controls.getLauncher()
        return launcher
    end

    ---------------------------------------------------------------------------
    -- AUTO-DEMO (optional)
    ---------------------------------------------------------------------------

    if config.autoDemo then
        task.spawn(function()
            -- Continuous firing at target
            while demoFolder.Parent do
                controls.fireAt()
                task.wait(0.5)
            end
        end)
    end

    print("Launcher Demo running. Controls:")
    print("  demo.fire()              - Fire in muzzle direction")
    print("  demo.fireAt(pos)         - Fire at target position")
    print("  demo.setForce(200)       - Change launch force")
    print("  demo.setMethod('spring') - Change launch method")
    print("  demo.setCooldown(0.2)    - Change cooldown")
    print("  demo.cleanup()           - Remove demo")

    return controls
end

return Demo
