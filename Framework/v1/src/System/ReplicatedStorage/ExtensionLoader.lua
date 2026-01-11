--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- ExtensionLoader.ModuleScript
-- Utility for loading extension modules from path strings
-- Used by bootstrap to bind game-specific extensions to Lib modules

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExtensionLoader = {}

--[[
    Load an extension module from a dot-separated path

    @param extensionPath string - Path like "Game.MarshmallowBag.Extension"
    @return table|nil - The extension module or nil if not found
]]
function ExtensionLoader.load(extensionPath)
    if not extensionPath or extensionPath == "" then
        return nil
    end

    local parts = string.split(extensionPath, ".")
    local current = ReplicatedStorage

    for _, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then
            return nil
        end
    end

    if current:IsA("ModuleScript") then
        local success, ext = pcall(require, current)
        if success then
            return ext
        else
            warn("[ExtensionLoader] Failed to require extension:", extensionPath, "-", tostring(ext))
        end
    end

    return nil
end

--[[
    Check if an extension exists at the given path without loading it

    @param extensionPath string - Path like "Game.MarshmallowBag.Extension"
    @return boolean - True if extension exists
]]
function ExtensionLoader.exists(extensionPath)
    if not extensionPath or extensionPath == "" then
        return false
    end

    local parts = string.split(extensionPath, ".")
    local current = ReplicatedStorage

    for _, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then
            return false
        end
    end

    return current:IsA("ModuleScript")
end

return ExtensionLoader
