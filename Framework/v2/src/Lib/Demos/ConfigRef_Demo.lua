--[[
    ConfigRef_Demo.lua - Demonstrates Config Reference System

    Shows how to use cfg.* references in static layouts for dimension values
    that participate in the class cascade.

    Run in Roblox Studio command bar:
        require(game.ReplicatedStorage.Lib).Demos.ConfigRef_Demo()
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
local Geometry = Lib.Factory.Geometry

-- Get the cfg proxy for config references
local cfg = Geometry.cfg

--------------------------------------------------------------------------------
-- EXAMPLE 1: Basic Config References
--------------------------------------------------------------------------------

local BasicRoom = {
    name = "BasicRoom",
    spec = {
        bounds = { X = 40, Y = 30, Z = 40 },

        classes = {
            room = {
                -- Dimension config
                W = 40,
                D = 40,
                WALL_H = 30,
                WALL_T = 1,
            },
            concrete = { Material = "Concrete", Color = {180, 175, 165} },
        },

        class = "room",

        parts = {
            -- Floor uses cfg references
            { id = "Floor", class = "concrete",
              position = {0, 0, 0},
              size = {cfg.W, 1, cfg.D} },

            -- Walls use cfg references with arithmetic
            { id = "Wall_South", class = "concrete",
              position = {0, 1, 0},
              size = {cfg.W, cfg.WALL_H, cfg.WALL_T} },

            { id = "Wall_North", class = "concrete",
              position = {0, 1, cfg.D - cfg.WALL_T},
              size = {cfg.W, cfg.WALL_H, cfg.WALL_T} },

            { id = "Wall_West", class = "concrete",
              position = {0, 1, 0},
              size = {cfg.WALL_T, cfg.WALL_H, cfg.D} },

            { id = "Wall_East", class = "concrete",
              position = {cfg.W - cfg.WALL_T, 1, 0},
              size = {cfg.WALL_T, cfg.WALL_H, cfg.D} },
        },
    },
}

--------------------------------------------------------------------------------
-- EXAMPLE 2: Config with xref Inheritance (TODO: requires xref config cascade)
--------------------------------------------------------------------------------

-- Parent layout can override child config via class cascade
-- (This is the target architecture - xref config cascade needs implementation)

--------------------------------------------------------------------------------
-- EXAMPLE 3: Runtime Context Queries
--------------------------------------------------------------------------------

local function demoContext()
    print("\n=== Context Demo ===")

    -- Create context from spec
    local ctx = Geometry.createContext(BasicRoom.spec)

    -- Query config values
    print("W:", ctx:get("W"))
    print("WALL_T:", ctx:get("WALL_T"))
    print("missing:", ctx:get("missing", "default"))

    -- Query derived values
    print("gap:", ctx:getDerived("gap"))  -- 2 * wallThickness (needs wallThickness in config)

    -- Child context with override
    local childCtx = ctx:child({
        class = "thick",
        classes = {
            thick = { WALL_T = 4 },
        },
    })
    print("child WALL_T:", childCtx:get("WALL_T"))
    print("child W:", childCtx:get("W"))  -- Inherited from parent

    print("===================\n")
end

--------------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------------

return function()
    print("[ConfigRef_Demo] Starting...")

    -- Build the room
    local container = Geometry.build(BasicRoom, workspace)
    container:PivotTo(CFrame.new(0, 10, 0))

    print("[ConfigRef_Demo] Built BasicRoom at origin")

    -- Show context demo
    demoContext()

    -- Show resolved config from metadata
    local resolved = Geometry.resolve(BasicRoom)
    print("[ConfigRef_Demo] Resolved config:", resolved._meta.config)

    print("[ConfigRef_Demo] Done!")

    return container
end
