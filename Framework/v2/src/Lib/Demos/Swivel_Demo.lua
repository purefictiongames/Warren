--[[
    LibPureFiction Framework v2
    Swivel Component Demo

    Demonstrates single-axis rotation with visual feedback.

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
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Swivel = Lib.Components.Swivel

local Demo = {}

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

    -- Rotating turret head
    local turretHead = Instance.new("Part")
    turretHead.Name = "TurretHead"
    turretHead.Size = Vector3.new(4, 2, 4)
    turretHead.CFrame = CFrame.new(position)
    turretHead.Anchored = true
    turretHead.BrickColor = BrickColor.new("Bright blue")
    turretHead.Material = Enum.Material.SmoothPlastic
    turretHead.Parent = demoFolder

    -- Direction indicator (barrel)
    local barrel = Instance.new("Part")
    barrel.Name = "Barrel"
    barrel.Size = Vector3.new(0.8, 0.8, 4)
    barrel.CFrame = turretHead.CFrame * CFrame.new(0, 0, -2)
    barrel.Anchored = true
    barrel.BrickColor = BrickColor.new("Really red")
    barrel.Material = Enum.Material.Neon
    barrel.Parent = demoFolder

    -- Weld barrel to turret head
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
    angleLabel.Text = "Angle: 0°"
    angleLabel.Parent = billboardGui

    ---------------------------------------------------------------------------
    -- CREATE SWIVEL COMPONENT
    ---------------------------------------------------------------------------

    local swivel = Swivel:new({
        id = "Demo_Swivel",
        model = turretHead,
    })
    swivel.Sys.onInit(swivel)

    -- Configure swivel
    swivel.In.onConfigure(swivel, {
        axis = "Y",
        mode = "continuous",
        speed = 60,  -- Degrees per second
        minAngle = -90,
        maxAngle = 90,
    })

    -- Wire output to update display
    swivel.Out = {
        Fire = function(self, signal, data)
            if signal == "rotated" then
                angleLabel.Text = string.format("Angle: %.1f°", data.angle)
            elseif signal == "limitReached" then
                angleLabel.Text = string.format("LIMIT: %s", data.limit:upper())
                -- Flash the barrel
                local originalColor = barrel.BrickColor
                barrel.BrickColor = BrickColor.new("Bright yellow")
                task.delay(0.2, function()
                    if barrel.Parent then
                        barrel.BrickColor = originalColor
                    end
                end)
            end
        end,
    }

    -- Update barrel position with turret head
    local connection = game:GetService("RunService").Heartbeat:Connect(function()
        if turretHead.Parent and barrel.Parent then
            barrel.CFrame = turretHead.CFrame * CFrame.new(0, 0, -2)
        end
    end)

    ---------------------------------------------------------------------------
    -- DEMO CONTROLS
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.rotateForward()
        swivel.In.onRotate(swivel, { direction = "forward" })
    end

    function controls.rotateReverse()
        swivel.In.onRotate(swivel, { direction = "reverse" })
    end

    function controls.stop()
        swivel.In.onStop(swivel)
    end

    function controls.setAngle(degrees)
        swivel.In.onSetAngle(swivel, { degrees = degrees })
    end

    function controls.setMode(mode)
        swivel.In.onConfigure(swivel, { mode = mode })
    end

    function controls.setSpeed(speed)
        swivel.In.onConfigure(swivel, { speed = speed })
    end

    function controls.setLimits(min, max)
        swivel.In.onConfigure(swivel, { minAngle = min, maxAngle = max })
    end

    function controls.cleanup()
        connection:Disconnect()
        swivel.Sys.onStop(swivel)
        demoFolder:Destroy()
    end

    function controls.getSwivel()
        return swivel
    end

    ---------------------------------------------------------------------------
    -- AUTO-DEMO (optional)
    ---------------------------------------------------------------------------

    if config.autoDemo then
        task.spawn(function()
            -- Sweep back and forth
            while demoFolder.Parent do
                controls.rotateForward()
                task.wait(3)
                controls.rotateReverse()
                task.wait(3)
            end
        end)
    end

    print("Swivel Demo running. Controls:")
    print("  demo.rotateForward()  - Start rotating forward")
    print("  demo.rotateReverse()  - Start rotating reverse")
    print("  demo.stop()           - Stop rotation")
    print("  demo.setAngle(45)     - Set to specific angle")
    print("  demo.cleanup()        - Remove demo")

    return controls
end

return Demo
