--[[
    LibPureFiction Framework v2
    SwivelLauncher_Demo.lua - Full Swivel Turret + Launcher Demonstration

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Demonstrates the complete swivel launcher turret system:
    - Yaw swivel: Rotates left/right (Y-axis) - blue base
    - Pitch swivel: Rotates up/down (X-axis) - green arm, mounted on yaw
    - Launcher: Fires projectiles/beam - blue muzzle, mounted on pitch
    - Magazine: External ammo supply - colored by ammo level, left of muzzle
    - Battery: External power for beam - colored by power level, right of muzzle

    The demo cycles through:
    1. Auto fire mode with swivel tracking
    2. Semi fire mode with manual aiming
    3. Beam mode demonstrating heat and power management

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    Demos.SwivelLauncher.run()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

local SwivelLauncherOrchestrator = Lib.Components.SwivelLauncherOrchestrator

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
    ground.Size = Vector3.new(100, 1, 100)
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
    billboardGui.Size = UDim2.new(0, 300, 0, 100)
    billboardGui.StudsOffset = Vector3.new(0, 6, 0)
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
    -- CREATE ORCHESTRATOR
    ---------------------------------------------------------------------------

    local orchestrator = SwivelLauncherOrchestrator:new({
        id = "Demo_SwivelLauncherOrchestrator",
        model = yawPart,
        attributes = {
            pitchModel = pitchPart,
            -- Swivel config
            yawConfig = {
                speed = 60,
                minAngle = -180,
                maxAngle = 180,
            },
            pitchConfig = {
                speed = 45,
                minAngle = -30,
                maxAngle = 60,
            },
            -- Launcher config
            fireMode = "auto",
            cooldown = 0.15,
            projectileComponent = "Tracer",
            magazineCapacity = 30,
            reloadTime = 1.5,
            beamComponent = "PlasmaBeam",
            beamMaxHeat = 100,
            beamHeatRate = 35,
            beamCoolRate = 20,
            batteryCapacity = 100,
            batteryRechargeRate = 15,
            -- Visual config
            launcherSize = Vector3.new(1, 1, 2),
        },
    })

    ---------------------------------------------------------------------------
    -- SUBSCRIBE TO SIGNALS
    ---------------------------------------------------------------------------

    local currentMode = "AUTO"
    local yawAngle = 0
    local pitchAngle = 0
    local currentAmmo = 30
    local maxAmmo = 30
    local heatPercent = 0
    local powerPercent = 100

    local function updateStatus()
        local lines = { "SWIVEL LAUNCHER - " .. currentMode }
        table.insert(lines, string.format("Yaw:%.0f Pitch:%.0f", yawAngle, pitchAngle))

        if currentMode == "BEAM" then
            table.insert(lines, string.format("Heat:%.0f%% Power:%.0f%%", heatPercent, powerPercent))
        else
            if maxAmmo > 0 then
                table.insert(lines, string.format("Ammo: %d/%d", currentAmmo, maxAmmo))
            end
        end

        statusLabel.Text = table.concat(lines, "\n")
    end

    local originalOutFire = orchestrator.Out.Fire
    orchestrator.Out.Fire = function(outSelf, signal, data)
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
            task.delay(0.1, function()
                statusLabel.TextColor3 = Color3.new(0, 1, 0)
            end)

        elseif signal == "ready" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)

        elseif signal == "ammoChanged" then
            currentAmmo = data.current or currentAmmo
            maxAmmo = data.max or maxAmmo
            updateStatus()

        elseif signal == "reloadStarted" then
            statusLabel.Text = currentMode .. "\nRELOADING..."
            statusLabel.TextColor3 = Color3.new(1, 1, 0)

        elseif signal == "reloadComplete" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)
            updateStatus()

        elseif signal == "magazineEmpty" then
            statusLabel.Text = currentMode .. "\nMAGAZINE EMPTY!"
            statusLabel.TextColor3 = Color3.new(1, 0, 0)

        -- Launcher beam signals
        elseif signal == "beamStart" then
            statusLabel.TextColor3 = Color3.new(1, 0, 0)
            updateStatus()

        elseif signal == "beamEnd" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)

        elseif signal == "heatChanged" then
            heatPercent = (data.percent or 0) * 100
            updateStatus()

        elseif signal == "overheated" then
            statusLabel.Text = currentMode .. "\nOVERHEATED!"
            statusLabel.TextColor3 = Color3.new(1, 0.3, 0)

        elseif signal == "cooledDown" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)
            updateStatus()

        elseif signal == "powerChanged" then
            powerPercent = (data.percent or 0) * 100
            updateStatus()

        elseif signal == "powerDepleted" then
            statusLabel.Text = currentMode .. "\nNO POWER!"
            statusLabel.TextColor3 = Color3.new(0.5, 0, 0)

        elseif signal == "powerRestored" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)
            updateStatus()
        end

        originalOutFire(outSelf, signal, data)
    end

    ---------------------------------------------------------------------------
    -- INITIALIZE AND START
    ---------------------------------------------------------------------------

    orchestrator.Sys.onInit(orchestrator)
    orchestrator.Sys.onStart(orchestrator)

    ---------------------------------------------------------------------------
    -- AUTOMATED DEMO SEQUENCE
    ---------------------------------------------------------------------------

    task.spawn(function()
        print("=== SWIVEL LAUNCHER DEMO ===")
        print("Full turret system: Swivel + Launcher + Magazine + Battery")
        print("")

        task.wait(1)

        while demoFolder.Parent do
            -- Phase 1: AUTO mode with swivel sweep
            print("Mode: AUTO - sweeping and firing")
            currentMode = "AUTO"
            orchestrator.In.onConfigure(orchestrator, {
                fireMode = "auto",
                cooldown = 0.15,
            })
            updateStatus()
            task.wait(0.3)

            -- Sweep left while firing
            if not demoFolder.Parent then return end
            orchestrator.In.onRotateYaw(orchestrator, { direction = "forward" })
            orchestrator.In.onRotatePitch(orchestrator, { direction = "forward" })
            orchestrator.In.onTriggerDown(orchestrator, {})
            task.wait(2)

            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerUp(orchestrator, {})
            orchestrator.In.onStopYaw(orchestrator, {})
            orchestrator.In.onStopPitch(orchestrator, {})
            task.wait(0.3)

            -- Sweep right while firing
            if not demoFolder.Parent then return end
            orchestrator.In.onRotateYaw(orchestrator, { direction = "reverse" })
            orchestrator.In.onRotatePitch(orchestrator, { direction = "reverse" })
            orchestrator.In.onTriggerDown(orchestrator, {})
            task.wait(2)

            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerUp(orchestrator, {})
            orchestrator.In.onStop(orchestrator, {})
            task.wait(0.3)

            -- Reload
            print("  Reloading...")
            orchestrator.In.onReload(orchestrator, {})
            task.wait(2)

            if not demoFolder.Parent then return end

            -- Phase 2: SEMI mode with precise shots
            print("Mode: SEMI - precise shots while aiming")
            currentMode = "SEMI"
            orchestrator.In.onConfigure(orchestrator, {
                fireMode = "semi",
                cooldown = 0.4,
            })
            updateStatus()
            task.wait(0.3)

            -- Fire 5 shots while sweeping
            for i = 1, 5 do
                if not demoFolder.Parent then return end
                orchestrator.In.onSetYawAngle(orchestrator, { degrees = -60 + (i - 1) * 30 })
                orchestrator.In.onSetPitchAngle(orchestrator, { degrees = (i % 2 == 0) and 30 or -15 })
                task.wait(0.4)
                orchestrator.In.onTriggerDown(orchestrator, {})
                task.wait(0.1)
                orchestrator.In.onTriggerUp(orchestrator, {})
                task.wait(0.3)
            end

            task.wait(0.5)
            if not demoFolder.Parent then return end

            -- Phase 3: BEAM mode - overheat demo
            print("Mode: BEAM - sweeping until overheat")
            currentMode = "BEAM"
            orchestrator.In.onConfigure(orchestrator, {
                fireMode = "beam",
            })
            maxAmmo = -1
            updateStatus()
            task.wait(0.3)

            -- Center turret
            orchestrator.In.onSetYawAngle(orchestrator, { degrees = 0 })
            orchestrator.In.onSetPitchAngle(orchestrator, { degrees = 0 })
            task.wait(0.5)

            -- Fire beam while sweeping slowly
            if not demoFolder.Parent then return end
            orchestrator.In.onRotateYaw(orchestrator, { direction = "forward" })
            orchestrator.In.onTriggerDown(orchestrator, {})
            task.wait(3.5)  -- Will overheat

            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerUp(orchestrator, {})
            orchestrator.In.onStopYaw(orchestrator, {})

            -- Wait for cooldown
            print("  Cooling down...")
            task.wait(6)

            if not demoFolder.Parent then return end

            -- Phase 4: BEAM mode - power depletion demo
            print("Mode: BEAM - sustained fire until power depleted")
            orchestrator.In.onConfigure(orchestrator, {
                beamHeatRate = 10,  -- Slower heat buildup
            })
            updateStatus()
            task.wait(0.3)

            -- Sweep while firing
            if not demoFolder.Parent then return end
            orchestrator.In.onRotateYaw(orchestrator, { direction = "reverse" })
            orchestrator.In.onTriggerDown(orchestrator, {})
            task.wait(4)  -- Will deplete power

            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerUp(orchestrator, {})
            orchestrator.In.onStopYaw(orchestrator, {})

            -- Wait for recharge
            print("  Recharging power...")
            task.wait(8)

            if not demoFolder.Parent then return end

            -- Reset for next cycle
            orchestrator.In.onConfigure(orchestrator, {
                fireMode = "auto",
                beamHeatRate = 35,
            })

            -- Return to center
            orchestrator.In.onSetYawAngle(orchestrator, { degrees = 0 })
            orchestrator.In.onSetPitchAngle(orchestrator, { degrees = 0 })

            print("")
            print("--- Cycle complete ---")
            print("")
            task.wait(2)
        end
    end)

    ---------------------------------------------------------------------------
    -- CLEANUP
    ---------------------------------------------------------------------------

    demoFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("Demo cleanup...")
            orchestrator.Sys.onStop(orchestrator)
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
            orchestrator.In.onConfigure(orchestrator, { fireMode = mode })
            updateStatus()
        end
    end

    function controls.fire()
        orchestrator.In.onFire(orchestrator, {})
    end

    function controls.triggerDown()
        orchestrator.In.onTriggerDown(orchestrator, {})
    end

    function controls.triggerUp()
        orchestrator.In.onTriggerUp(orchestrator, {})
    end

    function controls.rotateYaw(direction)
        orchestrator.In.onRotateYaw(orchestrator, { direction = direction })
    end

    function controls.rotatePitch(direction)
        orchestrator.In.onRotatePitch(orchestrator, { direction = direction })
    end

    function controls.stop()
        orchestrator.In.onStop(orchestrator, {})
    end

    function controls.setYaw(degrees)
        orchestrator.In.onSetYawAngle(orchestrator, { degrees = degrees })
    end

    function controls.setPitch(degrees)
        orchestrator.In.onSetPitchAngle(orchestrator, { degrees = degrees })
    end

    function controls.reload()
        orchestrator.In.onReload(orchestrator, {})
    end

    print("============================================")
    print("  SWIVEL LAUNCHER DEMO")
    print("============================================")
    print("")
    print("Automated demo cycles through:")
    print("  1. AUTO mode - sweeping fire")
    print("  2. SEMI mode - precise shots")
    print("  3. BEAM mode - overheat")
    print("  4. BEAM mode - power depletion")
    print("")
    print("Manual controls:")
    print("  demo.setMode('auto'|'semi'|'beam')")
    print("  demo.fire() / demo.triggerDown() / demo.triggerUp()")
    print("  demo.rotateYaw('forward'|'reverse')")
    print("  demo.rotatePitch('forward'|'reverse')")
    print("  demo.setYaw(degrees) / demo.setPitch(degrees)")
    print("  demo.stop() / demo.reload()")
    print("  demo.cleanup()")
    print("")

    return controls
end

return Demo
