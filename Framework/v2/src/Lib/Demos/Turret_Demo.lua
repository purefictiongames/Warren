--[[
    LibPureFiction Framework v2
    Turret System Demo - Fully Physics-Based with HingeConstraint Servos

    Demonstrates proper turret construction using Roblox physics:
    - basePlatform: Anchored (fixed to world)
    - yawBase: HingeConstraint servo on Y axis (left/right)
    - pitchArm: HingeConstraint servo on X axis (up/down)
    - muzzle: Welded to pitchArm

    All motion is physics-driven via servo motors - no direct CFrame manipulation.
    This ensures smooth interpolated movement.

    Uses Out:Fire / In signal pattern for control signals.

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
local Debris = game:GetService("Debris")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

-- Use framework's InputCapture system for exclusive input focus
local InputCapture = Lib.System.InputCapture

local Node = require(ReplicatedStorage.Lib.Node)
-- Note: Not using Swivel component - using HingeConstraint servos for smooth physics-based motion

local Demo = {}

--------------------------------------------------------------------------------
-- TURRET MANUAL CONTROLLER NODE
-- Declarative control mapping for manual turret control
--------------------------------------------------------------------------------

local TurretManualController = Node.extend({
    name = "TurretManualController",
    domain = "client",

    -- Declarative control mapping
    Controls = {
        -- Directional aiming (digital keys + analog stick)
        aimUp = {
            keys = { Enum.KeyCode.Up },
            buttons = { Enum.KeyCode.DPadUp },
            axis = { stick = "Thumbstick1", direction = "Y+", deadzone = 0.2 },
        },
        aimDown = {
            keys = { Enum.KeyCode.Down },
            buttons = { Enum.KeyCode.DPadDown },
            axis = { stick = "Thumbstick1", direction = "Y-", deadzone = 0.2 },
        },
        aimLeft = {
            keys = { Enum.KeyCode.Left },
            buttons = { Enum.KeyCode.DPadLeft },
            axis = { stick = "Thumbstick1", direction = "X-", deadzone = 0.2 },
        },
        aimRight = {
            keys = { Enum.KeyCode.Right },
            buttons = { Enum.KeyCode.DPadRight },
            axis = { stick = "Thumbstick1", direction = "X+", deadzone = 0.2 },
        },

        -- Fire action (instant trigger)
        fire = {
            keys = { Enum.KeyCode.Space },
            buttons = { Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR2 },
        },

        -- Exit action (hold-to-trigger)
        exit = {
            keys = { Enum.KeyCode.E },
            buttons = { Enum.KeyCode.ButtonY },
            holdDuration = 1.5,
        },
    },

    Sys = {
        onInit = function(self)
            self._keysHeld = {
                up = false,
                down = false,
                left = false,
                right = false,
            }
            self._exitProgress = 0
            self._onFire = nil       -- Callback for firing
            self._onExit = nil       -- Callback for exiting manual mode
        end,
    },

    In = {
        onActionBegan = function(self, action)
            if action == "aimUp" then
                self._keysHeld.up = true
            elseif action == "aimDown" then
                self._keysHeld.down = true
            elseif action == "aimLeft" then
                self._keysHeld.left = true
            elseif action == "aimRight" then
                self._keysHeld.right = true
            elseif action == "fire" then
                if self._onFire then
                    self._onFire()
                end
            end
        end,

        onActionEnded = function(self, action)
            if action == "aimUp" then
                self._keysHeld.up = false
            elseif action == "aimDown" then
                self._keysHeld.down = false
            elseif action == "aimLeft" then
                self._keysHeld.left = false
            elseif action == "aimRight" then
                self._keysHeld.right = false
            elseif action == "exit" then
                -- Reset exit progress if released early
                self._exitProgress = 0
            end
        end,

        onActionHeld = function(self, action, progress)
            if action == "exit" then
                self._exitProgress = progress
            end
        end,

        onActionTriggered = function(self, action)
            if action == "exit" then
                if self._onExit then
                    self._onExit()
                end
            end
        end,

        onControlReleased = function(self)
            -- Reset all state
            self._keysHeld = {
                up = false,
                down = false,
                left = false,
                right = false,
            }
            self._exitProgress = 0
        end,
    },

    -- Public methods
    getKeysHeld = function(self)
        return self._keysHeld
    end,

    getExitProgress = function(self)
        return self._exitProgress
    end,

    setCallbacks = function(self, onFire, onExit)
        self._onFire = onFire
        self._onExit = onExit
    end,
})

--------------------------------------------------------------------------------
-- TRACER PROJECTILE CREATION
--------------------------------------------------------------------------------

local function createTracerTemplate()
    local templateFolder = ReplicatedStorage:FindFirstChild("Templates")
    if not templateFolder then
        templateFolder = Instance.new("Folder")
        templateFolder.Name = "Templates"
        templateFolder.Parent = ReplicatedStorage
    end

    -- Remove old template if exists
    local existing = templateFolder:FindFirstChild("TurretTracer")
    if existing then
        existing:Destroy()
    end

    -- Create tracer round
    local tracer = Instance.new("Part")
    tracer.Name = "TurretTracer"
    tracer.Size = Vector3.new(0.3, 0.3, 1.5)
    tracer.Color = Color3.new(1, 0.8, 0)
    tracer.Material = Enum.Material.Neon
    tracer.Anchored = false
    tracer.CanCollide = false
    tracer.CastShadow = false
    tracer.Parent = templateFolder

    -- Glow
    local light = Instance.new("PointLight")
    light.Color = Color3.new(1, 0.6, 0)
    light.Brightness = 2
    light.Range = 8
    light.Parent = tracer

    -- Trail attachments
    local att0 = Instance.new("Attachment")
    att0.Name = "TrailBack"
    att0.Position = Vector3.new(0, 0, 0.75)
    att0.Parent = tracer

    local att1 = Instance.new("Attachment")
    att1.Name = "TrailFront"
    att1.Position = Vector3.new(0, 0, -0.75)
    att1.Parent = tracer

    -- Trail effect
    local trail = Instance.new("Trail")
    trail.Attachment0 = att1
    trail.Attachment1 = att0
    trail.Lifetime = 0.5
    trail.MinLength = 0.1
    trail.FaceCamera = true
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0.2),
    })
    trail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 0.8)),
        ColorSequenceKeypoint.new(0.3, Color3.new(1, 0.5, 0)),
        ColorSequenceKeypoint.new(1, Color3.new(1, 0.2, 0)),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.LightEmission = 1
    trail.Parent = tracer

    return tracer
