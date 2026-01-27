# GeometrySpec - Declarative Geometry Definition System

LibPureFiction Framework v2

## Overview

GeometrySpec is a declarative system for defining geometry using Lua tables. It provides a unified way to specify parts with positions, sizes, and class-based styling.

**Use cases:**
- **Zone nodes** - Map areas with mount points and player detection
- **Node geometry** - Turrets, launchers, any node with generated parts
- **Mount point definitions** - Named positions for spawning child nodes

Think of it as a style sheet for 3D parts - define geometry as data, apply classes for shared attributes.

## Quick Start

```lua
local GeometrySpec = require(game.ReplicatedStorage.Lib.GeometrySpec)

local turretSpec = {
    bounds = {4, 6, 4},
    parts = {
        { id = "base", class = "frame", size = {4, 2, 4}, position = {0, 0, 0} },
        { id = "head", class = "frame", size = {3, 1.5, 3}, position = {0, 2, 0} },
        { id = "barrel", class = "accent", size = {0.5, 0.5, 3}, position = {0, 2.5, 1.5} },
    },
    classes = {
        frame = { Material = "DiamondPlate", Color = {80, 80, 85} },
        accent = { Material = "Metal", Color = {40, 40, 40} },
    },
}

local model = GeometrySpec.build(turretSpec)
```

## Core Concepts

### Bounded Containers

Every spec defines a bounding volume. Parts are positioned relative to this container.

```lua
{
    bounds = {width, height, depth},  -- in studs
    origin = "corner",                -- or "center", "floor-center"
    parts = { ... },
}
```

**Origin options:**
- `"corner"` - `{0,0,0}` at min corner (default)
- `"center"` - `{0,0,0}` at volume center
- `"floor-center"` - `{0,0,0}` at center XZ, Y=0 at floor

### Parts

Generic 3D elements with position, size, and optional class:

```lua
parts = {
    { id = "base", position = {0, 0, 0}, size = {4, 2, 4} },
    { id = "pillar", position = {2, 2, 2}, size = {1, 4, 1}, class = "metal" },
}
```

**Part properties:**
- `id` - Unique identifier (optional, required if you need to reference it)
- `position` - `{x, y, z}` relative to container origin
- `size` - `{width, height, depth}`
- `class` - Space-separated class names for styling
- `shape` - `"block"` (default), `"cylinder"`, `"sphere"`, `"wedge"`
- Any inline Roblox properties (Material, Color, etc.)

### Mount Points

Named positions for attaching child nodes:

```lua
mounts = {
    { id = "turret1", position = {5, 0, 5}, facing = {0, 0, 1} },
    { id = "turret2", position = {15, 0, 5}, facing = {0, 0, 1} },
    { id = "spawnPoint", position = {10, 0, -5}, class = "rearGuard" },
}
```

Mount points don't create geometry - they're positions for the orchestrator to spawn nodes at.

## Class-Based Styling

Three-level cascade: `defaults → classes → inline`

```lua
local spec = {
    defaults = {
        Anchored = true,
        CanCollide = true,
        Material = "SmoothPlastic",
    },

    classes = {
        frame = { Material = "DiamondPlate", Color = {80, 80, 85} },
        accent = { Material = "Metal", Color = {40, 40, 40} },
        trigger = { CanCollide = false, Transparency = 1 },
    },

    parts = {
        { id = "base", class = "frame", size = {4, 2, 4}, position = {0, 0, 0} },
        { id = "highlight", class = "frame accent", size = {1, 1, 1}, position = {0, 3, 0} },  -- multiple classes
        { id = "zone", class = "trigger", size = {10, 10, 10}, position = {0, 5, 0} },
    },
}
```

**Resolution order:**
1. Start with `defaults`
2. Merge each class (space-separated, left to right)
3. Merge inline properties (highest priority)

```lua
-- Implementation is ~5 lines
local function resolveAttrs(part, classes, defaults)
    local result = Table.clone(defaults or {})
    for className in (part.class or ""):gmatch("%S+") do
        Table.merge(result, classes[className] or {})
    end
    return Table.merge(result, part)
end
```

## Scale

Convert definition units to studs:

```lua
scale = "4:1"    -- 4 studs per 1 definition unit (e.g., meters)
scale = 4        -- Same as "4:1"
```

Useful for working in "real" units:

```lua
{
    scale = "4:1",  -- 1 unit = 1 meter = 4 studs
    bounds = {5, 3, 5},  -- 5m x 3m x 5m room
    parts = {
        { position = {2.5, 0, 2.5}, size = {1, 2, 1} },  -- 1m x 2m x 1m pillar
    },
}
```

## Scanner (Visual → Config Workflow)

Build geometry visually in Studio, export to config code.

