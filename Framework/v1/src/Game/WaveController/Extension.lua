--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- WaveController Extension
-- Game-specific extension for the WaveController Lib module
-- Provides custom difficulty curves and wave configuration

return {
    --[[
        Initialize game-specific state

        @param private table - Mutable private state table
        @param self LibModule - The WaveController module instance
        @param model Instance - The deployed model in RuntimeAssets
    ]]
    init = function(private, self, model)
        -- Game-specific configuration
        private.campersPerWaveBase = 10
        private.campersPerWaveGrowth = 2
        private.maxConcurrentBase = 1
        private.maxConcurrentGrowth = 0.5
        private.maxConcurrentCap = 4
        private.spawnIntervalBase = 5
        private.spawnIntervalDecay = 0.5
        private.spawnIntervalFloor = 2
    end,

    --[[
        Start game-specific behaviors

        @param private table - Mutable private state table
        @param self LibModule - The WaveController module instance
    ]]
    start = function(private, self)
        -- Game-specific startup
    end,

    --[[
        Reset game-specific state

        @param private table - Mutable private state table
        @param self LibModule - The WaveController module instance
    ]]
    reset = function(private, self)
        -- Reset any game-specific state
    end,

    --[[
        Intercept incoming messages
        Can be used to modify wave control commands

        @param private table - Mutable private state table
        @param self LibModule - The WaveController module instance
        @param message table - The incoming message
        @return nil (pass through), false (block), or table (modified message)
    ]]
    onInput = function(private, self, message)
        return nil
    end,

    --[[
        Intercept outgoing messages

        @param private table - Mutable private state table
        @param self LibModule - The WaveController module instance
        @param message table - The outgoing message
        @return nil (pass through), false (block), or table (modified message)
    ]]
    onOutput = function(private, self, message)
        return nil
    end,
}
