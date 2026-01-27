# MapLayout - Declarative 3D Map Definition System

LibPureFiction Framework v2

## Overview

MapLayout is a declarative system for defining 3D game maps using Lua tables. Similar to the GUI Layout system but for architectural elements like walls, floors, stairs, doors, and windows.

Think of it like CAD/architectural drafting - you define geometry with positions, dimensions, and relationships rather than drag-and-drop placement.

## Key Features

- **Declarative table-based definitions** - Define maps as data, not imperative code
- **CSS-like class/ID system** - Style and target elements with cascading properties
- **Relative positioning** - Reference other elements by ID (`#wallA:end`)
- **Surface-based attachments** - Weld objects to specific surfaces (`+x`, `-x`, `top`, etc.)
- **Cascade-based property resolution** - defaults → types → classes → ids → inline
- **Areas (Prefabs)** - Bounded 3D containers with strict validation
- **Scanner** - Reverse workflow: build in Studio, export to config

## Quick Start

```lua
local MapLayout = require(game.ReplicatedStorage.Lib.MapLayout)

-- Define a simple room
local mapDef = {
    walls = {
        { id = "northWall", class = "exterior brick", from = {0, 0}, to = {20, 0}, height = 12 },
        { id = "eastWall", class = "exterior brick", from = "#northWall:end", to = {20, 15}, height = 12 },
        { class = "exterior brick", from = "#eastWall:end", to = "#northWall:start", height = 12 },
    },
    platforms = {
        { id = "turretMount", class = "metal", position = {10, 12, 7.5}, size = {4, 1, 4} },
    },
}

-- Define styles
local styles = {
    defaults = {
        Anchored = true,
        CanCollide = true,
    },
    classes = {
        ["exterior"] = { Material = "Concrete", Color = {180, 175, 165} },
        ["brick"] = { Material = "Brick" },
        ["metal"] = { Material = "DiamondPlate", Color = {80, 80, 85} },
    },
}

-- Build the map
local map = MapLayout.build(mapDef, styles)

-- Target elements by ID
local mount = MapLayout.getInstance("#turretMount")
```

## Coordinate System

- 2D footprint uses `{x, z}` coordinates (horizontal plane)
- Height (y) is specified separately as a property
- Full 3D positions use `{x, y, z}` when needed
- Units are studs (Roblox native units)

## Scale

Maps can define a scale factor to convert definition units to studs:

```lua
scale = "4:1"    -- 4 studs per 1 definition unit
scale = "1:2"    -- 0.5 studs per 1 definition unit
scale = 4        -- Same as "4:1"
```

Example working in "meters" where 1 meter = 4 studs:

```lua
local mapDef = {
    scale = "4:1",
    walls = {
        { from = {0, 0}, to = {10, 0}, height = 3 },  -- 40 studs long, 12 studs tall
    },
}
```

Scale applies to literal positions and dimensions. Referenced positions (`#wallA:end`) are already in studs.

## Element Types

### Walls

Defined with `from`/`to` endpoints on the XZ plane:

```lua
walls = {
    {
        id = "northWall",
        class = "exterior",
        from = {0, 0},           -- {x, z} start point
        to = {20, 0},            -- {x, z} end point
        height = 10,             -- Y height in studs
        thickness = 1,           -- Wall thickness (optional, default from style)
    },
}
```

### Floors

Flat surfaces defined by position and size:

```lua
floors = {
    {
        id = "mainFloor",
        class = "concrete",
        position = {10, 0, 7.5},     -- {x, y, z} center position
        size = {20, 0.5, 15},        -- {width, height, depth}
    },
}
```

### Platforms

General 3D blocks:

```lua
platforms = {
    {
        id = "pedestal",
        class = "metal",
        position = {5, 2, 5},
        size = {4, 4, 4},
    },
}
```

### Cylinders

```lua
cylinders = {
    {
        id = "pillar",
        position = {10, 5, 10},
        height = 10,
        radius = 2,
    },
}
```

### Spheres

```lua
spheres = {
    {
        id = "dome",
        position = {10, 15, 10},
        radius = 5,
    },
}
```

### Wedges

```lua
wedges = {
    {
        id = "ramp",
        position = {5, 1, 5},
        size = {4, 2, 8},
    },
}
```

## Reference Syntax

Elements can reference other elements by ID for relative positioning.

### Selectors

```lua
"#wallA"           -- Reference element with id "wallA"
".exterior"        -- (future) Reference elements with class "exterior"
```

### Reference Points

```lua
"#wallA:start"     -- Starting point (from)
"#wallA:end"       -- Ending point (to)
"#wallA:center"    -- Midpoint
"#wallA:farX"      -- Endpoint with larger X value
"#wallA:farZ"      -- Endpoint with larger Z value
"#wallA:nearX"     -- Endpoint with smaller X value
"#wallA:nearZ"     -- Endpoint with smaller Z value
```

