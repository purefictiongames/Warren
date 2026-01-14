--[[
    LibPureFiction Framework v2
    Turret System Demo - Fully Automated Showcase

    Demonstrates all turret components and API calls automatically.
    Just run and watch!

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar:

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    local demo = Demos.Turret.run()
    -- Sit back and watch the automated demo!

    -- To stop early:
    demo.cleanup()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

local Swivel = Lib.Components.Swivel
local Targeter = Lib.Components.Targeter
local Launcher = Lib.Components.Launcher

local SpawnerCore = require(ReplicatedStorage.Lib.Internal.SpawnerCore)

local Demo = {}

function Demo.run(config)
    config = config or {}
    local position = config.position or Vector3.new(0, 5, 0)

    ---------------------------------------------------------------------------
    -- CLEANUP EXISTING DEMO (handles Studio persistence between runs)
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("Turret_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end

    -- Clean up old template to ensure fresh tracer settings
    local templateFolder = ReplicatedStorage:FindFirstChild("Templates")
    if templateFolder then
        local oldBullet = templateFolder:FindFirstChild("TurretBullet")
        if oldBullet then
            oldBullet:Destroy()
        end
    end

    ---------------------------------------------------------------------------
    -- ANNOUNCEMENT SYSTEM
    ---------------------------------------------------------------------------

    local function announce(text, duration)
        duration = duration or 2
        print("[DEMO] " .. text)
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
    local oldTemplate = templateFolder:FindFirstChild("TurretBullet")
    if oldTemplate then
        oldTemplate:Destroy()
    end

    -- Create highly visible tracer round
    local bulletTemplate = Instance.new("Part")
    bulletTemplate.Name = "TurretBullet"
    bulletTemplate.Size = Vector3.new(0.6, 0.6, 2.5)  -- Larger, elongated bullet
    bulletTemplate.BrickColor = BrickColor.new("Bright yellow")
    bulletTemplate.Color = Color3.new(1, 0.9, 0.2)  -- Bright yellow-orange
    bulletTemplate.Material = Enum.Material.Neon
    bulletTemplate.Anchored = true
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
    local trailAttach0 = Instance.new("Attachment")
    trailAttach0.Name = "TrailFront"
    trailAttach0.Position = Vector3.new(0, 0, -1.25)  -- Front of bullet
    trailAttach0.Parent = bulletTemplate

    local trailAttach1 = Instance.new("Attachment")
    trailAttach1.Name = "TrailBack"
    trailAttach1.Position = Vector3.new(0, 0, 1.25)   -- Back of bullet
    trailAttach1.Parent = bulletTemplate

    -- Main tracer trail - bright and long
    local trail = Instance.new("Trail")
    trail.Name = "TracerTrail"
    trail.Attachment0 = trailAttach0
    trail.Attachment1 = trailAttach1
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

    if not SpawnerCore.isInitialized() then
        SpawnerCore.init({ templates = templateFolder })
    end

    ---------------------------------------------------------------------------
    -- CREATE TURRET VISUAL MODEL
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "Turret_Demo"
    demoFolder.Parent = workspace

    -- Ground plane
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(200, 1, 200)
    ground.Position = Vector3.new(0, -1, 0)
    ground.Anchored = true
    ground.BrickColor = BrickColor.new("Dark stone grey")
    ground.Material = Enum.Material.Slate
    ground.Parent = demoFolder

    -- Base platform
    local basePlatform = Instance.new("Part")
    basePlatform.Name = "BasePlatform"
    basePlatform.Size = Vector3.new(8, 1, 8)
    basePlatform.Position = position - Vector3.new(0, 2, 0)
    basePlatform.Anchored = true
    basePlatform.BrickColor = BrickColor.new("Really black")
    basePlatform.Material = Enum.Material.DiamondPlate
    basePlatform.Parent = demoFolder

    -- Yaw base
    local yawBase = Instance.new("Part")
    yawBase.Name = "YawBase"
    yawBase.Size = Vector3.new(5, 2, 5)
    yawBase.CFrame = CFrame.new(position)
    yawBase.Anchored = true
    yawBase.BrickColor = BrickColor.new("Medium stone grey")
    yawBase.Material = Enum.Material.Metal
    yawBase.Parent = demoFolder

    -- Pitch arm
    local pitchArm = Instance.new("Part")
    pitchArm.Name = "PitchArm"
    pitchArm.Size = Vector3.new(1.5, 1.5, 4)
    pitchArm.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
    pitchArm.Anchored = true
    pitchArm.BrickColor = BrickColor.new("Bright blue")
    pitchArm.Material = Enum.Material.SmoothPlastic
    pitchArm.Parent = demoFolder

    -- Scanner
    local scanner = Instance.new("Part")
    scanner.Name = "Scanner"
    scanner.Size = Vector3.new(0.5, 0.5, 0.5)
    scanner.CFrame = pitchArm.CFrame * CFrame.new(0, 0.5, -1.5)
    scanner.Anchored = true
    scanner.BrickColor = BrickColor.new("Medium stone grey")
    scanner.Material = Enum.Material.Neon
    scanner.Shape = Enum.PartType.Ball
    scanner.Parent = demoFolder

    -- Muzzle
    local muzzle = Instance.new("Part")
    muzzle.Name = "Muzzle"
    muzzle.Size = Vector3.new(0.6, 0.6, 1)
    muzzle.CFrame = pitchArm.CFrame * CFrame.new(0, 0, -2.5)
    muzzle.Anchored = true
    muzzle.BrickColor = BrickColor.new("Really black")
    muzzle.Material = Enum.Material.Metal
    muzzle.Parent = demoFolder

    -- Muzzle flash
    local muzzleFlash = Instance.new("Part")
    muzzleFlash.Name = "MuzzleFlash"
    muzzleFlash.Size = Vector3.new(0.8, 0.8, 0.2)
    muzzleFlash.CFrame = muzzle.CFrame * CFrame.new(0, 0, -0.6)
    muzzleFlash.Anchored = true
    muzzleFlash.CanCollide = false
    muzzleFlash.BrickColor = BrickColor.new("Bright yellow")
    muzzleFlash.Material = Enum.Material.Neon
    muzzleFlash.Transparency = 1
    muzzleFlash.Parent = demoFolder

    -- Main status billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 400, 0, 120)
    billboard.StudsOffset = Vector3.new(0, 8, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = yawBase

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundTransparency = 0.2
    statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    statusLabel.TextColor3 = Color3.new(0, 1, 0)
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.Code
    statusLabel.Text = "TURRET SYSTEM DEMO\nInitializing..."
    statusLabel.Parent = billboard

    -- Phase indicator
    local phaseBillboard = Instance.new("BillboardGui")
    phaseBillboard.Size = UDim2.new(0, 500, 0, 60)
    phaseBillboard.StudsOffset = Vector3.new(0, 12, 0)
    phaseBillboard.AlwaysOnTop = true
    phaseBillboard.Parent = yawBase

    local phaseLabel = Instance.new("TextLabel")
    phaseLabel.Size = UDim2.new(1, 0, 1, 0)
    phaseLabel.BackgroundTransparency = 0.3
    phaseLabel.BackgroundColor3 = Color3.new(0.2, 0.2, 0.5)
    phaseLabel.TextColor3 = Color3.new(1, 1, 1)
    phaseLabel.TextScaled = true
    phaseLabel.Font = Enum.Font.GothamBold
    phaseLabel.Text = "INITIALIZING"
    phaseLabel.Parent = phaseBillboard

    -- Target & projectile folders
    local targetFolder = Instance.new("Folder")
    targetFolder.Name = "Enemies"
    targetFolder.Parent = demoFolder

    local projectileFolder = Instance.new("Folder")
    projectileFolder.Name = "Projectiles"
    projectileFolder.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- CREATE TURRET COMPONENTS
    ---------------------------------------------------------------------------

    local yawSwivel = Swivel:new({ id = "Turret_YawSwivel", model = yawBase })
    yawSwivel.Sys.onInit(yawSwivel)
    yawSwivel.In.onConfigure(yawSwivel, {
        axis = "Y", mode = "continuous", speed = 120,
        minAngle = -180, maxAngle = 180,
    })

    local pitchSwivel = Swivel:new({ id = "Turret_PitchSwivel", model = pitchArm })
    pitchSwivel.Sys.onInit(pitchSwivel)
    pitchSwivel.In.onConfigure(pitchSwivel, {
        axis = "X", mode = "continuous", speed = 90,
        minAngle = -30, maxAngle = 60,
    })

    local targeter = Targeter:new({ id = "Turret_Targeter", model = scanner })
    targeter.Sys.onInit(targeter)
    targeter.In.onConfigure(targeter, {
        beamMode = "cone", beamRadius = 5, rayCount = 12,
        range = 100, scanMode = "continuous", trackingMode = "lock",
        filter = { class = "Enemy" },
    })

    local launcher = Launcher:new({ id = "Turret_Launcher", model = muzzle })
    launcher.Sys.onInit(launcher)
    launcher.In.onConfigure(launcher, {
        projectileTemplate = "TurretBullet",
        launchForce = 80,  -- Slower for visible tracer flight
        launchMethod = "impulse",
        cooldown = 0.2,
    })

    ---------------------------------------------------------------------------
    -- CONTROLLER STATE
    ---------------------------------------------------------------------------

    local controller = {
        active = false,
        currentTarget = nil,
        shotsFired = 0,
        running = true,
    }

    local function calculateAimAngles(targetPosition)
        local turretPos = yawBase.Position
        local toTarget = targetPosition - turretPos
        local yawAngle = math.deg(math.atan2(toTarget.X, -toTarget.Z))
        local horizontalDist = math.sqrt(toTarget.X^2 + toTarget.Z^2)
        local pitchAngle = math.deg(math.atan2(toTarget.Y - 1.5, horizontalDist))
        return yawAngle, pitchAngle
    end

    -- Wire outputs
    targeter.Out = {
        Fire = function(self, signal, data)
            if not controller.active then return end
            if signal == "acquired" or signal == "tracking" then
                local closest = data.targets[1]
                if closest then
                    controller.currentTarget = closest
                    if closest.target:IsA("BasePart") then
                        closest.target.BrickColor = BrickColor.new("Bright orange")
                    end
                end
            elseif signal == "lost" then
                controller.currentTarget = nil
                for _, enemy in ipairs(targetFolder:GetChildren()) do
                    if enemy:IsA("BasePart") then
                        enemy.BrickColor = BrickColor.new("Bright red")
                    end
                end
            end
        end,
    }

    launcher.Out = {
        Fire = function(self, signal, data)
            if signal == "fired" then
                controller.shotsFired = controller.shotsFired + 1
                muzzleFlash.Transparency = 0
                task.delay(0.03, function()
                    if muzzleFlash.Parent then muzzleFlash.Transparency = 1 end
                end)
                if data.projectile then
                    data.projectile.Parent = projectileFolder
                end
            end
        end,
    }

    ---------------------------------------------------------------------------
    -- GEOMETRY UPDATE
    ---------------------------------------------------------------------------

    local function updateTurretGeometry()
        local yawCFrame = yawBase.CFrame
        local pitchOffset = CFrame.new(0, 1.5, 0)
        local pitchRotation = CFrame.Angles(math.rad(-pitchSwivel:getCurrentAngle()), 0, 0)
        local combinedCFrame = yawCFrame * pitchOffset * pitchRotation
        pitchArm.CFrame = combinedCFrame
        scanner.CFrame = combinedCFrame * CFrame.new(0, 0.5, -1.5)
        muzzle.CFrame = combinedCFrame * CFrame.new(0, 0, -2.5)
        muzzleFlash.CFrame = muzzle.CFrame * CFrame.new(0, 0, -0.6)
    end

    ---------------------------------------------------------------------------
    -- HELPER FUNCTIONS
    ---------------------------------------------------------------------------

    local targetCounter = 0

    local function spawnEnemy(pos, moving)
        targetCounter = targetCounter + 1
        local enemy = Instance.new("Part")
        enemy.Name = "Enemy_" .. targetCounter
        enemy.Size = Vector3.new(4, 4, 4)
        enemy.Position = pos
        enemy.Anchored = true
        enemy.BrickColor = BrickColor.new("Bright red")
        enemy.Material = Enum.Material.SmoothPlastic
        enemy:SetAttribute("NodeClass", "Enemy")
        enemy.Parent = targetFolder

        if moving then
            task.spawn(function()
                local startPos = pos
                local t = math.random() * math.pi * 2
                local speed = 0.03 + math.random() * 0.02
                while enemy.Parent and controller.running do
                    t = t + speed
                    enemy.Position = startPos + Vector3.new(
                        math.sin(t) * 15,
                        math.sin(t * 1.3) * 5,
                        math.cos(t * 0.7) * 15
                    )
                    task.wait()
                end
            end)
        end
        return enemy
    end

    local function clearEnemies()
        targetFolder:ClearAllChildren()
        controller.currentTarget = nil
    end

    local function clearProjectiles()
        projectileFolder:ClearAllChildren()
    end

    local function setPhase(text)
        phaseLabel.Text = text
        announce(text)
    end

    local function setStatus(text, color)
        statusLabel.Text = text
        statusLabel.TextColor3 = color or Color3.new(0, 1, 0)
    end

    ---------------------------------------------------------------------------
    -- MAIN CONTROL LOOP
    ---------------------------------------------------------------------------

    local controlConnection = RunService.Heartbeat:Connect(function(dt)
        if not demoFolder.Parent or not controller.running then return end

        updateTurretGeometry()

        if not controller.active then return end

        if controller.currentTarget then
            local targetPos = controller.currentTarget.position
            local yawAngle, pitchAngle = calculateAimAngles(targetPos)
            local currentYaw = yawSwivel:getCurrentAngle()
            local currentPitch = pitchSwivel:getCurrentAngle()

            local yawDiff = yawAngle - currentYaw
            local pitchDiff = pitchAngle - currentPitch

            while yawDiff > 180 do yawDiff = yawDiff - 360 end
            while yawDiff < -180 do yawDiff = yawDiff + 360 end

            local aimThreshold = 5

            if math.abs(yawDiff) > 1 then
                local direction = yawDiff > 0 and "forward" or "reverse"
                yawSwivel.In.onRotate(yawSwivel, { direction = direction })
            else
                yawSwivel.In.onStop(yawSwivel)
            end

            if math.abs(pitchDiff) > 1 then
                local direction = pitchDiff > 0 and "reverse" or "forward"
                pitchSwivel.In.onRotate(pitchSwivel, { direction = direction })
            else
                pitchSwivel.In.onStop(pitchSwivel)
            end

            if math.abs(yawDiff) < aimThreshold and math.abs(pitchDiff) < aimThreshold then
                if launcher:isReady() then
                    launcher.In.onFire(launcher, { targetPosition = targetPos })
                end
            end
        else
            yawSwivel.In.onStop(yawSwivel)
            pitchSwivel.In.onStop(pitchSwivel)
        end
    end)

    -- Cleanup old projectiles
    local cleanupConnection = RunService.Heartbeat:Connect(function()
        for _, proj in ipairs(projectileFolder:GetChildren()) do
            if proj:IsA("BasePart") then
                if proj.Position.Y < -20 or proj.Position.Magnitude > 300 then
                    proj:Destroy()
                end
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- AUTOMATED DEMO SEQUENCE
    ---------------------------------------------------------------------------

    task.spawn(function()
        task.wait(1)

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 1: SWIVEL DEMONSTRATION
        -----------------------------------------------------------------------
        setPhase("PHASE 1: SWIVEL COMPONENT")
        setStatus("Demonstrating Swivel\nSingle-axis rotation", Color3.new(0, 0.7, 1))
        task.wait(1)

        -- Yaw rotation demo
        setStatus("Yaw Swivel: Rotating Forward\nSpeed: 120 deg/sec", Color3.new(0, 0.7, 1))
        yawSwivel.In.onRotate(yawSwivel, { direction = "forward" })
        task.wait(2)

        setStatus("Yaw Swivel: Rotating Reverse", Color3.new(0, 0.7, 1))
        yawSwivel.In.onRotate(yawSwivel, { direction = "reverse" })
        task.wait(2)

        setStatus("Yaw Swivel: Stop", Color3.new(0, 0.7, 1))
        yawSwivel.In.onStop(yawSwivel)
        task.wait(0.5)

        -- Pitch rotation demo
        setStatus("Pitch Swivel: Looking Up\nMin: -30, Max: 60 degrees", Color3.new(0, 0.7, 1))
        pitchSwivel.In.onRotate(pitchSwivel, { direction = "reverse" })
        task.wait(1.5)

        setStatus("Pitch Swivel: Looking Down", Color3.new(0, 0.7, 1))
        pitchSwivel.In.onRotate(pitchSwivel, { direction = "forward" })
        task.wait(1.5)
        pitchSwivel.In.onStop(pitchSwivel)

        -- Direct angle setting
        setStatus("Swivel: setAngle(45)\nDirect positioning", Color3.new(0, 0.7, 1))
        yawSwivel.In.onSetAngle(yawSwivel, { degrees = 45 })
        task.wait(1)

        setStatus("Swivel: setAngle(0)\nReturning to center", Color3.new(0, 0.7, 1))
        yawSwivel.In.onSetAngle(yawSwivel, { degrees = 0 })
        pitchSwivel.In.onSetAngle(pitchSwivel, { degrees = 0 })
        task.wait(1)

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 2: TARGETER DEMONSTRATION
        -----------------------------------------------------------------------
        setPhase("PHASE 2: TARGETER COMPONENT")
        setStatus("Demonstrating Targeter\nRaycast-based detection", Color3.new(0, 1, 0.5))
        task.wait(1)

        -- Enable scanning
        setStatus("Targeter: onEnable()\nScanning for targets...", Color3.new(0, 1, 0.5))
        scanner.BrickColor = BrickColor.new("Bright green")
        targeter.In.onEnable(targeter)
        task.wait(2)

        -- Spawn a target
        setStatus("Spawning target...\nFilter: { class = 'Enemy' }", Color3.new(0, 1, 0.5))
        local enemy1 = spawnEnemy(position + Vector3.new(0, 5, -30), false)
        task.wait(2)

        setStatus("TARGET ACQUIRED!\nTracking mode: 'lock'", Color3.new(1, 0.5, 0))
        task.wait(2)

        -- Change beam mode
        setStatus("Changing beam mode...\nbeamMode: 'pinpoint'", Color3.new(0, 1, 0.5))
        targeter.In.onConfigure(targeter, { beamMode = "pinpoint" })
        task.wait(1.5)

        setStatus("beamMode: 'cylinder'\nParallel rays in radius", Color3.new(0, 1, 0.5))
        targeter.In.onConfigure(targeter, { beamMode = "cylinder" })
        task.wait(1.5)

        setStatus("beamMode: 'cone'\nSpreading rays from origin", Color3.new(0, 1, 0.5))
        targeter.In.onConfigure(targeter, { beamMode = "cone" })
        task.wait(1.5)

        -- Disable and clear
        setStatus("Targeter: onDisable()", Color3.new(0, 1, 0.5))
        targeter.In.onDisable(targeter)
        scanner.BrickColor = BrickColor.new("Medium stone grey")
        clearEnemies()
        task.wait(1)

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 3: LAUNCHER DEMONSTRATION
        -----------------------------------------------------------------------
        setPhase("PHASE 3: LAUNCHER COMPONENT")
        setStatus("Demonstrating Launcher\nPhysics-based projectiles", Color3.new(1, 0.8, 0))
        task.wait(1)

        -- Blind fire
        setStatus("Launcher: onFire()\nBlind fire (muzzle direction)", Color3.new(1, 0.8, 0))
        launcher.In.onFire(launcher)
        task.wait(0.5)
        launcher.In.onFire(launcher)
        task.wait(0.5)
        launcher.In.onFire(launcher)
        task.wait(1)

        -- Targeted fire
        setStatus("Launcher: onFire({ targetPosition })\nAimed fire at coordinates", Color3.new(1, 0.8, 0))
        local targetPos = position + Vector3.new(20, 10, -40)
        launcher.In.onFire(launcher, { targetPosition = targetPos })
        task.wait(0.3)
        launcher.In.onFire(launcher, { targetPosition = targetPos + Vector3.new(5, 0, 0) })
        task.wait(0.3)
        launcher.In.onFire(launcher, { targetPosition = targetPos + Vector3.new(-5, 0, 0) })
        task.wait(1)

        -- Change launch force
        setStatus("Changing launchForce: 120\nFaster projectiles", Color3.new(1, 0.8, 0))
        launcher.In.onConfigure(launcher, { launchForce = 120 })
        launcher.In.onFire(launcher)
        task.wait(0.3)
        launcher.In.onFire(launcher)
        task.wait(1)

        -- Reset force
        launcher.In.onConfigure(launcher, { launchForce = 80 })

        -- Cooldown demonstration
        setStatus("Cooldown: 0.5s\nRapid fire blocked", Color3.new(1, 0.8, 0))
        launcher.In.onConfigure(launcher, { cooldown = 0.5 })
        launcher.In.onFire(launcher)
        task.wait(0.1)
        launcher.In.onFire(launcher)  -- Should be blocked
        task.wait(0.1)
        launcher.In.onFire(launcher)  -- Should be blocked
        task.wait(1)

        setStatus("Cooldown: 0.1s\nFast fire rate", Color3.new(1, 0.8, 0))
        launcher.In.onConfigure(launcher, { cooldown = 0.1 })
        for i = 1, 5 do
            launcher.In.onFire(launcher)
            task.wait(0.15)
        end
        task.wait(1)

        clearProjectiles()

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 4: INTEGRATED TURRET SYSTEM
        -----------------------------------------------------------------------
        setPhase("PHASE 4: INTEGRATED TURRET")
        setStatus("Full System Integration\nAuto-track & Fire", Color3.new(1, 0.3, 0.3))
        task.wait(1)

        -- Configure for combat
        launcher.In.onConfigure(launcher, { cooldown = 0.2, launchForce = 80 })
        targeter.In.onConfigure(targeter, { beamMode = "cone", trackingMode = "lock" })

        -- Activate system
        setStatus("TURRET ONLINE\nSearching for targets...", Color3.new(0, 1, 0))
        scanner.BrickColor = BrickColor.new("Bright green")
        controller.active = true
        targeter.In.onEnable(targeter)
        task.wait(2)

        -- Single stationary target
        setStatus("Spawning stationary target", Color3.new(1, 0.5, 0))
        spawnEnemy(position + Vector3.new(15, 3, -25), false)
        task.wait(4)
        clearEnemies()
        task.wait(1)

        -- Multiple targets
        setStatus("Spawning multiple targets\nClosest target prioritized", Color3.new(1, 0.5, 0))
        spawnEnemy(position + Vector3.new(-20, 5, -35), false)
        spawnEnemy(position + Vector3.new(10, 2, -20), false)
        spawnEnemy(position + Vector3.new(25, 8, -40), false)
        task.wait(6)
        clearEnemies()
        task.wait(1)

        -- Moving targets
        setStatus("Moving targets!\nReal-time tracking", Color3.new(1, 0, 0))
        spawnEnemy(position + Vector3.new(0, 5, -30), true)
        spawnEnemy(position + Vector3.new(-15, 3, -25), true)
        task.wait(8)

        -- High fire rate
        setStatus("High fire rate: 10 shots/sec", Color3.new(1, 0, 0))
        launcher.In.onConfigure(launcher, { cooldown = 0.1 })
        task.wait(5)

        if not controller.running then return end

        -----------------------------------------------------------------------
        -- PHASE 5: COMPLETE
        -----------------------------------------------------------------------
        setPhase("DEMO COMPLETE")
        setStatus("All API calls demonstrated!\nShots fired: " .. controller.shotsFired, Color3.new(0, 1, 0))

        -- Deactivate
        task.wait(3)
        controller.active = false
        targeter.In.onDisable(targeter)
        yawSwivel.In.onStop(yawSwivel)
        pitchSwivel.In.onStop(pitchSwivel)
        scanner.BrickColor = BrickColor.new("Medium stone grey")
        clearEnemies()

        setStatus("TURRET OFFLINE\nCall demo.cleanup() to remove", Color3.new(0.5, 0.5, 0.5))

        announce("Demo complete! Total shots: " .. controller.shotsFired)
    end)

    ---------------------------------------------------------------------------
    -- CONTROLS (for manual override if needed)
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.cleanup()
        controller.running = false
        controller.active = false
        controlConnection:Disconnect()
        cleanupConnection:Disconnect()
        yawSwivel.Sys.onStop(yawSwivel)
        pitchSwivel.Sys.onStop(pitchSwivel)
        targeter.Sys.onStop(targeter)
        launcher.Sys.onStop(launcher)
        demoFolder:Destroy()
        announce("Demo cleaned up")
    end

    function controls.getStats()
        return {
            shotsFired = controller.shotsFired,
            active = controller.active,
        }
    end

    print("============================================")
    print("  TURRET SYSTEM - AUTOMATED DEMO")
    print("============================================")
    print("")
    print("Sit back and watch! The demo will showcase:")
    print("  - Phase 1: Swivel rotation controls")
    print("  - Phase 2: Targeter detection system")
    print("  - Phase 3: Launcher projectile firing")
    print("  - Phase 4: Full integrated turret")
    print("")
    print("To stop early: demo.cleanup()")
    print("")

    return controls
end

return Demo
