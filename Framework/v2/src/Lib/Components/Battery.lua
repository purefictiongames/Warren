--[[
    LibPureFiction Framework v2
    Battery.lua - Power Storage Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Battery provides power storage for components that consume energy (beam
    weapons, shields, etc). It maintains charge state and handles draw requests
    from any number of consumers.

    Battery is consumer-agnostic - it doesn't track who is drawing power. It
    simply receives draw requests, deducts from its charge, and emits state
    changes. Multiple consumers can wire to the same Battery.

    Auto-recharges when below capacity. Can also receive external recharge
    signals from Generator, Solar, or other power source components.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onDiscoverBattery({ requesterId })
            - Discovery handshake from consumers (e.g., Launcher)
            - Responds with batteryPresent signal

        onDraw({ amount, _passthrough? })
            - Request to draw power from battery
            - amount: power units to draw
            - Responds with powerDrawn signal (granted amount may be less)

        onRecharge({ amount })
            - Add power to battery (from Generator, Solar, etc)
            - Capped at capacity

        onConfigure({ capacity?, rechargeRate?, ... })
            - Configure battery settings

    OUT (emits):
        batteryPresent({ batteryId, capacity, current })
            - Discovery handshake response
            - Confirms battery is wired and available

        powerDrawn({ granted, remaining, capacity, _passthrough? })
            - Response to draw request
            - granted: actual amount drawn (may be less than requested)
            - remaining: current charge after draw
            - capacity: max capacity

        powerChanged({ current, max, percent })
            - Emitted when charge level changes (draw or recharge)

        powerDepleted({})
            - Emitted when charge reaches zero

        powerRestored({})
            - Emitted when charge returns from zero

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Capacity: number (default 100)
        Maximum power storage

    RechargeRate: number (default 10)
        Power units recharged per second (auto-recharge)

    StartingCharge: number (default nil, uses Capacity)
        Initial charge on init (nil = start at full capacity)

    Visible: boolean (default true)
        Whether the battery model is visible

    Size: Vector3 (default 1, 2, 1)
        Size of default battery part (if no model provided)

    Color: BrickColor (default "Bright green")
        Initial color of default battery part (overridden by power-level coloring)

    WeldTo: BasePart (default nil)
        If provided, welds the default battery part to this part

    WeldOffset: CFrame (default CFrame.new(2, 0, 0))
        Offset from WeldTo part (only used if WeldTo is set)

    Position: Vector3 (default 0, 5, 0)
        Absolute position for default part (only used if WeldTo is nil)

--]]

local Node = require(script.Parent.Parent.Node)
local RunService = game:GetService("RunService")

