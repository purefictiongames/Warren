--[[
    IGW v2 Pipeline — PassageNode
    Creates blocking Parts in door holes. Manages blocked/open state.

    Pipeline signal: onSpawnPassages(payload) — reads payload.doors, creates
    a collidable box Part per door hole sized to fill the opening.

    Door types (determined by door.type in payload, default "auto"):
      auto          — green, opens automatically on player proximity
      keyed         — blue, requires key item selected + interact (E)
      shootThrough  — red, requires weapon item selected + interact (E)
      destructible  — orange, requires bomb item selected + interact (E)

    Each door is a runtime DoorInstance with:
    - blocked/open state
    - canResolve(interaction) → boolean
    - resolve(interaction) → opens the door if canResolve passes
    - open() / close() — direct state control
    - autoClose support (seconds until re-close, 0 = stays open)
    - onStateChanged callback registration

    Room orchestrator owns placement — this node reads door positions
    from payload.doors (computed by DoorPlanner).
--]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Capture module reference for requiring BackpackStub at runtime
local _components = script.Parent.Parent

--------------------------------------------------------------------------------
-- DOOR TYPE PROFILES
--------------------------------------------------------------------------------

local DOOR_TYPES = {
    auto = {
        color = Color3.fromRGB(100, 200, 100),
        transparency = 0.5,
        proximityOpen = true,
        requiredItem = nil,
    },
    keyed = {
        color = Color3.fromRGB(80, 120, 220),
        transparency = 0.3,
        proximityOpen = false,
        requiredItem = "key",
        promptText = "Unlock",
        consumeItem = true,
    },
    shootThrough = {
        color = Color3.fromRGB(220, 60, 60),
        transparency = 0.3,
        proximityOpen = false,
        requiredItem = "weapon",
        promptText = "Break",
        consumeItem = false,
    },
    destructible = {
        color = Color3.fromRGB(220, 140, 40),
        transparency = 0.3,
        proximityOpen = false,
        requiredItem = "bomb",
        promptText = "Destroy",
        consumeItem = true,
    },
}

--------------------------------------------------------------------------------
-- DOOR INSTANCE — runtime state for a single door
--------------------------------------------------------------------------------

local DoorInstance = {}
DoorInstance.__index = DoorInstance

local _registry = {}  -- doorId → DoorInstance

function DoorInstance.new(part, doorData, config)
    local self = setmetatable({}, DoorInstance)
    self.id = doorData.id
    self.part = part
    self.doorData = doorData
    self.doorType = config.doorType or "auto"
    self.state = "blocked"
    self.autoClose = config.autoClose or 0
    self._originalPosition = part.Position
    self._originalTransparency = part.Transparency
    self._closeThread = nil
    self._callbacks = {}
    self._connections = {}
    self._zone = nil
    _registry[self.id] = self
    return self
end

--- Returns true if this door can be opened by the given interaction.
function DoorInstance:canResolve(interaction)
    local profile = DOOR_TYPES[self.doorType]
    if not profile then return false end
    if profile.proximityOpen then return true end
    if profile.requiredItem then
        return interaction and interaction.item == profile.requiredItem
    end
    return false
end

--- Attempt to open the door via an interaction.
-- Checks canResolve first; does nothing if it returns false.
function DoorInstance:resolve(interaction)
    if self.state ~= "blocked" then return end
    if not self:canResolve(interaction) then return end

    local profile = DOOR_TYPES[self.doorType]
    if profile and profile.consumeItem and interaction and interaction.consume then
        interaction.consume()
    end

    self:open()
end

--- Open the door unconditionally. Plays slide-up tween animation.
function DoorInstance:open()
    if self.state == "open" then return end
    local oldState = self.state
    self.state = "open"

    -- Cancel any pending close
    if self._closeThread then
        task.cancel(self._closeThread)
        self._closeThread = nil
    end

    -- Tween: slide up out of doorway + fade
    local slideHeight = self.doorData.height
    local openPos = self._originalPosition + Vector3.new(0, slideHeight, 0)
    local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(self.part, tweenInfo, {
        Position = openPos,
        Transparency = 1,
    })

    tween:Play()
    tween.Completed:Once(function()
        self.part.CanCollide = false
    end)

    self:_fireStateChanged(oldState, "open")

    -- Schedule auto-close
    if self.autoClose > 0 then
        self._closeThread = task.delay(self.autoClose, function()
            self:close()
        end)
    end
end

--- Close the door. Restores collision and plays slide-down tween.
function DoorInstance:close()
    if self.state == "blocked" then return end
    local oldState = self.state
    self.state = "blocked"

    -- Cancel any pending close
    if self._closeThread then
        task.cancel(self._closeThread)
        self._closeThread = nil
    end

    -- Restore collision immediately
    self.part.CanCollide = true

    -- Tween: slide back down + restore opacity
    local profile = DOOR_TYPES[self.doorType]
    local targetTransparency = profile and profile.transparency or self._originalTransparency
    local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local tween = TweenService:Create(self.part, tweenInfo, {
        Position = self._originalPosition,
        Transparency = targetTransparency,
    })
    tween:Play()

    self:_fireStateChanged(oldState, "blocked")
end

--- Register a callback for state changes: callback(oldState, newState, doorInstance)
function DoorInstance:onStateChanged(callback)
    table.insert(self._callbacks, callback)
end

function DoorInstance:_fireStateChanged(oldState, newState)
    for _, cb in ipairs(self._callbacks) do
        task.spawn(cb, oldState, newState, self)
    end
end

function DoorInstance:destroy()
    if self._closeThread then
        task.cancel(self._closeThread)
        self._closeThread = nil
    end
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    self._connections = {}
    if self._zone and self._zone.Parent then
        self._zone:Destroy()
    end
    _registry[self.id] = nil
    if self.part and self.part.Parent then
        self.part:Destroy()
    end
end

--------------------------------------------------------------------------------
-- PROXIMITY + INTERACTION SETUP
--------------------------------------------------------------------------------

local _backpackStub = nil

local function getBackpackStub()
    if _backpackStub then return _backpackStub end
    local mod = _components:FindFirstChild("BackpackStub")
    if mod then
        _backpackStub = require(mod)
        _backpackStub.serverInit()
    end
    return _backpackStub
end

--- Create invisible detection zone for auto-open doors
local function setupProximityZone(doorInst, container)
    local door = doorInst.doorData
    local padding = 10

    local zoneSize
    if door.axis == 2 then
        zoneSize = Vector3.new(door.width + padding, 16, door.height + padding)
    elseif door.widthAxis == 1 then
        zoneSize = Vector3.new(door.width + padding, door.height, 16)
    else
        zoneSize = Vector3.new(16, door.height, door.width + padding)
    end

    local zone = Instance.new("Part")
    zone.Name = "PassageZone_" .. door.id
    zone.Size = zoneSize
    zone.Position = doorInst._originalPosition
    zone.Anchored = true
    zone.CanCollide = false
    zone.Transparency = 1
    zone.CanQuery = false
    zone.Parent = container or workspace
    doorInst._zone = zone

    local conn = zone.Touched:Connect(function(hit)
        local player = Players:GetPlayerFromCharacter(hit.Parent)
        if player and doorInst.state == "blocked" then
            doorInst:open()
        end
    end)
    table.insert(doorInst._connections, conn)
end

--- Create ProximityPrompt for interactive doors (keyed, shoot, bomb)
local function setupProximityPrompt(doorInst)
    local profile = DOOR_TYPES[doorInst.doorType]
    if not profile or not profile.requiredItem then return end

    local prompt = Instance.new("ProximityPrompt")
    prompt.ObjectText = profile.promptText or "Interact"
    prompt.ActionText = profile.promptText or "Interact"
    prompt.MaxActivationDistance = 12
    prompt.HoldDuration = 0
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
    prompt.Parent = doorInst.part

    local conn = prompt.Triggered:Connect(function(player)
        if doorInst.state ~= "blocked" then return end

        local backpack = getBackpackStub()
        if not backpack then return end

        local selectedItem = backpack.getSelectedItem(player)
        local interaction = {
            player = player,
            item = selectedItem,
            consume = function()
                backpack.consumeItem(player, profile.requiredItem)
            end,
        }

        doorInst:resolve(interaction)
    end)
    table.insert(doorInst._connections, conn)
end

--------------------------------------------------------------------------------
-- PUBLIC API — other nodes access doors via PassageNode.API
--------------------------------------------------------------------------------

local PassageAPI = {}

function PassageAPI.getDoor(doorId)
    return _registry[doorId]
end

function PassageAPI.getAllDoors()
    return _registry
end

function PassageAPI.getDoorCount()
    local count = 0
    for _ in pairs(_registry) do count = count + 1 end
    return count
end

--------------------------------------------------------------------------------
-- PIPELINE NODE
--------------------------------------------------------------------------------

return {
    name = "PassageNode",
    domain = "server",

    API = PassageAPI,
    DoorInstance = DoorInstance,
    DOOR_TYPES = DOOR_TYPES,

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self)
            for _, door in pairs(_registry) do
                door:destroy()
            end
        end,
    },

    In = {
        onSpawnPassages = function(self, payload)
            local doors = payload.doors or {}
            local wt = self:getAttribute("wallThickness") or 2
            local autoClose = self:getAttribute("autoClose") or 0
            local container = payload.container

            if #doors == 0 then
                print("[PassageNode] No doors to spawn")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            -- Initialize backpack for interactive doors
            getBackpackStub()

            local count = 0
            local typeCounts = {}

            for _, door in ipairs(doors) do
                local doorType = door.type or "auto"
                local profile = DOOR_TYPES[doorType] or DOOR_TYPES.auto
                typeCounts[doorType] = (typeCounts[doorType] or 0) + 1

                -- Size: width x height x depth (depth = wall gap between rooms)
                local depth = wt * 2
                local size
                if door.axis == 2 then
                    size = Vector3.new(door.width, depth, door.height)
                elseif door.widthAxis == 1 then
                    size = Vector3.new(door.width, door.height, depth)
                else
                    size = Vector3.new(depth, door.height, door.width)
                end

                local position = Vector3.new(
                    door.center[1],
                    door.center[2],
                    door.center[3]
                )

                local part = Instance.new("Part")
                part.Name = "Passage_" .. door.id
                part.Size = size
                part.Position = position
                part.Anchored = true
                part.CanCollide = true
                part.Transparency = profile.transparency
                part.Color = profile.color
                part.Material = Enum.Material.SmoothPlastic
                part.TopSurface = Enum.SurfaceType.Smooth
                part.BottomSurface = Enum.SurfaceType.Smooth

                if container then
                    part.Parent = container
                else
                    part.Parent = workspace
                end

                local doorInst = DoorInstance.new(part, door, {
                    autoClose = autoClose,
                    doorType = doorType,
                })

                -- Set up runtime behavior based on type
                if profile.proximityOpen then
                    setupProximityZone(doorInst, container)
                elseif profile.requiredItem then
                    setupProximityPrompt(doorInst)
                end

                count = count + 1
            end

            -- Summary log
            local parts = {}
            for t, c in pairs(typeCounts) do
                table.insert(parts, t .. "=" .. c)
            end
            table.sort(parts)
            print(string.format("[PassageNode] Spawned %d passages (%s) autoClose=%s",
                count, table.concat(parts, " "), tostring(autoClose)))
            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
