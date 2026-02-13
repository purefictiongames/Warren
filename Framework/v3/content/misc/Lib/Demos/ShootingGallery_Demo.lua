--[[
    LibPureFiction Framework v2
    Shooting Gallery Demo - Carnival-Style Target Shooting Game

    Demonstrates framework composability AND cross-domain IPC:
    - NodePool: Manages pool of PathFollower instances (server)
    - PathFollower: Moves targets along track (server)
    - AttributeSet: Target health + player score (server)
    - Cross-domain IPC: Client input → Server game logic

    ============================================================================
    ARCHITECTURE
    ============================================================================

    Server (GalleryManager node):
    - Game state (score, kills, round timer)
    - Target spawning and movement (NodePool + PathFollower)
    - Turret physics (HingeConstraints)
    - Damage calculation and hit detection
    - Projectile spawning

    Client (GalleryInput node):
    - Input handling (turret aiming, fire button)
    - Camera control
    - Sends commands to server via IPC cross-domain routing

    Both:
    - HUD reads from replicated Roblox Attributes on GameState part

    ============================================================================
    USAGE
    ============================================================================

    1. Run from SERVER command bar:
       ```lua
       local Demos = require(game.ReplicatedStorage.Lib.Demos)
       local demo = Demos.ShootingGallery.run()
       ```

    2. Join with a client and walk to the turret!

    3. Cleanup:
       ```lua
       demo.cleanup()
       ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local System = Lib.System
local Node = require(ReplicatedStorage.Lib.Node)
local AttributeSet = require(ReplicatedStorage.Lib.Internal.AttributeSet)
local Dropper = require(ReplicatedStorage.Lib.Components.Dropper)
local SpawnerCore = require(ReplicatedStorage.Lib.Internal.SpawnerCore)

local Demo = {}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local TRACK_LENGTH = 80
local ROUND_DURATION = 60
local POINTS_PER_KILL = 100
local POINTS_PER_HIT = 10
local DAMAGE_PER_HIT = 10

-- Target row configurations (3 independent circuits)
local TARGET_ROWS = {
    {
        name = "Row1_Low",
        height = 5,
        zOffset = -18,
        speed = 18,          -- Fast
        interval = 2.0,
        health = 20,         -- Easier to kill
        color = BrickColor.new("Bright orange"),
        size = Vector3.new(3, 3, 0.5),
    },
    {
        name = "Row2_Mid",
        height = 9,
        zOffset = -22,
        speed = 12,          -- Medium
        interval = 2.5,
        health = 30,         -- Standard
        color = BrickColor.new("Bright yellow"),
        size = Vector3.new(2.5, 3.5, 0.5),
    },
    {
        name = "Row3_High",
        height = 13,
        zOffset = -26,
        speed = 8,           -- Slow
        interval = 3.0,
        health = 40,         -- Tougher
        color = BrickColor.new("Bright red"),
        size = Vector3.new(2, 4, 0.5),
    },
}

--------------------------------------------------------------------------------
-- SERVER: GALLERY MANAGER NODE
--------------------------------------------------------------------------------

local GalleryManager = Node.extend({
    name = "GalleryManager",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._gameStats = nil
            self._activeTargets = {}       -- { [assetId] = { part, stats, healthFill, tween, rowConfig } }
            self._turretState = { yaw = 0, pitch = 10 }
            self._roundTimerTask = nil

            -- These will be set by demo setup
            self._muzzle = nil
            self._yawHinge = nil
            self._pitchHinge = nil
            self._projectilesFolder = nil
            self._targetsFolder = nil
            self._tracerTemplate = nil
            self._gameStatePart = nil
            self._galleryPosition = Vector3.new(0, 0, 0)
            self._rowConfigs = {}  -- { [rowName] = { height, zOffset, speed, health } }
        end,
    },

    In = {
        -- Client sends aim updates
        onAim = function(self, data)
            self._turretState.yaw = math.clamp(data.yaw or 0, -60, 60)
            self._turretState.pitch = math.clamp(data.pitch or 0, -20, 45)

            -- Apply to turret physics
            if self._yawHinge then
                self._yawHinge.TargetAngle = self._turretState.yaw
            end
            if self._pitchHinge then
                self._pitchHinge.TargetAngle = self._turretState.pitch
            end
        end,

        -- Client sends fire command
        onFire = function(self, data)
            if not self._muzzle or not self._projectilesFolder then return end

            -- Update stats
            local shots = self._gameStats:get("shots") + 1
            self._gameStats:setBase("shots", shots)
            self:_updateReplicatedStats()

            -- Spawn projectile (internal behavior, not external node control)
            self:_fireProjectile()
        end,

        -- Start round - fires signals to start Droppers
        onStartRound = function(self)
            if self._gameStats:get("roundActive") then return end

            self._gameStats:setBase("score", 0)
            self._gameStats:setBase("kills", 0)
            self._gameStats:setBase("hits", 0)
            self._gameStats:setBase("shots", 0)
            self._gameStats:setBase("timeRemaining", ROUND_DURATION)
            self._gameStats:setBase("roundActive", true)
            self:_updateReplicatedStats()

            -- Signal to start all Droppers (routed via wiring)
            self.Out:Fire("startDroppers", {})

            -- Start internal timer (not external node control)
            self._roundTimerTask = task.spawn(function()
                while self._gameStats:get("timeRemaining") > 0 and self._gameStats:get("roundActive") do
                    task.wait(1)
                    local remaining = self._gameStats:get("timeRemaining") - 1
                    self._gameStats:setBase("timeRemaining", remaining)
                    self:_updateReplicatedStats()
                end

                if self._gameStats:get("roundActive") then
                    -- Use In handler, not direct method
                    self.In.onStopRound(self)
                end
            end)

            self.Out:Fire("roundStarted", {})
            print("[Gallery] Round started!")
        end,

        -- Stop round - fires signals to stop Droppers
        onStopRound = function(self)
            self._gameStats:setBase("roundActive", false)
            self:_updateReplicatedStats()

            -- Signal to stop all Droppers
            self.Out:Fire("stopDroppers", {})

            if self._roundTimerTask then
                pcall(task.cancel, self._roundTimerTask)
                self._roundTimerTask = nil
            end

            -- Signal to despawn all remaining targets
            for assetId, _ in pairs(self._activeTargets) do
                self.Out:Fire("returnTarget", { assetId = assetId })
            end
            self._activeTargets = {}

            local score = self._gameStats:get("score")
            local kills = self._gameStats:get("kills")
            local shots = self._gameStats:get("shots")
            local hits = self._gameStats:get("hits")
            local accuracy = shots > 0 and (hits / shots * 100) or 0

            self.Out:Fire("roundEnded", {
                score = score,
                kills = kills,
                accuracy = accuracy,
            })

            print(string.format("\n=== ROUND OVER ===\nScore: %d | Kills: %d | Accuracy: %.0f%%\n", score, kills, accuracy))
        end,

        -- Received from Dropper when a target spawns
        onTargetSpawned = function(self, data)
            if not self._targetsFolder then return end

            local instance = data.instance
            local assetId = data.assetId
            local rowName = data.templateName  -- Template name indicates which row

            -- Get row config
            local rowConfig = self._rowConfigs[rowName]
            if not rowConfig then
                print("[Gallery] Unknown row:", rowName)
                return
            end

            -- Move to targets folder
            instance.Parent = self._targetsFolder

            -- Add health bar
            local billboard = Instance.new("BillboardGui")
            billboard.Size = UDim2.new(0, 50, 0, 8)
            billboard.StudsOffset = Vector3.new(0, instance.Size.Y / 2 + 0.5, 0)
            billboard.AlwaysOnTop = true
            billboard.Parent = instance

            local bgFrame = Instance.new("Frame")
            bgFrame.Size = UDim2.new(1, 0, 1, 0)
            bgFrame.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
            bgFrame.BorderSizePixel = 0
            bgFrame.Parent = billboard
            Instance.new("UICorner", bgFrame).CornerRadius = UDim.new(0, 2)

            local healthFill = Instance.new("Frame")
            healthFill.Name = "Fill"
            healthFill.Size = UDim2.new(1, 0, 1, 0)
            healthFill.BackgroundColor3 = Color3.new(0, 1, 0)
            healthFill.BorderSizePixel = 0
            healthFill.Parent = bgFrame
            Instance.new("UICorner", healthFill).CornerRadius = UDim.new(0, 2)

            -- Create health tracking
            local maxHealth = rowConfig.health
            local stats = AttributeSet.new({
                health = { type = "number", default = maxHealth, min = 0, max = maxHealth },
                maxHealth = { type = "number", default = maxHealth },
            })

            -- Calculate end position and tween
            local startPos = instance.Position
            local endPos = self._galleryPosition + Vector3.new(-TRACK_LENGTH/2, rowConfig.height, rowConfig.zOffset)
            local distance = (endPos - startPos).Magnitude
            local duration = distance / rowConfig.speed

            local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
            local tween = TweenService:Create(instance, tweenInfo, { Position = endPos })

            -- Store target data
            self._activeTargets[assetId] = {
                part = instance,
                stats = stats,
                healthFill = healthFill,
                tween = tween,
                rowConfig = rowConfig,
            }

            -- Health subscription
            stats:subscribe("health", function(newHealth)
                local pct = math.clamp(newHealth / maxHealth, 0, 1)
                healthFill.Size = UDim2.new(pct, 0, 1, 0)
                healthFill.BackgroundColor3 = pct > 0.5 and Color3.new(0, 1, 0)
                    or pct > 0.25 and Color3.new(1, 1, 0)
                    or Color3.new(1, 0, 0)

                if newHealth <= 0 then
                    -- Target destroyed!
                    local score = self._gameStats:get("score") + POINTS_PER_KILL
                    local kills = self._gameStats:get("kills") + 1
                    self._gameStats:setBase("score", score)
                    self._gameStats:setBase("kills", kills)
                    self:_updateReplicatedStats()

                    -- Visual feedback
                    local explosion = Instance.new("Explosion")
                    explosion.Position = instance.Position
                    explosion.BlastRadius = 0
                    explosion.BlastPressure = 0
                    explosion.Parent = workspace

                    -- Cleanup and signal return
                    tween:Cancel()
                    self._activeTargets[assetId] = nil
                    self.Out:Fire("returnTarget", { assetId = assetId })
                end
            end)

            -- When tween completes -> signal to despawn
            tween.Completed:Connect(function()
                if self._activeTargets[assetId] then
                    self._activeTargets[assetId] = nil
                    self.Out:Fire("returnTarget", { assetId = assetId })
                end
            end)

            -- Start movement
            tween:Play()
            print("[Gallery] Target spawned and moving:", assetId)
        end,

        -- Received when a target is despawned by Dropper
        onTargetDespawned = function(self, data)
            local assetId = data.assetId
            if self._activeTargets[assetId] then
                local targetData = self._activeTargets[assetId]
                if targetData.tween then
                    targetData.tween:Cancel()
                end
                self._activeTargets[assetId] = nil
            end
        end,
    },

    Out = {
        roundStarted = {},
        roundEnded = {},
        scoreUpdated = {},
        startDroppers = {},   -- -> Dropper.In.onStart (all 3)
        stopDroppers = {},    -- -> Dropper.In.onStop (all 3)
        returnTarget = {},    -- -> Dropper.In.onReturn
    },

    _fireProjectile = function(self)
        if not self._tracerTemplate or not self._muzzle then return end

        local projectile = self._tracerTemplate:Clone()
        local muzzlePos = self._muzzle.Position
        local muzzleDir = self._muzzle.CFrame.LookVector

        projectile.CFrame = CFrame.new(muzzlePos, muzzlePos + muzzleDir)
        projectile.Parent = self._projectilesFolder
        projectile.AssemblyLinearVelocity = muzzleDir * 200

        local attachment = Instance.new("Attachment")
        attachment.Parent = projectile

        local antiGravity = Instance.new("VectorForce")
        antiGravity.Attachment0 = attachment
        antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
        antiGravity.ApplyAtCenterOfMass = true
        antiGravity.Force = Vector3.new(0, projectile:GetMass() * workspace.Gravity, 0)
        antiGravity.Parent = projectile

        -- Hit detection
        local hitConn
        hitConn = projectile.Touched:Connect(function(hitPart)
            if hitPart:IsDescendantOf(self._projectilesFolder) then return end
            if hitPart.Name == "YawBase" or hitPart.Name == "PitchArm" or hitPart.Name == "Muzzle" then return end
            if hitPart.Name == "BasePlatform" or hitPart.Name == "Ground" or hitPart.Name == "Backdrop" then return end
            if hitPart.Name == "Waypoint" then return end

            -- Check if target
            local targetData = self._activeTargets[hitPart]
            if targetData then
                local stats = targetData.stats
                stats:setBase("health", stats:get("health") - DAMAGE_PER_HIT)

                local hits = self._gameStats:get("hits") + 1
                local score = self._gameStats:get("score") + POINTS_PER_HIT
                self._gameStats:setBase("hits", hits)
                self._gameStats:setBase("score", score)
                self:_updateReplicatedStats()

                -- Flash
                local origColor = hitPart.BrickColor
                hitPart.BrickColor = BrickColor.new("White")
                task.delay(0.05, function()
                    if hitPart.Parent then hitPart.BrickColor = origColor end
                end)
            end

            hitConn:Disconnect()
            projectile:Destroy()
        end)

        Debris:AddItem(projectile, 3)
    end,

    _updateReplicatedStats = function(self)
        if not self._gameStatePart then return end
        self._gameStatePart:SetAttribute("Score", self._gameStats:get("score"))
        self._gameStatePart:SetAttribute("Kills", self._gameStats:get("kills"))
        self._gameStatePart:SetAttribute("Hits", self._gameStats:get("hits"))
        self._gameStatePart:SetAttribute("Shots", self._gameStats:get("shots"))
        self._gameStatePart:SetAttribute("TimeRemaining", self._gameStats:get("timeRemaining"))
        self._gameStatePart:SetAttribute("RoundActive", self._gameStats:get("roundActive"))
    end,

    -- Setup method called by demo (configuration phase - direct calls OK per ARCHITECTURE.md)
    setup = function(self, config)
        self._muzzle = config.muzzle
        self._yawHinge = config.yawHinge
        self._pitchHinge = config.pitchHinge
        self._projectilesFolder = config.projectilesFolder
        self._targetsFolder = config.targetsFolder
        self._tracerTemplate = config.tracerTemplate
        self._gameStatePart = config.gameStatePart
        self._gameStats = config.gameStats
        self._galleryPosition = config.galleryPosition or Vector3.new(0, 0, 0)

        -- Store row configs for use by onTargetSpawned
        -- Key is the template name (used by Dropper)
        for _, rowConfig in ipairs(TARGET_ROWS) do
            self._rowConfigs[rowConfig.name] = rowConfig
        end
    end,
})

--------------------------------------------------------------------------------
-- CLIENT: GALLERY INPUT NODE
--------------------------------------------------------------------------------

local GalleryInput = Node.extend({
    name = "GalleryInput",
    domain = "client",

    Controls = {
        aimUp = {
            keys = { Enum.KeyCode.Up, Enum.KeyCode.W },
            buttons = { Enum.KeyCode.DPadUp },
            axis = { stick = "Thumbstick1", direction = "Y+", deadzone = 0.2 },
        },
        aimDown = {
            keys = { Enum.KeyCode.Down, Enum.KeyCode.S },
            buttons = { Enum.KeyCode.DPadDown },
            axis = { stick = "Thumbstick1", direction = "Y-", deadzone = 0.2 },
        },
        aimLeft = {
            keys = { Enum.KeyCode.Left, Enum.KeyCode.A },
            buttons = { Enum.KeyCode.DPadLeft },
            axis = { stick = "Thumbstick1", direction = "X-", deadzone = 0.2 },
        },
        aimRight = {
            keys = { Enum.KeyCode.Right, Enum.KeyCode.D },
            buttons = { Enum.KeyCode.DPadRight },
            axis = { stick = "Thumbstick1", direction = "X+", deadzone = 0.2 },
        },
        fire = {
            keys = { Enum.KeyCode.Space },
            buttons = { Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR2 },
        },
        exit = {
            keys = { Enum.KeyCode.E },
            buttons = { Enum.KeyCode.ButtonY },
            holdDuration = 1.5,
        },
    },

    Sys = {
        onInit = function(self)
            self._keysHeld = { up = false, down = false, left = false, right = false }
            self._exitProgress = 0
            self._yaw = 0
            self._pitch = 10
            self._onExit = nil
        end,
    },

    In = {
        onActionBegan = function(self, action)
            if action == "aimUp" then self._keysHeld.up = true
            elseif action == "aimDown" then self._keysHeld.down = true
            elseif action == "aimLeft" then self._keysHeld.left = true
            elseif action == "aimRight" then self._keysHeld.right = true
            elseif action == "fire" then
                self.Out:Fire("fire", {})
            end
        end,

        onActionEnded = function(self, action)
            if action == "aimUp" then self._keysHeld.up = false
            elseif action == "aimDown" then self._keysHeld.down = false
            elseif action == "aimLeft" then self._keysHeld.left = false
            elseif action == "aimRight" then self._keysHeld.right = false
            elseif action == "exit" then self._exitProgress = 0
            end
        end,

        onActionHeld = function(self, action, progress)
            if action == "exit" then self._exitProgress = progress end
        end,

        onActionTriggered = function(self, action)
            if action == "exit" and self._onExit then
                self._onExit()
            end
        end,

        onControlReleased = function(self)
            self._keysHeld = { up = false, down = false, left = false, right = false }
            self._exitProgress = 0
        end,
    },

    Out = {
        aim = {},   -- -> GalleryManager.onAim
        fire = {},  -- -> GalleryManager.onFire
    },

    -- Called each frame by the demo
    update = function(self, dt)
        local turnSpeed = 60 * dt

        if self._keysHeld.left then self._yaw = self._yaw + turnSpeed end
        if self._keysHeld.right then self._yaw = self._yaw - turnSpeed end
        if self._keysHeld.up then self._pitch = self._pitch + turnSpeed end
        if self._keysHeld.down then self._pitch = self._pitch - turnSpeed end

        self._yaw = math.clamp(self._yaw, -60, 60)
        self._pitch = math.clamp(self._pitch, -20, 45)

        -- Send aim to server
        self.Out:Fire("aim", { yaw = self._yaw, pitch = self._pitch })
    end,

    getState = function(self)
        return {
            yaw = self._yaw,
            pitch = self._pitch,
            exitProgress = self._exitProgress,
        }
    end,

    setExitCallback = function(self, callback)
        self._onExit = callback
    end,
})

--------------------------------------------------------------------------------
-- TRACER TEMPLATE
--------------------------------------------------------------------------------

local function createTracerTemplate(folder)
    local tracer = Instance.new("Part")
    tracer.Name = "GalleryTracer"
    tracer.Size = Vector3.new(0.3, 0.3, 1.5)
    tracer.Color = Color3.new(1, 0.8, 0)
    tracer.Material = Enum.Material.Neon
    tracer.Anchored = false
    tracer.CanCollide = false
    tracer.CastShadow = false
    tracer.Parent = folder

    local light = Instance.new("PointLight")
    light.Color = Color3.new(1, 0.6, 0)
    light.Brightness = 2
    light.Range = 8
    light.Parent = tracer

    local att0 = Instance.new("Attachment")
    att0.Name = "TrailBack"
    att0.Position = Vector3.new(0, 0, 0.75)
    att0.Parent = tracer

    local att1 = Instance.new("Attachment")
    att1.Name = "TrailFront"
    att1.Position = Vector3.new(0, 0, -0.75)
    att1.Parent = tracer

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

--------------------------------------------------------------------------------
-- DEMO.RUN (SERVER)
--------------------------------------------------------------------------------

function Demo.run(config)
    config = config or {}
    local galleryPosition = config.position or Vector3.new(0, 0, 0)

    if not RunService:IsServer() then
        warn("ShootingGallery Demo must be run from the SERVER command bar.")
        warn("Then join with a client to play!")
        return { cleanup = function() end }
    end

    -- Cleanup existing
    local existingDemo = workspace:FindFirstChild("ShootingGallery_Demo")
    if existingDemo then existingDemo:Destroy() end

    -- Reset IPC for clean state
    System.IPC.reset()

    ---------------------------------------------------------------------------
    -- CREATE WORLD
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "ShootingGallery_Demo"
    demoFolder.Parent = workspace

    local targetsFolder = Instance.new("Folder")
    targetsFolder.Name = "Targets"
    targetsFolder.Parent = demoFolder

    local projectilesFolder = Instance.new("Folder")
    projectilesFolder.Name = "Projectiles"
    projectilesFolder.Parent = demoFolder

    -- GameState part for replicating stats to clients
    local gameStatePart = Instance.new("Part")
    gameStatePart.Name = "GameState"
    gameStatePart.Transparency = 1
    gameStatePart.Anchored = true
    gameStatePart.CanCollide = false
    gameStatePart.Position = Vector3.new(0, -100, 0)
    gameStatePart.Parent = demoFolder
    gameStatePart:SetAttribute("Score", 0)
    gameStatePart:SetAttribute("Kills", 0)
    gameStatePart:SetAttribute("Hits", 0)
    gameStatePart:SetAttribute("Shots", 0)
    gameStatePart:SetAttribute("TimeRemaining", ROUND_DURATION)
    gameStatePart:SetAttribute("RoundActive", false)

    -- Ground
    local ground = Instance.new("Part")
    ground.Name = "Ground"
    ground.Size = Vector3.new(100, 1, 60)
    ground.Position = galleryPosition + Vector3.new(0, -0.5, 0)
    ground.Anchored = true
    ground.BrickColor = BrickColor.new("Dark stone grey")
    ground.Material = Enum.Material.Slate
    ground.Parent = demoFolder

    -- Backdrop (sized for 3 target rows)
    local backdrop = Instance.new("Part")
    backdrop.Name = "Backdrop"
    backdrop.Size = Vector3.new(TRACK_LENGTH + 20, 20, 15)
    backdrop.Position = galleryPosition + Vector3.new(0, 10, -28)
    backdrop.Anchored = true
    backdrop.BrickColor = BrickColor.new("Really black")
    backdrop.Material = Enum.Material.SmoothPlastic
    backdrop.Parent = demoFolder

    -- Booth frames
    local boothLeft = Instance.new("Part")
    boothLeft.Name = "BoothLeft"
    boothLeft.Size = Vector3.new(2, 15, 30)
    boothLeft.Position = galleryPosition + Vector3.new(-TRACK_LENGTH/2 - 5, 7.5, -10)
    boothLeft.Anchored = true
    boothLeft.BrickColor = BrickColor.new("Bright red")
    boothLeft.Material = Enum.Material.Wood
    boothLeft.Parent = demoFolder

    local boothRight = boothLeft:Clone()
    boothRight.Name = "BoothRight"
    boothRight.Position = galleryPosition + Vector3.new(TRACK_LENGTH/2 + 5, 7.5, -10)
    boothRight.Parent = demoFolder

    -- Sign
    local sign = Instance.new("Part")
    sign.Name = "Sign"
    sign.Size = Vector3.new(30, 4, 1)
    sign.Position = galleryPosition + Vector3.new(0, 18, -10)
    sign.Anchored = true
    sign.BrickColor = BrickColor.new("Bright yellow")
    sign.Material = Enum.Material.Neon
    sign.Parent = demoFolder

    local signGui = Instance.new("SurfaceGui")
    signGui.Face = Enum.NormalId.Front
    signGui.Parent = sign

    local signLabel = Instance.new("TextLabel")
    signLabel.Size = UDim2.new(1, 0, 1, 0)
    signLabel.BackgroundTransparency = 1
    signLabel.Text = "SHOOTING GALLERY"
    signLabel.TextColor3 = Color3.new(0, 0, 0)
    signLabel.TextScaled = true
    signLabel.Font = Enum.Font.GothamBold
    signLabel.Parent = signGui

    ---------------------------------------------------------------------------
    -- CREATE TURRET
    ---------------------------------------------------------------------------

    local turretPos = galleryPosition + Vector3.new(0, 2, 15)

    local basePlatform = Instance.new("Part")
    basePlatform.Name = "BasePlatform"
    basePlatform.Size = Vector3.new(6, 1, 6)
    basePlatform.Position = turretPos - Vector3.new(0, 1.5, 0)
    basePlatform.Anchored = true
    basePlatform.BrickColor = BrickColor.new("Really black")
    basePlatform.Material = Enum.Material.DiamondPlate
    basePlatform.Parent = demoFolder

    local controlPrompt = Instance.new("ProximityPrompt")
    controlPrompt.ObjectText = "Turret"
    controlPrompt.ActionText = "Man Turret"
    controlPrompt.HoldDuration = 0.5
    controlPrompt.MaxActivationDistance = 15
    controlPrompt.RequiresLineOfSight = false
    controlPrompt.Parent = basePlatform

    local yawBase = Instance.new("Part")
    yawBase.Name = "YawBase"
    yawBase.Size = Vector3.new(4, 1.5, 4)
    yawBase.CFrame = CFrame.new(turretPos)
    yawBase.Anchored = false
    yawBase.CanCollide = false
    yawBase.BrickColor = BrickColor.new("Medium stone grey")
    yawBase.Material = Enum.Material.Metal
    yawBase.Parent = demoFolder

    local baseAttachment = Instance.new("Attachment")
    baseAttachment.Position = Vector3.new(0, 0.5, 0)
    baseAttachment.CFrame = CFrame.Angles(0, 0, math.rad(90))
    baseAttachment.Parent = basePlatform

    local yawBaseAttachment = Instance.new("Attachment")
    yawBaseAttachment.Position = Vector3.new(0, -0.75, 0)
    yawBaseAttachment.CFrame = CFrame.Angles(0, 0, math.rad(90))
    yawBaseAttachment.Parent = yawBase

    local yawHinge = Instance.new("HingeConstraint")
    yawHinge.Attachment0 = baseAttachment
    yawHinge.Attachment1 = yawBaseAttachment
    yawHinge.ActuatorType = Enum.ActuatorType.Servo
    yawHinge.AngularSpeed = math.rad(120)
    yawHinge.ServoMaxTorque = 100000
    yawHinge.TargetAngle = 0
    yawHinge.LimitsEnabled = true
    yawHinge.LowerAngle = -60
    yawHinge.UpperAngle = 60
    yawHinge.Parent = basePlatform

    local pitchArm = Instance.new("Part")
    pitchArm.Name = "PitchArm"
    pitchArm.Size = Vector3.new(1.2, 1.2, 3)
    pitchArm.CFrame = CFrame.new(turretPos + Vector3.new(0, 1, 0))
    pitchArm.Anchored = false
    pitchArm.CanCollide = false
    pitchArm.BrickColor = BrickColor.new("Bright blue")
    pitchArm.Material = Enum.Material.SmoothPlastic
    pitchArm.Parent = demoFolder

    local yawTopAttachment = Instance.new("Attachment")
    yawTopAttachment.Position = Vector3.new(0, 0.75, 0)
    yawTopAttachment.Parent = yawBase

    local pitchAttachment = Instance.new("Attachment")
    pitchAttachment.Position = Vector3.new(0, 0, 0)
    pitchAttachment.Parent = pitchArm

    local pitchHinge = Instance.new("HingeConstraint")
    pitchHinge.Attachment0 = yawTopAttachment
    pitchHinge.Attachment1 = pitchAttachment
    pitchHinge.ActuatorType = Enum.ActuatorType.Servo
    pitchHinge.AngularSpeed = math.rad(120)
    pitchHinge.ServoMaxTorque = 100000
    pitchHinge.TargetAngle = 10
    pitchHinge.LimitsEnabled = true
    pitchHinge.LowerAngle = -20
    pitchHinge.UpperAngle = 45
    pitchHinge.Parent = yawBase

    local muzzle = Instance.new("Part")
    muzzle.Name = "Muzzle"
    muzzle.Size = Vector3.new(0.5, 0.5, 0.8)
    muzzle.CFrame = pitchArm.CFrame * CFrame.new(0, 0, -1.9)
    muzzle.Anchored = false
    muzzle.CanCollide = false
    muzzle.BrickColor = BrickColor.new("Bright red")
    muzzle.Material = Enum.Material.Neon
    muzzle.Parent = demoFolder

    local muzzleWeld = Instance.new("WeldConstraint")
    muzzleWeld.Part0 = pitchArm
    muzzleWeld.Part1 = muzzle
    muzzleWeld.Parent = pitchArm

    -- Tracer template
    local tracerTemplate = createTracerTemplate(ReplicatedStorage)

    ---------------------------------------------------------------------------
    -- GAME STATE
    ---------------------------------------------------------------------------

    local gameStats = AttributeSet.new({
        score = { type = "number", default = 0, min = 0 },
        kills = { type = "number", default = 0, min = 0 },
        hits = { type = "number", default = 0, min = 0 },
        shots = { type = "number", default = 0, min = 0 },
        timeRemaining = { type = "number", default = ROUND_DURATION, min = 0 },
        roundActive = { type = "boolean", default = false },
    })

    ---------------------------------------------------------------------------
    -- TARGET TEMPLATES (for SpawnerCore)
    ---------------------------------------------------------------------------

    local templateFolder = Instance.new("Folder")
    templateFolder.Name = "GalleryTargetTemplates"
    templateFolder.Parent = ReplicatedStorage

    -- Create a template for each row type
    for _, rowConfig in ipairs(TARGET_ROWS) do
        local template = Instance.new("Part")
        template.Name = rowConfig.name
        template.Size = rowConfig.size
        template.Anchored = true
        template.CanCollide = false
        template.BrickColor = rowConfig.color
        template.Material = Enum.Material.SmoothPlastic
        template.Parent = templateFolder
    end

    -- Initialize SpawnerCore with templates
    if not SpawnerCore.isInitialized() then
        SpawnerCore.init({ templates = templateFolder })
    end

    ---------------------------------------------------------------------------
    -- CREATE 3 DROPPER INSTANCES (one per target row)
    ---------------------------------------------------------------------------

    local droppers = {}
    for _, rowConfig in ipairs(TARGET_ROWS) do
        -- Create spawn position part for this row
        local spawnPoint = Instance.new("Part")
        spawnPoint.Name = rowConfig.name .. "_SpawnPoint"
        spawnPoint.Size = Vector3.new(1, 1, 1)
        spawnPoint.Transparency = 1
        spawnPoint.Anchored = true
        spawnPoint.CanCollide = false
        spawnPoint.Position = galleryPosition + Vector3.new(TRACK_LENGTH/2, rowConfig.height, rowConfig.zOffset)
        spawnPoint.Parent = demoFolder

        local dropper = Dropper:new({
            id = "Dropper_" .. rowConfig.name,
            model = spawnPoint,
        })
        dropper.Sys.onInit(dropper)

        -- Configure dropper (setup phase - direct calls OK per ARCHITECTURE.md)
        dropper.In.onConfigure(dropper, {
            templateName = rowConfig.name,
            interval = rowConfig.interval,
            maxActive = 10,
        })

        droppers[rowConfig.name] = dropper
    end

    ---------------------------------------------------------------------------
    -- REGISTER NODES WITH IPC
    ---------------------------------------------------------------------------

    System.IPC.registerNode(GalleryManager)
    System.IPC.registerNode(GalleryInput)

    -- Create server-side manager instance
    local manager = System.IPC.createInstance("GalleryManager", { id = "gallery_manager" })

    -- Define mode with cross-domain wiring
    System.IPC.defineMode("ShootingGallery", {
        nodes = { "GalleryManager", "GalleryInput" },
        wiring = {
            GalleryInput = { "GalleryManager" },  -- client -> server
            GalleryManager = { "GalleryInput" },  -- server -> client
        },
    })

    -- Initialize and start IPC
    System.IPC.init()
    System.IPC.switchMode("ShootingGallery")
    System.IPC.start()

    -- Setup manager with references (configuration phase - direct calls OK)
    manager:setup({
        muzzle = muzzle,
        yawHinge = yawHinge,
        pitchHinge = pitchHinge,
        projectilesFolder = projectilesFolder,
        targetsFolder = targetsFolder,
        tracerTemplate = tracerTemplate,
        gameStatePart = gameStatePart,
        gameStats = gameStats,
        galleryPosition = galleryPosition,
    })

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS (manual wiring for demo - in production IPC does this)
    ---------------------------------------------------------------------------

    -- Manager.Out -> Droppers.In
    manager.Out = {
        Fire = function(self, signal, data)
            if signal == "startDroppers" then
                -- Signal all droppers to start
                for _, dropper in pairs(droppers) do
                    dropper.In.onStart(dropper)
                end
            elseif signal == "stopDroppers" then
                -- Signal all droppers to stop
                for _, dropper in pairs(droppers) do
                    dropper.In.onStop(dropper)
                end
            elseif signal == "returnTarget" then
                -- Find which dropper owns this target and signal return
                for _, dropper in pairs(droppers) do
                    dropper.In.onReturn(dropper, { assetId = data.assetId })
                end
            elseif signal == "roundStarted" or signal == "roundEnded" or signal == "scoreUpdated" then
                -- These go to client via cross-domain IPC (handled by IPC wiring)
                -- Forward to IPC for cross-domain routing
                System.IPC.send("gallery_manager", signal, data)
            end
        end,
    }

    -- Droppers.Out -> Manager.In
    for rowName, dropper in pairs(droppers) do
        dropper.Out = {
            Fire = function(self, signal, data)
                if signal == "spawned" then
                    manager.In.onTargetSpawned(manager, data)
                elseif signal == "despawned" then
                    manager.In.onTargetDespawned(manager, data)
                end
            end,
        }
    end

    ---------------------------------------------------------------------------
    -- CLIENT INITIALIZATION (via RemoteEvent)
    ---------------------------------------------------------------------------

    -- Create RemoteEvent for client init signal
    local clientInitRemote = Instance.new("RemoteEvent")
    clientInitRemote.Name = "ClientInit"
    clientInitRemote.Parent = demoFolder

    -- Signal existing players to initialize
    task.defer(function()
        for _, player in ipairs(Players:GetPlayers()) do
            print("[Gallery] Signaling client init for:", player.Name)
            clientInitRemote:FireClient(player)
        end
    end)

    -- Signal new players when they join
    Players.PlayerAdded:Connect(function(player)
        print("[Gallery] Player joined, signaling client init:", player.Name)
        -- Small delay to ensure player is fully loaded
        task.delay(1, function()
            clientInitRemote:FireClient(player)
        end)
    end)

    ---------------------------------------------------------------------------
    -- PROXIMITY PROMPT (starts round via signal)
    ---------------------------------------------------------------------------

    controlPrompt.Triggered:Connect(function(player)
        if not gameStats:get("roundActive") then
            -- Use In handler (signal pattern) not direct method call
            manager.In.onStartRound(manager)
        end
    end)

    ---------------------------------------------------------------------------
    -- API
    ---------------------------------------------------------------------------

    local api = {}

    function api.startRound()
        -- Use In handler (signal pattern)
        manager.In.onStartRound(manager)
    end

    function api.stopRound()
        -- Use In handler (signal pattern)
        manager.In.onStopRound(manager)
    end

    function api.getScore()
        return {
            score = gameStats:get("score"),
            kills = gameStats:get("kills"),
            hits = gameStats:get("hits"),
            shots = gameStats:get("shots"),
        }
    end

    function api.cleanup()
        -- Use In handler (signal pattern)
        manager.In.onStopRound(manager)

        -- Stop all droppers
        for _, dropper in pairs(droppers) do
            dropper.In.onStop(dropper)
            dropper.Sys.onStop(dropper)
        end

        System.IPC.stop()
        System.IPC.reset()
        tracerTemplate:Destroy()
        templateFolder:Destroy()
        demoFolder:Destroy()
        print("[Gallery] Cleaned up.")
    end

    ---------------------------------------------------------------------------
    -- INSTRUCTIONS
    ---------------------------------------------------------------------------

    print("============================================")
    print("  SHOOTING GALLERY DEMO")
    print("============================================")
    print("")
    print("Server is ready!")
    print("Join with a client and walk to the turret.")
    print("Press E to start the round.")
    print("")
    print("For client input, run in CLIENT command bar:")
    print("  require(game.ReplicatedStorage.Lib.Demos).ShootingGallery.client()")
    print("")
    print("API:")
    print("  demo.startRound()")
    print("  demo.stopRound()")
    print("  demo.getScore()")
    print("  demo.cleanup()")
    print("")

    return api
end

--------------------------------------------------------------------------------
-- DEMO.CLIENT (CLIENT)
--------------------------------------------------------------------------------

function Demo.client()
    if RunService:IsServer() then
        warn("Demo.client() must be run from CLIENT command bar")
        return
    end

    local demoFolder = workspace:WaitForChild("ShootingGallery_Demo", 5)
    if not demoFolder then
        warn("ShootingGallery demo not found. Run Demo.run() on server first.")
        return
    end

    local gameStatePart = demoFolder:WaitForChild("GameState")
    local muzzle = demoFolder:WaitForChild("Muzzle")
    local basePlatform = demoFolder:WaitForChild("BasePlatform")
    local controlPrompt = basePlatform:WaitForChild("ProximityPrompt")

    -- Register BOTH node classes so wiring can be resolved for cross-domain routing
    -- (Client needs to know about GalleryManager even though it only creates GalleryInput)
    System.IPC.registerNode(GalleryManager)
    System.IPC.registerNode(GalleryInput)

    -- Define the mode on client (wiring must match server)
    System.IPC.defineMode("ShootingGallery", {
        nodes = { "GalleryManager", "GalleryInput" },
        wiring = {
            GalleryInput = { "GalleryManager" },  -- client -> server
            GalleryManager = { "GalleryInput" },  -- server -> client
        },
    })

    -- Switch to the demo mode
    System.IPC.switchMode("ShootingGallery")

    -- Create client-side input node (lifecycle handlers called automatically since IPC is already running)
    local input = System.IPC.createInstance("GalleryInput", { id = "gallery_input" })

    ---------------------------------------------------------------------------
    -- HUD
    ---------------------------------------------------------------------------

    local player = Players.LocalPlayer
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ShootingGalleryHUD"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = player:WaitForChild("PlayerGui")

    local scoreFrame = Instance.new("Frame")
    scoreFrame.Size = UDim2.new(0, 300, 0, 80)
    scoreFrame.Position = UDim2.new(0.5, -150, 0, 10)
    scoreFrame.BackgroundColor3 = Color3.new(0, 0, 0)
    scoreFrame.BackgroundTransparency = 0.3
    scoreFrame.Parent = screenGui
    Instance.new("UICorner", scoreFrame).CornerRadius = UDim.new(0, 8)

    local scoreLabel = Instance.new("TextLabel")
    scoreLabel.Size = UDim2.new(1, -20, 0.6, 0)
    scoreLabel.Position = UDim2.new(0, 10, 0, 5)
    scoreLabel.BackgroundTransparency = 1
    scoreLabel.Text = "SCORE: 0"
    scoreLabel.TextColor3 = Color3.new(1, 1, 0)
    scoreLabel.TextSize = 32
    scoreLabel.Font = Enum.Font.GothamBold
    scoreLabel.TextXAlignment = Enum.TextXAlignment.Center
    scoreLabel.Parent = scoreFrame

    local statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(1, -20, 0.4, 0)
    statsLabel.Position = UDim2.new(0, 10, 0.6, 0)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text = "Walk to turret and press E!"
    statsLabel.TextColor3 = Color3.new(1, 1, 1)
    statsLabel.TextSize = 14
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.TextXAlignment = Enum.TextXAlignment.Center
    statsLabel.Parent = scoreFrame

    local timerLabel = Instance.new("TextLabel")
    timerLabel.Size = UDim2.new(0, 100, 0, 40)
    timerLabel.Position = UDim2.new(1, -110, 0, 10)
    timerLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    timerLabel.BackgroundTransparency = 0.3
    timerLabel.Text = "--"
    timerLabel.TextColor3 = Color3.new(1, 1, 1)
    timerLabel.TextSize = 24
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.Parent = screenGui
    Instance.new("UICorner", timerLabel).CornerRadius = UDim.new(0, 8)

    ---------------------------------------------------------------------------
    -- INPUT CONTROL
    ---------------------------------------------------------------------------

    local InputCapture = Lib.System.InputCapture
    local camera = workspace.CurrentCamera
    local inControl = false
    local inputClaim = nil
    local savedCameraState = nil

    local function startControl()
        if inControl then return end
        inControl = true

        savedCameraState = {
            cameraType = camera.CameraType,
            cameraSubject = camera.CameraSubject,
        }
        camera.CameraType = Enum.CameraType.Scriptable

        inputClaim = InputCapture.claimForNode(input, { disableCharacter = true })

        if not inputClaim then
            warn("[Gallery] Failed to claim input! Controls:", input.Controls)
            return
        end

        controlPrompt.ActionText = "Release (Hold E)"
        statsLabel.Text = "WASD to aim | SPACE to fire | Hold E to exit"
        print("[Gallery] Player took control of turret")
    end

    local function stopControl()
        if not inControl then return end
        inControl = false

        if inputClaim then
            inputClaim:release()
            inputClaim = nil
        end

        if savedCameraState then
            camera.CameraType = savedCameraState.cameraType
            camera.CameraSubject = savedCameraState.cameraSubject
            savedCameraState = nil
        end

        controlPrompt.ActionText = "Man Turret"
        statsLabel.Text = "Walk to turret and press E!"
    end

    input:setExitCallback(stopControl)

    controlPrompt.Triggered:Connect(function()
        if inControl then
            stopControl()
        else
            startControl()
        end
    end)

    ---------------------------------------------------------------------------
    -- MAIN LOOP
    ---------------------------------------------------------------------------

    local running = true
    local mainConnection = RunService.Heartbeat:Connect(function(dt)
        if not running then return end

        -- Update HUD from replicated attributes
        scoreLabel.Text = string.format("SCORE: %d", gameStatePart:GetAttribute("Score") or 0)
        local shots = gameStatePart:GetAttribute("Shots") or 0
        local hits = gameStatePart:GetAttribute("Hits") or 0
        local accuracy = shots > 0 and (hits / shots * 100) or 0
        local kills = gameStatePart:GetAttribute("Kills") or 0

        if inControl then
            statsLabel.Text = string.format("Kills: %d | Accuracy: %.0f%% | Hold E to exit", kills, accuracy)
        end

        local timeRemaining = gameStatePart:GetAttribute("TimeRemaining") or 0
        local roundActive = gameStatePart:GetAttribute("RoundActive")
        if roundActive then
            timerLabel.Text = string.format("%ds", timeRemaining)
            timerLabel.TextColor3 = timeRemaining <= 10 and Color3.new(1, 0.3, 0.3) or Color3.new(1, 1, 1)
        else
            timerLabel.Text = "--"
        end

        -- Update input and camera when in control
        if inControl then
            input:update(dt)

            local muzzleCF = muzzle.CFrame
            local cameraOffset = muzzleCF * CFrame.new(0, 0.4, 1.5)
            camera.CFrame = CFrame.new(cameraOffset.Position, cameraOffset.Position + muzzleCF.LookVector)
        end
    end)

    print("[Gallery Client] Initialized! Walk to turret and press E.")

    return {
        cleanup = function()
            running = false
            stopControl()
            mainConnection:Disconnect()
            screenGui:Destroy()
            -- Note: Don't stop IPC here - it's managed by the global bootstrap
            print("[Gallery Client] Cleaned up.")
        end
    }
end

return Demo
