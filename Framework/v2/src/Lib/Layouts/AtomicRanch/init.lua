--[[
    AtomicRanch Layout Components

    Modular layout pieces for the atomic ranch house.
--]]

local AtomicRanch = {}

-- Lazy load components
setmetatable(AtomicRanch, {
    __index = function(_, key)
        local module = script:FindFirstChild(key)
        if module then
            return require(module)
        end
        return nil
    end,
})

return AtomicRanch
