--[[
    LibPureFiction Framework v2
    Test Suite Index

    Usage in Studio Command Bar:

    ```lua
    -- Run all tests
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.IPC.runAll()

    -- Run specific group
    Tests.IPC.runGroup("Node")
    Tests.IPC.runGroup("IPC Registration")
    Tests.IPC.runGroup("IPC Messaging")

    -- List available groups
    Tests.IPC.list()
    ```
--]]

local Tests = {}

-- Safe require wrapper that reports errors instead of failing silently
local function safeRequire(name, module)
    local success, result = pcall(function()
        return require(module)
    end)

    if success then
        return result
    else
        warn(string.format("[Tests] Failed to load '%s': %s", name, tostring(result)))
        -- Return a stub that reports the error when accessed
        return setmetatable({}, {
            __index = function(_, key)
                error(string.format("Test module '%s' failed to load: %s", name, tostring(result)), 2)
            end,
        })
    end
end

Tests.IPC = safeRequire("IPC_Node_Tests", script:WaitForChild("IPC_Node_Tests"))
Tests.Hatcher = safeRequire("Hatcher_Tests", script:WaitForChild("Hatcher_Tests"))
Tests.Zone = safeRequire("Zone_Tests", script:WaitForChild("Zone_Tests"))
Tests.ConveyorBelt = safeRequire("ConveyorBelt_Tests", script:WaitForChild("ConveyorBelt_Tests"))
Tests.Dropper = safeRequire("Dropper_Tests", script:WaitForChild("Dropper_Tests"))
Tests.PathedConveyor = safeRequire("PathedConveyor_Tests", script:WaitForChild("PathedConveyor_Tests"))
Tests.Checkpoint = safeRequire("Checkpoint_Tests", script:WaitForChild("Checkpoint_Tests"))
Tests.SchemaValidator = safeRequire("SchemaValidator_Tests", script:WaitForChild("SchemaValidator_Tests"))
Tests.Orchestrator = safeRequire("Orchestrator_Tests", script:WaitForChild("Orchestrator_Tests"))

return Tests