--------------------------------------------------------------------------------
-- BATTERY NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Battery = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                current = 0,
                rechargeConnection = nil,
                wasDepleted = false,
                -- Visual
                part = nil,
                partIsDefault = false,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            if state.rechargeConnection then
                state.rechargeConnection:Disconnect()
            end
            -- Destroy weld if we created it
            if state.weld then
                state.weld:Destroy()
            end
            -- Destroy default part if we created it
            if state.partIsDefault and state.part then
                state.part:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    --[[
        Private: Create a default battery part.
        If weldTo is provided, welds the battery to that part with an offset.
    --]]
    local function createDefaultPart(self, weldTo)
        local state = getState(self)

        local size = self:getAttribute("Size") or Vector3.new(1, 2, 1)
        local color = self:getAttribute("Color") or BrickColor.new("Bright green")
        local visible = self:getAttribute("Visible")
        if visible == nil then visible = true end

        local part = Instance.new("Part")
        part.Name = self.id .. "_Battery"
        part.Size = size
        part.CanCollide = false
        part.BrickColor = color
        part.Material = Enum.Material.Neon
        part.Transparency = visible and 0 or 1

        -- Position and weld to reference part if provided
        if weldTo and weldTo:IsA("BasePart") then
            -- Get offset from config or use default (to the right side)
            local offset = self:getAttribute("WeldOffset") or CFrame.new(2, 0, 0)

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
            local position = self:getAttribute("Position") or Vector3.new(0, 5, 0)
            part.Position = position
            part.Anchored = true
            part.Parent = workspace
        end

        state.part = part
        state.partIsDefault = true
        self.model = part

        return part
    end

    --[[
        Private: Update part visibility based on attribute.
    --]]
    local function updateVisibility(self)
        local state = getState(self)
        local visible = self:getAttribute("Visible")
        if visible == nil then visible = true end

        if state.part then
            state.part.Transparency = visible and 0 or 1
        end
    end

    --[[
        Private: Update part color based on power level.
        Green (full) → Yellow (mid) → Red (empty)
    --]]
    local function updatePartColor(self)
        local state = getState(self)
        if not state.part then return end

        local capacity = self:getAttribute("Capacity") or 100
        local percent = state.current / capacity

        -- Color gradient: Red (0%) → Yellow (50%) → Green (100%)
        local color
        if percent > 0.5 then
            -- Green to Yellow (100% to 50%)
            local t = (percent - 0.5) * 2  -- 0 to 1
            color = Color3.new(1 - t, 1, 0)  -- Yellow to Green
        else
            -- Yellow to Red (50% to 0%)
            local t = percent * 2  -- 0 to 1
            color = Color3.new(1, t, 0)  -- Red to Yellow
        end

        state.part.Color = color
    end

    --[[
        Private: Emit powerChanged signal with current state.
    --]]
    local function emitPowerChanged(self)
        local state = getState(self)
        local capacity = self:getAttribute("Capacity") or 100

        self.Out:Fire("powerChanged", {
            current = state.current,
            max = capacity,
            percent = state.current / capacity,
        })

        -- Update visual color based on power level
        updatePartColor(self)
    end

    --[[
        Private: Start the auto-recharge loop.
        Runs continuously, only recharges when below capacity.
    --]]
    local function startRechargeLoop(self)
        local state = getState(self)

        if state.rechargeConnection then
            return
        end

        state.rechargeConnection = RunService.Heartbeat:Connect(function(dt)
            local capacity = self:getAttribute("Capacity") or 100
            local rechargeRate = self:getAttribute("RechargeRate") or 10

            -- Skip if at full capacity
            if state.current >= capacity then
                return
            end

            -- Track if we were depleted before recharge
            local wasDepleted = state.current <= 0

            -- Recharge
            state.current = math.min(capacity, state.current + rechargeRate * dt)

            -- Emit power restored if coming back from zero
            if wasDepleted and state.current > 0 then
                state.wasDepleted = false
                self.Out:Fire("powerRestored", {})
            end

            emitPowerChanged(self)
        end)
    end

    local function stopRechargeLoop(self)
        local state = getState(self)

        if state.rechargeConnection then
            state.rechargeConnection:Disconnect()
            state.rechargeConnection = nil
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "Battery",
        domain = "server",

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Default attributes
                if self:getAttribute("Capacity") == nil then
                    self:setAttribute("Capacity", 100)
                end
                if self:getAttribute("RechargeRate") == nil then
                    self:setAttribute("RechargeRate", 10)
                end
                if self:getAttribute("Visible") == nil then
                    self:setAttribute("Visible", true)
                end

                -- Initialize charge
                local startingCharge = self:getAttribute("StartingCharge")
                local capacity = self:getAttribute("Capacity")
                state.current = startingCharge or capacity

                -- Set up visual part
                if self.model then
                    -- Use provided model
                    if self.model:IsA("BasePart") then
                        state.part = self.model
                    elseif self.model:IsA("Model") and self.model.PrimaryPart then
                        state.part = self.model.PrimaryPart
                    end
                    state.partIsDefault = false
                else
                    -- Create default part, optionally welded to a reference part
                    local weldTo = self:getAttribute("WeldTo")
                    createDefaultPart(self, weldTo)
                end

                -- Apply initial visibility and color
                updateVisibility(self)
                updatePartColor(self)
            end,

            onStart = function(self)
                -- Start auto-recharge loop
                startRechargeLoop(self)

                -- Emit initial state
                emitPowerChanged(self)
            end,

            onStop = function(self)
                stopRechargeLoop(self)
                cleanupState(self)
            end,
        },

        In = {
            --[[
                Discovery handshake from consumers.
                Responds synchronously with batteryPresent.
            --]]
            onDiscoverBattery = function(self, data)
                local state = getState(self)
                local capacity = self:getAttribute("Capacity") or 100

                self.Out:Fire("batteryPresent", {
                    batteryId = self.id,
                    capacity = capacity,
                    current = state.current,
                })
            end,

            --[[
                Draw power from battery.
                Grants up to the requested amount (may be less if insufficient).
            --]]
            onDraw = function(self, data)
                if not data or not data.amount then
                    return
                end

                local state = getState(self)
                local capacity = self:getAttribute("Capacity") or 100
                local requested = math.max(0, data.amount)

                -- Calculate how much we can actually grant
                local granted = math.min(requested, state.current)
                state.current = state.current - granted

                -- Emit draw response
                self.Out:Fire("powerDrawn", {
                    granted = granted,
                    remaining = state.current,
                    capacity = capacity,
                    _passthrough = data._passthrough,
                })

                -- Emit state change
                emitPowerChanged(self)

                -- Check for depletion
                if state.current <= 0 and not state.wasDepleted then
                    state.wasDepleted = true
                    self.Out:Fire("powerDepleted", {})
                end
            end,

            --[[
                Receive external recharge (from Generator, Solar, etc).
            --]]
            onRecharge = function(self, data)
                if not data or not data.amount then
                    return
                end

                local state = getState(self)
                local capacity = self:getAttribute("Capacity") or 100
                local amount = math.max(0, data.amount)

                -- Track if we were depleted before recharge
                local wasDepleted = state.current <= 0

                -- Add charge, capped at capacity
                state.current = math.min(capacity, state.current + amount)

                -- Emit power restored if coming back from zero
                if wasDepleted and state.current > 0 then
                    state.wasDepleted = false
                    self.Out:Fire("powerRestored", {})
                end

                emitPowerChanged(self)
            end,

            --[[
                Configure battery settings.
            --]]
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.capacity ~= nil then
                    local newCapacity = math.max(1, data.capacity)
                    self:setAttribute("Capacity", newCapacity)
                    -- Cap current charge to new capacity
                    local oldCurrent = state.current
                    state.current = math.min(state.current, newCapacity)
                    -- Emit if current was capped
                    if state.current ~= oldCurrent then
                        emitPowerChanged(self)
                    end
                end

                if data.rechargeRate ~= nil then
                    self:setAttribute("RechargeRate", math.max(0, data.rechargeRate))
                end

                if data.startingCharge ~= nil then
                    self:setAttribute("StartingCharge", data.startingCharge)
                end

                -- Allow setting current charge directly via config
                if data.current ~= nil then
                    local capacity = self:getAttribute("Capacity") or 100
                    state.current = math.min(math.max(0, data.current), capacity)
                    emitPowerChanged(self)
                end

                -- Visual configuration
                if data.visible ~= nil then
                    self:setAttribute("Visible", data.visible)
                    updateVisibility(self)
                end

                if data.color ~= nil then
                    self:setAttribute("Color", data.color)
                    if state.part and state.partIsDefault then
                        state.part.BrickColor = data.color
                    end
                end

                if data.size ~= nil then
                    self:setAttribute("Size", data.size)
                    if state.part and state.partIsDefault then
                        state.part.Size = data.size
                    end
                end

                if data.position ~= nil and state.part then
                    state.part.Position = data.position
                end
            end,
        },

        Out = {
            -- Discovery
            batteryPresent = {},  -- { batteryId, capacity, current }

            -- Draw response
            powerDrawn = {},      -- { granted, remaining, capacity, _passthrough? }

            -- State changes
            powerChanged = {},    -- { current, max, percent }
            powerDepleted = {},   -- {}
            powerRestored = {},   -- {}
        },
    }
end)

return Battery
