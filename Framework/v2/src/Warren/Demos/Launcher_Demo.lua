--[[
    Warren Framework v2
    Launcher_Demo.lua - Automated Launcher Demonstration

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Demonstrates all launcher features:

    Fire Modes:
    - Manual: single shot per signal, with magazine
    - Semi: one shot per trigger press, with magazine
    - Auto: continuous fire while trigger held, with magazine
    - Beam: continuous beam with heat/power management

    Components:
    - Tracer: straight-flying projectile with glowing trail
    - PlasmaBeam: pulsing cyan beam with hit detection

    Systems:
    - Magazine capacity and reload
    - Projectile velocity
    - Beam intensity, heat buildup, overheat, cooldown
    - Beam power drain and recharge

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Demos = require(game.ReplicatedStorage.Warren.Demos)
    Demos.Launcher.run()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))

local LauncherDemoOrchestrator = Lib.Components.LauncherDemoOrchestrator

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
    demoFolder.Name = "Launcher_Demo"
    demoFolder.Parent = workspace

    -- Muzzle (the launcher)
    local muzzle = Instance.new("Part")
    muzzle.Name = "Muzzle"
    muzzle.Size = Vector3.new(1.5, 1.5, 3)
    muzzle.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(-15), 0, 0)
    muzzle.Anchored = true
    muzzle.BrickColor = BrickColor.new("Bright blue")
    muzzle.Material = Enum.Material.SmoothPlastic
    muzzle.Parent = demoFolder

    -- Status display
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 220, 0, 80)
    billboardGui.StudsOffset = Vector3.new(0, 4, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = muzzle

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

    local orchestrator = LauncherDemoOrchestrator:new({
        id = "Demo_LauncherOrchestrator",
        model = muzzle,
        attributes = {
            fireMode = "manual",
            cooldown = 0.3,
            -- Use Tracer component for projectiles (straight-flying with trail)
            -- Tracer owns its own velocity (default 200 studs/sec)
            projectileComponent = "Tracer",
            magazineCapacity = 30,
            reloadTime = 1.5,
            -- Use PlasmaBeam component for beam mode (pulsing cyan beam)
            -- PlasmaBeam owns its own width/color/pulse settings
            beamComponent = "PlasmaBeam",
            beamMaxHeat = 100,
            beamHeatRate = 40,      -- Overheats in ~2.5s
            beamCoolRate = 20,
            beamPowerCapacity = 100,
            beamPowerDrainRate = 30, -- Depletes in ~3.3s
            beamPowerRechargeRate = 15,
        },
    })

    ---------------------------------------------------------------------------
    -- SUBSCRIBE TO SIGNALS
    ---------------------------------------------------------------------------

    local currentMode = "MANUAL"
    local currentAmmo = 30
    local maxAmmo = 30
    local heatPercent = 0
    local powerPercent = 100

    local function updateStatus()
        if currentMode == "BEAM" then
            statusLabel.Text = string.format("%s\nHeat:%.0f%% Pwr:%.0f%%",
                currentMode, heatPercent, powerPercent)
        else
            if maxAmmo > 0 then
                statusLabel.Text = string.format("%s\nAmmo: %d/%d", currentMode, currentAmmo, maxAmmo)
            else
                statusLabel.Text = currentMode
            end
        end
    end

    local originalOutFire = orchestrator.Out.Fire
    orchestrator.Out.Fire = function(outSelf, signal, data)
        data = data or {}

        if signal == "fired" then
            currentAmmo = data.ammo or currentAmmo
            maxAmmo = data.maxAmmo or maxAmmo
            statusLabel.TextColor3 = Color3.new(1, 0.5, 0)
            updateStatus()

        elseif signal == "ready" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)

        elseif signal == "ammoChanged" then
            currentAmmo = data.current or currentAmmo
            maxAmmo = data.max or maxAmmo
            updateStatus()

        elseif signal == "reloadStarted" then
            statusLabel.Text = string.format("%s\nRELOADING...", currentMode)
            statusLabel.TextColor3 = Color3.new(1, 1, 0)

        elseif signal == "reloadComplete" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)
            updateStatus()

        elseif signal == "magazineEmpty" then
            statusLabel.Text = string.format("%s\nEMPTY!", currentMode)
            statusLabel.TextColor3 = Color3.new(1, 0, 0)

        elseif signal == "beamStart" then
            statusLabel.TextColor3 = Color3.new(1, 0, 0)
            updateStatus()

        elseif signal == "beamEnd" then
            statusLabel.TextColor3 = Color3.new(0, 1, 0)

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
        print("=== LAUNCHER DEMO ===")
        print("Magazine + Beam Heat/Power systems")
        print("")

        task.wait(1)

        while demoFolder.Parent do
            -- Phase 1: MANUAL with magazine
            print("Mode: MANUAL - 5 shot magazine")
            currentMode = "MANUAL"
            orchestrator.In.onConfigure(orchestrator, {
                fireMode = "manual",
                magazineCapacity = 30,
                cooldown = 0.3,
            })
            updateStatus()
            task.wait(0.5)

            -- Fire until empty
            for i = 1, 6 do
                if not demoFolder.Parent then return end
                orchestrator.In.onFire(orchestrator, {})
                task.wait(0.4)
            end

            -- Reload
            task.wait(0.5)
            if not demoFolder.Parent then return end
            print("  Reloading...")
            orchestrator.In.onReload(orchestrator, {})
            task.wait(2)

            if not demoFolder.Parent then return end

            -- Phase 2: SEMI with magazine
            print("Mode: SEMI - trigger press")
            currentMode = "SEMI"
            orchestrator.In.onConfigure(orchestrator, { fireMode = "semi" })
            updateStatus()
            task.wait(0.5)

            for i = 1, 5 do
                if not demoFolder.Parent then return end
                orchestrator.In.onTriggerDown(orchestrator, {})
                task.wait(0.1)
                orchestrator.In.onTriggerUp(orchestrator, {})
                task.wait(0.4)
            end

            -- Reload
            task.wait(0.5)
            if not demoFolder.Parent then return end
            orchestrator.In.onReload(orchestrator, {})
            task.wait(2)

            if not demoFolder.Parent then return end

            -- Phase 3: AUTO with magazine
            print("Mode: AUTO - hold trigger, empties magazine")
            currentMode = "AUTO"
            orchestrator.In.onConfigure(orchestrator, {
                fireMode = "auto",
                cooldown = 0.15,
            })
            updateStatus()
            task.wait(0.5)

            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerDown(orchestrator, {})
            task.wait(1.5)  -- Fire until empty
            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerUp(orchestrator, {})

            -- Reload
            task.wait(0.5)
            if not demoFolder.Parent then return end
            orchestrator.In.onReload(orchestrator, {})
            task.wait(2)

            if not demoFolder.Parent then return end

            -- Phase 4: BEAM - overheat demo
            print("Mode: BEAM - hold until overheat")
            currentMode = "BEAM"
            maxAmmo = -1
            orchestrator.In.onConfigure(orchestrator, { fireMode = "beam" })
            updateStatus()
            task.wait(0.5)

            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerDown(orchestrator, {})
            task.wait(3)  -- Will overheat
            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerUp(orchestrator, {})

            -- Wait for cooldown
            print("  Cooling down...")
            task.wait(6)

            if not demoFolder.Parent then return end

            -- Phase 5: BEAM - power depletion demo
            print("Mode: BEAM - hold until power depleted")
            orchestrator.In.onConfigure(orchestrator, {
                beamHeatRate = 10,  -- Slower heat buildup
            })
            updateStatus()
            task.wait(0.5)

            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerDown(orchestrator, {})
            task.wait(4)  -- Will deplete power
            if not demoFolder.Parent then return end
            orchestrator.In.onTriggerUp(orchestrator, {})

            -- Wait for recharge
            print("  Recharging power...")
            task.wait(8)

            if not demoFolder.Parent then return end

            -- Reset for next cycle
            orchestrator.In.onConfigure(orchestrator, {
                beamHeatRate = 40,
                beamPowerCapacity = 100,
            })

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
end

return Demo
