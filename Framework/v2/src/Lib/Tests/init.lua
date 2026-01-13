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

Tests.IPC = require(script:WaitForChild("IPC_Node_Tests"))

return Tests