### Along Positioning

```lua
{ along = "#wallA", at = 20 }              -- 20 studs from start
{ along = "#wallA", at = "50%" }           -- 50% along length
{ along = "#wallA", at = 20, surface = "-x" }  -- On the -X surface
```

## Surface Notation

### For Blocks/Rectangles

```lua
"+x", "-x", "+y", "-y", "+z", "-z"
-- Or aliases:
"top", "bottom", "front", "back", "left", "right"
```

### For Cylinders

```lua
"top", "bottom"
{ barrel = 90 }     -- Angle around circumference (degrees)
```

### For Spheres

```lua
{ direction = {0, 1, 0} }          -- Normalized vector
{ azimuth = 45, elevation = 30 }   -- Spherical coordinates
```

### For Wedges

```lua
"slope", "base", "back", "left", "right"
```

## Styles

Styles follow a CSS-like cascade: defaults → types → classes → ids → inline.

```lua
local styles = {
    -- Applied to all elements
    defaults = {
        Anchored = true,
        CanCollide = true,
        Material = "SmoothPlastic",
        Color = {163, 162, 165},
    },

    -- Applied by element type
    types = {
        wall = { thickness = 1 },
        floor = { thickness = 0.5 },
        platform = { Material = "Metal" },
    },

    -- Applied by class (space-separated, all apply)
    classes = {
        ["concrete"] = { Material = "Concrete", Color = {180, 175, 165} },
        ["brick"] = { Material = "Brick", Color = {180, 100, 80} },
        ["exterior"] = { thickness = 1.5 },
        ["interior"] = { thickness = 0.5 },
        ["trigger"] = { CanCollide = false, Transparency = 1 },
    },

    -- Applied by specific ID
    ids = {
        ["mainEntrance"] = { Color = {200, 50, 50} },
    },
}
```

## Areas (Prefabs)

Areas are bounded 3D containers that work like HTML `<div>` tags:

- Define a bounding volume (width, height, depth)
- Have identity (class/ID for styling and targeting)
- Establish local coordinate systems for contained geometry
- Can be nested (areas within areas)
- Can be instantiated multiple times (prefab system)

### Defining an Area Template

```lua
MapLayout.defineArea("hallway", {
    bounds = {20, 8, 6},      -- width, height, depth in studs
    origin = "corner",        -- or "center", "floor-center"
    class = "hallway interior",

    walls = {
        { id = "north", from = {0, 0}, to = {20, 0}, height = 8 },
        { id = "south", from = {0, 6}, to = {20, 6}, height = 8 },
    },

    floors = {
        { id = "floor", position = {10, 0, 3}, size = {20, 0.5, 6} },
    },
})
```

### Using Areas in a Map

```lua
local mapDef = {
    areas = {
        -- From template
        { template = "hallway", id = "hall1", position = {0, 0, 0} },
        { template = "hallway", id = "hall2", position = {20, 0, 0} },

        -- Inline definition
        {
            id = "lobby",
            bounds = {16, 12, 16},
            origin = "corner",
            walls = { ... },
            floors = { ... },
            position = {40, 0, 0},
        },
    },
}
```

### Origin Options

- `"corner"` - `{0,0,0}` at min corner (default)
- `"center"` - `{0,0,0}` at center of bounds
- `"floor-center"` - `{0,0,0}` at center XZ, Y=0 at floor

### Bounds Validation

Geometry must stay within area bounds. If any element exceeds bounds, the build will FAIL with detailed error messages:

```lua
local result = MapLayout.validateArea("myArea", areaDef)
if not result.isValid then
    print(result:format())  -- Detailed error with suggestions
end
```

### Namespaced IDs

Elements within areas are accessed with namespaced IDs:

```lua
MapLayout.get("#hallway1/floor")      -- Floor inside hallway1
MapLayout.get("#lobby/pillar1")       -- Pillar inside lobby
```

## Scanner (Reverse Workflow)

Scanner lets you build geometry visually in Studio, then convert it to MapLayout config code.

### Area Scanning

1. Create a Part, name it (e.g., "testArea")
2. Add attribute: `MapLayoutTag = "area"`
3. Nest geometry parts as CHILDREN under it in Explorer
4. Run in command bar:

```lua
require(game.ReplicatedStorage.Lib.MapLayout).scanArea("testArea")
```

5. Copy generated code from Output
6. Delete original parts, use config going forward

### Explorer Structure

```
workspace
    testArea (Part with MapLayoutTag = "area")
        ├── northWall (Part)
        ├── southWall (Part)
        └── floor (Part)
```

### Scanner Attributes

Tag parts with these attributes to guide the scanner:

| Attribute | Type | Description |
|-----------|------|-------------|
| `MapLayoutId` | string | Element's 'id' in config |
| `MapLayoutName` | string | Alias for MapLayoutId |
| `MapLayoutClass` | string | Element's 'class' in config |
| `MapLayoutTag` | string | Set to "area" for bounding boxes, or as alias for class |
| `MapLayoutType` | string | Override inferred type ("wall", "floor", etc.) |
| `MapLayoutIgnore` | boolean | Skip this part entirely |

