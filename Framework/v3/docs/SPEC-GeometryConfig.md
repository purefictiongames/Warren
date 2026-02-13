# Geometry Config Cascade Specification

**Status:** Draft
**Date:** 2026-02-03
**Context:** Extend Factory/Geometry.lua to support dimension config cascade

## Overview

Extend the existing Factory/Geometry system so that **dimension config is part of the class system** and cascades through xrefs, enabling centralized dimension management and derived value computation.

This addresses the root causes from POSTMORTEM-terrain-attempt-1.md without creating parallel infrastructure.

## Design Principles

1. **Corner-based coordinates only** - All positions use corner origin (0,0,0), no center-based
2. **Config is class data** - Dimensions live in the class system alongside styling
3. **Extend existing reference system** - Use `config.wallThickness` not `$wallThickness`
4. **Bounds are required** - Explicit `bounds = {X, Y, Z}` on all layouts (XHTML strict philosophy)
5. **Errors break build** - Missing references fail loudly with clear messages

## Current State

**What exists:**
- `ClassResolver` - CSS-like cascade for style properties
- `Factory/Geometry` - Part resolution, xref composition, arrays, CSG
- Cascade: parent → defaults → base[type] → classes → ids → inline
- `bounds` field already in spec format (see _Example.lua)

**What's missing:**
- Dimension values (wallThickness, baseUnit) don't participate in cascade
- Derived values (gap = 2 × wallThickness) computed manually everywhere
- No way for parent layouts to override child layout dimensions via xref
- No unified query interface for nodes at runtime

## Changes to Spec Structure

### Dimensions in Classes

Dimensions become part of the class system, alongside styling:

```lua
return {
    name = "DungeonRoom",
    spec = {
        -- REQUIRED: Explicit bounds (X, Y, Z)
        bounds = { X = 40, Y = 30, Z = 40 },

        -- Coordinate system (corner-based only)
        origin = "corner",

        -- Classes include BOTH styling AND dimensions
        classes = {
            -- Styling
            exterior = { Material = "Brick", Color = {140, 110, 90} },

            -- Dimensions (same cascade system)
            room = {
                wallThickness = 1,
                baseUnit = 5,
                doorSize = 12,
            },

            -- Combined (styling + dimensions together)
            fortress = {
                wallThickness = 4,
                Material = "Cobblestone",
                Color = {80, 80, 85},
            },
        },

        -- Layout-level class (parts inherit from this)
        class = "room",

        -- Parts
        parts = {
            { id = "Floor", class = "exterior", position = {0, 0, 0}, size = {40, 1, 40} },
        },
    },
}
```

### Class Inheritance via xref

When a layout xrefs another, classes cascade down:

```lua
-- Parent layout
return {
    name = "Dungeon",
    spec = {
        bounds = { X = 200, Y = 50, Z = 200 },
        class = "fortress",  -- Layout-level class

        classes = {
            fortress = { wallThickness = 4 },
        },

        parts = {
            { id = "Room1", xref = RoomLayout, position = {0, 0, 0} },
            { id = "Room2", xref = RoomLayout, position = {100, 0, 0},
              class = "thin" },  -- Override for this room
        },
    },
}

-- Child layout (RoomLayout)
return {
    name = "Room",
    spec = {
        bounds = { X = 40, Y = 30, Z = 40 },
        class = "room",  -- Default class

        classes = {
            room = { wallThickness = 1 },
            thin = { wallThickness = 0.5 },
        },

        parts = { ... },
    },
}
```