end

local function fireTracer(muzzle, projectilesFolder, speed)
    speed = speed or 200

    -- Clone template
    local templateFolder = ReplicatedStorage:FindFirstChild("Templates")
    local template = templateFolder and templateFolder:FindFirstChild("TurretTracer")
    if not template then
        template = createTracerTemplate()
    end

    local projectile = template:Clone()

    -- Position at muzzle, oriented in firing direction
    local muzzlePos = muzzle.Position
    local muzzleDir = muzzle.CFrame.LookVector
    projectile.CFrame = CFrame.new(muzzlePos, muzzlePos + muzzleDir)

    -- Parent before setting physics
    projectile.Parent = projectilesFolder

    -- Set velocity in firing direction
    projectile.AssemblyLinearVelocity = muzzleDir * speed

    -- Counteract gravity with VectorForce
    local attachment = Instance.new("Attachment")
    attachment.Parent = projectile

    local antiGravity = Instance.new("VectorForce")
    antiGravity.Name = "AntiGravity"
    antiGravity.Attachment0 = attachment
    antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
    antiGravity.ApplyAtCenterOfMass = true
    -- Force = mass * gravity (workspace.Gravity default is 196.2)
    antiGravity.Force = Vector3.new(0, projectile:GetMass() * workspace.Gravity, 0)
    antiGravity.Parent = projectile

    -- Auto-cleanup after 3 seconds
    Debris:AddItem(projectile, 3)

    return projectile
