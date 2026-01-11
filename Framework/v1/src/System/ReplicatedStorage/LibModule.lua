--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- LibModule.ModuleScript
-- Base class for Lib modules with extension hook support
-- Provides a standardized pattern for binding game-specific extensions to generic library code

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lazy-load Debug to avoid circular dependencies during early boot
local Debug = nil
local function getDebug()
    if not Debug then
        local debugModule = ReplicatedStorage:FindFirstChild("System.Debug")
        if debugModule then
            Debug = require(debugModule)
        end
    end
    return Debug
end

local LibModule = {}
LibModule.__index = LibModule

--[[
    Create a new LibModule instance

    @param moduleName string - Name of the module (for logging)
    @return LibModule instance
]]
function LibModule.new(moduleName)
    local self = setmetatable({}, LibModule)
    self._moduleName = moduleName or "LibModule"
    self._hooks = {}
    self._private = {}
    return self
end

--[[
    Internal hook caller with pcall protection

    Calls a hook function if it exists, passing (private, self, ...args)
    Returns nil if hook doesn't exist or throws

    @param name string - Hook name
    @param ... any - Arguments to pass to hook
    @return any - Hook return value or nil
]]
function LibModule:_callHook(name, ...)
    local hook = self._hooks[name]
    if not hook then
        return nil
    end

    local success, result = pcall(hook, self._private, self, ...)
    if not success then
        local debug = getDebug()
        if debug then
            debug:Warn(self._moduleName, "Hook '" .. name .. "' failed:", tostring(result))
        else
            warn("[" .. self._moduleName .. "] Hook '" .. name .. "' failed: " .. tostring(result))
        end
        return nil
    end
    return result
end

--[[
    Bind extension hooks to this module

    Extensions are tables with optional hook functions:
    - init(private, self, model) - Called during module initialization
    - start(private, self) - Called when module starts
    - stop(private, self) - Called when module stops
    - reset(private, self) - Called on reset
    - onInput(private, self, message) - Intercept incoming messages
    - onOutput(private, self, message) - Intercept outgoing messages

    Each hook receives:
    - private: Mutable table of private state (can add/modify)
    - self: The LibModule instance (access public methods)
    - Additional hook-specific arguments

    @param extensions table - Table of hook functions
]]
function LibModule:bind(extensions)
    if not extensions then
        return
    end

    local debug = getDebug()
    local boundCount = 0

    for name, fn in pairs(extensions) do
        if type(fn) == "function" then
            self._hooks[name] = fn
            boundCount = boundCount + 1
            if debug then
                debug:Verbose(self._moduleName, "Bound hook:", name)
            end
        end
    end

    if debug and boundCount > 0 then
        debug:Message(self._moduleName, "Bound", boundCount, "extension hooks")
    end
end

--[[
    Check if a hook is bound

    @param name string - Hook name
    @return boolean
]]
function LibModule:hasHook(name)
    return self._hooks[name] ~= nil
end

--[[
    Get the private state table

    Used by subclasses to access/initialize private state
    Extensions can add their own state to this table

    @return table - Private state table
]]
function LibModule:getPrivate()
    return self._private
end

--------------------------------------------------------------------------------
-- LIFECYCLE HOOKS
--------------------------------------------------------------------------------

--[[
    Initialize the module

    Called during INIT stage with the deployed model
    Extensions can add state to private table

    @param model Instance - The deployed model in RuntimeAssets
]]
function LibModule:_init(model)
    self._private.model = model
    self:_callHook("init", model)
end

--[[
    Start the module

    Called during START stage
    Extensions can begin behaviors
]]
function LibModule:_start()
    self:_callHook("start")
end

--[[
    Stop the module

    Called on game end or cleanup
    Extensions should pause behaviors
]]
function LibModule:_stop()
    self:_callHook("stop")
end

--[[
    Reset the module

    Called on round reset
    Extensions should reset game-specific state
]]
function LibModule:_reset()
    self:_callHook("reset")
end

--------------------------------------------------------------------------------
-- MESSAGE INTERCEPTION HOOKS
--------------------------------------------------------------------------------

--[[
    Handle incoming message with optional extension interception

    Extensions can:
    - Return nil: Pass message through unchanged
    - Return false: Block the message entirely
    - Return table: Replace with modified message

    @param message table - Incoming message
    @return table|nil - Processed message or nil if blocked
]]
function LibModule:_handleInput(message)
    local result = self:_callHook("onInput", message)

    if result == false then
        -- Extension blocked the message
        return nil
    end

    if result and type(result) == "table" then
        -- Extension modified the message
        return result
    end

    -- Pass through unchanged
    return message
end

--[[
    Handle outgoing message with optional extension interception

    Extensions can:
    - Return nil: Pass message through unchanged
    - Return false: Block the message entirely
    - Return table: Replace with modified message

    @param message table - Outgoing message
    @return table|nil - Processed message or nil if blocked
]]
function LibModule:_handleOutput(message)
    local result = self:_callHook("onOutput", message)

    if result == false then
        -- Extension blocked the message
        return nil
    end

    if result and type(result) == "table" then
        -- Extension modified the message
        return result
    end

    -- Pass through unchanged
    return message
end

--------------------------------------------------------------------------------
-- UTILITY METHODS
--------------------------------------------------------------------------------

--[[
    Get the module name

    @return string
]]
function LibModule:getName()
    return self._moduleName
end

--[[
    Get the deployed model

    @return Instance|nil
]]
function LibModule:getModel()
    return self._private.model
end

return LibModule
