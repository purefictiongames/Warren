--[[
    IGW Phase 2 — Backpack (Server-Side Inventory)
    Real inventory system replacing BackpackStub.

    4-slot backpack. Items picked up from the world fill slots.
    Stackable items (key, bomb) share a slot; each pickup increments count.
    Players start with an empty backpack.

    API:
        Backpack.serverInit()                    — create RemoteEvents (call once)
        Backpack.addItem(player, name, count)    — add to backpack, returns bool
        Backpack.canAdd(player, name)            — check if item fits
        Backpack.getSelectedItem(player)         — returns item name or nil
        Backpack.consumeItem(player, name)       — decrement count, returns bool
        Backpack.dropItem(player, slotIndex)     — remove 1 from slot, returns {name,count} or nil
        Backpack.selectSlot(player, index)       — change selected slot
        Backpack.getInventory(player)            — { slots, capacity, selected }
        Backpack.getSlotCount(player)            — number of occupied slots
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Backpack = {}

local _initialized = false
local _inventories = {}  -- player → { slots = {}, capacity = N, selected = N }
local _updateEvent = nil -- fires to client on inventory change

local CAPACITY = 4

--------------------------------------------------------------------------------
-- ITEM DEFINITIONS
--------------------------------------------------------------------------------

local ITEM_DEFS = {
    key     = { stackable = true,  maxStack = 99 },
    weapon  = { stackable = true,  maxStack = 99 },
    bomb    = { stackable = true,  maxStack = 99 },
}

--------------------------------------------------------------------------------
-- INTERNALS
--------------------------------------------------------------------------------

local function ensureInventory(player)
    if _inventories[player] then return end
    _inventories[player] = {
        slots = {},       -- array of { name = string, count = number } or nil gaps
        capacity = CAPACITY,
        selected = 1,
    }
end

local function notifyClient(player)
    if _updateEvent then
        _updateEvent:FireClient(player, Backpack.getInventory(player))
    end
end

--- Find slot index holding itemName, or nil
local function findSlot(inv, itemName)
    for i, slot in ipairs(inv.slots) do
        if slot and slot.name == itemName then
            return i
        end
    end
    return nil
end

--- Find first empty slot index, or nil
local function findEmptySlot(inv)
    -- Check existing array for nil gaps
    for i = 1, inv.capacity do
        if not inv.slots[i] then
            return i
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Backpack.serverInit()
    if _initialized then return end
    _initialized = true

    local selectEvent = Instance.new("RemoteEvent")
    selectEvent.Name = "BackpackSelect"
    selectEvent.Parent = ReplicatedStorage

    local queryFunc = Instance.new("RemoteFunction")
    queryFunc.Name = "BackpackQuery"
    queryFunc.Parent = ReplicatedStorage

    _updateEvent = Instance.new("RemoteEvent")
    _updateEvent.Name = "BackpackUpdate"
    _updateEvent.Parent = ReplicatedStorage

    local dropEvent = Instance.new("RemoteEvent")
    dropEvent.Name = "BackpackDrop"
    dropEvent.Parent = ReplicatedStorage

    selectEvent.OnServerEvent:Connect(function(player, slotIndex)
        Backpack.selectSlot(player, slotIndex)
    end)

    dropEvent.OnServerEvent:Connect(function(player, slotIndex)
        Backpack.dropItem(player, slotIndex)
    end)

    queryFunc.OnServerInvoke = function(player)
        return Backpack.getInventory(player)
    end

    Players.PlayerRemoving:Connect(function(player)
        _inventories[player] = nil
    end)

    print("[Backpack] Initialized — capacity " .. CAPACITY)
end

function Backpack.canAdd(player, itemName)
    ensureInventory(player)
    local inv = _inventories[player]
    local def = ITEM_DEFS[itemName]

    -- If stackable and we already have a slot with this item
    if def and def.stackable then
        local idx = findSlot(inv, itemName)
        if idx then
            return inv.slots[idx].count < def.maxStack
        end
    end

    -- Need an empty slot
    return findEmptySlot(inv) ~= nil
end

function Backpack.addItem(player, itemName, count)
    count = count or 1
    ensureInventory(player)
    local inv = _inventories[player]
    local def = ITEM_DEFS[itemName]

    -- Try stacking into existing slot
    if def and def.stackable then
        local idx = findSlot(inv, itemName)
        if idx then
            inv.slots[idx].count = math.min(
                inv.slots[idx].count + count,
                def.maxStack
            )
            notifyClient(player)
            return true
        end
    end

    -- Find empty slot
    local emptyIdx = findEmptySlot(inv)
    if not emptyIdx then
        return false  -- backpack full
    end

    inv.slots[emptyIdx] = { name = itemName, count = count }

    -- Auto-select first item if nothing selected
    if not inv.slots[inv.selected] then
        inv.selected = emptyIdx
    end

    notifyClient(player)
    return true
end

function Backpack.getSelectedItem(player)
    ensureInventory(player)
    local inv = _inventories[player]
    if not inv.selected then return nil end
    local slot = inv.slots[inv.selected]
    if slot and slot.count > 0 then
        return slot.name
    end
    return nil
end

function Backpack.consumeItem(player, itemName)
    ensureInventory(player)
    local inv = _inventories[player]
    local idx = findSlot(inv, itemName)
    if not idx then return false end

    local slot = inv.slots[idx]
    if slot.count <= 0 then return false end

    slot.count = slot.count - 1
    if slot.count <= 0 then
        inv.slots[idx] = nil
    end

    notifyClient(player)
    return true
end

function Backpack.dropItem(player, slotIndex)
    ensureInventory(player)
    local inv = _inventories[player]
    local slot = inv.slots[slotIndex]
    if not slot then return nil end

    local dropped = { name = slot.name, count = 1 }
    slot.count = slot.count - 1
    if slot.count <= 0 then
        inv.slots[slotIndex] = nil
    end

    notifyClient(player)
    return dropped
end

function Backpack.selectSlot(player, slotIndex)
    ensureInventory(player)
    local inv = _inventories[player]
    if slotIndex >= 1 and slotIndex <= inv.capacity then
        inv.selected = slotIndex
        notifyClient(player)
    end
end

function Backpack.getInventory(player)
    ensureInventory(player)
    local inv = _inventories[player]
    -- Return a clean copy (nil slots become explicit for serialization)
    local slots = {}
    for i = 1, inv.capacity do
        slots[i] = inv.slots[i] or false  -- false = empty slot
    end
    return { slots = slots, capacity = inv.capacity, selected = inv.selected }
end

function Backpack.getSlotCount(player)
    ensureInventory(player)
    local inv = _inventories[player]
    local count = 0
    for i = 1, inv.capacity do
        if inv.slots[i] then count = count + 1 end
    end
    return count
end

return Backpack
