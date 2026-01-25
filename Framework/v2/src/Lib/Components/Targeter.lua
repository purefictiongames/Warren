--[[
    LibPureFiction Framework v2
    Targeter.lua - Raycast-Based Target Detection Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Targeter provides raycast-based target detection. Mounts to a surface and
    casts rays in the LookVector direction to detect targets.

    Used for:
    - Turret target acquisition
    - Searchlight detection
    - Proximity sensors
    - Line-of-sight checks

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
            - Start scanning (continuous/interval modes)

        onDisable({})
            - Stop scanning

        onScan({})
            - Manual scan trigger (pulse mode)

        onConfigure({ filter?, range?, beamMode?, ... })
            - Update configuration

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

    TrackingMode: string (default "once")
        "once" or "lock"

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local targeter = Targeter:new({ model = workspace.TurretScanner })
    targeter.Sys.onInit(targeter)
    targeter.In.onConfigure(targeter, {
        beamMode = "cone",
        beamRadius = 5,
        range = 150,
        trackingMode = "lock",
        filter = { class = "Enemy" },
    })

    -- Wire output to turret controller
    targeter.Out = {
        Fire = function(self, signal, data)
            if signal == "acquired" then
                turretController.In.onTargetAcquired(turretController, data)
            elseif signal == "tracking" then
                turretController.In.onTargetTracking(turretController, data)
            elseif signal == "lost" then
                turretController.In.onTargetLost(turretController, data)
            end
        end,
    }

    targeter.In.onEnable(targeter)
    ```

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
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
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
    local function processResults(self, targets)
        local state = getState(self)
        local trackingMode = self:getAttribute("TrackingMode") or "once"
        local hadTargets = state.hasTargets
        local hasTargetsNow = #targets > 0

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

        -- Exclude own model from raycast
        if self.model then
            state.raycastParams.FilterDescendantsInstances = { self.model }
        end

        -- Cast all rays
        for _, ray in ipairs(rays) do
            local result = workspace:Raycast(ray.origin, ray.direction, state.raycastParams)
            if result then
                local hitPart = result.Instance
                local entity = EntityUtils.getEntityFromPart(hitPart)

                -- Check if entity passes filter
                if entity and EntityUtils.passesFilter(entity, state.filter) then
                    -- Calculate distance from origin
                    local distance = (result.Position - ray.origin).Magnitude

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
        processResults(self, targets)
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
            -- Pulse mode doesn't auto-scan
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

                -- RaycastParams setup
                state.raycastParams = RaycastParams.new()
                state.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                state.raycastParams.FilterDescendantsInstances = {}

                -- Get origin from model
                if self.model then
                    if self.model:IsA("BasePart") then
                        state.origin = self.model
                    elseif self.model:IsA("Model") and self.model.PrimaryPart then
                        state.origin = self.model.PrimaryPart
                    end
                end

                -- Default attributes
                if not self:getAttribute("BeamMode") then
                    self:setAttribute("BeamMode", "pinpoint")
                end
                if not self:getAttribute("BeamRadius") then
                    self:setAttribute("BeamRadius", 1)
                end
                if not self:getAttribute("RayCount") then
                    self:setAttribute("RayCount", 8)
                end
                if not self:getAttribute("Range") then
                    self:setAttribute("Range", 100)
                end
                if not self:getAttribute("ScanMode") then
                    self:setAttribute("ScanMode", "continuous")
                end
                if not self:getAttribute("Interval") then
                    self:setAttribute("Interval", 0.5)
                end
                if not self:getAttribute("TrackingMode") then
                    self:setAttribute("TrackingMode", "once")
                end
            end,

            onStart = function(self)
                -- Nothing additional on start
            end,

            onStop = function(self)
                stopScanning(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
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
                Manual scan trigger (pulse mode).
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
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS (intentionally exposed)
        ------------------------------------------------------------------------

        --[[
            Check if currently scanning.
        --]]
        isScanning = function(self)
            local state = getState(self)
            return state.scanning
        end,

        --[[
            Check if currently has targets.
        --]]
        hasTargets = function(self)
            local state = getState(self)
            return state.hasTargets
        end,

        --[[
            Check if enabled.
        --]]
        isEnabled = function(self)
            local state = getState(self)
            return state.enabled
        end,
    }
end)

return Targeter