### Auto-Cleanup (Snapping)

The scanner automatically cleans up small geometry gaps (0.5 stud threshold):

- Wall endpoints snap to area boundaries and other walls
- Floor/platform edges expand to fill small gaps
- Wall heights snap to area height

This prevents disjointed geometry from minor placement inaccuracies in Studio.

### Mirror Preview (Experimental)

For iterative development, use `mirrorArea` to see a cleaned-up copy:

```lua
local MapLayout = require(game.ReplicatedStorage.Lib.MapLayout)
local mirror = MapLayout.mirrorArea("testArea")

-- Adjust original parts, then run again to refresh
local mirror = MapLayout.mirrorArea("testArea")

-- When satisfied, export final config
MapLayout.scanArea("testArea")
```

### Type Inference

The scanner auto-detects element types based on dimensions:

- **Walls**: Tall and thin in one horizontal dimension
- **Floors**: Flat and wide (Y is small relative to X and Z)
- **Platforms**: Everything else (box-shaped)
- **Spheres**: Ball-shaped parts
- **Cylinders**: Cylinder-shaped parts
- **Wedges**: WedgePart instances

Override with the `MapLayoutType` attribute if needed.

## API Reference

### Building

```lua
MapLayout.build(definition, styles, parent)  -- Build map, returns Model
MapLayout.get(selector)                       -- Get element by ID selector
MapLayout.getInstance(selector)               -- Get the Part/Model instance
MapLayout.clear()                             -- Clear registry before rebuild
```

### Scale

```lua
MapLayout.getScale()              -- Get current build scale factor
MapLayout.parseScale(value)       -- Parse "5:1" or 5 to number
MapLayout.toStuds(value)          -- Convert definition units to studs
MapLayout.fromStuds(value)        -- Convert studs to definition units
```

### Areas

```lua
MapLayout.defineArea(name, definition)    -- Register area template
MapLayout.hasArea(name)                   -- Check if template exists
MapLayout.validateArea(id, definition)    -- Validate without building
MapLayout.clearAreas()                    -- Clear all templates
```

### Scanner

```lua
MapLayout.scan(container, options)            -- Scan container, print code
MapLayout.scanToTable(container, options)     -- Scan, return config table
MapLayout.scanArea(areaName, container, options)  -- Scan named area
MapLayout.mirrorArea(areaName, container, options) -- Build preview copy
MapLayout.listAreas(container)                -- List all tagged areas
```

## Module Structure

```
MapLayout/
├── init.lua           -- Main entry point, public API
├── StyleResolver.lua  -- CSS-like cascade resolution
├── Registry.lua       -- Element tracking and lookups
├── ReferenceResolver.lua  -- Relative positioning
├── GeometryFactory.lua    -- Part creation
├── MapBuilder.lua     -- Main build orchestrator
├── AreaFactory.lua    -- Area template registration
├── AreaBuilder.lua    -- Area instantiation
├── BoundsValidator.lua    -- Bounds validation
└── Scanner.lua        -- Reverse workflow (geometry → config)
```

## Best Practices

1. **Use areas for reusable structures** - Define hallways, rooms, etc. as templates
2. **Use classes for material/style** - Keep geometry definitions clean
3. **Use IDs for targeting** - Only add IDs to elements you need to reference
4. **Use relative positioning** - Connect walls with `#wallA:end` syntax
5. **Validate areas** - Use `validateArea()` during development
6. **Start with Scanner** - Rough out layouts in Studio, then export

## Example: Complete Room

```lua
local MapLayout = require(game.ReplicatedStorage.Lib.MapLayout)

local styles = {
    defaults = { Anchored = true, CanCollide = true },
    classes = {
        ["concrete"] = { Material = "Concrete", Color = {180, 175, 165} },
        ["wood"] = { Material = "Wood", Color = {150, 100, 60} },
    },
}

MapLayout.defineArea("simpleRoom", {
    bounds = {20, 10, 15},
    origin = "corner",

    walls = {
        { id = "north", class = "concrete", from = {0, 0}, to = {20, 0}, height = 10 },
        { id = "south", class = "concrete", from = {0, 15}, to = {20, 15}, height = 10 },
        { id = "east", class = "concrete", from = {20, 0}, to = {20, 15}, height = 10 },
        { id = "west", class = "concrete", from = {0, 0}, to = {0, 15}, height = 10 },
    },

    floors = {
        { id = "floor", class = "wood", position = {10, 0, 7.5}, size = {20, 0.5, 15} },
    },
})

local map = MapLayout.build({
    areas = {
        { template = "simpleRoom", id = "room1", position = {0, 0, 0} },
    },
}, styles)
```
