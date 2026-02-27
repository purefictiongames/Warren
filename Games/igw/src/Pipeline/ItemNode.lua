--[[
    IGW Phase 2 Pipeline — ItemNode
    Spawns collectible item pickups in dungeon rooms.

    Pipeline signal: onSpawnItems(payload) — reads payload.rooms and payload.spawn,
    places item Parts on room floors. Items bob and spin for visibility.

    Pickup: player walks over item → Touched event → adds to backpack → item destroyed.
    If backpack is full, item stays in the world.

    Item types placed based on door types present (keys for keyed doors, etc.)
    plus random scatter for variety.
--]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local _components = script.Parent.Parent

--------------------------------------------------------------------------------
-- ITEM TYPE DEFINITIONS
--------------------------------------------------------------------------------

local ITEM_TYPES = {
    key = {
        color = Color3.fromRGB(80, 120, 220),
        material = Enum.Material.SmoothPlastic,
        size = Vector3.new(1.5, 1.5, 1.5),
        shape = Enum.PartType.Block,
    },
    weapon = {
        color = Color3.fromRGB(220, 60, 60),
        material = Enum.Material.Metal,
        size = Vector3.new(2.5, 1, 0.8),
        shape = Enum.PartType.Block,
    },
    bomb = {
        color = Color3.fromRGB(220, 140, 40),
        material = Enum.Material.SmoothPlastic,
        size = Vector3.new(2, 2, 2),
        shape = Enum.PartType.Ball,
    },
}

--------------------------------------------------------------------------------
-- ITEM INSTANCE — runtime state for a world pickup
--------------------------------------------------------------------------------

local ItemInstance = {}
ItemInstance.__index = ItemInstance

local _registry = {}  -- itemId → ItemInstance

function ItemInstance.new(part, itemType, itemId)
    local self = setmetatable({}, ItemInstance)
    self.id = itemId
    self.part = part
    self.itemType = itemType
    self.pickedUp = false
    self._connections = {}
    _registry[itemId] = self
    return self
end

function ItemInstance:pickup(player, backpack)
    if self.pickedUp then return false end
    if not backpack.canAdd(player, self.itemType) then return false end

    self.pickedUp = true
    backpack.addItem(player, self.itemType, 1)
    self:destroy()
    return true
end

function ItemInstance:destroy()
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    self._connections = {}
    _registry[self.id] = nil
    if self.part and self.part.Parent then
        self.part:Destroy()
    end
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local _backpack = nil

local function getBackpack()
    if _backpack then return _backpack end
    local mod = _components:FindFirstChild("Backpack")
    if mod then
        _backpack = require(mod)
        _backpack.serverInit()
    end
    return _backpack
end

--- Pick a random floor position inside a room
local function randomFloorPos(room, rng)
    local pos = room.position
    local dims = room.dims
    local margin = 4  -- stay away from walls
    local halfW = math.max(1, dims[1] / 2 - margin)
    local halfD = math.max(1, dims[3] / 2 - margin)

    local x = pos[1] + (rng:NextNumber() * 2 - 1) * halfW
    local y = pos[2] - dims[2] / 2 + 2  -- 2 studs above floor
    local z = pos[3] + (rng:NextNumber() * 2 - 1) * halfD

    return Vector3.new(x, y, z)
end

--- Create a bobbing + spinning animation on a part
local function animatePickup(part)
    local basePos = part.Position
    local bobHeight = 1.5
    local duration = 2

    -- Bob up
    local upInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut,
        -1, true)  -- -1 = infinite repeat, true = reverses
    local upTween = TweenService:Create(part, upInfo, {
        Position = basePos + Vector3.new(0, bobHeight, 0),
    })
    upTween:Play()

    -- Spin via CFrame (use a looping script approach since TweenService
    -- can't smoothly rotate continuously). We'll use a simple Heartbeat.
    local RunService = game:GetService("RunService")
    local spinSpeed = math.rad(90)  -- 90 deg/sec
    local conn = RunService.Heartbeat:Connect(function(dt)
        if not part.Parent then return end
        part.CFrame = part.CFrame * CFrame.Angles(0, spinSpeed * dt, 0)
    end)

    return conn, upTween
end

--- Create an item pickup Part + Touched zone
local function createPickup(itemType, position, itemId, container)
    local profile = ITEM_TYPES[itemType]
    if not profile then
        warn("[ItemNode] Unknown item type: " .. tostring(itemType))
        return nil
    end

    local part = Instance.new("Part")
    part.Name = "Item_" .. itemType .. "_" .. itemId
    part.Shape = profile.shape
    part.Size = profile.size
    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0
    part.Color = profile.color
    part.Material = profile.material
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.CastShadow = false

    if container then
        part.Parent = container
    else
        part.Parent = workspace
    end

    local itemInst = ItemInstance.new(part, itemType, itemId)

    -- Animate
    local spinConn, bobTween = animatePickup(part)
    table.insert(itemInst._connections, spinConn)

    -- Pickup zone (slightly larger than the item)
    local zone = Instance.new("Part")
    zone.Name = "ItemZone_" .. itemId
    zone.Size = Vector3.new(6, 6, 6)
    zone.Position = position
    zone.Anchored = true
    zone.CanCollide = false
    zone.Transparency = 1
    zone.CanQuery = false
    zone.Parent = container or workspace

    local backpack = getBackpack()

    local touchConn = zone.Touched:Connect(function(hit)
        if itemInst.pickedUp then return end
        local player = Players:GetPlayerFromCharacter(hit.Parent)
        if not player then return end
        if not backpack then return end

        if itemInst:pickup(player, backpack) then
            zone:Destroy()
            if bobTween then bobTween:Cancel() end
        end
    end)
    table.insert(itemInst._connections, touchConn)

    return itemInst
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

local ItemAPI = {}

function ItemAPI.getItem(itemId)
    return _registry[itemId]
end

function ItemAPI.getAllItems()
    return _registry
end

function ItemAPI.getItemCount()
    local count = 0
    for _ in pairs(_registry) do count = count + 1 end
    return count
end

--------------------------------------------------------------------------------
-- PIPELINE NODE
--------------------------------------------------------------------------------

return {
    name = "ItemNode",
    domain = "server",

    API = ItemAPI,
    ITEM_TYPES = ITEM_TYPES,

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self)
            for _, item in pairs(_registry) do
                item:destroy()
            end
        end,
    },

    In = {
        onSpawnItems = function(self, payload)
            local Dom = _G.Warren.Dom
            local rooms = payload.rooms or {}
            local container = payload.container

            -- Initialize backpack system
            getBackpack()

            local rng = Random.new(payload.seed or os.time())
            local itemId = 1
            local placed = 0
            local resolverCount = 0

            -- Read resolver items from DOM room nodes (baked by DependencyResolver)
            local root = Dom and Dom.getRoot()
            local hasResolverItems = false

            if root then
                for _, child in ipairs(Dom.getChildren(root)) do
                    local roomId = Dom.getAttribute(child, "RoomId")
                    local resolverItems = Dom.getAttribute(child, "ResolverItems")
                    if roomId and resolverItems then
                        hasResolverItems = true
                        local room = rooms[roomId] or rooms[tostring(roomId)]
                        if room then
                            for _, itemType in ipairs(resolverItems) do
                                local pos = randomFloorPos(room, rng)
                                createPickup(itemType, pos, itemId, container)
                                itemId = itemId + 1
                                placed = placed + 1
                                resolverCount = resolverCount + 1
                            end
                        end
                    end
                end
            end

            if hasResolverItems then
                -- Bonus scatter (reduced density — resolver handles critical items)
                local scatterTypes = { "key", "weapon", "bomb" }
                for _, room in pairs(rooms) do
                    if rng:NextNumber() < 0.2 then
                        local itemType = scatterTypes[rng:NextInteger(1, #scatterTypes)]
                        local pos = randomFloorPos(room, rng)
                        createPickup(itemType, pos, itemId, container)
                        itemId = itemId + 1
                        placed = placed + 1
                    end
                end

                print(string.format("[ItemNode] Spawned %d items (%d resolver, %d bonus)",
                    placed, resolverCount, placed - resolverCount))
            else
                --------------------------------------------------------
                -- Fallback: no DOM resolver data (backward compat)
                --------------------------------------------------------

                local spawn = payload.spawn
                local spawnPos = spawn and spawn.position or { 0, 0, 0 }
                local roomList = {}
                for id, room in pairs(rooms) do
                    local dx = room.position[1] - spawnPos[1]
                    local dz = room.position[3] - spawnPos[3]
                    local dist = math.sqrt(dx * dx + dz * dz)
                    table.insert(roomList, { id = id, room = room, dist = dist })
                end
                table.sort(roomList, function(a, b) return a.dist < b.dist end)

                local guaranteedTypes = { "key", "weapon", "bomb", "key", "bomb", "weapon" }
                for i, itemType in ipairs(guaranteedTypes) do
                    local roomEntry = roomList[math.min(i + 1, #roomList)]
                    if roomEntry then
                        local pos = randomFloorPos(roomEntry.room, rng)
                        createPickup(itemType, pos, itemId, container)
                        itemId = itemId + 1
                        placed = placed + 1
                    end
                end

                local scatterTypes = { "key", "weapon", "bomb" }
                for i = #guaranteedTypes + 2, #roomList do
                    local roomEntry = roomList[i]
                    if roomEntry and rng:NextNumber() < 0.45 then
                        local itemType = scatterTypes[rng:NextInteger(1, #scatterTypes)]
                        local pos = randomFloorPos(roomEntry.room, rng)
                        createPickup(itemType, pos, itemId, container)
                        itemId = itemId + 1
                        placed = placed + 1
                    end
                end

                print(string.format("[ItemNode] Spawned %d items (fallback) across %d rooms",
                    placed, #roomList))
            end

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
