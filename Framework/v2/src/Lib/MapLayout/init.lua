--[[
    LibPureFiction Framework v2
    MapLayout/init.lua - Declarative 3D Map Definition System

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    MapLayout is a declarative system for defining 3D game maps using Lua tables.
    Similar to the GUI Layout system but for architectural elements like walls,
    floors, stairs, doors, and windows.

    Think of it like CAD/architectural drafting - you define geometry with
    positions, dimensions, and relationships rather than drag-and-drop placement.

    Key features:
    - Declarative table-based definitions
    - CSS-like class/ID system for styling and targeting
    - Relative positioning (reference other elements by ID)
    - Surface-based attachments (weld objects to specific surfaces)
    - Cascade-based property resolution (defaults → class → id → inline)

    ============================================================================
    USAGE
    ============================================================================

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

    -- Target elements by ID for attachments
    local mount = MapLayout.Registry:Get("#turretMount")
    ```

    ============================================================================
    COORDINATE SYSTEM
    ============================================================================

    - 2D footprint uses {x, z} coordinates (horizontal plane)
    - Height (y) is specified separately as a property
    - Full 3D positions use {x, y, z} when needed
    - Units are studs (Roblox native units), but see SCALE below

    ============================================================================
    SCALE
    ============================================================================

    Maps can define a scale factor to convert definition units to studs:

        scale = "4:1"    -- 4 studs per 1 definition unit
        scale = "1:2"    -- 0.5 studs per 1 definition unit
        scale = 4        -- Same as "4:1"

    Example: Working in "meters" where 1 meter = 4 studs:

        local mapDef = {
            scale = "4:1",
            walls = {
                { from = {0, 0}, to = {10, 0}, height = 3 },  -- 40 studs long, 12 studs tall
            },
        }

    Scale applies to literal positions and dimensions.
    Referenced positions (#wallA:end) are already in studs.
    Elements can override with their own scale: { scale = "2:1", ... }

    ============================================================================
    REFERENCE SYNTAX
    ============================================================================

    Elements can reference other elements by ID:

    Selectors:
        "#wallA"           - Reference element with id "wallA"
        ".exterior"        - (future) Reference elements with class "exterior"

    Reference points:
        "#wallA:start"     - Starting point (from)
        "#wallA:end"       - Ending point (to)
        "#wallA:center"    - Midpoint
        "#wallA:farX"      - Endpoint with larger X value
        "#wallA:farZ"      - Endpoint with larger Z value
        "#wallA:nearX"     - Endpoint with smaller X value
        "#wallA:nearZ"     - Endpoint with smaller Z value

    Along positioning:
        { along = "#wallA", at = 20 }           - 20 studs from start
        { along = "#wallA", at = "50%" }        - 50% along length
        { along = "#wallA", at = 20, surface = "-x" }  - On the -X surface

    ============================================================================
    SURFACE NOTATION
    ============================================================================

    For blocks/rectangles:
        "+x", "-x", "+y", "-y", "+z", "-z"
        Or aliases: "top", "bottom", "front", "back", "left", "right"

    For cylinders:
        "top", "bottom"
        { barrel = 90 }     - Angle around circumference (degrees)

    For spheres:
        { direction = {0, 1, 0} }   - Normalized vector
        { azimuth = 45, elevation = 30 }  - Spherical coordinates

    For wedges:
        "slope", "base", "back", "left", "right"

    ============================================================================
    AREAS (PREFABS)
    ============================================================================

    Areas are bounded 3D containers that work like HTML <div> tags:
    - Define a bounding volume (width, height, depth)
    - Have identity (class/ID for styling and targeting)
    - Establish local coordinate systems for contained geometry
    - Can be nested (areas within areas)
    - Can be instantiated multiple times (prefab system)

    Defining an area template:
        ```lua
        MapLayout.AreaFactory.define("hallway", {
            bounds = {20, 8, 6},      -- width, height, depth
            origin = "corner",        -- or "center", "floor-center"
            class = "hallway interior",

            walls = {
                { id = "north", from = {0, 0}, to = {20, 0}, height = 8 },
            },
        })
        ```

    Using areas in a map:
        ```lua
        local mapDef = {
            areas = {
                { template = "hallway", id = "hall1", position = {0, 0, 0} },
                { template = "hallway", id = "hall2", anchor = "#hall1", surface = "+x" },
            },
        }
        ```

    Origin options:
        "corner"       - {0,0,0} at min corner (default)
        "center"       - {0,0,0} at center of bounds
        "floor-center" - {0,0,0} at center XZ, Y=0 at floor

    IMPORTANT: Geometry must stay within area bounds. If any element
    exceeds bounds, the build will FAIL with detailed error messages.

    ============================================================================
    SCANNER (REVERSE WORKFLOW)
    ============================================================================

    Scanner lets you build geometry visually in Studio, then convert it to
    MapLayout config code.

    AREA SCANNING (Recommended):
    1. Create a Part, name it (e.g., "testArea")
    2. Add attribute: MapLayoutTag = "area"
    3. Nest geometry parts as CHILDREN under it in Explorer:
           testArea (Part, MapLayoutTag = "area")
               ├── northWall (Part)
               ├── southWall (Part)
               └── floor (Part)
    4. Run:
       ```lua
       require(game.ReplicatedStorage.Lib.MapLayout).scanArea("testArea")
       ```
    5. Copy generated code from output
    6. Delete original parts, use config going forward

    LIVE MIRROR PREVIEW:
    For iterative development, use mirrorArea to see a cleaned-up copy:
       ```lua
       local mirror = MapLayout.mirrorArea("testArea")
       -- Adjust original parts...
       mirror = mirror.refresh()  -- Update the mirror
       -- When satisfied:
       mirror.cleanup()
       MapLayout.scanArea("testArea")  -- Export final config
       ```

    AUTO-CLEANUP:
    The scanner automatically snaps geometry within 0.5 studs:
    - Wall endpoints snap to area boundaries and other walls
    - Floor/platform edges expand to fill small gaps
    - Wall heights snap to area height

    OPTIONAL ATTRIBUTES:
       - MapLayoutTag: Set to "area" for bounding box parts
       - MapLayoutType: Override inferred type ("wall", "floor", etc.)
       - MapLayoutIgnore: Skip this part

    The scanner auto-detects element types:
    - Tall thin parts → walls
    - Flat wide parts → floors
    - Everything else → platforms
    - Ball shapes → spheres
    - Cylinders → cylinders
    - WedgeParts → wedges

--]]

local MapLayout = {
    _VERSION = "1.0.0-dev",
}

-- Core modules
MapLayout.StyleResolver = require(script.StyleResolver)
MapLayout.Registry = require(script.Registry)
MapLayout.ReferenceResolver = require(script.ReferenceResolver)
MapLayout.GeometryFactory = require(script.GeometryFactory)
MapLayout.MapBuilder = require(script.MapBuilder)

-- Area system (prefabs)
MapLayout.AreaFactory = require(script.AreaFactory)
MapLayout.AreaBuilder = require(script.AreaBuilder)
MapLayout.BoundsValidator = require(script.BoundsValidator)

-- Scanner (reverse workflow: geometry → config)
MapLayout.Scanner = require(script.Scanner)

--[[
    Build a map from a definition and optional styles.

    @param definition: The map definition table
    @param styles: Optional stylesheet for classes/ids
    @param parent: Optional parent instance (default: workspace)
    @return: Model containing all generated geometry
--]]
function MapLayout.build(definition, styles, parent)
    return MapLayout.MapBuilder.build(definition, styles, parent)
end

--[[
    Get an element by selector.

    @param selector: ID selector (e.g., "#wallA") or element ID
    @return: The registered element data, or nil if not found
--]]
function MapLayout.get(selector)
    return MapLayout.Registry.get(selector)
end

--[[
    Get the Part/Model instance for an element.

    @param selector: ID selector or element ID
    @return: The Roblox instance, or nil if not found
--]]
function MapLayout.getInstance(selector)
    local entry = MapLayout.Registry.get(selector)
    return entry and entry.instance or nil
end

--[[
    Clear the registry (call before rebuilding a map).
--]]
function MapLayout.clear()
    MapLayout.Registry.clear()
end

--[[
    Get the current build scale factor.

    @return: Scale factor (number)
--]]
function MapLayout.getScale()
    return MapLayout.MapBuilder.getScale()
end

--[[
    Parse a scale value.

    @param scaleValue: Scale definition ("5:1", 5, "1:2", 0.5)
    @return: Numeric scale factor
--]]
function MapLayout.parseScale(scaleValue)
    return MapLayout.MapBuilder.parseScale(scaleValue)
end

--[[
    Convert a value from definition units to studs.

    @param value: Number or array in definition units
    @return: Value in studs
--]]
function MapLayout.toStuds(value)
    return MapLayout.MapBuilder.toStuds(value)
end

--[[
    Convert a value from studs to definition units.

    @param value: Number or array in studs
    @return: Value in definition units
--]]
function MapLayout.fromStuds(value)
    return MapLayout.MapBuilder.fromStuds(value)
end

--[[
    Define an area template (prefab).

    @param name: Unique template name
    @param definition: Area definition with bounds and geometry
--]]
function MapLayout.defineArea(name, definition)
    return MapLayout.AreaFactory.define(name, definition)
end

--[[
    Check if an area template exists.

    @param name: Template name
    @return: boolean
--]]
function MapLayout.hasArea(name)
    return MapLayout.AreaFactory.exists(name)
end

--[[
    Validate an area definition without building it.
    Returns validation result with any errors.

    @param areaId: Area identifier for error messages
    @param areaDef: Area definition to validate
    @return: ValidationResult with isValid, errors, format() method
--]]
function MapLayout.validateArea(areaId, areaDef)
    local origin = areaDef.origin or "corner"
    local originOffset = MapLayout.AreaFactory.getOriginOffset(origin, areaDef.bounds or {0, 0, 0})
    return MapLayout.BoundsValidator.validate(areaId, areaDef, originOffset)
end

--[[
    Clear all registered area templates.
--]]
function MapLayout.clearAreas()
    MapLayout.AreaFactory.clear()
end

--[[
    Scan geometry and generate MapLayout config code.

    Usage in Studio command bar:
        require(game.ReplicatedStorage.Lib.MapLayout).scan(workspace.MyLayout)

    @param container: Model, Folder, etc. containing geometry
    @param options: Optional configuration
    @return: Lua code string (also printed to output)
--]]
function MapLayout.scan(container, options)
    options = options or {}
    options.includeStyles = options.includeStyles ~= false  -- Default true

    local code = MapLayout.Scanner.scanToCode(container, options)

    -- Print to output for easy copy
    print("\n" .. string.rep("=", 70))
    print("-- MapLayout Scanner Output for: " .. container.Name)
    print("-- Copy the code below into your layout definition file")
    print(string.rep("=", 70))
    print(code)
    print(string.rep("=", 70) .. "\n")

    return code
end

--[[
    Scan geometry and get config table (without code generation).

    @param container: Model, Folder, etc.
    @param options: Optional configuration
    @return: Config table
--]]
function MapLayout.scanToTable(container, options)
    return MapLayout.Scanner.scan(container, options)
end

--[[
    Scan a named area.

    Find a part named `areaName` with MapLayoutTag = "area",
    use it as the bounding box, and scan its CHILDREN for geometry.

    Explorer structure:
        testArea (Part with MapLayoutTag = "area")
            ├── wall1 (Part)
            ├── wall2 (Part)
            └── floor1 (Part)

    Usage:
        MapLayout.scanArea("testArea")
        MapLayout.scanArea("testArea", workspace)

    @param areaName: Name of the area part (Roblox Name property)
    @param container: Where to search (default: workspace)
    @param options: Optional configuration
    @return: Lua code string (also printed to output)
--]]
function MapLayout.scanArea(areaName, container, options)
    container = container or workspace
    options = options or {}

    local config = MapLayout.Scanner.scanArea(areaName, container, options)
    if not config then
        return nil
    end

    local code = MapLayout.Scanner.generateCode(config, options)

    -- Print to output for easy copy
    print("\n" .. string.rep("=", 70))
    print("-- MapLayout Scanner Output for area: " .. areaName)
    print("-- Copy the code below into your layout definition file")
    print(string.rep("=", 70))
    print(code)
    print(string.rep("=", 70) .. "\n")

    return code
end

--[[
    Mirror an area: scan and build a clean copy adjacent to the original.

    Live preview tool for iterating on layouts:
    1. Build rough geometry in Studio
    2. Run mirrorArea
    3. See the snapped/cleaned version next to the original
    4. Adjust original parts and call result.refresh()
    5. When satisfied, export with scanArea

    Usage:
        local mirror = MapLayout.mirrorArea("testArea")
        -- Make changes to original...
        mirror = mirror.refresh()  -- Update mirror
        -- When done:
        mirror.cleanup()

    @param areaName: Name of the area part
    @param container: Where to search (default: workspace)
    @param options: Optional configuration
        - offset: Direction ("x", "-x", "z", "-z") default: "x"
        - gap: Studs between original and mirror (default: 2)
        - styles: Style definitions
    @return: { model, config, cleanup(), refresh() }
--]]
function MapLayout.mirrorArea(areaName, container, options)
    return MapLayout.Scanner.mirrorArea(areaName, container, options)
end

--[[
    List all areas found in a container.

    @param container: Where to search (default: workspace)
--]]
function MapLayout.listAreas(container)
    local areas = MapLayout.Scanner.findAreas(container or workspace)

    print("\n=== MapLayout Areas ===")
    if #areas == 0 then
        print("  No areas found.")
        print("  Tag a part with MapLayoutTag = 'area' and MapLayoutName = 'yourName'")
    else
        for _, area in ipairs(areas) do
            local size = area.part.Size
            print(string.format("  %s: bounds {%.1f, %.1f, %.1f} at %s",
                area.name,
                size.X, size.Y, size.Z,
                tostring(area.part.Position)
            ))
        end
    end
    print("=======================\n")

    return areas
end

return MapLayout
