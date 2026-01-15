--[[
    LibPureFiction Framework v2
    Swivel Component Demo - Physics-Based with Signal Architecture

    Demonstrates physics-based Swivel using HingeConstraint servos.
    Uses Out:Fire / In signal pattern, not direct handler calls.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar:

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    local demo = Demos.Swivel.run()

    -- Controls:
    demo.rotateForward()   -- Start rotating forward
    demo.rotateReverse()   -- Start rotating reverse
    demo.stop()            -- Stop rotation
    demo.setAngle(45)      -- Set to specific angle
    demo.cleanup()         -- Remove demo objects
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

local Node = require(ReplicatedStorage.Lib.Node)
local Swivel = Lib.Components.Swivel

local Demo = {}

--------------------------------------------------------------------------------
-- SWIVEL CONTROLLER NODE
-- Fires signals to control swivel, receives signals back
--------------------------------------------------------------------------------

local SwivelController = Node.extend({
    name = "SwivelController",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._currentAngle = 0
        end,
    },

    In = {
        -- Receive rotation updates from Swivel
        onRotated = function(self, data)
            self._currentAngle = data.angle
        end,

        onLimitReached = function(self, data)
            -- Could trigger reverse, notification, etc.
        end,

        onStopped = function(self)
            -- Rotation stopped
        end,
    },

    Out = {
        rotate = {},      -- -> Swivel.In.onRotate
        stop = {},        -- -> Swivel.In.onStop
        setAngle = {},    -- -> Swivel.In.onSetAngle
        configure = {},   -- -> Swivel.In.onConfigure
    },

    -- Controller methods that fire signals
    rotateForward = function(self)
        self.Out:Fire("rotate", { direction = "forward" })
    end,

    rotateReverse = function(self)
        self.Out:Fire("rotate", { direction = "reverse" })
    end,

    stopRotation = function(self)
        self.Out:Fire("stop", {})
    end,

    setTargetAngle = function(self, degrees)
        self.Out:Fire("setAngle", { degrees = degrees })
    end,

    setMode = function(self, mode)
        self.Out:Fire("configure", { mode = mode })
    end,

    setSpeed = function(self, speed)
        self.Out:Fire("configure", { speed = speed })
    end,

    setLimits = function(self, min, max)
        self.Out:Fire("configure", { minAngle = min, maxAngle = max })
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

    local existingDemo = workspace:FindFirstChild("Swivel_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end

    ---------------------------------------------------------------------------
    -- CREATE VISUAL SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "Swivel_Demo"
    demoFolder.Parent = workspace

    -- Base platform (stationary)
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(6, 1, 6)
    base.Position = position - Vector3.new(0, 1, 0)
    base.Anchored = true
    base.BrickColor = BrickColor.new("Dark stone grey")
    base.Material = Enum.Material.Metal
    base.Parent = demoFolder

    -- Rotating turret head (will be unanchored by Swivel for physics)
    local turretHead = Instance.new("Part")
    turretHead.Name = "TurretHead"
    turretHead.Size = Vector3.new(4, 2, 4)
    turretHead.CFrame = CFrame.new(position)
    turretHead.Anchored = false  -- Physics-driven
    turretHead.CanCollide = false
    turretHead.BrickColor = BrickColor.new("Bright blue")
    turretHead.Material = Enum.Material.SmoothPlastic
    turretHead.Parent = demoFolder

    -- Direction indicator (barrel) - welded to turretHead
    local barrel = Instance.new("Part")
    barrel.Name = "Barrel"
    barrel.Size = Vector3.new(0.8, 0.8, 4)
    barrel.CFrame = turretHead.CFrame * CFrame.new(0, 0, -2)
    barrel.Anchored = false  -- Physics-driven via weld
    barrel.CanCollide = false
    barrel.BrickColor = BrickColor.new("Really red")
    barrel.Material = Enum.Material.Neon
    barrel.Parent = demoFolder

    -- Weld barrel to turret head (physics constraint keeps them together)
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = turretHead
    weld.Part1 = barrel
    weld.Parent = turretHead

    -- Angle display
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 200, 0, 50)
    billboardGui.StudsOffset = Vector3.new(0, 4, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = turretHead

    local angleLabel = Instance.new("TextLabel")
    angleLabel.Size = UDim2.new(1, 0, 1, 0)
    angleLabel.BackgroundTransparency = 0.3
    angleLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    angleLabel.TextColor3 = Color3.new(1, 1, 1)
    angleLabel.TextScaled = true
    angleLabel.Font = Enum.Font.Code
    angleLabel.Text = "PHYSICS-BASED\nAngle: 0"
    angleLabel.Parent = billboardGui

    ---------------------------------------------------------------------------
    -- CREATE NODES
    ---------------------------------------------------------------------------

    -- Swivel with anchor (base) - creates HingeConstraint for smooth physics rotation
    local swivel = Swivel:new({
        id = "Demo_Swivel",
        model = turretHead,
        anchor = base,  -- Hinge attaches turretHead to base
    })
    swivel.Sys.onInit(swivel)
    swivel.Sys.onStart(swivel)  -- Start monitoring for angle signals

    -- Configure swivel (setup phase - direct call OK per ARCHITECTURE.md)
    swivel.In.onConfigure(swivel, {
        axis = "Y",
        mode = "continuous",
        speed = 60,  -- Degrees per second
        minAngle = -90,
        maxAngle = 90,
    })

    -- Controller
    local controller = SwivelController:new({ id = "Demo_SwivelController" })
    controller.Sys.onInit(controller)

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS (manual wiring for demo - in production IPC does this)
    ---------------------------------------------------------------------------

    -- Controller.Out -> Swivel.In
    controller.Out = {
        Fire = function(self, signal, data)
            if signal == "rotate" then
                swivel.In.onRotate(swivel, data)
            elseif signal == "stop" then
                swivel.In.onStop(swivel)
            elseif signal == "setAngle" then
                swivel.In.onSetAngle(swivel, data)
            elseif signal == "configure" then
                swivel.In.onConfigure(swivel, data)
            end
        end,
    }

    -- Swivel.Out -> Controller.In + UI updates
    swivel.Out = {
        Fire = function(self, signal, data)
            if signal == "rotated" then
                controller.In.onRotated(controller, data)
                angleLabel.Text = string.format("PHYSICS-BASED\nAngle: %.1f", data.angle)
            elseif signal == "limitReached" then
                controller.In.onLimitReached(controller, data)
                angleLabel.Text = string.format("LIMIT: %s", data.limit:upper())
                -- Flash the barrel
                local originalColor = barrel.BrickColor
                barrel.BrickColor = BrickColor.new("Bright yellow")
                task.delay(0.2, function()
                    if barrel.Parent then
                        barrel.BrickColor = originalColor
                    end
                end)
            elseif signal == "stopped" then
                angleLabel.Text = string.format("PHYSICS-BASED\nStopped: %.1f", swivel:getCurrentAngle())
            end
        end,
    }

    -- No manual CFrame updates needed - physics handles everything via:
    -- - HingeConstraint servo rotates turretHead
    -- - WeldConstraint keeps barrel attached to turretHead

    ---------------------------------------------------------------------------
    -- DEMO CONTROLS (fire signals through controller)
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.rotateForward()
        controller:rotateForward()
    end

    function controls.rotateReverse()
        controller:rotateReverse()
    end

    function controls.stop()
        controller:stopRotation()
    end

    function controls.setAngle(degrees)
        controller:setTargetAngle(degrees)
    end

    function controls.setMode(mode)
        controller:setMode(mode)
    end

    function controls.setSpeed(speed)
        controller:setSpeed(speed)
    end

    function controls.setLimits(min, max)
        controller:setLimits(min, max)
    end

    function controls.cleanup()
        swivel.Sys.onStop(swivel)  -- Cleans up HingeConstraint and attachments
        demoFolder:Destroy()
    end

    function controls.getSwivel()
        return swivel
    end

    function controls.getController()
        return controller
    end

    ---------------------------------------------------------------------------
    -- AUTO-DEMO (optional)
    ---------------------------------------------------------------------------

    if config.autoDemo then
        task.spawn(function()
            -- Sweep back and forth using signals
            while demoFolder.Parent do
                controls.rotateForward()
                task.wait(3)
                controls.rotateReverse()
                task.wait(3)
            end
        end)
    end

    print("============================================")
    print("  PHYSICS-BASED SWIVEL DEMO")
    print("============================================")
    print("")
    print("Architecture:")
    print("  base       - Anchored (fixed)")
    print("  turretHead - HingeConstraint servo (Y axis)")
    print("  barrel     - WeldConstraint to turretHead")
    print("")
    print("All motion via physics - no CFrame manipulation!")
    print("")
    print("Controls:")
    print("  demo.rotateForward()  - Motor mode, continuous")
    print("  demo.rotateReverse()  - Motor mode, continuous")
    print("  demo.stop()           - Stop and hold position")
    print("  demo.setAngle(45)     - Servo mode, smooth move")
    print("  demo.cleanup()        - Remove demo")
    print("")

    return controls
end

return Demo
