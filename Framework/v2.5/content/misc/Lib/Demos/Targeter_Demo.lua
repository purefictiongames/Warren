--[[
    LibPureFiction Framework v2
    Targeter Component Demo - Visual Targeting Beam

    Demonstrates the refactored Targeter component with:
    - Built-in visual targeting beam (auto-creates)
    - Auto-start scanning in onStart (batteries included)
    - Bi-directional discovery handshake
    - Target lock behavior (acquired/tracking/lost signals)

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar:

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    local demo = Demos.Targeter.run()

    -- Controls:
    demo.enable()                   -- Enable scanning
    demo.disable()                  -- Disable scanning
    demo.scan()                     -- Manual scan (pulse mode)
    demo.addTarget(position)        -- Add target at position
    demo.removeTargets()            -- Remove all targets
    demo.setBeamMode("cone")        -- Change beam mode
    demo.setBeamColor(Color3.new()) -- Change beam color
    demo.setBeamVisible(false)      -- Hide visual beam
    demo.cleanup()                  -- Remove demo objects
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

local Targeter = Lib.Components.Targeter

local Demo = {}

--------------------------------------------------------------------------------
-- DEMO
--------------------------------------------------------------------------------

function Demo.run(config)
    config = config or {}
    local position = config.position or Vector3.new(0, 10, 0)

    ---------------------------------------------------------------------------
    -- CLEANUP EXISTING DEMO
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("Targeter_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end
    task.wait(0.1)

    ---------------------------------------------------------------------------
    -- CREATE VISUAL SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "Targeter_Demo"
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

    -- Scanner mount (base)
    local mount = Instance.new("Part")
    mount.Name = "Mount"
    mount.Size = Vector3.new(4, 2, 4)
    mount.Position = position - Vector3.new(0, 1, 0)
    mount.Anchored = true
    mount.BrickColor = BrickColor.new("Really black")
    mount.Material = Enum.Material.DiamondPlate
    mount.Parent = demoFolder

    -- Scanner head (the part that rotates and scans)
    local scanner = Instance.new("Part")
    scanner.Name = "Scanner"
    scanner.Size = Vector3.new(2, 2, 3)
    scanner.CFrame = CFrame.new(position)
    scanner.Anchored = true
    scanner.BrickColor = BrickColor.new("Bright green")
    scanner.Material = Enum.Material.SmoothPlastic
    scanner.Parent = demoFolder

    -- Add a lens detail to show direction
    local lens = Instance.new("Part")
    lens.Name = "Lens"
    lens.Size = Vector3.new(1, 1, 0.2)
    lens.Shape = Enum.PartType.Cylinder
    lens.Anchored = false
    lens.CanCollide = false
    lens.BrickColor = BrickColor.new("Cyan")
    lens.Material = Enum.Material.Glass
    lens.Transparency = 0.3
    lens.Parent = scanner

    local lensWeld = Instance.new("WeldConstraint")
    lensWeld.Part0 = scanner
    lensWeld.Part1 = lens
    lensWeld.Parent = lens

    lens.CFrame = scanner.CFrame * CFrame.new(0, 0, -1.6) * CFrame.Angles(0, 0, math.rad(90))

    -- Status display
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 280, 0, 100)
    billboardGui.StudsOffset = Vector3.new(0, 5, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = mount

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundTransparency = 0.3
    statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    statusLabel.TextColor3 = Color3.new(0, 1, 0)
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.Code
    statusLabel.Text = "TARGETER DEMO\nInitializing..."
    statusLabel.Parent = billboardGui

    -- Target folder
    local targetFolder = Instance.new("Folder")
    targetFolder.Name = "Targets"
    targetFolder.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- STATE TRACKING
    ---------------------------------------------------------------------------

    local currentTargets = {}
    local targetCounter = 0
    local enabled = true  -- Targeter auto-starts

    ---------------------------------------------------------------------------
    -- CREATE TARGETER
    ---------------------------------------------------------------------------

    local targeter = Targeter:new({
        id = "Demo_Targeter",
        model = scanner,
        attributes = {
            -- Raycast config
            BeamMode = "pinpoint",
            BeamRadius = 3,
            RayCount = 8,
            Range = 80,
            ScanMode = "continuous",
            Interval = 0.1,
            TrackingMode = "lock",
            AutoStart = true,
            -- Visual beam config
            BeamVisible = true,
            BeamColor = Color3.new(0, 1, 0),  -- Green
            BeamWidth = 0.15,
            BeamTransparency = 0.3,
        },
    })

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS
    ---------------------------------------------------------------------------

    -- Subscribe to Targeter output signals
    local originalOutFire = targeter.Out.Fire
    targeter.Out.Fire = function(outSelf, signal, data)
        data = data or {}

        if signal == "acquired" then
            currentTargets = data.targets or {}
            statusLabel.TextColor3 = Color3.new(1, 0.5, 0)
            statusLabel.Text = string.format(
                "TARGETER DEMO\nACQUIRED!\nTargets: %d",
                #currentTargets
            )

            -- Highlight targets
            for _, targetData in ipairs(currentTargets) do
                if targetData.target and targetData.target:IsA("BasePart") then
                    targetData.target.BrickColor = BrickColor.new("Bright orange")
                end
            end

        elseif signal == "tracking" then
            currentTargets = data.targets or {}
            local closest = currentTargets[1]
            statusLabel.TextColor3 = Color3.new(1, 0, 0)
            statusLabel.Text = string.format(
                "TARGETER DEMO\nLOCKED: %d targets\nClosest: %.1f studs",
                #currentTargets,
                closest and closest.distance or 0
            )

        elseif signal == "lost" then
            currentTargets = {}
            statusLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
            statusLabel.Text = "TARGETER DEMO\nTARGET LOST"

            -- Reset target colors
            for _, target in ipairs(targetFolder:GetChildren()) do
                if target:IsA("BasePart") then
                    target.BrickColor = BrickColor.new("Bright red")
                end
            end

        elseif signal == "discoverLauncher" then
            -- Targeter is looking for a Launcher
            -- In this demo we're standalone, so no response
            print("[Demo] Targeter fired discoverLauncher - no Launcher wired")

        elseif signal == "targeterPresent" then
            -- Response to a Launcher's discovery (if wired)
            print("[Demo] Targeter responded with targeterPresent:", data)
        end

        -- Call original if it exists
        if originalOutFire then
            originalOutFire(outSelf, signal, data)
        end
    end

    ---------------------------------------------------------------------------
    -- INITIALIZE AND START
    ---------------------------------------------------------------------------

    targeter.Sys.onInit(targeter)

    -- Configure filter for our demo targets
    targeter.In.onConfigure(targeter, {
        filter = { class = "DemoTarget" },
    })

    targeter.Sys.onStart(targeter)

    statusLabel.Text = "TARGETER DEMO\nSCANNING...\nAdd targets to detect"

    ---------------------------------------------------------------------------
    -- SCANNER ROTATION ANIMATION
    ---------------------------------------------------------------------------

    local rotationSpeed = 20  -- degrees per second
    local currentAngle = 0
    local rotationDirection = 1  -- 1 = right, -1 = left
    local maxAngle = 60

    local rotationConnection = RunService.Heartbeat:Connect(function(dt)
        if not demoFolder.Parent then return end
        if not enabled then return end

        -- Sweep left and right
        currentAngle = currentAngle + rotationSpeed * rotationDirection * dt

        if currentAngle >= maxAngle then
            currentAngle = maxAngle
            rotationDirection = -1
        elseif currentAngle <= -maxAngle then
            currentAngle = -maxAngle
            rotationDirection = 1
        end

        scanner.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(currentAngle), 0)
    end)

    ---------------------------------------------------------------------------
    -- DEMO CONTROLS
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.enable()
        targeter.In.onEnable(targeter)
        enabled = true
        statusLabel.Text = "TARGETER DEMO\nSCANNING..."
        statusLabel.TextColor3 = Color3.new(0, 1, 0)
        scanner.BrickColor = BrickColor.new("Bright green")
    end

    function controls.disable()
        targeter.In.onDisable(targeter)
        enabled = false
        statusLabel.Text = "TARGETER DEMO\nOFFLINE"
        statusLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
        scanner.BrickColor = BrickColor.new("Medium stone grey")
    end

    function controls.scan()
        targeter.In.onScan(targeter)
    end

    function controls.addTarget(targetPosition)
        targetPosition = targetPosition or (position + Vector3.new(
            math.random(-30, 30),
            math.random(-5, 5),
            -math.random(15, 50)
        ))

        targetCounter = targetCounter + 1
        local target = Instance.new("Part")
        target.Name = "Target_" .. targetCounter
        target.Size = Vector3.new(4, 4, 4)
        target.Position = targetPosition
        target.Anchored = true
        target.BrickColor = BrickColor.new("Bright red")
        target.Material = Enum.Material.SmoothPlastic
        target:SetAttribute("NodeClass", "DemoTarget")
        target.Parent = targetFolder

        print(string.format("[Demo] Added target at %.0f, %.0f, %.0f",
            targetPosition.X, targetPosition.Y, targetPosition.Z))

        return target
    end

    function controls.removeTargets()
        targetFolder:ClearAllChildren()
        currentTargets = {}
        print("[Demo] Removed all targets")
    end

    function controls.setBeamMode(mode)
        targeter.In.onConfigure(targeter, { beamMode = mode })
        print("[Demo] Beam mode set to:", mode)
    end

    function controls.setTrackingMode(mode)
        targeter.In.onConfigure(targeter, { trackingMode = mode })
        print("[Demo] Tracking mode set to:", mode)
    end

    function controls.setScanMode(mode)
        targeter.In.onConfigure(targeter, { scanMode = mode })
        print("[Demo] Scan mode set to:", mode)
    end

    function controls.setRange(range)
        targeter.In.onConfigure(targeter, { range = range })
        print("[Demo] Range set to:", range)
    end

    function controls.setBeamColor(color)
        targeter.In.onConfigure(targeter, { beamColor = color })
        print("[Demo] Beam color changed")
    end

    function controls.setBeamVisible(visible)
        targeter.In.onConfigure(targeter, { beamVisible = visible })
        print("[Demo] Beam visible:", visible)
    end

    function controls.setBeamWidth(width)
        targeter.In.onConfigure(targeter, { beamWidth = width })
        print("[Demo] Beam width:", width)
    end

    function controls.pointAt(direction)
        local pos = scanner.Position
        scanner.CFrame = CFrame.new(pos, pos + direction)
        currentAngle = 0
        rotationDirection = 1
    end

    function controls.stopRotation()
        rotationSpeed = 0
    end

    function controls.startRotation(speed)
        rotationSpeed = speed or 20
    end

    function controls.cleanup()
        print("[Demo] Cleaning up...")
        rotationConnection:Disconnect()
        targeter.Sys.onStop(targeter)
        demoFolder:Destroy()
        print("[Demo] Cleanup complete")
    end

    function controls.getTargeter()
        return targeter
    end

    ---------------------------------------------------------------------------
    -- AUTO-DEMO
    ---------------------------------------------------------------------------

    if config.autoDemo ~= false then
        -- Add some targets automatically
        task.spawn(function()
            task.wait(1)
            if not demoFolder.Parent then return end

            controls.addTarget(position + Vector3.new(0, 0, -25))
            task.wait(0.5)
            if not demoFolder.Parent then return end

            controls.addTarget(position + Vector3.new(15, 3, -30))
            task.wait(0.5)
            if not demoFolder.Parent then return end

            controls.addTarget(position + Vector3.new(-20, -2, -20))
        end)
    end

    ---------------------------------------------------------------------------
    -- CLEANUP ON DESTROY
    ---------------------------------------------------------------------------

    demoFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            rotationConnection:Disconnect()
            targeter.Sys.onStop(targeter)
        end
    end)

    ---------------------------------------------------------------------------
    -- PRINT INSTRUCTIONS
    ---------------------------------------------------------------------------

    print("============================================")
    print("  TARGETER DEMO")
    print("============================================")
    print("")
    print("Features:")
    print("  - Built-in visual targeting beam")
    print("  - Auto-starts scanning (batteries included)")
    print("  - Target lock: acquired → tracking → lost")
    print("  - Beam changes color when locked (green → red)")
    print("")
    print("Controls:")
    print("  demo.addTarget(pos)         - Add target")
    print("  demo.removeTargets()        - Clear all targets")
    print("  demo.enable() / disable()   - Toggle scanning")
    print("  demo.setBeamMode('cone')    - pinpoint/cylinder/cone")
    print("  demo.setBeamColor(Color3)   - Change beam color")
    print("  demo.setBeamVisible(false)  - Hide beam")
    print("  demo.setRange(100)          - Change range")
    print("  demo.stopRotation()         - Stop scanner rotation")
    print("  demo.cleanup()              - Remove demo")
    print("")

    return controls
end

return Demo
