-- Marshmallow.Script (Server)
-- Handles cooking logic when called by ZoneController

local tool = script.Parent
local cookFunction = tool:WaitForChild("cook")

-- Cooking state
local toastLevel = 0       -- 0 = raw, 100 = perfectly cooked, 150+ = burned
local maxToastLevel = 150

-- Initialize attribute for replication to client
tool:SetAttribute("ToastLevel", toastLevel)

-- Handle cook callback from ZoneController
cookFunction.OnInvoke = function(state)
    -- state contains: deltaTime, tickRate, zoneCenter, zoneSize, (future: heat)
    local heat = state.heat or 10  -- default heat if not provided
    local dt = state.deltaTime or 0.5

    -- Apply heat based on time
    toastLevel = math.min(toastLevel + (heat * dt), maxToastLevel)
    tool:SetAttribute("ToastLevel", toastLevel)

    -- Log cooking progress
    if toastLevel < 50 then
        print("Marshmallow: Warming up...", math.floor(toastLevel))
    elseif toastLevel < 100 then
        print("Marshmallow: Cooking nicely!", math.floor(toastLevel))
    elseif toastLevel < 120 then
        print("Marshmallow: Golden brown!", math.floor(toastLevel))
    else
        print("Marshmallow: Starting to burn!", math.floor(toastLevel))
    end

    return toastLevel
end

print("Marshmallow ready - ToastLevel:", toastLevel)
