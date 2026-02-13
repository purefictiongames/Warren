--[[
    LibPureFiction Framework v2
    Targeter.lua - Raycast-Based Target Detection Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Targeter provides raycast-based target detection with visual targeting beam.
    Mounts to a surface and casts rays in the LookVector direction to detect
    targets.

    Features:
    - Multiple beam modes (pinpoint, cylinder, cone)
    - Visual targeting beam with configurable appearance
    - Target lock tracking with acquired/tracking/lost signals
    - Auto-starts scanning in onStart (batteries included)
    - Bi-directional discovery handshake with Launcher

    Used for:
    - Turret target acquisition
    - Searchlight detection
    - Proximity sensors
    - Line-of-sight checks

    When wired to a Launcher via LauncherOrchestrator, the Targeter provides
    target lock feedback. The Launcher discovers the Targeter, which responds
    with its presence. Targeter also discovers the Launcher for bi-directional
    awareness.

    ============================================================================
    BEAM MODES
    ============================================================================

    pinpoint:
        Single ray from surface center.
        Use for precise targeting.

    cylinder:
        Parallel rays in a radius around center.
        Use for wide beam detection.

    cone:
        Rays spread outward from origin point.
        Use for expanding search pattern.

    ============================================================================
    SCAN MODES
    ============================================================================

    continuous:
        Scans every Heartbeat.
        Use for real-time tracking.

    interval:
        Scans every N seconds.
        Use for performance optimization.

    pulse:
        Scans only on onScan signal.
        Use for manual control.

    ============================================================================
    TRACKING MODES
    ============================================================================

    once:
        Emits 'acquired' when targets first detected.
        Does not emit again while targets remain.
        Use for fire-and-forget detection.

    lock:
        Emits 'acquired' on first detection.
        Emits 'tracking' continuously while targets in beam.
        Emits 'lost' when targets leave beam.
        Use for target lock behavior.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onEnable({})
            - Start scanning (if not already running)

        onDisable({})
            - Stop scanning

        onScan({})
            - Manual scan trigger (pulse mode, or force immediate scan)

        onConfigure({ filter?, range?, beamMode?, beamColor?, ... })
            - Update configuration

        -- Discovery handshake (from Launcher)
        onDiscoverTargeter({ launcherId })
            - Launcher is checking if we're wired
            - Responds with Out.targeterPresent

        -- Discovery handshake response (from Launcher)
        onLauncherPresent({ launcherId })
            - Launcher responded to our discovery
            - Sets hasExternalLauncher = true

    OUT (emits):
        acquired({ targets: Array<{ target, position, normal, distance }> })
            - Targets detected, sorted by distance (closest first)
            - In "once" mode: fires when targets first detected
            - In "lock" mode: fires on first detection

        tracking({ targets: Array<...> })
            - Continuous signal while targets in beam (lock mode only)
            - Same payload format as acquired

        lost({})
            - Had targets, now none (lock mode only)

        -- Discovery handshake
        discoverLauncher({ targeterId })
            - Fired at onStart to discover if Launcher is wired

        targeterPresent({ targeterId, range, beamMode, trackingMode })
            - Response to Launcher's discoverTargeter

    ============================================================================
    ATTRIBUTES
    ============================================================================

    BeamMode: string (default "pinpoint")
        "pinpoint", "cylinder", or "cone"

    BeamRadius: number (default 1)
        Radius in studs (cylinder/cone)

    RayCount: number (default 8)
        Number of rays for cylinder/cone modes

    Range: number (default 100)
        Max raycast distance

    ScanMode: string (default "continuous")
        "continuous", "interval", or "pulse"

    Interval: number (default 0.5)
        Seconds between scans (interval mode)

    TrackingMode: string (default "lock")
        "once" or "lock"

    -- Visual Beam Attributes
    BeamVisible: boolean (default true)
        Whether the visual targeting beam is shown

    BeamColor: Color3 (default green: 0, 1, 0)
        Color of the targeting beam

    BeamWidth: number (default 0.15)
        Width of the beam in studs

    BeamTransparency: number (default 0.3)
        Transparency of the beam (0 = solid, 1 = invisible)

    AutoStart: boolean (default true)
        Whether to start scanning automatically in onStart

--]]

local RunService = game:GetService("RunService")
local Node = require(script.Parent.Parent.Node)
local EntityUtils = require(script.Parent.Parent.Internal.EntityUtils)

