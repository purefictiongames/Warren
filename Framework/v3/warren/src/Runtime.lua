--[[
    Warren Framework v3.0
    Runtime.lua - Runtime Context Detection

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Detects whether Warren is running on Roblox or Lune and exposes
    context flags used by all other modules for conditional loading.

    This module MUST have zero dependencies on any Roblox or Lune API
    beyond the globals used for detection.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Runtime = require(path.to.Runtime)

    if Runtime.isRoblox then
        -- Roblox-only code
    end

    if Runtime.isLune then
        -- Lune-only code
    end
    ```
--]]

local Runtime = {}

--------------------------------------------------------------------------------
-- DETECTION
--------------------------------------------------------------------------------

-- Roblox exposes a global `game` of type "Instance".
-- Lune does not. This is the simplest reliable discriminator.
local _isRoblox = (function()
    local ok, result = pcall(function()
        return typeof(game) == "Instance"
    end)
    return ok and result == true
end)()

Runtime.context = _isRoblox and "roblox" or "lune"
Runtime.isRoblox = _isRoblox
Runtime.isLune = not _isRoblox

return Runtime
