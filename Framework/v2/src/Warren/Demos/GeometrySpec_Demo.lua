--[[
    Warren Framework v2
    GeometrySpec Demo - Declarative Geometry Definition

    This demo showcases the GeometrySpec system for defining geometry
    using declarative Lua tables with class-based styling.

    Use cases demonstrated:
    - Turret geometry definition
    - Zone with mount points
    - Class-based styling

    Run from server context:
    ```lua
    local Demos = require(game.ReplicatedStorage.Warren.Demos)
    Demos.GeometrySpec()
    ```
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lib = require(ReplicatedStorage.Warren)
local GeometrySpec = Lib.GeometrySpec

--------------------------------------------------------------------------------
-- EXAMPLE 1: TURRET GEOMETRY
--------------------------------------------------------------------------------

-- Define turret geometry specification
local turretSpec = {
    bounds = {4, 6, 4},
    origin = "floor-center",

    defaults = {
        Anchored = true,
        CanCollide = true,
    },

    classes = {
        frame = { Material = "DiamondPlate", Color = {80, 80, 85} },
        barrel = { Material = "Metal", Color = {40, 40, 40} },
        accent = { Material = "Neon", Color = {100, 200, 255} },
    },

    parts = {
        -- Base
        { id = "base", class = "frame", position = {0, 1, 0}, size = {4, 2, 4} },

        -- Rotating head mount
        { id = "head", class = "frame", position = {0, 2.75, 0}, size = {3, 1.5, 3} },

        -- Barrel
        { id = "barrel", class = "barrel", position = {0, 2.75, 2}, size = {0.5, 0.5, 3} },

        -- Accent lights
        { id = "light1", class = "accent", position = {1.5, 1, 0}, size = {0.2, 0.5, 0.2} },
        { id = "light2", class = "accent", position = {-1.5, 1, 0}, size = {0.2, 0.5, 0.2} },
    },
}

--------------------------------------------------------------------------------
-- EXAMPLE 2: ZONE WITH MOUNT POINTS
--------------------------------------------------------------------------------

-- Define a defensive zone with turret mount positions
local zoneSpec = {
    bounds = {40, 12, 30},
    origin = "corner",

    defaults = {
        Anchored = true,
        CanCollide = true,
    },

    classes = {
        concrete = { Material = "Concrete", Color = {180, 175, 165} },
        metal = { Material = "DiamondPlate", Color = {100, 100, 105} },
        trigger = { CanCollide = false, Transparency = 0.95 },
    },

    parts = {
        -- Floor
        { id = "floor", class = "concrete", position = {20, 0.25, 15}, size = {40, 0.5, 30} },

        -- Elevated platforms for turrets
        { id = "platform1", class = "metal", position = {10, 1.5, 5}, size = {6, 2.5, 6} },
        { id = "platform2", class = "metal", position = {30, 1.5, 5}, size = {6, 2.5, 6} },
        { id = "platform3", class = "metal", position = {20, 1.5, 25}, size = {6, 2.5, 6} },

        -- Detection zone (invisible trigger)
        { id = "detectionZone", class = "trigger", position = {20, 6, 15}, size = {40, 12, 30} },
    },

    -- Mount points for spawning turrets (no geometry created)
    mounts = {
        { id = "turret1", position = {10, 2.75, 5}, facing = {0, 0, 1} },
        { id = "turret2", position = {30, 2.75, 5}, facing = {0, 0, 1} },
        { id = "turret3", position = {20, 2.75, 25}, facing = {0, 0, -1} },
    },
}

--------------------------------------------------------------------------------
-- EXAMPLE 3: DIFFERENT SHAPES
--------------------------------------------------------------------------------

local shapesSpec = {
    bounds = {20, 10, 20},
    origin = "floor-center",

    defaults = {
        Anchored = true,
        Material = "SmoothPlastic",
    },

    classes = {
        red = { Color = {220, 60, 60} },
        green = { Color = {60, 220, 60} },
        blue = { Color = {60, 60, 220} },
        yellow = { Color = {220, 220, 60} },
    },

    parts = {
        -- Block
        { id = "block", class = "red", position = {-6, 2, 0}, size = {3, 4, 3} },

        -- Cylinder
        { id = "pillar", class = "green", position = {0, 3, 0}, shape = "cylinder", height = 6, radius = 1.5 },

        -- Sphere
        { id = "ball", class = "blue", position = {6, 2, 0}, shape = "sphere", radius = 2 },

        -- Wedge
        { id = "ramp", class = "yellow", position = {0, 1.5, 6}, shape = "wedge", size = {4, 3, 6} },
    },
}

--------------------------------------------------------------------------------
-- DEMO RUNNER
--------------------------------------------------------------------------------

return function()
    print("\n" .. string.rep("=", 60))
    print("GeometrySpec Demo")
    print(string.rep("=", 60))

    -- Clean up any previous demo
    local existing = workspace:FindFirstChild("GeometrySpecDemo")
    if existing then
        existing:Destroy()
    end

    local demoContainer = Instance.new("Model")
    demoContainer.Name = "GeometrySpecDemo"

    -- Build turret example
    print("\n[1] Building turret geometry...")
    GeometrySpec.clear()
    local turret = GeometrySpec.build({ name = "Turret", spec = turretSpec })
    turret:PivotTo(CFrame.new(0, 0, 0))
    turret.Parent = demoContainer

    -- Get parts by ID
    local base = GeometrySpec.getInstance("base")
    local barrel = GeometrySpec.getInstance("barrel")
    print("  - Container type:", turret.ClassName)
    print("  - Base part:", base and base.Name or "not found")
    print("  - Barrel part:", barrel and barrel.Name or "not found")

    -- Build zone example
    print("\n[2] Building zone with mount points...")
    GeometrySpec.clear()
    local zone = GeometrySpec.build({ name = "DefensiveZone", spec = zoneSpec })
    zone:PivotTo(CFrame.new(50, 0, 0))
    zone.Parent = demoContainer

    -- Access mount points
    local mount1 = GeometrySpec.get("turret1")
    local mount2 = GeometrySpec.get("turret2")
    print("  - Container size:", zone.Size)
    print("  - Mount 1 position:", mount1 and mount1.geometry.position or "not found")
    print("  - Mount 2 facing:", mount2 and mount2.geometry.facing or "not found")

    -- Build shapes example
    print("\n[3] Building shapes showcase...")
    GeometrySpec.clear()
    local shapes = GeometrySpec.build({ name = "Shapes", spec = shapesSpec })
    shapes:PivotTo(CFrame.new(100, 0, 0))
    shapes.Parent = demoContainer

    -- Parent demo container
    demoContainer.Parent = workspace

    print("\n" .. string.rep("=", 60))
    print("Demo complete! Check workspace.GeometrySpecDemo")
    print("  - Turret (Part container) at origin")
    print("  - DefensiveZone (Part container) at X=50")
    print("  - Shapes (Part container) at X=100")
    print(string.rep("=", 60) .. "\n")

    return demoContainer
end
