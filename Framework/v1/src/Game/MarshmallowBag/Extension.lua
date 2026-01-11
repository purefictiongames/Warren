--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- MarshmallowBag Extension
-- Game-specific extension for the Dispenser Lib module
-- Adds marshmallow-specific behavior and messaging

return {
    --[[
        Initialize game-specific state
        Called during module initialization with the deployed model

        @param private table - Mutable private state table
        @param self LibModule - The Dispenser module instance
        @param model Instance - The deployed model in RuntimeAssets
    ]]
    init = function(private, self, model)
        -- Game-specific state
        private.totalDispensed = 0
        private.lastDispenseTime = 0
    end,

    --[[
        Start game-specific behaviors
        Called after all modules are initialized

        @param private table - Mutable private state table
        @param self LibModule - The Dispenser module instance
    ]]
    start = function(private, self)
        -- Game-specific startup logic
    end,

    --[[
        Reset game-specific state
        Called on round reset

        @param private table - Mutable private state table
        @param self LibModule - The Dispenser module instance
    ]]
    reset = function(private, self)
        private.totalDispensed = 0
        private.lastDispenseTime = 0
    end,

    --[[
        Intercept incoming messages

        @param private table - Mutable private state table
        @param self LibModule - The Dispenser module instance
        @param message table - The incoming message
        @return nil (pass through), false (block), or table (modified message)
    ]]
    onInput = function(private, self, message)
        -- Pass through all messages unchanged
        return nil
    end,

    --[[
        Intercept outgoing messages

        @param private table - Mutable private state table
        @param self LibModule - The Dispenser module instance
        @param message table - The outgoing message
        @return nil (pass through), false (block), or table (modified message)
    ]]
    onOutput = function(private, self, message)
        -- Track dispense count on dispense action
        if message.action == "dispensed" then
            private.totalDispensed = private.totalDispensed + 1
            private.lastDispenseTime = os.clock()
        end

        -- Pass through unchanged
        return nil
    end,
}