end

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

        -- Yaw: angle around Y axis
        -- Roblox CFrame.Angles(0, yaw, 0): positive = counterclockwise from above
        -- atan2(X, -Z) gives positive for +X targets, but we need clockwise rotation
        -- So negate: positive X target -> negative yaw (clockwise)
        local yawAngle = math.deg(math.atan2(-toTarget.X, -toTarget.Z))

        -- Pitch: angle from horizontal to target
        -- Positive = target is above horizontal
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

    -- Base platform - ANCHORED (fixed to world)
    local basePlatform = Instance.new("Part")
    basePlatform.Name = "BasePlatform"
    basePlatform.Size = Vector3.new(8, 1, 8)
    basePlatform.Position = position - Vector3.new(0, 2, 0)
    basePlatform.Anchored = true
    basePlatform.BrickColor = BrickColor.new("Really black")
    basePlatform.Material = Enum.Material.DiamondPlate
    basePlatform.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- PROXIMITY PROMPT: Take/Release manual control
    ---------------------------------------------------------------------------

    local controlPrompt = Instance.new("ProximityPrompt")
    controlPrompt.ObjectText = "Turret"
    controlPrompt.ActionText = "Take Control"
    controlPrompt.HoldDuration = 1.5  -- Hold for 1.5 seconds to activate
    controlPrompt.MaxActivationDistance = 20  -- Larger range for turret POV
    controlPrompt.RequiresLineOfSight = false
    controlPrompt.KeyboardKeyCode = Enum.KeyCode.E
    controlPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY  -- Y button on controller
    controlPrompt.Parent = basePlatform

    -- Yaw base (rotates left/right) - UNANCHORED, connected via HingeConstraint
    local yawBase = Instance.new("Part")
    yawBase.Name = "YawBase"
    yawBase.Size = Vector3.new(5, 2, 5)
    yawBase.CFrame = CFrame.new(position)
    yawBase.Anchored = false  -- Physics-driven
    yawBase.CanCollide = false
    yawBase.BrickColor = BrickColor.new("Medium stone grey")
    yawBase.Material = Enum.Material.Metal
    yawBase.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- YAW HINGE: Connects yawBase to basePlatform
    -- Rotates around Y axis (vertical) for left/right aiming
    ---------------------------------------------------------------------------

    -- Attachment on basePlatform (top center, yaw axis = Y)
    local baseAttachment = Instance.new("Attachment")
    baseAttachment.Name = "YawHingeAttachment"
    baseAttachment.Position = Vector3.new(0, 0.5, 0)  -- Top of platform
    -- Rotate attachment so PrimaryAxis (X) points UP (Y) for yaw rotation
    baseAttachment.CFrame = CFrame.Angles(0, 0, math.rad(90))
    baseAttachment.Parent = basePlatform

    -- Attachment on yawBase (bottom center, same orientation)
    local yawBaseAttachment = Instance.new("Attachment")
    yawBaseAttachment.Name = "YawHingeAttachment"
    yawBaseAttachment.Position = Vector3.new(0, -1, 0)  -- Bottom of yawBase
    yawBaseAttachment.CFrame = CFrame.Angles(0, 0, math.rad(90))
    yawBaseAttachment.Parent = yawBase

    -- HingeConstraint for yaw rotation
    local yawHinge = Instance.new("HingeConstraint")
    yawHinge.Name = "YawHinge"
    yawHinge.Attachment0 = baseAttachment
    yawHinge.Attachment1 = yawBaseAttachment
    yawHinge.ActuatorType = Enum.ActuatorType.Servo
    yawHinge.AngularSpeed = math.rad(180)  -- Degrees per second
    yawHinge.ServoMaxTorque = 100000
    yawHinge.TargetAngle = 0
    yawHinge.LimitsEnabled = false  -- Full 360° rotation allowed
    yawHinge.Parent = basePlatform

    -- Pitch arm (rotates up/down) - UNANCHORED, connected via HingeConstraint
    local pitchArm = Instance.new("Part")
    pitchArm.Name = "PitchArm"
    pitchArm.Size = Vector3.new(1.5, 1.5, 4)
    pitchArm.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
    pitchArm.Anchored = false
    pitchArm.CanCollide = false
    pitchArm.BrickColor = BrickColor.new("Bright blue")
    pitchArm.Material = Enum.Material.SmoothPlastic
    pitchArm.Parent = demoFolder

    ---------------------------------------------------------------------------
    -- PITCH HINGE: Connects pitchArm to yawBase
    -- Rotates around X axis (horizontal) for up/down aiming
    ---------------------------------------------------------------------------

    -- Attachment on yawBase (top center, pitch axis = X)
    local yawTopAttachment = Instance.new("Attachment")
    yawTopAttachment.Name = "PitchHingeAttachment"
    yawTopAttachment.Position = Vector3.new(0, 1, 0)  -- Top of yawBase
    -- Default orientation: PrimaryAxis = X (pitch axis)
    yawTopAttachment.Parent = yawBase

    -- Attachment on pitchArm (center)
    local pitchAttachment = Instance.new("Attachment")
    pitchAttachment.Name = "PitchHingeAttachment"
    pitchAttachment.Position = Vector3.new(0, 0, 0)
    pitchAttachment.Parent = pitchArm

    -- HingeConstraint for pitch rotation
    local pitchHinge = Instance.new("HingeConstraint")
    pitchHinge.Name = "PitchHinge"
    pitchHinge.Attachment0 = yawTopAttachment
    pitchHinge.Attachment1 = pitchAttachment
    pitchHinge.ActuatorType = Enum.ActuatorType.Servo
    pitchHinge.AngularSpeed = math.rad(180)
    pitchHinge.ServoMaxTorque = 100000
    pitchHinge.TargetAngle = 0
    pitchHinge.LimitsEnabled = true
    pitchHinge.LowerAngle = -45  -- Look down
    pitchHinge.UpperAngle = 60   -- Look up
    pitchHinge.Parent = yawBase

    -- Muzzle (shows where turret is pointing) - welded to pitchArm
    local muzzle = Instance.new("Part")
    muzzle.Name = "Muzzle"
    muzzle.Size = Vector3.new(0.6, 0.6, 1)
    muzzle.CFrame = pitchArm.CFrame * CFrame.new(0, 0, -2.5)
    muzzle.Anchored = false
    muzzle.CanCollide = false
    muzzle.BrickColor = BrickColor.new("Bright red")
    muzzle.Material = Enum.Material.Neon
    muzzle.Parent = demoFolder

    -- Weld muzzle to pitchArm so it follows
    local muzzleWeld = Instance.new("WeldConstraint")
    muzzleWeld.Name = "MuzzleWeld"
    muzzleWeld.Part0 = pitchArm
    muzzleWeld.Part1 = muzzle
    muzzleWeld.Parent = pitchArm

    ---------------------------------------------------------------------------
    -- TRACKING BEAM: Shows where turret is actually pointing
    ---------------------------------------------------------------------------

    local beamAttachment0 = Instance.new("Attachment")
    beamAttachment0.Name = "BeamStart"
    beamAttachment0.Position = Vector3.new(0, 0, -0.5)  -- Front of muzzle
    beamAttachment0.Parent = muzzle

    local beamAttachment1 = Instance.new("Attachment")
    beamAttachment1.Name = "BeamEnd"
    beamAttachment1.Parent = demoFolder  -- Will be repositioned each frame

    local trackingBeam = Instance.new("Beam")
    trackingBeam.Name = "TrackingBeam"
    trackingBeam.Attachment0 = beamAttachment0
    trackingBeam.Attachment1 = beamAttachment1
    trackingBeam.Color = ColorSequence.new(Color3.new(0, 1, 0))  -- Green
    trackingBeam.Transparency = NumberSequence.new(0.3)
    trackingBeam.Width0 = 0.3
    trackingBeam.Width1 = 0.1
    trackingBeam.FaceCamera = true
    trackingBeam.Parent = muzzle

    -- Beam endpoint part (invisible, just holds attachment)
    local beamEndpoint = Instance.new("Part")
    beamEndpoint.Name = "BeamEndpoint"
    beamEndpoint.Size = Vector3.new(0.5, 0.5, 0.5)
    beamEndpoint.Transparency = 1
    beamEndpoint.Anchored = true
    beamEndpoint.CanCollide = false
    beamEndpoint.Parent = demoFolder
    beamAttachment1.Parent = beamEndpoint

    -- Status display (ScreenGui at bottom-right)
    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TurretDemoStatus"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    -- Parent to PlayerGui if available, otherwise to CoreGui or demoFolder
    if localPlayer then
        screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
    else
        screenGui.Parent = game:GetService("CoreGui")
    end

    local statusFrame = Instance.new("Frame")
    statusFrame.Name = "StatusFrame"
    statusFrame.Size = UDim2.new(0, 250, 0, 100)
    statusFrame.Position = UDim2.new(1, -260, 1, -110)  -- Bottom-right with margin
    statusFrame.BackgroundTransparency = 0.2
    statusFrame.BackgroundColor3 = Color3.new(0, 0, 0)
    statusFrame.BorderSizePixel = 0
    statusFrame.Parent = screenGui

    -- Rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = statusFrame

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -16, 1, -8)
    statusLabel.Position = UDim2.new(0, 8, 0, 4)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.new(0, 1, 0)
    statusLabel.TextSize = 14
    statusLabel.Font = Enum.Font.Code
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.Text = "TURRET DEMO"
    statusLabel.Parent = statusFrame

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
    -- PROJECTILES FOLDER
    ---------------------------------------------------------------------------

    local projectilesFolder = Instance.new("Folder")
    projectilesFolder.Name = "Projectiles"
    projectilesFolder.Parent = demoFolder

    -- Create tracer template
    createTracerTemplate()

    ---------------------------------------------------------------------------
    -- CREATE CONTROLLER NODE
    ---------------------------------------------------------------------------

    local controller = TurretController:new({ id = "Turret_Controller" })
    controller.Sys.onInit(controller)
    controller._turretOrigin = position + Vector3.new(0, 1.5, 0)

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS -> HingeConstraint servos
    -- Both yaw and pitch use physics-based servo motors for smooth motion
    ---------------------------------------------------------------------------

    controller.Out = {
        Fire = function(self, signal, data)
            if signal == "setYawAngle" then
                -- Yaw hinge: attachment rotated so +angle = CCW from above
                -- Our calculation gives negative for right (+X), positive for left (-X)
                -- Hinge with rotated attachment: positive = CCW from above
                -- So we can use the angle directly
                yawHinge.TargetAngle = data.degrees
            elseif signal == "setPitchAngle" then
                -- Pitch hinge: +angle = nose UP (tested empirically)
                pitchHinge.TargetAngle = data.degrees
            end
        end,
    }

    ---------------------------------------------------------------------------
    -- CONTROL STATE
    ---------------------------------------------------------------------------

    local state = {
        running = true,
        mode = "auto",  -- "auto" or "manual"
        manualYaw = 0,
        manualPitch = 0,
    }

    local targetTime = 0
    local lastFireTime = 0
    local fireInterval = 0.15
    local projectileSpeed = 150

    -- InputCapture claim (created when taking control)
    local inputClaim = nil

    -- Camera state (saved when entering manual mode)
    local savedCameraState = nil
    local camera = workspace.CurrentCamera

    ---------------------------------------------------------------------------
    -- MANUAL CONTROL: Using declarative TurretManualController
    ---------------------------------------------------------------------------

    -- Create manual controller node
    local manualController = TurretManualController:new({ id = "Turret_ManualController" })
    manualController.Sys.onInit(manualController)

    -- Forward declaration for stopManualControl
    local stopManualControl

    -- Set up controller callbacks
    manualController:setCallbacks(
        function()  -- onFire
            fireTracer(muzzle, projectilesFolder, 200)
        end,
        function()  -- onExit (called when hold duration reached)
            stopManualControl()
        end
    )

    local function startManualControl()
        state.mode = "manual"
        state.manualYaw = 0
        state.manualPitch = 0

        -- Update prompt
        controlPrompt.ActionText = "Release Control"
        trackingBeam.Color = ColorSequence.new(Color3.new(1, 0, 0))  -- Red beam

        -- Save camera state and switch to turret POV
        savedCameraState = {
            cameraType = camera.CameraType,
            cameraSubject = camera.CameraSubject,
            cFrame = camera.CFrame,
        }
        camera.CameraType = Enum.CameraType.Scriptable

        -- Claim input focus using declarative control mapping
        -- InputCapture reads Controls from the node and routes actions to In handlers
        inputClaim = InputCapture.claimForNode(manualController, { disableCharacter = true })

        print("[Turret] MANUAL MODE - Arrows/D-pad/Stick to aim, Space/A to fire, hold E/Y to release")
    end

    stopManualControl = function()
        -- Prevent re-entry if already in auto mode
        if state.mode == "auto" then return end

        state.mode = "auto"

        -- Update prompt
        controlPrompt.ActionText = "Take Control"
        trackingBeam.Color = ColorSequence.new(Color3.new(0, 1, 0))  -- Green beam

        -- Release input claim
        if inputClaim then
            local claim = inputClaim
            inputClaim = nil
            claim:release()
        end

        -- Restore camera
        if savedCameraState then
            camera.CameraType = savedCameraState.cameraType
            camera.CameraSubject = savedCameraState.cameraSubject
            savedCameraState = nil
        end

        print("[Turret] AUTO MODE - Tracking target")
    end

    -- ProximityPrompt toggle
    controlPrompt.Triggered:Connect(function(player)
        print("[Turret] ProximityPrompt triggered, current mode:", state.mode)
        if state.mode == "auto" then
            startManualControl()
        else
            stopManualControl()
        end
    end)

    -- Debug: show when prompt becomes visible/hidden
    controlPrompt.PromptShown:Connect(function()
        print("[Turret] ProximityPrompt shown")
    end)
    controlPrompt.PromptHidden:Connect(function()
        print("[Turret] ProximityPrompt hidden")
    end)

    ---------------------------------------------------------------------------
    -- MAIN LOOP
    ---------------------------------------------------------------------------

    local mainConnection = RunService.Heartbeat:Connect(function(dt)
        if not demoFolder.Parent or not state.running then return end

        -- Update tracking beam
        local muzzlePos = muzzle.Position
        local muzzleDir = muzzle.CFrame.LookVector
        beamEndpoint.Position = muzzlePos + muzzleDir * 100

        if state.mode == "auto" then
            -- AUTO MODE: Track moving target
            targetTime = targetTime + dt * 0.5
            local targetPos = position + Vector3.new(
                math.sin(targetTime) * 25,
                5 + math.sin(targetTime * 1.3) * 8,
                -30 + math.cos(targetTime * 0.7) * 15
            )
            target.Position = targetPos
            target.Transparency = 0

            -- Auto aim
            controller:updateAim(targetPos)

            -- Auto fire
            local currentTime = tick()
            if currentTime - lastFireTime >= fireInterval then
                lastFireTime = currentTime
                fireTracer(muzzle, projectilesFolder, projectileSpeed)
            end

            -- Update status
            local yaw, pitch = controller:calculateAimAngles(targetPos)
            local projectileCount = #projectilesFolder:GetChildren()
            statusLabel.Text = string.format(
                "TURRET DEMO - AUTO\n" ..
                "Yaw: %6.1f°  Pitch: %5.1f°\n" ..
                "Hold E/Y to take control",
                yaw, pitch
            )
            statusLabel.TextColor3 = Color3.new(0, 1, 0)
        else
            -- MANUAL MODE: Using declarative control mapping via TurretManualController
            target.Transparency = 1  -- Hide target

            -- Get keys held from controller
            local keysHeld = manualController:getKeysHeld()

            -- Apply held keys to adjust angles
            local turnSpeed = 90 * dt  -- 90 degrees per second
            if keysHeld.left then state.manualYaw = state.manualYaw + turnSpeed end
            if keysHeld.right then state.manualYaw = state.manualYaw - turnSpeed end
            if keysHeld.up then state.manualPitch = state.manualPitch + turnSpeed end
            if keysHeld.down then state.manualPitch = state.manualPitch - turnSpeed end

            -- Clamp to limits
            state.manualYaw = math.clamp(state.manualYaw, -180, 180)
            state.manualPitch = math.clamp(state.manualPitch, -45, 60)

            -- Apply manual angles to hinges
            yawHinge.TargetAngle = state.manualYaw
            pitchHinge.TargetAngle = state.manualPitch

            -- Update camera to turret POV
            local muzzleCF = muzzle.CFrame
            local cameraOffset = muzzleCF * CFrame.new(0, 0.5, 2)
            camera.CFrame = CFrame.new(cameraOffset.Position, cameraOffset.Position + muzzleCF.LookVector)

            -- Update status (with exit progress from controller)
            local exitProgress = ""
            local progress = manualController:getExitProgress()
            if progress > 0 then
                local pct = math.floor(progress * 100)
                exitProgress = string.format("\nReleasing... %d%%", pct)
            end
            statusLabel.Text = string.format(
                "TURRET DEMO - MANUAL\n" ..
                "Yaw: %6.1f°  Pitch: %5.1f°\n" ..
                "Hold E/Y to release%s",
                state.manualYaw, state.manualPitch, exitProgress
            )
            statusLabel.TextColor3 = Color3.new(1, 0.5, 0)
        end
    end)

    ---------------------------------------------------------------------------
    -- CONTROLS
    ---------------------------------------------------------------------------

    local controls = {}

    function controls.cleanup()
        state.running = false
        mainConnection:Disconnect()
        -- Stop manual control if active
        if state.mode == "manual" then
            stopManualControl()
        end
        -- Cleanup UI
        if screenGui then
            screenGui:Destroy()
        end
        demoFolder:Destroy()
        print("Demo cleaned up")
    end

    function controls.setMode(mode)
        if mode == "manual" and state.mode == "auto" then
            startManualControl()
        elseif mode == "auto" and state.mode == "manual" then
            stopManualControl()
        end
    end

    print("============================================")
    print("  TURRET DEMO - AUTO/MANUAL")
    print("============================================")
    print("")
    print("AUTO MODE (default):")
    print("  - Turret tracks red target automatically")
    print("  - Green beam")
    print("")
    print("MANUAL MODE:")
    print("  - Walk to turret and HOLD E/Y (1.5s)")
    print("  - Arrows / D-pad / Left stick to aim")
    print("  - Space / A / RT to fire")
    print("  - Camera snaps to turret POV")
    print("  - HOLD E/Y (1.5s) to release")
    print("  - Red beam")
    print("")
    print("demo.cleanup() to stop")
    print("")

    return controls
end

return Demo
