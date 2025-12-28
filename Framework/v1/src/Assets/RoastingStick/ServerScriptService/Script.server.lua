-- RoastingStick.Script (Server)
-- Auto-equips roasting stick on spawn, mounts marshmallows when received

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function setupRoastingStick()
    local templates = ReplicatedStorage:WaitForChild("Templates")
    local stickTemplate = templates:WaitForChild("RoastingStick")

    -- Get backpack events
    local forceItemDrop = ReplicatedStorage:WaitForChild("Backpack.ForceItemDrop")

    -- Mount marshmallow onto player's equipped stick
    local function mountMarshmallow(player, marshmallow)
        local character = player.Character
        if not character then
            return false, "no_character"
        end

        local stick = character:FindFirstChild("RoastingStick")
        if not stick then
            return false, "stick_not_equipped"
        end

        -- One marshmallow at a time rule
        if stick:FindFirstChild("Marshmallow") then
            return false, "already_mounted"
        end

        local stickHandle = stick:FindFirstChild("Handle")
        if not stickHandle then
            return false, "no_stick_handle"
        end

        local marshmallowHandle = marshmallow:FindFirstChild("Handle")
        if not marshmallowHandle then
            return false, "no_marshmallow_handle"
        end

        -- Position at tip of stick (cylinder length is along X axis)
        -- Offset along +X to reach the tip, center on YZ plane
        local tipOffset = stickHandle.Size.X / 2 + marshmallowHandle.Size.Y / 2
        marshmallowHandle.CFrame = stickHandle.CFrame * CFrame.new(tipOffset, 0, 0)

        -- Weld marshmallow to stick
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = stickHandle
        weld.Part1 = marshmallowHandle
        weld.Parent = marshmallowHandle

        -- Parent marshmallow to stick (removes from backpack)
        marshmallow.Parent = stick

        print("RoastingStick: Mounted marshmallow for", player.Name)
        return true, "mounted"
    end

    -- Listen for items added to player backpacks
    local itemAdded = ReplicatedStorage:WaitForChild("Backpack.ItemAdded")
    itemAdded.Event:Connect(function(data)
        local player = data.player
        local item = data.item

        -- Only handle marshmallows
        if item.Name ~= "Marshmallow" then return end

        task.wait(0.1) -- Let item fully load
        local success, reason = mountMarshmallow(player, item)

        -- If mount failed, force drop the item
        if not success then
            print("RoastingStick: Mount failed -", reason, "- dropping item")
            forceItemDrop:Fire({
                player = player,
                item = item,
            })
        end
    end)

    -- Give player a roasting stick and equip it
    local function giveStick(player)
        local character = player.Character
        local backpack = player:FindFirstChild("Backpack")

        -- Check if player already has one
        local hasStick = false
        if character then
            hasStick = character:FindFirstChild("RoastingStick") ~= nil
        end
        if not hasStick and backpack then
            hasStick = backpack:FindFirstChild("RoastingStick") ~= nil
        end

        if hasStick then return end

        -- Clone and give to player
        local stick = stickTemplate:Clone()

        -- Set grip so cylinder points forward (length is along X axis)
        stick.GripForward = Vector3.new(1, 0, 0)
        stick.GripUp = Vector3.new(0, 1, 0)


        stick.Parent = backpack

        -- Auto-equip
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then
                humanoid:EquipTool(stick)
            end
        end

        print("RoastingStick: Gave stick to", player.Name)
    end

    -- Setup player
    local function setupPlayer(player)
        player.CharacterAdded:Connect(function()
            task.wait(0.5)
            giveStick(player)
        end)

        if player.Character then
            giveStick(player)
        end
    end

    -- Listen for round reset to re-give sticks
    local timerExpired = ReplicatedStorage:WaitForChild("GlobalTimer.TimerExpired")
    timerExpired.Event:Connect(function()
        task.wait(3.5)  -- After Orchestrator's reset delay
        for _, player in ipairs(Players:GetPlayers()) do
            giveStick(player)
        end
    end)

    -- Setup existing and new players
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end

    Players.PlayerAdded:Connect(setupPlayer)

    print("RoastingStick: Setup complete")
end

setupRoastingStick()

print("RoastingStick.Script loaded")
