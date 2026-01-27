--[[
    LibPureFiction Framework v2
    MapLayout Demo - Declarative 3D Map Construction

    This demo showcases the MapLayout system for building game maps
    using declarative Lua table definitions, including:
    - Scale support (working in custom units)
    - Areas (bounded prefabs)
    - Nested areas
    - Bounds validation

    Run from server context:
    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    Demos.MapLayout()
    ```
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lib = require(ReplicatedStorage.Lib)
local MapLayout = Lib.MapLayout

--------------------------------------------------------------------------------
-- STYLE DEFINITIONS
--------------------------------------------------------------------------------

local styles = {
    -- Default properties for all elements
    defaults = {
        Anchored = true,
        CanCollide = true,
        CanTouch = true,
        Material = "SmoothPlastic",
        Color = {163, 162, 165}, -- Default gray
    },

    -- Type-specific defaults
    types = {
        wall = {
            thickness = 1,
        },
        floor = {
            thickness = 0.5,
        },
        platform = {
            Material = "Metal",
        },
    },

    -- Class-based styles
    classes = {
        -- Materials
        ["concrete"] = { Material = "Concrete", Color = {180, 175, 165} },
        ["brick"] = { Material = "Brick", Color = {180, 100, 80} },
        ["metal"] = { Material = "DiamondPlate", Color = {100, 100, 105} },
        ["wood"] = { Material = "Wood", Color = {150, 100, 60} },
        ["glass"] = { Material = "Glass", Transparency = 0.5 },

        -- Functional classes
        ["exterior"] = { thickness = 1.5 },
        ["interior"] = { thickness = 0.5 },
        ["reinforced"] = { thickness = 2 },

        -- Area types
        ["hallway"] = { Color = {200, 195, 185} },
        ["room"] = { Color = {220, 215, 205} },

        -- Special classes
        ["trigger"] = { CanCollide = false, Transparency = 1, CanTouch = true },
        ["decorative"] = { CanCollide = false, CanQuery = false },
        ["invisible"] = { Transparency = 1 },
    },

    -- ID-specific styles
    ids = {
        ["mainEntrance"] = { Color = {200, 50, 50} },
        ["turretMountA"] = { Color = {50, 50, 200} },
    },
}

--------------------------------------------------------------------------------
-- AREA TEMPLATE DEFINITIONS (PREFABS)
--------------------------------------------------------------------------------

-- Define a reusable hallway template
MapLayout.defineArea("hallway", {
    bounds = {20, 8, 6},      -- 20 wide, 8 tall, 6 deep (in studs)
    origin = "corner",
    class = "hallway concrete",

    walls = {
        -- Long walls
        { id = "north", class = "interior", from = {0, 0}, to = {20, 0}, height = 8 },
        { id = "south", class = "interior", from = {0, 6}, to = {20, 6}, height = 8 },
    },

    floors = {
        { id = "floor", class = "concrete", position = {10, 0, 3}, size = {20, 6} },
    },
})

-- Define a small room template
MapLayout.defineArea("smallRoom", {
    bounds = {12, 10, 12},    -- 12x12 footprint, 10 tall
    origin = "floor-center",  -- {0,0,0} is center of floor
    class = "room concrete",

    walls = {
        { id = "north", class = "interior", from = {-6, -6}, to = {6, -6}, height = 10 },
        { id = "south", class = "interior", from = {-6, 6}, to = {6, 6}, height = 10 },
        { id = "east", class = "interior", from = {6, -6}, to = {6, 6}, height = 10 },
        { id = "west", class = "interior", from = {-6, -6}, to = {-6, 6}, height = 10 },
    },

    floors = {
        { id = "floor", class = "wood", position = {0, 0, 0}, size = {12, 12} },
    },

    platforms = {
        -- A table in the center
        { id = "table", class = "wood", position = {0, 2, 0}, size = {4, 0.5, 3} },
    },
})

-- Define a connector piece (doorway)
MapLayout.defineArea("connector", {
    bounds = {4, 8, 2},
    origin = "corner",
    class = "hallway",

    floors = {
        { id = "floor", class = "concrete", position = {2, 0, 1}, size = {4, 2} },
    },
})

--------------------------------------------------------------------------------
-- MAP DEFINITION USING AREAS
--------------------------------------------------------------------------------

local mapDefinition = {
    name = "AreaDemo",

    -- No scale for this demo - working directly in studs
    -- scale = "1:1",

    -- Loose geometry (not in an area)
    floors = {
        -- Ground plane
        {
            id = "ground",
            class = "concrete",
            position = {40, -0.5, 30},
            size = {100, 80},
            thickness = 1,
        },
    },

    -- Areas (prefab instances)
    areas = {
        -- First hallway at origin
        {
            template = "hallway",
            id = "hallway1",
            position = {10, 0, 10},
        },

        -- Second hallway connected to the first
        {
            template = "hallway",
            id = "hallway2",
            position = {30, 0, 10},  -- Starts where hallway1 ends
        },

        -- A room at the end of hallway2
        {
            template = "smallRoom",
            id = "endRoom",
            position = {56, 0, 13},  -- Offset to connect to hallway end
        },

        -- Inline area definition (not from template)
        {
            id = "lobby",
            bounds = {16, 12, 16},
            origin = "corner",
            class = "room brick",

            walls = {
                { id = "north", class = "exterior brick", from = {0, 0}, to = {16, 0}, height = 12 },
                { id = "south", class = "exterior brick", from = {0, 16}, to = {16, 16}, height = 12 },
                { id = "east", class = "exterior brick", from = {16, 0}, to = {16, 16}, height = 12 },
                { id = "west", class = "exterior brick", from = {0, 0}, to = {0, 16}, height = 12 },
            },

            floors = {
                { id = "floor", class = "wood", position = {8, 0, 8}, size = {16, 16} },
            },

            platforms = {
                { id = "pillar1", class = "concrete", position = {4, 6, 4}, size = {2, 12, 2} },
                { id = "pillar2", class = "concrete", position = {12, 6, 4}, size = {2, 12, 2} },
                { id = "pillar3", class = "concrete", position = {4, 6, 12}, size = {2, 12, 2} },
                { id = "pillar4", class = "concrete", position = {12, 6, 12}, size = {2, 12, 2} },
            },

            position = {10, 0, 30},
        },
    },
}

--------------------------------------------------------------------------------
-- BOUNDS VALIDATION DEMO
--------------------------------------------------------------------------------

-- This area definition has geometry that exceeds bounds - will fail validation
local invalidAreaDef = {
    id = "invalidArea",
    bounds = {10, 8, 10},
    origin = "corner",

    walls = {
        { id = "tooLong", from = {0, 0}, to = {15, 0}, height = 8 },  -- X=15 exceeds bounds of 10!
    },
}

--------------------------------------------------------------------------------
-- DEMO FUNCTION
--------------------------------------------------------------------------------

local function runDemo()
    print("=== MapLayout Demo with Areas ===")

    -- Clean up existing demo
    local existing = workspace:FindFirstChild("AreaDemo")
    if existing then
        existing:Destroy()
    end

    -- Show registered templates
    print("\n--- Registered Area Templates ---")
    local templates = MapLayout.AreaFactory.list()
    for _, name in ipairs(templates) do
        local template = MapLayout.AreaFactory.get(name)
        print(string.format("  %s: bounds = {%d, %d, %d}, origin = %s",
            name,
            template.bounds[1], template.bounds[2], template.bounds[3],
            template.origin
        ))
    end

    -- Demonstrate bounds validation (this should fail)
    print("\n--- Bounds Validation Demo ---")
    print("Testing invalid area (geometry exceeds bounds)...")

    local validationResult = MapLayout.validateArea("invalidArea", invalidAreaDef)
    if not validationResult.isValid then
        print("Validation FAILED (as expected):")
        print(validationResult:format())
    else
        print("Validation passed (unexpected!)")
    end

    -- Build the actual map
    print("\n--- Building Map ---")
    print("Building map with areas...")

    local map = MapLayout.build(mapDefinition, styles)

    print("Map built:", map.Name)
    print("Top-level children:", #map:GetChildren())

    -- Show area hierarchy
    print("\n--- Area Hierarchy ---")
    for _, child in ipairs(map:GetChildren()) do
        if child:GetAttribute("MapLayoutArea") then
            local areaId = child:GetAttribute("MapLayoutId")
            local bounds = child:GetAttribute("MapLayoutBounds")
            print(string.format("  Area '%s': bounds = %s", areaId, bounds))

            -- Show nested elements
            local elementCount = 0
            for _, elem in ipairs(child:GetChildren()) do
                if elem:IsA("BasePart") then
                    elementCount = elementCount + 1
                end
            end
            print(string.format("    Contains %d elements", elementCount))
        elseif child:IsA("BasePart") then
            local id = child:GetAttribute("MapLayoutId") or child.Name
            print(string.format("  Element '%s' (loose, not in area)", id))
        end
    end

    -- Demonstrate registry lookups with namespaced IDs
    print("\n--- Registry Lookups ---")

    -- Lookup area by ID
    local hallway1 = MapLayout.get("#hallway1")
    if hallway1 then
        print("hallway1:", hallway1.instance.Name, "at", hallway1.geometry.position)
    end

    -- Lookup namespaced element (area/element)
    local hallway1Floor = MapLayout.get("#hallway1/floor")
    if hallway1Floor then
        print("hallway1/floor:", hallway1Floor.instance.Name)
    end

    -- Lookup element in inline area
    local lobbyPillar = MapLayout.get("#lobby/pillar1")
    if lobbyPillar then
        print("lobby/pillar1:", lobbyPillar.instance.Name, "at", lobbyPillar.instance.Position)
    end

    print("\n--- Registry Contents ---")
    MapLayout.Registry.dump()

    print("\n=== Demo Complete ===")
    print("Check workspace for 'AreaDemo' model")

    return map
end

return runDemo
