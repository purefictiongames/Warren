-- Backpack.Script (Server)
-- Handles backpack events: item added, force drop, force pickup

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local itemAdded = ReplicatedStorage:WaitForChild("Backpack.ItemAdded")
local forceItemDrop = ReplicatedStorage:WaitForChild("Backpack.ForceItemDrop")
local forceItemPickup = ReplicatedStorage:WaitForChild("Backpack.ForceItemPickup")

-- Watch a player's backpack and fire events when items are added
local function watchBackpack(player)
    local backpack = player:WaitForChild("Backpack")

    backpack.ChildAdded:Connect(function(item)
        itemAdded:Fire({
            player = player,
            item = item,
        })
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
    print("Backpack: Dropped", item.Name, "for", player.Name)
end

-- Listen for force drop requests
forceItemDrop.Event:Connect(function(data)
    local player = data.player
    local item = data.item

    if player and item then
        dropItem(player, item)
    end
end)

-- Pick up an item into player's backpack
local function pickupItem(player, item)
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then
        return
    end

    item.Parent = backpack
    print("Backpack: Picked up", item.Name, "for", player.Name)
end

-- Listen for force pickup requests
forceItemPickup.Event:Connect(function(data)
    local player = data.player
    local item = data.item

    if player and item then
        pickupItem(player, item)
    end
end)

-- Setup player
local function setupPlayer(player)
    watchBackpack(player)
end

-- Handle existing and new players
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)

print("Backpack.Script loaded")
