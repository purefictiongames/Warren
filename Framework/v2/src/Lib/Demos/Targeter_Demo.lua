--[[
    LibPureFiction Framework v2
    Targeter Component Demo - Signal-Based Architecture

    Uses Out:Fire / In signal pattern, not direct handler calls.

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

local Node = require(ReplicatedStorage.Lib.Node)
local Targeter = Lib.Components.Targeter

local Demo = {}

--------------------------------------------------------------------------------
-- TARGETER CONTROLLER NODE
-- Fires signals to control targeter, receives signals back
--------------------------------------------------------------------------------

local TargeterController = Node.extend({
    name = "TargeterController",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._targets = {}
            self._isEnabled = false
        end,
    },

    In = {
        -- Receive target updates from Targeter
        onAcquired = function(self, data)
            self._targets = data.targets
        end,

        onTracking = function(self, data)
            self._targets = data.targets
        end,

        onLost = function(self)
            self._targets = {}
        end,
    },

    Out = {
        enable = {},      -- -> Targeter.In.onEnable
        disable = {},     -- -> Targeter.In.onDisable
        scan = {},        -- -> Targeter.In.onScan
        configure = {},   -- -> Targeter.In.onConfigure
    },

    -- Controller methods that fire signals
    enableScanning = function(self)
        self._isEnabled = true
        self.Out:Fire("enable", {})
    end,

    disableScanning = function(self)
        self._isEnabled = false
        self.Out:Fire("disable", {})
    end,

    triggerScan = function(self)
        self.Out:Fire("scan", {})
    end,

    setBeamMode = function(self, mode)
        self.Out:Fire("configure", { beamMode = mode })
    end,

    setTrackingMode = function(self, mode)
        self.Out:Fire("configure", { trackingMode = mode })
    end,

    setScanMode = function(self, mode)
        self.Out:Fire("configure", { scanMode = mode })
    end,

    setRange = function(self, range)
        self.Out:Fire("configure", { range = range })
    end,
})

--------------------------------------------------------------------------------
-- DEMO
--------------------------------------------------------------------------------

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
    statusLabel.Text = "SIGNAL-BASED\nTARGETER: OFFLINE"
    statusLabel.Parent = billboardGui

    -- Target folder
    local targetFolder = Instance.new("Folder")
    targetFolder.Name = "Targets"
    targetFolder.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- BEAM VISUALIZATION
    ---------------------------------------------------------------------------

    local beamParts = {}
    local currentTargets = {}

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
    -- CREATE NODES
    ---------------------------------------------------------------------------

    local targeter = Targeter:new({
        id = "Demo_Targeter",
        model = scanner,
    })
    targeter.Sys.onInit(targeter)

    -- Configure targeter (setup phase - direct call OK per ARCHITECTURE.md)
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

    -- Controller
    local controller = TargeterController:new({ id = "Demo_TargeterController" })
    controller.Sys.onInit(controller)

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS (manual wiring for demo - in production IPC does this)
    ---------------------------------------------------------------------------

    -- Controller.Out -> Targeter.In
    controller.Out = {
        Fire = function(self, signal, data)
            if signal == "enable" then
                targeter.In.onEnable(targeter)
            elseif signal == "disable" then
                targeter.In.onDisable(targeter)
            elseif signal == "scan" then
                targeter.In.onScan(targeter)
            elseif signal == "configure" then
                targeter.In.onConfigure(targeter, data)
            end
        end,
    }

    -- Targeter.Out -> Controller.In + UI updates
    targeter.Out = {
        Fire = function(self, signal, data)
            if signal == "acquired" then
                controller.In.onAcquired(controller, data)
                currentTargets = data.targets
                statusLabel.TextColor3 = Color3.new(1, 0.5, 0)
                statusLabel.Text = string.format("SIGNAL-BASED\nACQUIRED! Targets: %d", #data.targets)

                -- Highlight targets
                for _, targetData in ipairs(data.targets) do
                    if targetData.target:IsA("BasePart") then
                        targetData.target.BrickColor = BrickColor.new("Bright orange")
                    end
                end

            elseif signal == "tracking" then
                controller.In.onTracking(controller, data)
                currentTargets = data.targets
                statusLabel.TextColor3 = Color3.new(1, 0, 0)
                statusLabel.Text = string.format(
                    "SIGNAL-BASED\nTRACKING: %d\nClosest: %.1f studs",
                    #data.targets,
                    data.targets[1] and data.targets[1].distance or 0
                )

            elseif signal == "lost" then
                controller.In.onLost(controller)
                currentTargets = {}
                statusLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
                statusLabel.Text = "SIGNAL-BASED\nTARGET LOST"

                -- Reset target colors
                for _, target in ipairs(targetFolder:GetChildren()) do
                    if target:IsA("BasePart") then
                        target.BrickColor = BrickColor.new("Bright red")
                    end
                end
            end
        end,
    }

    -- Track enabled state via signals (not direct method calls)
    local targeterEnabled = false

    -- Beam visualization update (uses tracked state, not direct method calls)
    local visualConnection = RunService.Heartbeat:Connect(function()
        if not demoFolder.Parent then return end

        clearBeams()

        if not targeterEnabled then return end

        -- Draw beams to tracked targets (state from signals, not direct calls)
        local origin = scanner.Position
        for _, targetData in ipairs(currentTargets) do
            local direction = targetData.position - origin
            drawBeam(origin, direction, targetData, true)
        end
    end)

    ---------------------------------------------------------------------------
    -- DEMO CONTROLS (fire signals through controller)
    ---------------------------------------------------------------------------

    local controls = {}
    local targetCounter = 0

    function controls.enable()
        controller:enableScanning()
        targeterEnabled = true
        statusLabel.Text = "SIGNAL-BASED\nSCANNING..."
        statusLabel.TextColor3 = Color3.new(0, 1, 0)
        scanner.BrickColor = BrickColor.new("Bright green")
    end

    function controls.disable()
        controller:disableScanning()
        targeterEnabled = false
        statusLabel.Text = "SIGNAL-BASED\nTARGETER: OFFLINE"
        statusLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
        scanner.BrickColor = BrickColor.new("Medium stone grey")
        clearBeams()
    end

    function controls.scan()
        controller:triggerScan()
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
        controller:setBeamMode(mode)
        print("Beam mode set to:", mode)
    end

    function controls.setTrackingMode(mode)
        controller:setTrackingMode(mode)
        print("Tracking mode set to:", mode)
    end

    function controls.setScanMode(mode)
        local wasEnabled = targeterEnabled
        if wasEnabled then controls.disable() end
        controller:setScanMode(mode)
        if wasEnabled then controls.enable() end
        print("Scan mode set to:", mode)
    end

    function controls.setRange(range)
        controller:setRange(range)
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

    function controls.getController()
        return controller
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

    print("============================================")
    print("  SIGNAL-BASED TARGETER DEMO")
    print("============================================")
    print("")
    print("Controller fires signals -> Targeter receives and scans")
    print("Proper Out:Fire / In pattern")
    print("")
    print("Controls:")
    print("  demo.enable()            - Fire enable signal")
    print("  demo.disable()           - Fire disable signal")
    print("  demo.addTarget(pos)      - Add target at position")
    print("  demo.removeTargets()     - Remove all targets")
    print("  demo.setBeamMode('cone') - Fire configure signal")
    print("  demo.cleanup()           - Remove demo")
    print("")

    return controls
end

return Demo
