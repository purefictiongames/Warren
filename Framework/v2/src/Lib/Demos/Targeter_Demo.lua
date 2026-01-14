--[[
    LibPureFiction Framework v2
    Targeter Component Demo

    Demonstrates raycast-based target detection with visual beam rendering.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar:

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    local demo = Demos.Targeter.run()

    -- Controls:
    demo.enable()              -- Start scanning
    demo.disable()             -- Stop scanning
    demo.scan()                -- Manual scan (pulse mode)
    demo.addTarget(position)   -- Add target at position
    demo.removeTargets()       -- Remove all targets
    demo.setBeamMode("cone")   -- Change beam mode
    demo.cleanup()             -- Remove demo objects
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Targeter = Lib.Components.Targeter

local Demo = {}

function Demo.run(config)
    config = config or {}
    local position = config.position or Vector3.new(0, 10, 0)

    ---------------------------------------------------------------------------
    -- CLEANUP EXISTING DEMO (handles Studio persistence between runs)
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("Targeter_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end

    ---------------------------------------------------------------------------
    -- CREATE VISUAL SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "Targeter_Demo"
    demoFolder.Parent = workspace

    -- Scanner mount
    local mount = Instance.new("Part")
    mount.Name = "Mount"
    mount.Size = Vector3.new(3, 3, 3)
    mount.Position = position
    mount.Anchored = true
    mount.BrickColor = BrickColor.new("Dark stone grey")
    mount.Material = Enum.Material.Metal
    mount.Shape = Enum.PartType.Ball
    mount.Parent = demoFolder

    -- Scanner emitter (the actual scanning part)
    local scanner = Instance.new("Part")
    scanner.Name = "Scanner"
    scanner.Size = Vector3.new(1, 1, 2)
    scanner.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, 0)
    scanner.Anchored = true
    scanner.BrickColor = BrickColor.new("Bright green")
    scanner.Material = Enum.Material.Neon
    scanner.Parent = demoFolder

    -- Beam visualization parts
    local beamFolder = Instance.new("Folder")
    beamFolder.Name = "BeamVisualization"
    beamFolder.Parent = demoFolder

    -- Status display
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 250, 0, 80)
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
    statusLabel.Text = "TARGETER: OFFLINE\nTargets: 0"
    statusLabel.Parent = billboardGui

    -- Target folder
    local targetFolder = Instance.new("Folder")
    targetFolder.Name = "Targets"
    targetFolder.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- BEAM VISUALIZATION
    ---------------------------------------------------------------------------

    local beamParts = {}

    local function clearBeams()
        for _, beam in ipairs(beamParts) do
            if beam.Parent then
                beam:Destroy()
            end
        end
        beamParts = {}
    end

    local function drawBeam(origin, direction, hit, isHit)
        local endPoint = hit and hit.position or (origin + direction)
        local distance = (endPoint - origin).Magnitude
        local midpoint = origin + (endPoint - origin) / 2

        local beam = Instance.new("Part")
        beam.Name = "Beam"
        beam.Size = Vector3.new(0.1, 0.1, distance)
        beam.CFrame = CFrame.new(midpoint, endPoint)
        beam.Anchored = true
        beam.CanCollide = false
        beam.Material = Enum.Material.Neon
        beam.BrickColor = isHit and BrickColor.new("Bright red") or BrickColor.new("Lime green")
        beam.Transparency = 0.3
        beam.Parent = beamFolder

        table.insert(beamParts, beam)
        return beam
    end

    ---------------------------------------------------------------------------
    -- CREATE TARGETER COMPONENT
    ---------------------------------------------------------------------------

    local targeter = Targeter:new({
        id = "Demo_Targeter",
        model = scanner,
    })
    targeter.Sys.onInit(targeter)

    -- Configure targeter
    targeter.In.onConfigure(targeter, {
        beamMode = "pinpoint",
        beamRadius = 3,
        rayCount = 8,
        range = 50,
        scanMode = "interval",
        interval = 0.1,
        trackingMode = "lock",
        filter = { class = "DemoTarget" },
    })

    -- Track targets for visualization
    local currentTargets = {}

    -- Wire output
    targeter.Out = {
        Fire = function(self, signal, data)
            if signal == "acquired" then
                statusLabel.TextColor3 = Color3.new(1, 0.5, 0)
                statusLabel.Text = string.format("ACQUIRED!\nTargets: %d", #data.targets)
                currentTargets = data.targets

                -- Highlight targets
                for _, targetData in ipairs(data.targets) do
                    if targetData.target:IsA("BasePart") then
                        targetData.target.BrickColor = BrickColor.new("Bright orange")
                    end
                end

            elseif signal == "tracking" then
                statusLabel.TextColor3 = Color3.new(1, 0, 0)
                statusLabel.Text = string.format("TRACKING\nTargets: %d\nClosest: %.1f studs",
                    #data.targets,
                    data.targets[1] and data.targets[1].distance or 0)
                currentTargets = data.targets

            elseif signal == "lost" then
                statusLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
                statusLabel.Text = "TARGET LOST\nTargets: 0"
                currentTargets = {}

                -- Reset target colors
                for _, target in ipairs(targetFolder:GetChildren()) do
                    if target:IsA("BasePart") then
                        target.BrickColor = BrickColor.new("Bright red")
                    end
                end
            end
        end,
    }

    -- Beam visualization update
    local visualConnection = RunService.Heartbeat:Connect(function()
        if not demoFolder.Parent then return end

        clearBeams()

        if not targeter:isEnabled() then return end

        -- Draw rays based on current beam mode
        local rays = targeter:_generateRays()
        for _, ray in ipairs(rays) do
            -- Find if this ray hit a target
            local hit = nil
            for _, targetData in ipairs(currentTargets) do
                local toTarget = targetData.position - ray.origin
                local dot = toTarget:Dot(ray.direction.Unit)
                if dot > 0 and dot < ray.direction.Magnitude then
                    hit = targetData
                    break
                end
            end
            drawBeam(ray.origin, ray.direction, hit, hit ~= nil)
        end
    end)

    ---------------------------------------------------------------------------
    -- DEMO CONTROLS
    ---------------------------------------------------------------------------

    local controls = {}
    local targetCounter = 0

    function controls.enable()
        targeter.In.onEnable(targeter)
        if targeter:isScanning() then
            statusLabel.Text = "SCANNING...\nTargets: 0"
            statusLabel.TextColor3 = Color3.new(0, 1, 0)
            scanner.BrickColor = BrickColor.new("Bright green")
        end
    end

    function controls.disable()
        targeter.In.onDisable(targeter)
        statusLabel.Text = "TARGETER: OFFLINE\nTargets: 0"
        statusLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
        scanner.BrickColor = BrickColor.new("Medium stone grey")
        clearBeams()
    end

    function controls.scan()
        targeter.In.onScan(targeter)
    end

    function controls.addTarget(targetPosition)
        targetPosition = targetPosition or (position + Vector3.new(
            math.random(-20, 20),
            math.random(-5, 5),
            -math.random(10, 40)
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

        return target
    end

    function controls.removeTargets()
        targetFolder:ClearAllChildren()
        currentTargets = {}
    end

    function controls.setBeamMode(mode)
        targeter.In.onConfigure(targeter, { beamMode = mode })
        print("Beam mode set to:", mode)
    end

    function controls.setTrackingMode(mode)
        targeter.In.onConfigure(targeter, { trackingMode = mode })
        print("Tracking mode set to:", mode)
    end

    function controls.setScanMode(mode)
        local wasEnabled = targeter:isEnabled()
        if wasEnabled then controls.disable() end
        targeter.In.onConfigure(targeter, { scanMode = mode })
        if wasEnabled then controls.enable() end
        print("Scan mode set to:", mode)
    end

    function controls.setRange(range)
        targeter.In.onConfigure(targeter, { range = range })
    end

    function controls.pointAt(direction)
        scanner.CFrame = CFrame.new(scanner.Position, scanner.Position + direction)
    end

    function controls.cleanup()
        visualConnection:Disconnect()
        targeter.Sys.onStop(targeter)
        demoFolder:Destroy()
    end

    function controls.getTargeter()
        return targeter
    end

    ---------------------------------------------------------------------------
    -- AUTO-DEMO (optional)
    ---------------------------------------------------------------------------

    if config.autoDemo then
        -- Add some targets
        controls.addTarget(position + Vector3.new(0, 0, -20))
        controls.addTarget(position + Vector3.new(10, 2, -25))
        controls.addTarget(position + Vector3.new(-8, -1, -15))

        -- Start scanning
        controls.enable()
    end

    print("Targeter Demo running. Controls:")
    print("  demo.enable()            - Start scanning")
    print("  demo.disable()           - Stop scanning")
    print("  demo.addTarget(pos)      - Add target at position")
    print("  demo.removeTargets()     - Remove all targets")
    print("  demo.setBeamMode('cone') - Change beam mode")
    print("  demo.cleanup()           - Remove demo")

    return controls
end

return Demo