**Workflow:**
1. Create parts in Studio (rough placement is fine)
2. Tag the container with `GeometrySpecTag = "area"`
3. Run scanner - get clean Lua config
4. Fine-tune in text editor (apply classes, adjust values)

### Basic Usage

```lua
-- In Studio command bar
local GeometrySpec = require(game.ReplicatedStorage.Lib.GeometrySpec)
GeometrySpec.scan(workspace.myContainer)
-- Outputs Lua config to console
```

### Explorer Structure

```
workspace
    myContainer (Part with GeometrySpecTag = "area")
        ├── base (Part)
        ├── pillar (Part)
        └── platform (Part)
```

### Attributes

Tag parts to guide the scanner:

| Attribute | Type | Description |
|-----------|------|-------------|
| `GeometrySpecId` | string | Part's `id` in config |
| `GeometrySpecClass` | string | Part's `class` in config |
| `GeometrySpecIgnore` | boolean | Skip this part |

### Auto-Cleanup (Snapping)

Scanner automatically cleans up small gaps (configurable threshold):
- Part edges snap to container bounds
- Parts snap to each other
- Sizes round to clean values

This bridges imprecise Studio placement to clean config output.

### Mirror Preview

Iterative workflow - see cleaned geometry before exporting:

```lua
GeometrySpec.mirror(workspace.myContainer)  -- Creates preview copy
-- Adjust original, run again to refresh
-- When satisfied:
GeometrySpec.scan(workspace.myContainer)    -- Export final config
```

## Zone Node Integration

When used as a Zone node component, GeometrySpec gains:
- Discovery handshake (standard node lifecycle)
- Player detection signals (PlayerEntered, PlayerExited)
- Interaction tracking
- Mount point coordination with orchestrator

```lua
-- Zone node uses GeometrySpec internally
local Zone = {
    spec = {
        bounds = {20, 10, 15},
        mounts = {
            { id = "turret1", position = {5, 0, 5}, facing = {0, 0, 1} },
        },
    },
    -- Signals: PlayerEntered, PlayerExited, MountReady, etc.
}
```

## API Reference

### Building

```lua
GeometrySpec.build(spec, parent)     -- Build geometry, returns Model
GeometrySpec.get(id)                 -- Get part by ID
GeometrySpec.clear()                 -- Clear registry before rebuild
```

### Class Resolution

```lua
GeometrySpec.resolve(part, spec)     -- Resolve all attributes for a part
```

### Scanner

```lua
GeometrySpec.scan(container, options)       -- Print config to console
GeometrySpec.scanToTable(container, options) -- Return config table
GeometrySpec.mirror(container, options)     -- Build preview copy
```

## Module Structure

```
GeometrySpec/
├── init.lua          -- Public API, build orchestration
├── ClassResolver.lua -- 3-level cascade resolution
└── Scanner.lua       -- Visual → config export
```

## Examples

### Turret Geometry

```lua
local turretSpec = {
    bounds = {4, 6, 4},
    defaults = { Anchored = true },
    classes = {
        frame = { Material = "DiamondPlate", Color = {80, 80, 85} },
        barrel = { Material = "Metal", Color = {40, 40, 40} },
    },
    parts = {
        { id = "base", class = "frame", position = {0, 0, 0}, size = {4, 2, 4} },
        { id = "head", class = "frame", position = {0, 2, 0}, size = {3, 1.5, 3} },
        { id = "barrel", class = "barrel", position = {0, 2.5, 1.5}, size = {0.5, 0.5, 3} },
    },
}
```

### Zone with Mount Points

```lua
local zoneSpec = {
    bounds = {40, 12, 30},
    defaults = { Anchored = true, CanCollide = true },
    classes = {
        concrete = { Material = "Concrete", Color = {180, 175, 165} },
        trigger = { CanCollide = false, Transparency = 1 },
    },
    parts = {
        { id = "floor", class = "concrete", position = {20, 0, 15}, size = {40, 0.5, 30} },
        { id = "detectionZone", class = "trigger", position = {20, 6, 15}, size = {40, 12, 30} },
    },
    mounts = {
        { id = "turret1", class = "frontLine", position = {10, 0.5, 5}, facing = {0, 0, 1} },
        { id = "turret2", class = "frontLine", position = {30, 0.5, 5}, facing = {0, 0, 1} },
        { id = "turret3", class = "rearGuard", position = {20, 0.5, 25}, facing = {0, 0, -1} },
    },
}
```

## Migration from MapLayout

If you have existing MapLayout configs:

| MapLayout | GeometrySpec |
|-----------|--------------|
| `walls`, `floors`, `platforms` | `parts` (use `shape` if needed) |
| `types` in styles | Remove (not needed) |
| `ids` in styles | Use inline properties |
| `#wallA:end` references | Use explicit positions or simple relative refs |
| `areas` | Use `mounts` for positions, nest specs for templates |
