--[[
    IGW Phase 1 — BackpackStub
    Minimal server-side inventory for testing door interactions.
    Throwaway scaffolding — Phase 2 builds the real inventory system.

    API:
        BackpackStub.serverInit()              — create RemoteEvents (call once)
        BackpackStub.getSelectedItem(player)   — returns item name or nil
        BackpackStub.consumeItem(player, name) — decrements count, returns bool
        BackpackStub.selectSlot(player, index) — change selected slot
        BackpackStub.getInventory(player)      — { slots = {{name,count},...}, selected = N }
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackpackStub = {}

local _initialized = false
local _inventories = {}  -- player → { slots = {{name,count},...}, selected = N }

local DEFAULT_ITEMS = {
    { name = "key", count = 3 },
    { name = "weapon", count = 1 },
    { name = "bomb", count = 2 },
}

function BackpackStub.serverInit()
    if _initialized then return end
    _initialized = true

    local selectEvent = Instance.new("RemoteEvent")
    selectEvent.Name = "BackpackSelect"
    selectEvent.Parent = ReplicatedStorage

    local queryFunc = Instance.new("RemoteFunction")
    queryFunc.Name = "BackpackQuery"
    queryFunc.Parent = ReplicatedStorage

    selectEvent.OnServerEvent:Connect(function(player, slotIndex)
        BackpackStub.selectSlot(player, slotIndex)
    end)

    queryFunc.OnServerInvoke = function(player)
        return BackpackStub.getInventory(player)
    end

    Players.PlayerRemoving:Connect(function(player)
        _inventories[player] = nil
    end)

    print("[BackpackStub] Initialized — 3 default items per player")
end

local function ensureInventory(player)
    if _inventories[player] then return end
    local slots = {}
    for _, item in ipairs(DEFAULT_ITEMS) do
        table.insert(slots, { name = item.name, count = item.count })
    end
    _inventories[player] = { slots = slots, selected = 1 }
end

function BackpackStub.getSelectedItem(player)
    ensureInventory(player)
    local inv = _inventories[player]
    if not inv.selected then return nil end
    local slot = inv.slots[inv.selected]
    if slot and slot.count > 0 then
        return slot.name
    end
    return nil
end

function BackpackStub.consumeItem(player, itemName)
    ensureInventory(player)
    local inv = _inventories[player]
    for _, slot in ipairs(inv.slots) do
        if slot.name == itemName and slot.count > 0 then
            slot.count = slot.count - 1
            return true
        end
    end
    return false
end

function BackpackStub.selectSlot(player, slotIndex)
    ensureInventory(player)
    local inv = _inventories[player]
    if slotIndex >= 1 and slotIndex <= #inv.slots then
        inv.selected = slotIndex
    end
end

function BackpackStub.getInventory(player)
    ensureInventory(player)
    local inv = _inventories[player]
    return { slots = inv.slots, selected = inv.selected }
end

return BackpackStub
