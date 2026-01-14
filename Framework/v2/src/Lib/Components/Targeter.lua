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

local Targeter = Node.extend({
    name = "Targeter",
    domain = "server",

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Internal state
            self._enabled = false
            self._scanning = false
            self._scanConnection = nil
            self._intervalTimer = 0
            self._hasTargets = false  -- For tracking mode state

            -- Filter configuration
            self._filter = {}

            -- RaycastParams setup
            self._raycastParams = RaycastParams.new()
            self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            self._raycastParams.FilterDescendantsInstances = {}

            -- Get origin from model
            self._origin = nil
            if self.model then
                if self.model:IsA("BasePart") then
                    self._origin = self.model
                elseif self.model:IsA("Model") and self.model.PrimaryPart then
                    self._origin = self.model.PrimaryPart
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
            self:_stopScanning()
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

    In = {
        --[[
            Configure targeter settings.
        --]]
        onConfigure = function(self, data)
            if not data then return end

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
                self._filter = data.filter or {}
            end

            -- Update raycast exclusion list
            if data.exclude then
                self._raycastParams.FilterDescendantsInstances = data.exclude
            end
        end,

        --[[
            Enable scanning.
        --]]
        onEnable = function(self)
            if self._enabled then return end
            self._enabled = true
            self:_startScanning()
        end,

        --[[
            Disable scanning.
        --]]
        onDisable = function(self)
            if not self._enabled then return end
            self._enabled = false
            self:_stopScanning()

            -- Fire lost if we had targets (lock mode)
            if self._hasTargets and self:getAttribute("TrackingMode") == "lock" then
                self._hasTargets = false
                self.Out:Fire("lost", {})
            end
        end,

        --[[
            Manual scan trigger (pulse mode).
        --]]
        onScan = function(self)
            self:_performScan()
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA
    ----------------------------------------------------------------------------

    Out = {
        acquired = {},  -- { targets: Array<{ target, position, normal, distance }> }
        tracking = {},  -- { targets: Array<...> }
        lost = {},      -- {}
    },

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    --[[
        Get the origin position for raycasting.
    --]]
    _getOrigin = function(self)
        if self._origin then
            return self._origin.Position
        end
        return Vector3.new(0, 0, 0)
    end,

    --[[
        Get the direction for raycasting (model's LookVector).
    --]]
    _getDirection = function(self)
        if self._origin then
            return self._origin.CFrame.LookVector
        end
        return Vector3.new(0, 0, -1)
    end,

    --[[
        Generate ray origins and directions based on beam mode.
        Returns array of { origin: Vector3, direction: Vector3 }
    --]]
    _generateRays = function(self)
        local rays = {}
        local beamMode = self:getAttribute("BeamMode") or "pinpoint"
        local origin = self:_getOrigin()
        local direction = self:_getDirection()
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
            if self._origin then
                local rightVector = self._origin.CFrame.RightVector
                local upVector = self._origin.CFrame.UpVector

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
            if self._origin then
                local rightVector = self._origin.CFrame.RightVector
                local upVector = self._origin.CFrame.UpVector

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
    end,

    --[[
        Perform a single scan and process results.
    --]]
    _performScan = function(self)
        local rays = self:_generateRays()
        local hitTargets = {}  -- { [instance] = { target, position, normal, distance } }

        -- Exclude own model from raycast
        if self.model then
            self._raycastParams.FilterDescendantsInstances = { self.model }
        end

        -- Cast all rays
        for _, ray in ipairs(rays) do
            local result = workspace:Raycast(ray.origin, ray.direction, self._raycastParams)
            if result then
                local hitPart = result.Instance
                local entity = EntityUtils.getEntityFromPart(hitPart)

                -- Check if entity passes filter
                if entity and EntityUtils.passesFilter(entity, self._filter) then
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
        self:_processResults(targets)
    end,

    --[[
        Process scan results and emit appropriate signals.
    --]]
    _processResults = function(self, targets)
        local trackingMode = self:getAttribute("TrackingMode") or "once"
        local hadTargets = self._hasTargets
        local hasTargets = #targets > 0

        if trackingMode == "once" then
            -- Fire acquired only on first detection
            if hasTargets and not hadTargets then
                self._hasTargets = true
                self.Out:Fire("acquired", { targets = targets })
            elseif not hasTargets then
                self._hasTargets = false
            end
        else -- lock mode
            if hasTargets then
                if not hadTargets then
                    -- First detection
                    self._hasTargets = true
                    self.Out:Fire("acquired", { targets = targets })
                else
                    -- Continuous tracking
                    self.Out:Fire("tracking", { targets = targets })
                end
            else
                if hadTargets then
                    -- Lost targets
                    self._hasTargets = false
                    self.Out:Fire("lost", {})
                end
            end
        end
    end,

    --[[
        Start the scanning loop based on scan mode.
    --]]
    _startScanning = function(self)
        if self._scanning then return end

        local scanMode = self:getAttribute("ScanMode") or "continuous"

        if scanMode == "pulse" then
            -- Pulse mode doesn't auto-scan
            return
        end

        self._scanning = true
        self._intervalTimer = 0

        self._scanConnection = RunService.Heartbeat:Connect(function(deltaTime)
            if not self._scanning or not self._enabled then return end

            if scanMode == "continuous" then
                self:_performScan()
            else -- interval
                self._intervalTimer = self._intervalTimer + deltaTime
                local interval = self:getAttribute("Interval") or 0.5
                if self._intervalTimer >= interval then
                    self._intervalTimer = 0
                    self:_performScan()
                end
            end
        end)
    end,

    --[[
        Stop the scanning loop.
    --]]
    _stopScanning = function(self)
        if not self._scanning then return end

        self._scanning = false

        if self._scanConnection then
            self._scanConnection:Disconnect()
            self._scanConnection = nil
        end
    end,

    --[[
        Check if currently scanning.
    --]]
    isScanning = function(self)
        return self._scanning
    end,

    --[[
        Check if currently has targets.
    --]]
    hasTargets = function(self)
        return self._hasTargets
    end,

    --[[
        Check if enabled.
    --]]
    isEnabled = function(self)
        return self._enabled
    end,
})

return Targeter
