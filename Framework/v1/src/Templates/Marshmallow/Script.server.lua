--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Marshmallow.Script (Server)
-- Handles cooking logic when called by ZoneController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local System = require(ReplicatedStorage:WaitForChild("System.System"))

local tool = script.Parent
local cookFunction = tool:WaitForChild("cook")
local handle = tool:WaitForChild("Handle")

-- Cooking state
local toastLevel = 0       -- 0 = raw, 100 = blackened
local maxToastLevel = 100

-- Toast colors
local TOAST_COLORS = {
    raw = Color3.fromRGB(255, 250, 240),    -- Off-white
    golden = Color3.fromRGB(210, 160, 60),  -- Golden brown
    burnt = Color3.fromRGB(60, 30, 10),     -- Dark brown
    blackened = Color3.fromRGB(15, 10, 5),  -- Near black
}

-- Calculate color based on toast level (0-100, 25% per bracket)
local function getToastColor(level)
    if level <= 25 then
        local t = level / 25
        return TOAST_COLORS.raw:Lerp(TOAST_COLORS.golden, t)
    elseif level <= 50 then
        local t = (level - 25) / 25
        return TOAST_COLORS.golden:Lerp(TOAST_COLORS.burnt, t)
    elseif level <= 75 then
        local t = (level - 50) / 25
        return TOAST_COLORS.burnt:Lerp(TOAST_COLORS.blackened, t)
    else
        return TOAST_COLORS.blackened
    end
end

-- Update handle color
local function updateColor()
    handle.Color = getToastColor(toastLevel)
end

-- Initialize attribute and color
tool:SetAttribute("ToastLevel", toastLevel)
updateColor()

-- Handle cook callback from ZoneController
cookFunction.OnInvoke = function(state)
    -- state contains: deltaTime, tickRate, zoneCenter, zoneSize, (future: heat)
    local heat = state.heat or 10  -- default heat if not provided
    local dt = state.deltaTime or 0.5

    -- Apply heat based on time
    toastLevel = math.min(toastLevel + (heat * dt), maxToastLevel)
    tool:SetAttribute("ToastLevel", toastLevel)
    updateColor()

    -- Log cooking progress
    if toastLevel < 50 then
        System.Debug:Message("Marshmallow", "Warming up...", math.floor(toastLevel))
    elseif toastLevel < 100 then
        System.Debug:Message("Marshmallow", "Cooking nicely!", math.floor(toastLevel))
    elseif toastLevel < 120 then
        System.Debug:Message("Marshmallow", "Golden brown!", math.floor(toastLevel))
    else
        System.Debug:Message("Marshmallow", "Starting to burn!", math.floor(toastLevel))
    end

    return toastLevel
end

System.Debug:Message("Marshmallow", "Ready - ToastLevel:", toastLevel)