--------------------------------------------------------------------------------
-- TARGETER NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Targeter = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                enabled = false,
                scanning = false,
                scanConnection = nil,
                intervalTimer = 0,
                hasTargets = false,
                filter = {},
                raycastParams = nil,
                origin = nil,
                -- Visual beam
                beamPart = nil,
                beamInner = nil,
                beamLight = nil,
                beamEndpoint = nil,
                beamIsDefault = false,
                -- Discovery
                hasExternalLauncher = false,
                launcherId = nil,
                -- Mount (for WeldTo pattern)
                mountPart = nil,
                mountIsDefault = false,
                weld = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            if state.scanConnection then
                state.scanConnection:Disconnect()
            end
            -- Destroy visual beam if we created it
            if state.beamIsDefault then
                if state.beamPart then
                    state.beamPart:Destroy()
                end
                if state.beamEndpoint then
                    state.beamEndpoint:Destroy()
                end
            end
            -- Destroy mount part if we created it
            if state.mountIsDefault and state.mountPart then
                state.mountPart:Destroy()
            end
            if state.weld then
                state.weld:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    --[[
        Private: Create a mount part for the targeter.
        If weldTo is provided, welds the part to that reference with an offset.
    --]]
    local function createMountPart(self, weldTo, weldOffset)
        local state = getState(self)

        local part = Instance.new("Part")
        part.Name = self.id .. "_TargeterMount"
        part.Size = Vector3.new(0.5, 0.5, 1)
        part.CanCollide = false
        part.CastShadow = false
        part.BrickColor = BrickColor.new("Bright green")
        part.Material = Enum.Material.Neon
        part.Transparency = 0.5

        -- Position and weld to reference part if provided
        if weldTo and weldTo:IsA("BasePart") then
            local offset = weldOffset or CFrame.new(0, 1, 0)  -- Default: on top

            part.CFrame = weldTo.CFrame * offset
            part.Anchored = false
            part.Parent = weldTo.Parent or workspace

            -- Create weld
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = weldTo
            weld.Part1 = part
            weld.Parent = part
            state.weld = weld
        else
            -- No reference, use absolute position
            part.Position = Vector3.new(0, 5, 0)
            part.Anchored = true
            part.Parent = workspace
        end

        state.mountPart = part
        state.mountIsDefault = true
        state.origin = part  -- Use mount as origin

        return part
    end

    --[[
        Private: Get the origin position for raycasting.
    --]]
    local function getOrigin(self)
        local state = getState(self)
        if state.origin then
            return state.origin.Position
        end
        return Vector3.new(0, 0, 0)
    end

    --[[
        Private: Get the direction for raycasting (model's LookVector).
    --]]
    local function getDirection(self)
        local state = getState(self)
        if state.origin then
            return state.origin.CFrame.LookVector
        end
        return Vector3.new(0, 0, -1)
    end

    --[[
        Private: Create the visual targeting beam.
    --]]
    local function createVisualBeam(self)
        local state = getState(self)

        local color = self:getAttribute("BeamColor") or Color3.new(0, 1, 0)
        local width = self:getAttribute("BeamWidth") or 0.15
        local visible = self:getAttribute("BeamVisible")
        if visible == nil then visible = true end

        local transparency = visible and (self:getAttribute("BeamTransparency") or 0.3) or 1

        -- Main beam part
        local beam = Instance.new("Part")
        beam.Name = self.id .. "_TargetingBeam"
        beam.Size = Vector3.new(width, width, 1)
        beam.Anchored = true
        beam.CanCollide = false
        beam.CastShadow = false
        beam.Color = color
        beam.Material = Enum.Material.Neon
        beam.Transparency = transparency
        beam.Parent = workspace

        -- Inner glow (brighter core)
        local innerBeam = Instance.new("Part")
        innerBeam.Name = "InnerGlow"
        innerBeam.Size = Vector3.new(width * 0.4, width * 0.4, 1)
        innerBeam.Anchored = true
        innerBeam.CanCollide = false
        innerBeam.CastShadow = false
        innerBeam.Color = Color3.new(1, 1, 1)
        innerBeam.Material = Enum.Material.Neon
        innerBeam.Transparency = transparency
        innerBeam.Parent = beam

        -- Light at origin
        local light = Instance.new("PointLight")
        light.Name = "BeamLight"
        light.Color = color
        light.Brightness = 1
        light.Range = 4
        light.Enabled = visible
        light.Parent = beam

        -- Endpoint indicator (small sphere where beam hits)
        local endpoint = Instance.new("Part")
        endpoint.Name = self.id .. "_BeamEndpoint"
        endpoint.Size = Vector3.new(width * 2, width * 2, width * 2)
        endpoint.Shape = Enum.PartType.Ball
        endpoint.Anchored = true
        endpoint.CanCollide = false
        endpoint.CastShadow = false
        endpoint.Color = color
        endpoint.Material = Enum.Material.Neon
        endpoint.Transparency = transparency
        endpoint.Parent = workspace

        state.beamPart = beam
        state.beamInner = innerBeam
        state.beamLight = light
        state.beamEndpoint = endpoint
        state.beamIsDefault = true

        return beam
    end

    --[[
        Private: Update the visual beam position and length.
    --]]
    local function updateVisualBeam(self, hitPosition)
        local state = getState(self)
        if not state.beamPart or not state.origin then
            return
        end

        local visible = self:getAttribute("BeamVisible")
        if visible == nil then visible = true end

        if not visible then
            state.beamPart.Transparency = 1
            state.beamInner.Transparency = 1
            state.beamEndpoint.Transparency = 1
            state.beamLight.Enabled = false
            return
        end

        local transparency = self:getAttribute("BeamTransparency") or 0.3
        local width = self:getAttribute("BeamWidth") or 0.15
        local range = self:getAttribute("Range") or 100
        local color = self:getAttribute("BeamColor") or Color3.new(0, 1, 0)

        local originPos = state.origin.Position
        local direction = state.origin.CFrame.LookVector

        -- Determine end position (hit or max range)
        local endPos = hitPosition or (originPos + direction * range)
        local beamLength = (endPos - originPos).Magnitude
        local midPoint = originPos + direction * (beamLength / 2)

        -- Update beam part
        state.beamPart.Size = Vector3.new(width, width, beamLength)
        state.beamPart.CFrame = CFrame.new(midPoint, endPos)
        state.beamPart.Color = color
        state.beamPart.Transparency = transparency

        -- Update inner glow
        state.beamInner.Size = Vector3.new(width * 0.4, width * 0.4, beamLength)
        state.beamInner.CFrame = state.beamPart.CFrame
        state.beamInner.Transparency = transparency

        -- Update endpoint
        state.beamEndpoint.Position = endPos
        state.beamEndpoint.Color = color
        state.beamEndpoint.Transparency = hitPosition and transparency or 1  -- Hide if no hit
        state.beamEndpoint.Size = Vector3.new(width * 2, width * 2, width * 2)

        -- Update light
        state.beamLight.Color = color
        state.beamLight.Enabled = true
    end

    --[[
        Private: Update beam color based on target state.
    --]]
    local function updateBeamTargetState(self, hasTargets)
        local state = getState(self)
        if not state.beamPart then return end

        -- Change color based on target state: green = searching, red = locked
        local baseColor = self:getAttribute("BeamColor") or Color3.new(0, 1, 0)

        if hasTargets then
            -- Target acquired - shift to red/orange
            state.beamPart.Color = Color3.new(1, 0.3, 0)
            state.beamInner.Color = Color3.new(1, 1, 0.8)
            state.beamEndpoint.Color = Color3.new(1, 0.3, 0)
            state.beamLight.Color = Color3.new(1, 0.3, 0)
        else
            -- Searching - use configured color
            state.beamPart.Color = baseColor
            state.beamInner.Color = Color3.new(1, 1, 1)
            state.beamEndpoint.Color = baseColor
            state.beamLight.Color = baseColor
        end
    end

    --[[
        Private: Generate ray origins and directions based on beam mode.
        Returns array of { origin: Vector3, direction: Vector3 }
    --]]
    local function generateRays(self)
        local state = getState(self)
        local rays = {}
        local beamMode = self:getAttribute("BeamMode") or "pinpoint"
        local origin = getOrigin(self)
        local direction = getDirection(self)
        local range = self:getAttribute("Range") or 100
        local radius = self:getAttribute("BeamRadius") or 1
        local rayCount = self:getAttribute("RayCount") or 8

        if beamMode == "pinpoint" then
            -- Single center ray
            table.insert(rays, {
                origin = origin,
                direction = direction * range,
            })
        elseif beamMode == "cylinder" then
            -- Center ray
            table.insert(rays, {
                origin = origin,
                direction = direction * range,
            })

            -- Ring of parallel rays
            if state.origin then
                local rightVector = state.origin.CFrame.RightVector
                local upVector = state.origin.CFrame.UpVector

                for i = 1, rayCount do
                    local angle = (i - 1) * (2 * math.pi / rayCount)
                    local offset = (math.cos(angle) * rightVector + math.sin(angle) * upVector) * radius
                    table.insert(rays, {
                        origin = origin + offset,
                        direction = direction * range,
                    })
                end
            end
        elseif beamMode == "cone" then
            -- Center ray
            table.insert(rays, {
                origin = origin,
                direction = direction * range,
            })

            -- Spreading rays
            if state.origin then
                local rightVector = state.origin.CFrame.RightVector
                local upVector = state.origin.CFrame.UpVector

                -- Calculate spread angle based on radius and range
                local spreadAngle = math.atan(radius / range)

                for i = 1, rayCount do
                    local angle = (i - 1) * (2 * math.pi / rayCount)
                    local spreadOffset = math.cos(angle) * rightVector + math.sin(angle) * upVector
                    -- Rotate direction by spread angle
                    local spreadDirection = (direction + spreadOffset * math.tan(spreadAngle)).Unit * range
                    table.insert(rays, {
                        origin = origin,
                        direction = spreadDirection,
                    })
                end
            end
        end

        return rays
    end

    --[[
        Private: Process scan results and emit appropriate signals.
    --]]
    local function processResults(self, targets, closestHitPosition)
        local state = getState(self)
        local trackingMode = self:getAttribute("TrackingMode") or "lock"
        local hadTargets = state.hasTargets
        local hasTargetsNow = #targets > 0

        -- Update visual beam
        updateVisualBeam(self, closestHitPosition)
        updateBeamTargetState(self, hasTargetsNow)

        if trackingMode == "once" then
            -- Fire acquired only on first detection
            if hasTargetsNow and not hadTargets then
                state.hasTargets = true
                self.Out:Fire("acquired", { targets = targets })
            elseif not hasTargetsNow then
                state.hasTargets = false
            end
        else -- lock mode
            if hasTargetsNow then
                if not hadTargets then
                    -- First detection
                    state.hasTargets = true
                    self.Out:Fire("acquired", { targets = targets })
                else
                    -- Continuous tracking
                    self.Out:Fire("tracking", { targets = targets })
                end
            else
                if hadTargets then
                    -- Lost targets
                    state.hasTargets = false
                    self.Out:Fire("lost", {})
                end
            end
        end
    end

    --[[
        Private: Perform a single scan and process results.
    --]]
    local function performScan(self)
        local state = getState(self)
        local rays = generateRays(self)
        local hitTargets = {}  -- { [instance] = { target, position, normal, distance } }
        local closestHitPosition = nil
        local closestDistance = math.huge

        -- Exclude own model from raycast
        if self.model then
            state.raycastParams.FilterDescendantsInstances = { self.model }
        end

        -- Also exclude the visual beam parts and mount part
        local excludeList = state.raycastParams.FilterDescendantsInstances or {}
        if state.beamPart then
            table.insert(excludeList, state.beamPart)
        end
        if state.beamEndpoint then
            table.insert(excludeList, state.beamEndpoint)
        end
        if state.mountPart then
            table.insert(excludeList, state.mountPart)
        end
        state.raycastParams.FilterDescendantsInstances = excludeList

        -- Cast all rays
        for _, ray in ipairs(rays) do
            local result = workspace:Raycast(ray.origin, ray.direction, state.raycastParams)
            if result then
                local hitPart = result.Instance
                local distance = (result.Position - ray.origin).Magnitude

                -- Track closest hit for visual beam
                if distance < closestDistance then
                    closestDistance = distance
                    closestHitPosition = result.Position
                end

                local entity = EntityUtils.getEntityFromPart(hitPart)

                -- Check if entity passes filter
                if entity and EntityUtils.passesFilter(entity, state.filter) then
                    -- Track unique targets (closest hit wins)
                    local existing = hitTargets[entity]
                    if not existing or distance < existing.distance then
                        hitTargets[entity] = {
                            target = entity,
                            position = result.Position,
                            normal = result.Normal,
                            distance = distance,
                        }
                    end
                end
            end
        end

        -- Convert to sorted array
        local targets = {}
        for _, targetData in pairs(hitTargets) do
            table.insert(targets, targetData)
        end

        -- Sort by distance (closest first)
        table.sort(targets, function(a, b)
            return a.distance < b.distance
        end)

        -- Process results based on tracking mode
        processResults(self, targets, closestHitPosition)
    end

    --[[
        Private: Stop the scanning loop.
    --]]
    local function stopScanning(self)
        local state = getState(self)
        if not state.scanning then return end

        state.scanning = false

        if state.scanConnection then
            state.scanConnection:Disconnect()
            state.scanConnection = nil
        end
    end

    --[[
        Private: Start the scanning loop based on scan mode.
    --]]
    local function startScanning(self)
        local state = getState(self)
        if state.scanning then return end

        local scanMode = self:getAttribute("ScanMode") or "continuous"

        if scanMode == "pulse" then
            -- Pulse mode doesn't auto-scan, but still update beam position
            state.scanning = true
            state.scanConnection = RunService.Heartbeat:Connect(function(deltaTime)
                -- Just update beam visual to follow origin
                updateVisualBeam(self, nil)
            end)
            return
        end

        state.scanning = true
        state.intervalTimer = 0

        state.scanConnection = RunService.Heartbeat:Connect(function(deltaTime)
            if not state.scanning or not state.enabled then return end

            if scanMode == "continuous" then
                performScan(self)
            else -- interval
                state.intervalTimer = state.intervalTimer + deltaTime
                local interval = self:getAttribute("Interval") or 0.5
                if state.intervalTimer >= interval then
                    state.intervalTimer = 0
                    performScan(self)
                else
                    -- Still update beam visual between scans
                    updateVisualBeam(self, nil)
                end
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "Targeter",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)
                local config = self._attributes or {}

                -- RaycastParams setup
                state.raycastParams = RaycastParams.new()
                state.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                state.raycastParams.FilterDescendantsInstances = {}

                -- Get origin from model, or create mount part if WeldTo specified
                if config.WeldTo then
                    -- WeldTo pattern: create a mount part welded to reference
                    createMountPart(self, config.WeldTo, config.WeldOffset)
                elseif self.model then
                    if self.model:IsA("BasePart") then
                        state.origin = self.model
                    elseif self.model:IsA("Model") and self.model.PrimaryPart then
                        state.origin = self.model.PrimaryPart
                    else
                        -- Model exists but no primary part - create mount
                        createMountPart(self, nil, nil)
                    end
                else
                    -- No model, no weldTo - create standalone mount
                    createMountPart(self, nil, nil)
                end

                -- Default attributes
                if self:getAttribute("BeamMode") == nil then
                    self:setAttribute("BeamMode", "pinpoint")
                end
                if self:getAttribute("BeamRadius") == nil then
                    self:setAttribute("BeamRadius", 1)
                end
                if self:getAttribute("RayCount") == nil then
                    self:setAttribute("RayCount", 8)
                end
                if self:getAttribute("Range") == nil then
                    self:setAttribute("Range", 100)
                end
                if self:getAttribute("ScanMode") == nil then
                    self:setAttribute("ScanMode", "continuous")
                end
                if self:getAttribute("Interval") == nil then
                    self:setAttribute("Interval", 0.5)
                end
                if self:getAttribute("TrackingMode") == nil then
                    self:setAttribute("TrackingMode", "lock")
                end
                if self:getAttribute("AutoStart") == nil then
                    self:setAttribute("AutoStart", true)
                end

                -- Visual beam defaults
                if self:getAttribute("BeamVisible") == nil then
                    self:setAttribute("BeamVisible", true)
                end
                if self:getAttribute("BeamColor") == nil then
                    self:setAttribute("BeamColor", Color3.new(0, 1, 0))
                end
                if self:getAttribute("BeamWidth") == nil then
                    self:setAttribute("BeamWidth", 0.15)
                end
                if self:getAttribute("BeamTransparency") == nil then
                    self:setAttribute("BeamTransparency", 0.3)
                end

                -- Create visual beam
                createVisualBeam(self)
            end,

            onStart = function(self)
                local state = getState(self)

                -- Discovery handshake: check if Launcher is wired
                -- If Launcher responds (sync), onLauncherPresent sets hasExternalLauncher = true
                state.hasExternalLauncher = false
                self.Out:Fire("discoverLauncher", { targeterId = self.id })

                -- Auto-start scanning if configured (default: true)
                if self:getAttribute("AutoStart") then
                    state.enabled = true
                    startScanning(self)
                end
            end,

            onStop = function(self)
                local state = getState(self)

                -- Fire lost if we had targets
                if state.hasTargets and self:getAttribute("TrackingMode") == "lock" then
                    state.hasTargets = false
                    self.Out:Fire("lost", {})
                end

                stopScanning(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            --[[
                Discovery handshake: Launcher is checking if we're wired.
                Respond immediately with our presence.
            --]]
            onDiscoverTargeter = function(self, data)
                self.Out:Fire("targeterPresent", {
                    targeterId = self.id,
                    range = self:getAttribute("Range"),
                    beamMode = self:getAttribute("BeamMode"),
                    trackingMode = self:getAttribute("TrackingMode"),
                })
            end,

            --[[
                Discovery handshake response: Launcher is present.
            --]]
            onLauncherPresent = function(self, data)
                local state = getState(self)
                state.hasExternalLauncher = true
                state.launcherId = data and data.launcherId
            end,

            --[[
                Configure targeter settings.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.beamMode then
                    local mode = string.lower(data.beamMode)
                    if mode == "pinpoint" or mode == "cylinder" or mode == "cone" then
                        self:setAttribute("BeamMode", mode)
                    end
                end

                if data.beamRadius then
                    self:setAttribute("BeamRadius", math.abs(data.beamRadius))
                end

                if data.rayCount then
                    self:setAttribute("RayCount", math.max(1, math.floor(data.rayCount)))
                end

                if data.range then
                    self:setAttribute("Range", math.abs(data.range))
                end

                if data.scanMode then
                    local mode = string.lower(data.scanMode)
                    if mode == "continuous" or mode == "interval" or mode == "pulse" then
                        self:setAttribute("ScanMode", mode)
                    end
                end

                if data.interval then
                    self:setAttribute("Interval", math.max(0.01, data.interval))
                end

                if data.trackingMode then
                    local mode = string.lower(data.trackingMode)
                    if mode == "once" or mode == "lock" then
                        self:setAttribute("TrackingMode", mode)
                    end
                end

                if data.filter ~= nil then
                    state.filter = data.filter or {}
                end

                -- Update raycast exclusion list
                if data.exclude then
                    state.raycastParams.FilterDescendantsInstances = data.exclude
                end

                -- Visual beam configuration
                if data.beamVisible ~= nil then
                    self:setAttribute("BeamVisible", data.beamVisible)
                end

                if data.beamColor then
                    self:setAttribute("BeamColor", data.beamColor)
                end

                if data.beamWidth then
                    self:setAttribute("BeamWidth", math.max(0.05, data.beamWidth))
                end

                if data.beamTransparency then
                    self:setAttribute("BeamTransparency", math.clamp(data.beamTransparency, 0, 1))
                end
            end,

            --[[
                Enable scanning.
            --]]
            onEnable = function(self)
                local state = getState(self)
                if state.enabled then return end
                state.enabled = true
                startScanning(self)
            end,

            --[[
                Disable scanning.
            --]]
            onDisable = function(self)
                local state = getState(self)
                if not state.enabled then return end
                state.enabled = false
                stopScanning(self)

                -- Fire lost if we had targets (lock mode)
                if state.hasTargets and self:getAttribute("TrackingMode") == "lock" then
                    state.hasTargets = false
                    self.Out:Fire("lost", {})
                end
            end,

            --[[
                Manual scan trigger (pulse mode, or force immediate scan).
            --]]
            onScan = function(self)
                performScan(self)
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            acquired = {},  -- { targets: Array<{ target, position, normal, distance }> }
            tracking = {},  -- { targets: Array<...> }
            lost = {},      -- {}

            -- Discovery handshake
            discoverLauncher = {},  -- { targeterId }
            targeterPresent = {},   -- { targeterId, range, beamMode, trackingMode }
        },
    }
end)

return Targeter
