-- RoastingStick.Script (Server)
-- Auto-equips roasting stick on game start, watches for marshmallows to mount

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function setupRoastingStick()
    local templates = ReplicatedStorage:WaitForChild("Templates")
    local stickTemplate = templates:WaitForChild("RoastingStick")

    -- Mount marshmallow onto player's equipped stick
    local function mountMarshmallow(player, marshmallow)
        local character = player.Character
        if not character then return false end

        local stick = character:FindFirstChild("RoastingStick")
        if not stick then
            -- Stick not equipped, leave marshmallow in backpack
            return false
        end

        -- Check if stick already has a marshmallow
        if stick:FindFirstChild("Marshmallow") then
            return false
        end

        local stickHandle = stick:FindFirstChild("Handle")
        if not stickHandle then return false end

        local marshmallowHandle = marshmallow:FindFirstChild("Handle")
        if marshmallowHandle then
            -- Position at tip of stick
            local tipOffset = stickHandle.Size.Y / 2 + (marshmallowHandle.Size.Y / 2)
            marshmallowHandle.CFrame = stickHandle.CFrame * CFrame.new(0, tipOffset, 0)

            -- Weld marshmallow to stick
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = stickHandle
            weld.Part1 = marshmallowHandle
            weld.Parent = marshmallowHandle
        end

        -- Parent marshmallow to stick (removes from backpack)
        marshmallow.Parent = stick

        print("RoastingStick: Mounted marshmallow for", player.Name)
        return true
    end

    -- Watch backpack for new marshmallows
    local function watchBackpack(player)
        local backpack = player:WaitForChild("Backpack")

        backpack.ChildAdded:Connect(function(child)
            if child.Name == "Marshmallow" and child:IsA("Tool") then
                -- Small delay to let it fully load
                task.wait(0.1)
                mountMarshmallow(player, child)
            end
        end)
    end

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
        watchBackpack(player)

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
