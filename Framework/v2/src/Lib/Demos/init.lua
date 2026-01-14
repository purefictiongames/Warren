--[[
    LibPureFiction Framework v2
    Demos Index

    Visual demonstrations of framework components.
    Run in Studio Command Bar to see components in action.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)

    -- Run individual component demos
    local swivelDemo = Demos.Swivel.run()
    local targeterDemo = Demos.Targeter.run()
    local launcherDemo = Demos.Launcher.run()

    -- Run full turret system demo
    local turretDemo = Demos.Turret.run()

    -- Run with auto-demo mode (automatic behavior)
    local demo = Demos.Turret.run({ autoDemo = true })

    -- Cleanup when done
    demo.cleanup()
    ```

    ============================================================================
    AVAILABLE DEMOS
    ============================================================================

    Swivel:
        Single-axis rotation component.
        Controls: rotateForward(), rotateReverse(), stop(), setAngle(deg)

    Targeter:
        Raycast-based target detection with beam visualization.
        Controls: enable(), disable(), addTarget(), setBeamMode()

    Launcher:
        Physics-based projectile firing.
        Controls: fire(), fireAt(pos), setForce(), setMethod()

    Turret (Composite):
        Full turret system with yaw/pitch swivels, targeter, and launcher.
        Auto-tracks and fires at targets.
        Controls: activate(), deactivate(), addTarget(), setFireRate()

    Conveyor (Composite):
        Tycoon-style dropper + path follower system.
        Items spawn, travel along waypoints, and get collected.
        Controls: dispense(count), setInterval(), start(), stop()

--]]

local Demos = {}

-- Lazy-load demos to avoid circular dependency
-- (Demo modules require Lib, which would cause recursion if loaded at init)
local loadedDemos = {}

local demoModules = {
    Swivel = "Swivel_Demo",
    Targeter = "Targeter_Demo",
    Launcher = "Launcher_Demo",
    Turret = "Turret_Demo",
    Conveyor = "Conveyor_Demo",
}

setmetatable(Demos, {
    __index = function(self, key)
        -- Check if it's a known demo
        local moduleName = demoModules[key]
        if moduleName then
            -- Lazy load on first access
            if not loadedDemos[key] then
                local success, result = pcall(function()
                    return require(script:WaitForChild(moduleName))
                end)

                if success then
                    loadedDemos[key] = result
                else
                    warn(string.format("[Demos] Failed to load '%s': %s", moduleName, tostring(result)))
                    -- Return error stub
                    loadedDemos[key] = setmetatable({}, {
                        __index = function()
                            error(string.format("Demo '%s' failed to load: %s", key, tostring(result)), 2)
                        end,
                    })
                end
            end
            return loadedDemos[key]
        end
        return nil
    end,
})

-- Convenience function to run all demos at once
function Demos.runAll(config)
    config = config or {}
    local demos = {}

    -- Position demos in a row
    local offset = 30

    demos.swivel = Demos.Swivel.run({
        position = Vector3.new(-offset * 1.5, 10, 0),
        autoDemo = config.autoDemo,
    })

    demos.targeter = Demos.Targeter.run({
        position = Vector3.new(-offset * 0.5, 10, 0),
        autoDemo = config.autoDemo,
    })

    demos.launcher = Demos.Launcher.run({
        position = Vector3.new(offset * 0.5, 10, 0),
        autoDemo = config.autoDemo,
    })

    demos.turret = Demos.Turret.run({
        position = Vector3.new(offset * 1.5, 5, 0),
        autoDemo = config.autoDemo,
    })

    demos.conveyor = Demos.Conveyor.run({
        position = Vector3.new(0, 5, offset * 2),
        autoDemo = config.autoDemo,
    })

    -- Cleanup all function
    function demos.cleanupAll()
        demos.swivel.cleanup()
        demos.targeter.cleanup()
        demos.launcher.cleanup()
        demos.turret.cleanup()
        demos.conveyor.cleanup()
    end

    print("All demos running. Call demos.cleanupAll() to remove all.")

    return demos
end

return Demos
