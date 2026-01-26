--[[
    LibPureFiction Framework v2
    Swivel_Demo.lua - Automated Dual-Swivel Turret Demonstration

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Demonstrates a turret-style dual-swivel system:
    - Yaw swivel: Rotates left/right (Y-axis) - blue part
    - Pitch swivel: Rotates up/down (X-axis) - green part, mounted on yaw

    Architecture:
    - Uses SwivelDemoOrchestrator (extended Orchestrator)
    - All control via In signals
    - All state via Out signals
    - Fully automated

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    Demos.Swivel.run()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

local SwivelDemoOrchestrator = Lib.Components.SwivelDemoOrchestrator

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
    demoFolder.Name = "Swivel_Demo"
    demoFolder.Parent = workspace

    -- Yaw part (base rotating part) - rotates left/right
    local yawPart = Instance.new("Part")
    yawPart.Name = "YawPart"
    yawPart.Size = Vector3.new(3, 1, 3)
    yawPart.Position = position
    yawPart.Anchored = false
    yawPart.CanCollide = false
    yawPart.BrickColor = BrickColor.new("Bright blue")
    yawPart.Material = Enum.Material.SmoothPlastic
    yawPart.Parent = demoFolder

    -- Pitch part (mounted on yaw) - rotates up/down
    local pitchPart = Instance.new("Part")
    pitchPart.Name = "PitchPart"
    pitchPart.Size = Vector3.new(2, 1, 3)
    pitchPart.Position = position + Vector3.new(0, 1, 0)
    pitchPart.Anchored = false
    pitchPart.CanCollide = false
    pitchPart.BrickColor = BrickColor.new("Bright green")
    pitchPart.Material = Enum.Material.SmoothPlastic
    pitchPart.Parent = demoFolder

    -- Status display
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 200, 0, 60)
    billboardGui.StudsOffset = Vector3.new(0, 4, 0)
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

    local orchestrator = SwivelDemoOrchestrator:new({
        id = "Demo_SwivelOrchestrator",
        model = yawPart,
        attributes = {
            pitchModel = pitchPart,
            yawConfig = {
                speed = 45,
                minAngle = -90,
                maxAngle = 90,
            },
            pitchConfig = {
                speed = 30,
                minAngle = -30,
                maxAngle = 60,
            },
        },
    })

    ---------------------------------------------------------------------------
    -- SUBSCRIBE TO SIGNALS
    ---------------------------------------------------------------------------

    local yawAngle = 0
    local pitchAngle = 0

    local originalOutFire = orchestrator.Out.Fire
    orchestrator.Out.Fire = function(outSelf, signal, data)
        if signal == "yawRotated" and data and data.angle then
            yawAngle = data.angle
            statusLabel.Text = string.format("Y:%.0f P:%.0f", yawAngle, pitchAngle)
        elseif signal == "pitchRotated" and data and data.angle then
            pitchAngle = data.angle
            statusLabel.Text = string.format("Y:%.0f P:%.0f", yawAngle, pitchAngle)
        elseif signal == "yawLimitReached" or signal == "pitchLimitReached" then
            statusLabel.Text = "LIMIT"
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
        print("=== DUAL SWIVEL DEMO ===")
        print("Yaw (blue): left/right rotation")
        print("Pitch (green): up/down rotation")
        print("")

        task.wait(1)

        while demoFolder.Parent do
            -- Phase 1: Yaw left
            print("Yaw: rotating left...")
            statusLabel.Text = "YAW LEFT"
            orchestrator.In.onRotateYaw(orchestrator, { direction = "forward" })
            task.wait(3)
            if not demoFolder.Parent then break end
            orchestrator.In.onStopYaw(orchestrator, {})
            task.wait(0.5)

            -- Phase 2: Pitch up
            print("Pitch: rotating up...")
            statusLabel.Text = "PITCH UP"
            orchestrator.In.onRotatePitch(orchestrator, { direction = "forward" })
            task.wait(2)
            if not demoFolder.Parent then break end
            orchestrator.In.onStopPitch(orchestrator, {})
            task.wait(0.5)

            -- Phase 3: Yaw right
            print("Yaw: rotating right...")
            statusLabel.Text = "YAW RIGHT"
            orchestrator.In.onRotateYaw(orchestrator, { direction = "reverse" })
            task.wait(3)
            if not demoFolder.Parent then break end
            orchestrator.In.onStopYaw(orchestrator, {})
            task.wait(0.5)

            -- Phase 4: Pitch down
            print("Pitch: rotating down...")
            statusLabel.Text = "PITCH DOWN"
            orchestrator.In.onRotatePitch(orchestrator, { direction = "reverse" })
            task.wait(2)
            if not demoFolder.Parent then break end
            orchestrator.In.onStopPitch(orchestrator, {})
            task.wait(0.5)

            -- Phase 5: Both at once
            print("Both: rotating together...")
            statusLabel.Text = "BOTH"
            orchestrator.In.onRotateYaw(orchestrator, { direction = "forward" })
            orchestrator.In.onRotatePitch(orchestrator, { direction = "forward" })
            task.wait(2)
            if not demoFolder.Parent then break end
            orchestrator.In.onStop(orchestrator, {})
            task.wait(1)
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
