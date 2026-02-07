--[[
    Warren Framework v2
    SwivelLauncher_Demo.lua - Shooting Gallery Demo

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Demonstrates the complete swivel launcher system with target tracking:
    - SwivelLauncherOrchestrator: Turret with targeting beam
    - TargetSpawnerOrchestrator: Spawns flying targets to shoot

    Features:
    - Auto-tracking via Targeter (green beam turns red when locked)
    - Flying targets with health (EntityStats)
    - Projectile hit detection and damage
    - Auto-aim mode that tracks and fires at targets
    - Manual mode for player control

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Demos = require(game.ReplicatedStorage.Warren.Demos)
    local demo = Demos.SwivelLauncher.run()

    -- Controls:
    demo.setMode('auto'|'semi'|'beam')
    demo.enableAutoAim()     -- Turret auto-tracks targets
    demo.disableAutoAim()    -- Manual control
    demo.spawnTargets(n)     -- Spawn n targets
    demo.cleanup()           -- Remove demo
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))

local SwivelLauncherOrchestrator = Lib.Components.SwivelLauncherOrchestrator
local TargetSpawnerOrchestrator = Lib.Components.TargetSpawnerOrchestrator

local Demo = {}

function Demo.run(config)
    config = config or {}
    local position = config.position or Vector3.new(0, 5, 0)

    ---------------------------------------------------------------------------
    -- CLEANUP ALL OLD DEMOS
    ---------------------------------------------------------------------------

    local demosToClean = {
        "Swivel_Demo",
        "Turret_Demo",
        "Launcher_Demo",
        "Targeter_Demo",
        "ShootingGallery_Demo",
        "Conveyor_Demo",
        "Combat_Demo",
        "SwivelLauncher_Demo",
    }

    for _, demoName in ipairs(demosToClean) do
        local existing = workspace:FindFirstChild(demoName)
        if existing then
            existing:Destroy()
        end
    end

    task.wait(0.1)

    ---------------------------------------------------------------------------
    -- CREATE VISUAL SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "SwivelLauncher_Demo"
    demoFolder.Parent = workspace

    -- Ground plane
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(150, 1, 150)
    ground.Position = Vector3.new(0, -0.5, 0)
    ground.Anchored = true
    ground.BrickColor = BrickColor.new("Dark stone grey")
    ground.Material = Enum.Material.Slate
    ground.Parent = demoFolder

    -- Base platform (anchored to world)
    local basePlatform = Instance.new("Part")
    basePlatform.Name = "BasePlatform"
    basePlatform.Size = Vector3.new(6, 1, 6)
    basePlatform.Position = position - Vector3.new(0, 1.5, 0)
    basePlatform.Anchored = true
    basePlatform.BrickColor = BrickColor.new("Really black")
    basePlatform.Material = Enum.Material.DiamondPlate
    basePlatform.Parent = demoFolder

    -- Yaw part (rotates left/right) - sits on platform
    local yawPart = Instance.new("Part")
    yawPart.Name = "YawPart"
    yawPart.Size = Vector3.new(4, 1.5, 4)
    yawPart.Position = position
    yawPart.Anchored = false
    yawPart.CanCollide = false
    yawPart.BrickColor = BrickColor.new("Bright blue")
    yawPart.Material = Enum.Material.Metal
    yawPart.Parent = demoFolder

    -- Pitch part (rotates up/down) - sits on yaw
    local pitchPart = Instance.new("Part")
    pitchPart.Name = "PitchPart"
    pitchPart.Size = Vector3.new(2, 1.5, 3)
    pitchPart.Position = position + Vector3.new(0, 1.5, 0)
    pitchPart.Anchored = false
    pitchPart.CanCollide = false
    pitchPart.BrickColor = BrickColor.new("Bright green")
    pitchPart.Material = Enum.Material.Metal
    pitchPart.Parent = demoFolder

    -- Status display
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 350, 0, 120)
    billboardGui.StudsOffset = Vector3.new(0, 8, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = pitchPart

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundTransparency = 0.3
    statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    statusLabel.TextColor3 = Color3.new(1, 1, 1)
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.Code
    statusLabel.Text = "INIT"
    statusLabel.Parent = billboardGui

    ---------------------------------------------------------------------------
    -- CREATE SWIVEL LAUNCHER ORCHESTRATOR
    ---------------------------------------------------------------------------

    local turret = SwivelLauncherOrchestrator:new({
        id = "Demo_SwivelLauncher",
        model = yawPart,
        attributes = {
            pitchModel = pitchPart,
            -- Swivel config
            yawConfig = {
                speed = 180,  -- Fast for tracking
                minAngle = -180,
                maxAngle = 180,
            },
            pitchConfig = {
                speed = 120,  -- Fast for tracking
                minAngle = -30,
                maxAngle = 60,
            },
            -- Launcher config
            fireMode = "auto",
            cooldown = 0.1,
            projectileComponent = "Tracer",
            magazineCapacity = 50,
            reloadTime = 1.5,
            beamComponent = "PlasmaBeam",
            beamMaxHeat = 100,
            beamHeatRate = 35,
            beamCoolRate = 20,
            batteryCapacity = 100,
            batteryRechargeRate = 15,
            -- Visual config
            launcherSize = Vector3.new(1, 1, 2),
            -- Targeter config (via LauncherDemoOrchestrator)
            targeterBeamVisible = true,
            targeterBeamColor = Color3.new(0, 1, 0),
            targeterRange = 120,
        },
    })

    ---------------------------------------------------------------------------
    -- CREATE TARGET SPAWNER ORCHESTRATOR
    ---------------------------------------------------------------------------

    local spawner = TargetSpawnerOrchestrator:new({
        id = "Demo_TargetSpawner",
        attributes = {
            MaxTargets = 5,
            RespawnDelay = 2,
            AutoRespawn = true,
            TargetHealth = 50,  -- Takes ~5 hits
            TargetSpeed = 5,    -- Slow targets for easier tracking
            FlyAreaCenter = Vector3.new(0, 25, -50),
            FlyAreaSize = Vector3.new(80, 30, 60),
        },
    })

    ---------------------------------------------------------------------------
    -- STATE
    ---------------------------------------------------------------------------

    local currentMode = "AUTO"
    local yawAngle = 0
    local pitchAngle = 0
    local currentAmmo = 50
    local maxAmmo = 50
    local heatPercent = 0
    local powerPercent = 100
    local targetsDestroyed = 0
    local autoAimEnabled = true
    local currentTarget = nil
    local autoAimConnection = nil

    local function updateStatus()
        local lines = { "SHOOTING GALLERY - " .. currentMode }
        table.insert(lines, string.format("Yaw:%.0f Pitch:%.0f", yawAngle, pitchAngle))

        if currentMode == "BEAM" then
            table.insert(lines, string.format("Heat:%.0f%% Power:%.0f%%", heatPercent, powerPercent))
        else
            if maxAmmo > 0 then
                table.insert(lines, string.format("Ammo: %d/%d", currentAmmo, maxAmmo))
            end
        end

        table.insert(lines, string.format("Kills: %d | AutoAim: %s",
            targetsDestroyed,
            autoAimEnabled and "ON" or "OFF"))

        if currentTarget then
            table.insert(lines, "TARGET LOCKED")
            statusLabel.TextColor3 = Color3.new(1, 0.3, 0)  -- Red when locked
        elseif autoAimEnabled then
            table.insert(lines, "SCANNING...")
            statusLabel.TextColor3 = Color3.new(0, 1, 0.5)  -- Cyan when scanning
        end

        statusLabel.Text = table.concat(lines, "\n")
    end

    ---------------------------------------------------------------------------
    -- TURRET SIGNAL HANDLING
    ---------------------------------------------------------------------------

    local originalTurretFire = turret.Out.Fire
    turret.Out.Fire = function(outSelf, signal, data)
        data = data or {}

        -- Swivel signals
        if signal == "yawRotated" and data.angle then
            yawAngle = data.angle
            updateStatus()
        elseif signal == "pitchRotated" and data.angle then
            pitchAngle = data.angle
            updateStatus()
        elseif signal == "yawLimitReached" or signal == "pitchLimitReached" then
            statusLabel.TextColor3 = Color3.new(1, 0.5, 0)
            task.delay(0.3, function()
                statusLabel.TextColor3 = Color3.new(1, 1, 1)
            end)

        -- Launcher projectile signals
        elseif signal == "fired" then
            currentAmmo = data.ammo or currentAmmo
            maxAmmo = data.maxAmmo or maxAmmo
            statusLabel.TextColor3 = Color3.new(1, 0.5, 0)
            updateStatus()
            task.delay(0.05, function()
                statusLabel.TextColor3 = Color3.new(0, 1, 0)
            end)

        elseif signal == "ready" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)

        elseif signal == "ammoChanged" then
            currentAmmo = data.current or currentAmmo
            maxAmmo = data.max or maxAmmo
            updateStatus()

        elseif signal == "reloadStarted" then
            statusLabel.Text = "RELOADING..."
            statusLabel.TextColor3 = Color3.new(1, 1, 0)

        elseif signal == "reloadComplete" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)
            updateStatus()

        elseif signal == "magazineEmpty" then
            statusLabel.Text = "MAGAZINE EMPTY!"
            statusLabel.TextColor3 = Color3.new(1, 0, 0)
            -- Auto-reload
            task.delay(0.5, function()
                turret.In.onReload(turret, {})
            end)

        -- Beam signals
        elseif signal == "heatChanged" then
            heatPercent = (data.percent or 0) * 100
            updateStatus()

        elseif signal == "overheated" then
            statusLabel.Text = "OVERHEATED!"
            statusLabel.TextColor3 = Color3.new(1, 0.3, 0)

        elseif signal == "cooledDown" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)
            updateStatus()

        elseif signal == "powerChanged" then
            powerPercent = (data.percent or 0) * 100
            updateStatus()

        elseif signal == "powerDepleted" then
            statusLabel.Text = "NO POWER!"
            statusLabel.TextColor3 = Color3.new(0.5, 0, 0)

        elseif signal == "powerRestored" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)
            updateStatus()

        -- Target tracking signals
        elseif signal == "targetAcquired" then
            currentTarget = data
            statusLabel.TextColor3 = Color3.new(1, 0.5, 0)
            updateStatus()

        elseif signal == "targetTracking" then
            currentTarget = data
            -- Auto-aim: track target position
            if autoAimEnabled and data.position then
                -- Calculate direction to target
                local turretPos = pitchPart.Position
                local targetPos = data.position
                local direction = (targetPos - turretPos)

                -- Calculate yaw angle (horizontal)
                local yawDir = Vector3.new(direction.X, 0, direction.Z).Unit
                local forward = Vector3.new(0, 0, -1)
                local yawAngleRad = math.atan2(yawDir.X, -yawDir.Z)
                local targetYaw = math.deg(yawAngleRad)

                -- Calculate pitch angle (vertical)
                local horizDistance = Vector2.new(direction.X, direction.Z).Magnitude
                local pitchAngleRad = math.atan2(direction.Y, horizDistance)
                local targetPitch = math.deg(pitchAngleRad)

                -- Set angles
                turret.In.onSetYawAngle(turret, { degrees = targetYaw })
                turret.In.onSetPitchAngle(turret, { degrees = targetPitch })
            end

        elseif signal == "targetLost" then
            currentTarget = nil
            statusLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
            updateStatus()
        end

        originalTurretFire(outSelf, signal, data)
    end

    ---------------------------------------------------------------------------
    -- SPAWNER SIGNAL HANDLING
    ---------------------------------------------------------------------------

    local originalSpawnerFire = spawner.Out.Fire
    spawner.Out.Fire = function(outSelf, signal, data)
        data = data or {}

        if signal == "targetSpawned" then
            print(string.format("[Demo] Target spawned"))

        elseif signal == "targetDestroyed" then
            targetsDestroyed = targetsDestroyed + 1
            updateStatus()
            print(string.format("[Demo] Target destroyed! Total kills: %d", targetsDestroyed))

        elseif signal == "waveComplete" then
            print("[Demo] Wave complete!")
        end

        originalSpawnerFire(outSelf, signal, data)
    end

    ---------------------------------------------------------------------------
    -- PROJECTILE HIT DETECTION
    ---------------------------------------------------------------------------

    -- Track which tracers we've already connected
    local tracerConnections = {}
    local activeTargetParts = {}  -- [part] = FlyingTarget component

    -- When a tracer hits something, check if it's a target and damage it
    local function onTracerHit(tracer, hitPart, hitPosition)
        -- Check if hit part is a target
        local nodeClass = hitPart:GetAttribute("NodeClass")
        if nodeClass == "FlyingTarget" then
            -- Find the FlyingTarget component for this part
            -- We track spawned targets by their drone part
            local targetComponent = nil
            for id, target in pairs(spawner:getNode("Spawner") and {} or {}) do
                -- Check via naming convention
            end

            -- Alternative: directly damage via the part
            -- The FlyingTarget has EntityStats wired to apply damage
            -- We need to find the target and call onHit

            -- For now, apply damage directly to any part with the NodeClass
            -- by finding its parent FlyingTarget in our tracked list
            local damage = 10  -- Damage per projectile hit

            -- Search for the target in spawner's active targets
            local spawnerState = spawner:getNode("Spawner")
            if not spawnerState then
                -- Manually find target by part
                for _, desc in ipairs(workspace:GetDescendants()) do
                    if desc.Name:match("_Drone$") and desc == hitPart then
                        -- Found the drone, apply damage visually
                        hitPart.BrickColor = BrickColor.new("White")
                        task.delay(0.1, function()
                            if hitPart and hitPart.Parent then
                                hitPart.BrickColor = BrickColor.new("Bright red")
                            end
                        end)
                        break
                    end
                end
            end
        end
    end

    -- Monitor for new tracer parts and connect their Touched event
    local hitConnection = workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") and string.match(descendant.Name, "_Tracer$") then
            -- Wait a frame for the part to be fully set up
            task.defer(function()
                if not descendant or not descendant.Parent then return end

                local conn = descendant.Touched:Connect(function(hitPart)
                    -- Check if we hit a target
                    local nodeClass = hitPart:GetAttribute("NodeClass")
                    if nodeClass == "FlyingTarget" then
                        -- Apply damage
                        local damage = 10

                        -- Flash the target white
                        local originalColor = hitPart.BrickColor
                        hitPart.BrickColor = BrickColor.new("White")
                        task.delay(0.1, function()
                            if hitPart and hitPart.Parent then
                                hitPart.BrickColor = originalColor
                            end
                        end)

                        -- Find the FlyingTarget component and damage it
                        -- Since FlyingTarget creates its drone with a specific name pattern,
                        -- we can find it in workspace
                        local targetId = hitPart.Name:match("^(.+)_Drone$")
                        if targetId then
                            -- The target tracks itself; we need to signal damage
                            -- The FlyingTarget wires EntityStats, which has an onApplyModifier
                            -- But we don't have direct access to the component...

                            -- Workaround: Use a BindableEvent on the part for hit signals
                            local hitEvent = hitPart:FindFirstChild("HitEvent")
                            if hitEvent and hitEvent:IsA("BindableEvent") then
                                hitEvent:Fire({ damage = damage })
                            end
                        end

                        -- Destroy the tracer on hit
                        descendant:Destroy()
                    end
                end)

                tracerConnections[descendant] = conn

                -- Clean up connection when tracer is destroyed
                descendant.AncestryChanged:Connect(function(_, parent)
                    if not parent and tracerConnections[descendant] then
                        tracerConnections[descendant]:Disconnect()
                        tracerConnections[descendant] = nil
                    end
                end)
            end)
        end
    end)

    ---------------------------------------------------------------------------
    -- INITIALIZE AND START
    ---------------------------------------------------------------------------

    turret.Sys.onInit(turret)
    spawner.Sys.onInit(spawner)

    turret.Sys.onStart(turret)
    spawner.Sys.onStart(spawner)

    ---------------------------------------------------------------------------
    -- AUTO-SCAN AND AUTO-AIM LOOP
    ---------------------------------------------------------------------------

    -- Scanning state
    local scanDirection = 1  -- 1 = right, -1 = left
    local scanSpeed = 90     -- degrees per second (faster scanning)
    local scanYawMin = -90
    local scanYawMax = 90
    local scanPitchTarget = 15  -- Look slightly up when scanning

    autoAimConnection = RunService.Heartbeat:Connect(function(dt)
        if not demoFolder.Parent then return end
        if not autoAimEnabled then return end

        if currentTarget then
            -- TARGET LOCKED: Fire at target
            turret.In.onTriggerDown(turret, {})
        else
            -- NO TARGET: Sweep/scan for targets
            local newYaw = yawAngle + (scanDirection * scanSpeed * dt)

            -- Reverse direction at limits
            if newYaw >= scanYawMax then
                newYaw = scanYawMax
                scanDirection = -1
            elseif newYaw <= scanYawMin then
                newYaw = scanYawMin
                scanDirection = 1
            end

            -- Set scan angles
            turret.In.onSetYawAngle(turret, { degrees = newYaw })
            turret.In.onSetPitchAngle(turret, { degrees = scanPitchTarget })
        end
    end)

    -- Release trigger when no target
    local lastHadTarget = false
    local targetCheckConnection = RunService.Heartbeat:Connect(function()
        if not demoFolder.Parent then return end

        local hasTarget = currentTarget ~= nil

        if lastHadTarget and not hasTarget then
            -- Lost target, release trigger
            turret.In.onTriggerUp(turret, {})
        end

        lastHadTarget = hasTarget
    end)

    ---------------------------------------------------------------------------
    -- SPAWN INITIAL WAVE
    ---------------------------------------------------------------------------

    task.delay(1, function()
        if not demoFolder.Parent then return end
        spawner.In.onSpawnWave(spawner, { count = 3 })
    end)

    updateStatus()

    ---------------------------------------------------------------------------
    -- CLEANUP
    ---------------------------------------------------------------------------

    demoFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("Demo cleanup...")
            if hitConnection then hitConnection:Disconnect() end
            if autoAimConnection then autoAimConnection:Disconnect() end
            if targetCheckConnection then targetCheckConnection:Disconnect() end
            turret.Sys.onStop(turret)
            spawner.Sys.onStop(spawner)
        end
    end)

    ---------------------------------------------------------------------------
    -- RETURN CONTROLS
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.cleanup()
        demoFolder:Destroy()
    end

    function controls.setMode(mode)
        if mode == "auto" or mode == "semi" or mode == "beam" then
            currentMode = string.upper(mode)
            turret.In.onConfigure(turret, { fireMode = mode })
            updateStatus()
        end
    end

    function controls.fire()
        turret.In.onFire(turret, {})
    end

    function controls.triggerDown()
        turret.In.onTriggerDown(turret, {})
    end

    function controls.triggerUp()
        turret.In.onTriggerUp(turret, {})
    end

    function controls.rotateYaw(direction)
        turret.In.onRotateYaw(turret, { direction = direction })
    end

    function controls.rotatePitch(direction)
        turret.In.onRotatePitch(turret, { direction = direction })
    end

    function controls.stop()
        turret.In.onStop(turret, {})
    end

    function controls.setYaw(degrees)
        turret.In.onSetYawAngle(turret, { degrees = degrees })
    end

    function controls.setPitch(degrees)
        turret.In.onSetPitchAngle(turret, { degrees = degrees })
    end

    function controls.reload()
        turret.In.onReload(turret, {})
    end

    function controls.enableAutoAim()
        autoAimEnabled = true
        updateStatus()
        print("[Demo] Auto-aim ENABLED")
    end

    function controls.disableAutoAim()
        autoAimEnabled = false
        turret.In.onTriggerUp(turret, {})
        updateStatus()
        print("[Demo] Auto-aim DISABLED")
    end

    function controls.spawnTargets(count)
        count = count or 1
        spawner.In.onSpawnWave(spawner, { count = count })
    end

    function controls.clearTargets()
        spawner.In.onClear(spawner)
    end

    function controls.setTargetHealth(health)
        spawner.In.onConfigure(spawner, { health = health })
    end

    function controls.setTargetSpeed(speed)
        spawner.In.onConfigure(spawner, { speed = speed })
    end

    function controls.setScanSpeed(speed)
        scanSpeed = speed or 45
        print(string.format("[Demo] Scan speed: %d deg/s", scanSpeed))
    end

    function controls.setScanRange(min, max)
        scanYawMin = min or -90
        scanYawMax = max or 90
        print(string.format("[Demo] Scan range: %d to %d deg", scanYawMin, scanYawMax))
    end

    function controls.setTurretSpeed(yaw, pitch)
        yaw = yaw or 180
        pitch = pitch or yaw  -- Default pitch to same as yaw if not specified
        turret.In.onConfigure(turret, {
            yawSpeed = yaw,
            pitchSpeed = pitch,
        })
        print(string.format("[Demo] Turret speed: yaw=%d, pitch=%d deg/s", yaw, pitch))
    end

    function controls.getTurret()
        return turret
    end

    function controls.getSpawner()
        return spawner
    end

    print("============================================")
    print("  SHOOTING GALLERY DEMO")
    print("============================================")
    print("")
    print("Features:")
    print("  - Auto-scanning turret sweeps to find targets")
    print("  - Targeting beam locks on (green -> red)")
    print("  - Flying targets with health (EntityStats)")
    print("  - Auto-fires when target locked")
    print("")
    print("Controls:")
    print("  demo.enableAutoAim() / disableAutoAim()")
    print("  demo.spawnTargets(n)     - Spawn targets")
    print("  demo.clearTargets()      - Remove all targets")
    print("  demo.setMode('auto'|'semi'|'beam')")
    print("  demo.setTargetHealth(n)  - Change target HP")
    print("  demo.setTargetSpeed(n)   - Change target speed")
    print("  demo.setTurretSpeed(yaw, pitch) - Turret rotation speed")
    print("  demo.setScanSpeed(n)     - Scan speed (deg/s)")
    print("  demo.cleanup()           - Remove demo")
    print("")

    return controls
end

return Demo
