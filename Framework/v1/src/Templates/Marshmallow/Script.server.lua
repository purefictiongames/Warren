-- Marshmallow.Script (Server)
-- Handles cooking logic when called by ZoneController

local tool = script.Parent
local cookFunction = tool:WaitForChild("cook")

-- Cooking state
local cookLevel = 0       -- 0 = raw, 100 = perfectly cooked, 150+ = burned
local maxCookLevel = 150

-- Initialize attribute for replication to client
tool:SetAttribute("CookLevel", cookLevel)

-- Handle cook callback from ZoneController
cookFunction.OnInvoke = function(state)
    -- state contains: deltaTime, tickRate, zoneCenter, zoneSize, (future: heat)
    local heat = state.heat or 10  -- default heat if not provided
    local dt = state.deltaTime or 0.5

    -- Apply heat based on time
    cookLevel = math.min(cookLevel + (heat * dt), maxCookLevel)
    tool:SetAttribute("CookLevel", cookLevel)

    -- Log cooking progress
    if cookLevel < 50 then
        print("Marshmallow: Warming up...", math.floor(cookLevel))
    elseif cookLevel < 100 then
        print("Marshmallow: Cooking nicely!", math.floor(cookLevel))
    elseif cookLevel < 120 then
        print("Marshmallow: Golden brown!", math.floor(cookLevel))
    else
        print("Marshmallow: Starting to burn!", math.floor(cookLevel))
    end

    return cookLevel
end

print("Marshmallow ready - CookLevel:", cookLevel)
