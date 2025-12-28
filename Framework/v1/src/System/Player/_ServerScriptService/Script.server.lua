-- Player.Script (Server)
-- Handles player-level system concerns

local Players = game:GetService("Players")

-- Setup player
local function setupPlayer(player)
    -- Player-specific setup goes here
end

-- Handle existing and new players
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)

print("Player.Script loaded")
