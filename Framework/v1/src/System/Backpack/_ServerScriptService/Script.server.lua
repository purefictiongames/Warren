-- Backpack.Script (Server)
-- Handles backpack events: item added, force drop, force pickup

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local itemAdded = ReplicatedStorage:WaitForChild("Backpack.ItemAdded", 10)
local forceItemDrop = ReplicatedStorage:WaitForChild("Backpack.ForceItemDrop", 10)
local forceItemPickup = ReplicatedStorage:WaitForChild("Backpack.ForceItemPickup", 10)

if not itemAdded then warn("Backpack: ItemAdded event not found!") end
if not forceItemDrop then warn("Backpack: ForceItemDrop event not found!") end
if not forceItemPickup then warn("Backpack: ForceItemPickup event not found!") end

-- Connect ChildAdded on a backpack instance
local function connectBackpackEvents(player, backpack)
    backpack.ChildAdded:Connect(function(item)
        if itemAdded then
            itemAdded:Fire({
                player = player,
                item = item,
            })
        end
    end)
end

-- Watch a player's backpack and fire events when items are added
-- Re-watches on character respawn since Backpack instance can change
local function watchBackpack(player)
    -- Watch current backpack (wait if not ready yet)
    local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 10)
    if backpack then
        connectBackpackEvents(player, backpack)
    end

    -- Re-watch when character spawns (Backpack gets recreated)
    player.CharacterAdded:Connect(function()
        task.wait(0.1) -- Let Backpack initialize
        local newBackpack = player:FindFirstChild("Backpack")
        if newBackpack then
            connectBackpackEvents(player, newBackpack)
        end
    end)
end

-- Drop an item on the ground near the player
local function dropItem(player, item)
    local character = player.Character
    if not character then
        item:Destroy()
        return
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        item:Destroy()
        return
    end

    -- Find the item's handle to position it
    local handle = item:FindFirstChild("Handle")
    if handle then
        -- Drop slightly in front of player, on the ground
        local dropPos = rootPart.Position + rootPart.CFrame.LookVector * 3
        dropPos = Vector3.new(dropPos.X, rootPart.Position.Y - 2, dropPos.Z)
        handle.CFrame = CFrame.new(dropPos)
    end

    item.Parent = Workspace
end

-- Listen for force drop requests
if forceItemDrop then
    forceItemDrop.Event:Connect(function(data)
        local player = data.player
        local item = data.item

        if player and item then
            dropItem(player, item)
        end
    end)
else
    warn("Backpack: Cannot listen for force drop - event not found")
end

-- Pick up an item into player's backpack
local function pickupItem(player, item)
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then
        return
    end

    item.Parent = backpack
end

-- Listen for force pickup requests
if forceItemPickup then
    forceItemPickup.Event:Connect(function(data)
        local player = data.player
        local item = data.item

        if player and item then
            pickupItem(player, item)
        end
    end)
else
    warn("Backpack: Cannot listen for force pickup - event not found")
end

-- Track which players we've set up
local trackedPlayers = {}

-- Handle existing and new players
for _, player in ipairs(Players:GetPlayers()) do
    trackedPlayers[player] = true
    watchBackpack(player)
end

Players.PlayerAdded:Connect(function(player)
    if not trackedPlayers[player] then
        trackedPlayers[player] = true
        watchBackpack(player)
    end
end)

-- Fallback: poll for untracked players (in case PlayerAdded doesn't fire)
task.spawn(function()
    while true do
        task.wait(1)
        for _, player in ipairs(Players:GetPlayers()) do
            if not trackedPlayers[player] then
                trackedPlayers[player] = true
                watchBackpack(player)
            end
        end
    end
end)

-- Clean up when players leave
Players.PlayerRemoving:Connect(function(player)
    trackedPlayers[player] = nil
end)

print("Backpack.Script loaded")
