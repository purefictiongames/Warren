--[[
    LibPureFiction Framework v2
    Test Suite Index

    Usage in Studio Command Bar:

    ```lua
    -- Stop all running nodes first (stops demos, cleans up connections)
    local Tests = require(game.ReplicatedStorage.Lib.Tests)
    Tests.stopAll()

    -- Run all tests
    Tests.Battery.runAll()

    -- Run specific group
    Tests.IPC.runGroup("Node")
    Tests.IPC.runGroup("IPC Registration")
    Tests.IPC.runGroup("IPC Messaging")

    -- List available groups
    Tests.IPC.list()
    ```
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tests = {}

--[[
    Stop all running nodes and clean up connections.
    Call this before running tests to ensure a clean state.

    This stops:
    - All IPC-managed instances
    - All nodes in Node.Registry (including demos)
    - All Heartbeat/RunService connections owned by nodes
--]]
function Tests.stopAll()
    local Lib = require(ReplicatedStorage:WaitForChild("Lib"))

    -- Just call System.stopAll() - nodes now auto-cleanup when their models are destroyed
    -- The Registry disconnects model connections first to prevent double-stop
    local result = Lib.System.stopAll()
    print("[Tests] Stopped all nodes - IPC:", result.ipcStopped, "Registry:", result.registryStopped)

    -- Clean up any orphaned demo folders (in case models weren't parented to them)
    local demosToClean = {
        "Swivel_Demo", "Turret_Demo", "Launcher_Demo", "Targeter_Demo",
        "ShootingGallery_Demo", "Conveyor_Demo", "Combat_Demo",
    }

    for _, demoName in ipairs(demosToClean) do
        local existing = workspace:FindFirstChild(demoName)
        if existing then
            existing:Destroy()
        end
    end

    return result
end

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

-- Turret System
Tests.Swivel = safeRequire("Swivel_Tests", script:WaitForChild("Swivel_Tests"))
Tests.Targeter = safeRequire("Targeter_Tests", script:WaitForChild("Targeter_Tests"))
Tests.Launcher = safeRequire("Launcher_Tests", script:WaitForChild("Launcher_Tests"))

-- Power
Tests.Battery = safeRequire("Battery_Tests", script:WaitForChild("Battery_Tests"))

-- Attribute System
Tests.AttributeSet = safeRequire("AttributeSet_Tests", script:WaitForChild("AttributeSet_Tests"))

-- Privacy Pattern (Closure-Based Refactor)
Tests.ClosurePrivacy = safeRequire("ClosurePrivacy_Tests", script:WaitForChild("ClosurePrivacy_Tests"))

return Tests
