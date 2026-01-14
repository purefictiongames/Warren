--[[
    LibPureFiction Framework v2
    Turret System Demo - Proper Signal-Based Architecture

    Uses Out:Fire / In signal pattern, not direct handler calls.

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar:

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    local demo = Demos.Turret.run()
    demo.cleanup()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

local Node = require(ReplicatedStorage.Lib.Node)
local Swivel = Lib.Components.Swivel

local Demo = {}

--------------------------------------------------------------------------------
-- TURRET CONTROLLER NODE
-- Fires signals to control swivels, receives signals back
--------------------------------------------------------------------------------

local TurretController = Node.extend({
    name = "TurretController",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._targetPosition = nil
            self._turretOrigin = Vector3.new(0, 0, 0)
        end,
    },

    In = {
        -- Receive target updates from Targeter
        onTargetUpdate = function(self, data)
            self._targetPosition = data.position
        end,

        onTargetLost = function(self)
            self._targetPosition = nil
        end,

        -- Receive rotation complete signals from Swivels
        onYawRotated = function(self, data)
            -- Swivel finished rotating, could trigger next action
        end,

        onPitchRotated = function(self, data)
            -- Swivel finished rotating
        end,
    },

    Out = {
        setYawAngle = {},   -- -> Swivel.In.onSetAngle
        setPitchAngle = {}, -- -> Swivel.In.onSetAngle
    },

    -- Calculate aim angles from target position
    calculateAimAngles = function(self, targetPosition)
        local toTarget = targetPosition - self._turretOrigin
        local yawAngle = math.deg(math.atan2(toTarget.X, -toTarget.Z))
        local horizontalDist = math.sqrt(toTarget.X^2 + toTarget.Z^2)
        local pitchAngle = math.deg(math.atan2(toTarget.Y, horizontalDist))
        return yawAngle, pitchAngle
    end,

    -- Update turret aim (called each frame when tracking)
    updateAim = function(self, targetPosition)
        local yaw, pitch = self:calculateAimAngles(targetPosition)

        -- Fire signals to swivels
        self.Out:Fire("setYawAngle", { degrees = yaw })
        self.Out:Fire("setPitchAngle", { degrees = pitch })
    end,
})

--------------------------------------------------------------------------------
-- DEMO
--------------------------------------------------------------------------------

function Demo.run(config)
    config = config or {}
    local position = config.position or Vector3.new(0, 5, 0)

    ---------------------------------------------------------------------------
    -- CLEANUP EXISTING DEMO
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("Turret_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end

    ---------------------------------------------------------------------------
    -- CREATE VISUAL SETUP
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

    -- Yaw base (rotates left/right)
    local yawBase = Instance.new("Part")
    yawBase.Name = "YawBase"
    yawBase.Size = Vector3.new(5, 2, 5)
    yawBase.CFrame = CFrame.new(position)
    yawBase.Anchored = true
    yawBase.BrickColor = BrickColor.new("Medium stone grey")
    yawBase.Material = Enum.Material.Metal
    yawBase.Parent = demoFolder

    -- Pitch arm (rotates up/down)
    local pitchArm = Instance.new("Part")
    pitchArm.Name = "PitchArm"
    pitchArm.Size = Vector3.new(1.5, 1.5, 4)
    pitchArm.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
    pitchArm.Anchored = true
    pitchArm.BrickColor = BrickColor.new("Bright blue")
    pitchArm.Material = Enum.Material.SmoothPlastic
    pitchArm.Parent = demoFolder

    -- Muzzle (shows where turret is pointing)
    local muzzle = Instance.new("Part")
    muzzle.Name = "Muzzle"
    muzzle.Size = Vector3.new(0.6, 0.6, 1)
    muzzle.CFrame = pitchArm.CFrame * CFrame.new(0, 0, -2.5)
    muzzle.Anchored = true
    muzzle.BrickColor = BrickColor.new("Bright red")
    muzzle.Material = Enum.Material.Neon
    muzzle.Parent = demoFolder

    -- Status display
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 300, 0, 100)
    billboard.StudsOffset = Vector3.new(0, 6, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = yawBase

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundTransparency = 0.2
    statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    statusLabel.TextColor3 = Color3.new(0, 1, 0)
    statusLabel.TextScaled = true
    statusLabel.Font = Enum.Font.Code
    statusLabel.Text = "SIGNAL-BASED TRACKING"
    statusLabel.Parent = billboard

    -- Target
    local target = Instance.new("Part")
    target.Name = "Target"
    target.Size = Vector3.new(4, 4, 4)
    target.Position = position + Vector3.new(0, 5, -30)
    target.Anchored = true
    target.BrickColor = BrickColor.new("Bright red")
    target.Material = Enum.Material.Neon
    target.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- CREATE NODES
    ---------------------------------------------------------------------------

    -- Yaw Swivel (controls yawBase rotation)
    local yawSwivel = Swivel:new({ id = "Turret_YawSwivel", model = yawBase })
    yawSwivel.Sys.onInit(yawSwivel)
    yawSwivel.In.onConfigure(yawSwivel, {
        axis = "Y",
        mode = "stepped",  -- Direct angle setting
        minAngle = -180,
        maxAngle = 180,
    })

    -- Pitch Swivel (controls pitchArm rotation)
    local pitchSwivel = Swivel:new({ id = "Turret_PitchSwivel", model = pitchArm })
    pitchSwivel.Sys.onInit(pitchSwivel)
    pitchSwivel.In.onConfigure(pitchSwivel, {
        axis = "X",
        mode = "stepped",
        minAngle = -45,
        maxAngle = 60,
    })

    -- Controller
    local controller = TurretController:new({ id = "Turret_Controller" })
    controller.Sys.onInit(controller)
    controller._turretOrigin = position + Vector3.new(0, 1.5, 0)

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS (manual wiring for demo - in production IPC does this)
    ---------------------------------------------------------------------------

    -- Controller.Out.setYawAngle -> YawSwivel.In.onSetAngle
    controller.Out = {
        Fire = function(self, signal, data)
            if signal == "setYawAngle" then
                yawSwivel.In.onSetAngle(yawSwivel, data)
            elseif signal == "setPitchAngle" then
                pitchSwivel.In.onSetAngle(pitchSwivel, data)
            end
        end,
    }

    -- Swivel.Out.rotated -> update geometry
    local function updateGeometry()
        -- After swivels update, position the dependent parts
        local yawCFrame = yawBase.CFrame
        local pitchCFrame = pitchArm.CFrame
        muzzle.CFrame = pitchCFrame * CFrame.new(0, 0, -2.5)
    end

    yawSwivel.Out = {
        Fire = function(self, signal, data)
            if signal == "rotated" then
                updateGeometry()
            end
        end,
    }

    pitchSwivel.Out = {
        Fire = function(self, signal, data)
            if signal == "rotated" then
                updateGeometry()
            end
        end,
    }

    ---------------------------------------------------------------------------
    -- MAIN LOOP - Just moves target and fires signals
    ---------------------------------------------------------------------------

    local state = { running = true }
    local targetTime = 0

    local mainConnection = RunService.Heartbeat:Connect(function(dt)
        if not demoFolder.Parent or not state.running then return end

        -- Move target
        targetTime = targetTime + dt * 0.5
        local targetPos = position + Vector3.new(
            math.sin(targetTime) * 25,
            5 + math.sin(targetTime * 1.3) * 8,
            -30 + math.cos(targetTime * 0.7) * 15
        )
        target.Position = targetPos

        -- Controller calculates aim and fires signals to swivels
        controller:updateAim(targetPos)

        -- Update status
        local yaw, pitch = controller:calculateAimAngles(targetPos)
        statusLabel.Text = string.format(
            "SIGNAL-BASED TRACKING\n" ..
            "Yaw: %.1f° | Pitch: %.1f°\n" ..
            "Target: (%.0f, %.0f, %.0f)",
            yaw, pitch,
            targetPos.X, targetPos.Y, targetPos.Z
        )
    end)

    ---------------------------------------------------------------------------
    -- CONTROLS
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.cleanup()
        state.running = false
        mainConnection:Disconnect()
        yawSwivel.Sys.onStop(yawSwivel)
        pitchSwivel.Sys.onStop(pitchSwivel)
        demoFolder:Destroy()
        print("Demo cleaned up")
    end

    print("============================================")
    print("  SIGNAL-BASED TURRET TRACKING")
    print("============================================")
    print("")
    print("Controller fires signals -> Swivels receive and rotate")
    print("Proper Out:Fire / In pattern")
    print("")
    print("To stop: demo.cleanup()")
    print("")

    return controls
end

return Demo