Resolution:
- Room1 gets `wallThickness = 4` (from parent's fortress class)
- Room2 gets `wallThickness = 0.5` (from inline thin class override)

## Changes to Geometry.lua

### 1. Config Proxy for Static Layouts

The `Geometry.cfg` proxy creates reference markers that resolve during the build phase:

```lua
local Geometry = require(path.to.Factory.Geometry)
local cfg = Geometry.cfg

return {
    name = "ExteriorWalls",
    spec = {
        bounds = { X = 64, Y = 10, Z = 40 },

        classes = {
            walls = {
                MAIN_W = 64,
                MAIN_D = 40,
                WALL_H = 10,
                WALL_T = 0.5,
            },
            wall = { Material = "SmoothPlastic", Color = {240, 235, 225} },
        },

        class = "walls",

        parts = {
            { id = "WallSouth", class = "wall",
              position = {0, 0, 0},
              size = {cfg.MAIN_W, cfg.WALL_H, cfg.WALL_T} },

            { id = "WallEast", class = "wall",
              position = {cfg.MAIN_W - cfg.WALL_T, 0, 0},
              size = {cfg.WALL_T, cfg.WALL_H, cfg.MAIN_D} },
        },
    },
}
```

When `cfg.MAIN_W` is accessed, it returns a marker `{ __isConfigRef = true, key = "MAIN_W" }`.
During `Geometry.resolve()`, markers are replaced with values from the resolved class cascade.

### 2. Config Resolution via Class Cascade

Config values resolve through the same ClassResolver cascade as styling:

```lua
-- In resolve(), when processing a part or xref:
local resolvedConfig = ClassResolver.resolve({
    class = partDef.class or spec.class,
    id = partDef.id,
}, spec, {
    -- Include dimension keys in resolution
    reservedKeys = { ... }  -- Exclude geometry keys, include config keys
})
```

### 3. Error on Missing References

Config references that can't be resolved throw clear errors:

```lua
-- In resolveReferences(), when a config ref is not found:
if not resolvedConfig[key] then
    error(string.format(
        "[Geometry] Config reference '%s' not found in layout '%s'. " ..
        "Check that the value is defined in classes or parent layout.",
        key, layoutName
    ))
end
```

### 4. Derived Value Registration

Module-level registration for computed values:

```lua
local derivedValues = {}

function Geometry.registerDerived(name, fn)
    derivedValues[name] = fn
end

-- Built-in derived values
Geometry.registerDerived("gap", function(cfg)
    return 2 * (cfg.wallThickness or 1)
end)

Geometry.registerDerived("shellSize", function(cfg, interiorDims)
    local wt = cfg.wallThickness or 1
    return {
        interiorDims[1] + 2 * wt,
        interiorDims[2] + 2 * wt,
        interiorDims[3] + 2 * wt,
    }
end)

Geometry.registerDerived("cutterDepth", function(cfg)
    return (cfg.wallThickness or 1) * 8
end)
```

### 5. Context Object for Runtime Queries

For nodes that need to query resolved config at runtime:

```lua
function Geometry.createContext(spec, parentContext)
    local ctx = {}

    -- Resolve config through class cascade
    local resolvedConfig = ClassResolver.resolve({
        class = spec.class,
    }, spec)

    -- Merge with parent context
    if parentContext then
        local merged = {}
        for k, v in pairs(parentContext.resolved) do merged[k] = v end
        for k, v in pairs(resolvedConfig) do merged[k] = v end
        resolvedConfig = merged
    end

    ctx.resolved = resolvedConfig

    function ctx:get(key, default)
        local value = self.resolved[key]
        if value ~= nil then return value end
        return default
    end

    function ctx:getDerived(name, ...)
        local fn = derivedValues[name]
        if not fn then
            error("Unknown derived value: " .. name)
        end
        return fn(self.resolved, ...)
    end

    function ctx:child(childSpec)
        return Geometry.createContext(childSpec, self)
    end

    return ctx
end
```

## Integration Points

### With LayoutBuilder (Runtime)

```lua
function LayoutBuilder.generate(config)
    -- Create context from generation config
    local ctx = Geometry.createContext({
        config = {
            wallThickness = config.wallThickness or 1,
            baseUnit = config.baseUnit or 5,
            doorSize = config.doorSize or 12,
        }
    })

    -- Use context for all calculations
    local gap = ctx:getDerived("gap")

    -- Pass context to planning functions
    local rooms = planRooms(cfg, ctx)
    local doors = planDoors(rooms, cfg, ctx)

    -- Store context in layout for instantiation
    layout.config = ctx.config
end
```

### With Static Layouts (Using cfg Proxy)

```lua
-- FlemishShop1_BaseShell.lua
local Geometry = require(path.to.Factory.Geometry)
local cfg = Geometry.cfg

return {
    name = "FlemishShop1_BaseShell",
    spec = {
        bounds = { X = 40, Y = 31, Z = 40 },

        classes = {
            shell = {
                W = 40,
                D = 40,
                WALL = 1,
                WALL_H = 30,
            },
            exterior = { Material = "SmoothPlastic", Color = {120, 115, 110} },
        },

        class = "shell",

        parts = {
            { id = "Floor", class = "exterior",
              position = {0, 0, 0},
              size = {cfg.W, 1, cfg.D} },

            { id = "Wall_South", class = "exterior",
              position = {0, 1, 0},
              size = {cfg.W, cfg.WALL_H, cfg.WALL} },

            -- Arithmetic works too
            { id = "Wall_East", class = "exterior",
              position = {cfg.W - cfg.WALL, 1, 0},
              size = {cfg.WALL, cfg.WALL_H, cfg.D} },
        },
    },
}
```

### With ShellBuilder Node

```lua
In = {
    onBuildShell = function(self, data)
        -- Get context from data or create default
        local ctx = data.ctx or Geometry.createContext({
            config = { wallThickness = data.wallThickness or 1 }
        })

        local wt = ctx:get("wallThickness")
        local shellBounds = ctx:getDerived("shellSize", data.dims)

        -- Build using resolved values
    end,
}
```

### With DoorCutter Node

```lua
In = {
    onCutDoor = function(self, data)
        local ctx = data.ctx
        local cutterDepth = ctx:getDerived("cutterDepth")

        -- Cutter geometry uses derived value
        local cutterSize = { door.width, door.height, cutterDepth }
    end,
}
```

## Migration Path

### Phase 1: Add Config to Geometry.lua
- Add `config` handling in `resolve()`
- Add config cascade in `expandXrefs()`
- Add `$variable` resolution in part sizes/positions

### Phase 2: Add Derived Values
- Add `registerDerived()` function
- Register built-in derived values (gap, shellSize, cutterDepth)
- Add `createContext()` for runtime queries

### Phase 3: Migrate LayoutBuilder
- Create context at start of `generate()`
- Replace inline calculations with context queries
- Pass context through planning functions

### Phase 4: Migrate Nodes
- ShellBuilder: use context for wall thickness
- DoorCutter: use context for cutter depth
- LayoutInstantiator: use context for all geometry

### Phase 5: Re-attempt Terrain
- TerrainManager uses same context
- Clearing geometry matches CSG geometry automatically
- Single source of truth achieved

## Example: Full Flow

```lua
local Geometry = require(path.to.Factory.Geometry)
local cfg = Geometry.cfg

-- 1. Derived values are pre-registered (gap, shellSize, cutterDepth)
-- Register custom ones if needed:
Geometry.registerDerived("totalHeight", function(config)
    return config.WALL_H + config.FLOOR_H + config.CEILING_H
end)

-- 2. Define layout with config in classes
local DungeonRoom = {
    name = "DungeonRoom",
    spec = {
        bounds = { X = 40, Y = 32, Z = 40 },

        classes = {
            room = {
                wallThickness = 1,
                baseUnit = 5,
                W = 40,
                D = 40,
                WALL_H = 30,
            },
            fortress = {
                wallThickness = 4,  -- Override for thick walls
            },
        },

        class = "room",  -- Use room config by default

        parts = {
            { id = "Floor", position = {0, 0, 0}, size = {cfg.W, 1, cfg.D} },
            { id = "Wall_South", position = {0, 1, 0},
              size = {cfg.W, cfg.WALL_H, cfg.wallThickness} },
        },
    },
}

-- 3. Build with Geometry
local model = Geometry.build(DungeonRoom, workspace)

-- 4. Or create context for runtime queries
local ctx = Geometry.createContext(DungeonRoom.spec)
print(ctx:get("wallThickness"))     -- 1
print(ctx:get("W"))                 -- 40
print(ctx:getDerived("gap"))        -- 2 (2 * wallThickness)

-- 5. Child context with fortress override
local fortressCtx = ctx:child({
    class = "fortress",
    classes = DungeonRoom.spec.classes,
})
print(fortressCtx:get("wallThickness")) -- 4
print(fortressCtx:getDerived("gap"))    -- 8
```

## Resolved Decisions

| Question | Decision |
|----------|----------|
| Coordinate system | Corner-based only (no center-based) |
| Config location | Part of class system, not separate section |
| Reference syntax | Extend existing system: `config.wallThickness` |
| Error handling | Break build with clear error message |
| Voxel snapping | Derived values only, no constraint system |
| Debugging | Use existing debug system (toTSV, scan) |
| Bounds | Required, explicit: `bounds = { X, Y, Z }` |

## Remaining Open Questions

1. ~~**Static vs function-based:**~~ **RESOLVED** - Static tables use `Geometry.cfg` proxy (e.g., `cfg.wallThickness`). No function-based layouts required.

2. ~~**Reserved keys:**~~ **RESOLVED** - Dimension keys cascade like any other property. No special handling needed.

3. **Backwards compatibility:** Skip for now - most existing layouts are lab tests, not production. Can write converter later if needed.

## Future Direction

The class system will eventually unify with the node system to support a DOM-like API for manipulating content and behavior at runtime. This config cascade work lays groundwork for that unification.

---

*This spec extends Factory/Geometry.lua rather than creating parallel infrastructure, maintaining architectural consistency.*
