--[[
    LibPureFiction Framework v2
    Combat Demo - Attribute System Integration

    Demonstrates the full attribute/combat system:
    - EntityStats: Stores entity attributes (health, defense)
    - DamageCalculator: Computes damage with defense mitigation
    - StatusEffect: Applies timed buffs/debuffs

    ============================================================================
    USAGE
    ============================================================================

    In Studio Command Bar:

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    local demo = Demos.Combat.run()

    -- Deal damage to the enemy
    demo.dealDamage(20)

    -- Apply a buff
    demo.applyBuff()

    -- Apply a debuff
    demo.applyDebuff()

    -- Check status
    demo.status()

    -- Clean up
    demo.cleanup()
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local System = Lib.System
local Node = Lib.Node

-- Components
local EntityStats = Lib.Components.EntityStats
local DamageCalculator = Lib.Components.DamageCalculator
local StatusEffect = Lib.Components.StatusEffect

local Demo = {}

--------------------------------------------------------------------------------
-- DEMO SETUP
--------------------------------------------------------------------------------

function Demo.run()
    print("\n========================================")
    print("  Combat System Demo")
    print("========================================\n")

    -- Check if running on server (required for server-domain components)
    local RunService = game:GetService("RunService")
    if not RunService:IsServer() then
        warn("Combat Demo must be run from the SERVER command bar.")
        warn("In Studio: View > Command Bar, then switch to Server view.")
        return {
            cleanup = function() end,
            status = function() warn("Demo not initialized - run on server") end,
        }
    end

    -- Reset IPC for clean state
    System.IPC.reset()
    System.Attribute.reset()

    -- Register components
    System.IPC.registerNode(EntityStats)
    System.IPC.registerNode(DamageCalculator)
    System.IPC.registerNode(StatusEffect)

    -- Create instances
    local enemyStats = System.IPC.createInstance("EntityStats", { id = "enemy_stats" })
    local damageCalc = System.IPC.createInstance("DamageCalculator", { id = "damage_calc" })
    local statusFx = System.IPC.createInstance("StatusEffect", { id = "status_fx" })

    -- Define wiring
    System.IPC.defineMode("Combat", {
        nodes = { "EntityStats", "DamageCalculator", "StatusEffect" },
        wiring = {
            -- DamageCalculator queries EntityStats and applies damage
            DamageCalculator = { "EntityStats" },
            EntityStats = { "DamageCalculator" },
            -- StatusEffect applies/removes modifiers on EntityStats
            StatusEffect = { "EntityStats" },
        },
    })

    -- Initialize IPC
    System.IPC.init()
    System.IPC.switchMode("Combat")
    System.IPC.start()

    -- Configure the enemy's stats
    local enemySchema = {
        health = {
            type = "number",
            default = 100,
            min = 0,
            max = 100,
            replicate = true,
        },
        maxHealth = {
            type = "number",
            default = 100,
            replicate = true,
        },
        baseDefense = {
            type = "number",
            default = 10,
            replicate = false,
        },
        effectiveDefense = {
            type = "number",
            derived = true,
            dependencies = { "baseDefense" },
            replicate = true,
            compute = function(values, mods)
                local base = values.baseDefense
                local add = mods.additive or 0
                local mult = mods.multiplicative or 1
                return (base + add) * mult
            end,
        },
        speed = {
            type = "number",
            default = 16,
            min = 0,
            replicate = true,
        },
    }

    -- Send configure signal
    enemyStats.In.onConfigure(enemyStats, {
        schema = enemySchema,
        entityId = "enemy_1",
    })

    -- Subscribe to attribute changes for logging and death detection
    local attrSet = enemyStats:getAttributeSet()
    if attrSet then
        attrSet:subscribeAll(function(name, newVal, oldVal)
            print(string.format("  [%s] %s: %s -> %s", "enemy_1", name, tostring(oldVal), tostring(newVal)))
            -- Death detection
            if name == "health" and newVal <= 0 then
                print("\n  *** ENEMY DIED! ***\n")
            end
        end)
    end

    print("Enemy created with:")
    print("  - Health: 100")
    print("  - Defense: 10")
    print("  - Speed: 16")
    print("")

    ----------------------------------------------------------------------------
    -- DEMO API
    ----------------------------------------------------------------------------

    local api = {}

    -- Deal raw damage to the enemy
    function api.dealDamage(amount)
        amount = amount or 20
        print(string.format("\nDealing %d raw damage...", amount))

        -- Send to DamageCalculator which will query defense and compute final
        damageCalc.In.onCalculateDamage(damageCalc, {
            targetId = "enemy_stats",
            rawDamage = amount,
            damageType = "physical",
            sourceId = "player",
        })

        -- Since DamageCalculator uses async query, we need to manually simulate
        -- the response flow for this demo (in real game, wiring handles this)
        task.wait(0.05)

        -- Get current defense
        local defense = enemyStats:get("effectiveDefense") or 0
        local finalDamage = math.max(1, amount - defense)

        print(string.format("  Defense: %d, Final damage: %d", defense, finalDamage))

        -- Apply damage directly for demo (normally wired through IPC)
        local currentHealth = enemyStats:get("health") or 0
        enemyStats.In.onSetAttribute(enemyStats, {
            attribute = "health",
            value = currentHealth - finalDamage,
        })
    end

    -- Deal true damage (ignores defense)
    function api.dealTrueDamage(amount)
        amount = amount or 15
        print(string.format("\nDealing %d TRUE damage (ignores defense)...", amount))

        local currentHealth = enemyStats:get("health") or 0
        enemyStats.In.onSetAttribute(enemyStats, {
            attribute = "health",
            value = currentHealth - amount,
        })
    end

    -- Apply a defense buff
    function api.applyBuff()
        print("\nApplying Iron Shield buff (+15 defense for 10s)...")

        statusFx.In.onApplyEffect(statusFx, {
            targetId = "enemy_stats",
            effectType = "iron_shield",
            duration = 10,
            modifiers = {
                { attribute = "effectiveDefense", operation = "additive", value = 15 },
            },
        })
    end

    -- Apply a speed debuff
    function api.applyDebuff()
        print("\nApplying Slow debuff (-50% speed for 5s)...")

        statusFx.In.onApplyEffect(statusFx, {
            targetId = "enemy_stats",
            effectType = "slow",
            duration = 5,
            modifiers = {
                { attribute = "speed", operation = "multiplicative", value = 0.5 },
            },
        })
    end

    -- Apply armor modifier directly
    function api.equipArmor(value)
        value = value or 5
        print(string.format("\nEquipping armor (+%d defense)...", value))

        enemyStats.In.onApplyModifier(enemyStats, {
            attribute = "effectiveDefense",
            operation = "additive",
            value = value,
            source = "equipped_armor",
        })
    end

    -- Remove armor
    function api.unequipArmor()
        print("\nUnequipping armor...")

        enemyStats.In.onRemoveModifier(enemyStats, {
            source = "equipped_armor",
        })
    end

    -- Heal the enemy
    function api.heal(amount)
        amount = amount or 25
        print(string.format("\nHealing for %d...", amount))

        local currentHealth = enemyStats:get("health") or 0
        local maxHealth = enemyStats:get("maxHealth") or 100
        local newHealth = math.min(maxHealth, currentHealth + amount)

        enemyStats.In.onSetAttribute(enemyStats, {
            attribute = "health",
            value = newHealth,
        })
    end

    -- Print current status
    function api.status()
        print("\n--- Enemy Status ---")
        print("  Health:", enemyStats:get("health"), "/", enemyStats:get("maxHealth"))
        print("  Defense:", enemyStats:get("effectiveDefense"), "(base:", enemyStats:getBase("baseDefense"), ")")
        print("  Speed:", enemyStats:get("speed"))

        local effects = statusFx:getEffectsForTarget("enemy_stats")
        if #effects > 0 then
            print("  Active effects:", #effects)
            for _, effectId in ipairs(effects) do
                local remaining = statusFx:getRemainingDuration(effectId)
                local effectData = statusFx:getActiveEffects()[effectId]
                if effectData then
                    print(string.format("    - %s (%.1fs remaining)", effectData.effectType, remaining or 0))
                end
            end
        else
            print("  Active effects: none")
        end
        print("--------------------\n")
    end

    -- Full combat scenario
    function api.scenario()
        print("\n=== Running Combat Scenario ===\n")

        api.status()

        print("Step 1: Equip armor")
        api.equipArmor(5)
        task.wait(0.1)
        api.status()

        print("Step 2: Deal 20 physical damage")
        api.dealDamage(20)
        task.wait(0.1)
        api.status()

        print("Step 3: Apply defense buff")
        api.applyBuff()
        task.wait(0.1)
        api.status()

        print("Step 4: Deal 30 physical damage (with buff active)")
        api.dealDamage(30)
        task.wait(0.1)
        api.status()

        print("Step 5: Deal 50 true damage")
        api.dealTrueDamage(50)
        task.wait(0.1)
        api.status()

        print("Step 6: Heal")
        api.heal(40)
        task.wait(0.1)
        api.status()

        print("=== Scenario Complete ===\n")
    end

    -- Cleanup
    function api.cleanup()
        print("\nCleaning up demo...")
        System.IPC.stop()
        System.IPC.reset()
        System.Attribute.reset()
        print("Demo cleaned up.\n")
    end

    -- Print usage
    print("Demo API:")
    print("  demo.dealDamage(amount)   - Deal physical damage")
    print("  demo.dealTrueDamage(amt)  - Deal true damage (ignores defense)")
    print("  demo.applyBuff()          - Apply defense buff")
    print("  demo.applyDebuff()        - Apply slow debuff")
    print("  demo.equipArmor(value)    - Add armor modifier")
    print("  demo.unequipArmor()       - Remove armor")
    print("  demo.heal(amount)         - Heal the enemy")
    print("  demo.status()             - Show current status")
    print("  demo.scenario()           - Run full combat scenario")
    print("  demo.cleanup()            - Clean up demo")
    print("")

    return api
end

return Demo
