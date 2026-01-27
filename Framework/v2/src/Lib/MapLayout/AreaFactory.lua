--[[
    LibPureFiction Framework v2
    MapLayout/AreaFactory.lua - Area Template Definition and Registration

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    AreaFactory manages area templates (prefabs) that can be instantiated
    multiple times in a map. Think of areas like <div> tags in HTML - they
    define bounded 3D spaces that contain geometry and can be nested.

    Areas:
    - Define a bounding volume (width, height, depth)
    - Have identity (class/ID for styling and targeting)
    - Establish local coordinate systems for contained geometry
    - Can be placed/anchored in the world or to other elements
    - Can be nested (areas within areas)
    - Can be instantiated multiple times (prefabs)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local AreaFactory = require(path.to.AreaFactory)

    -- Define an area template
    AreaFactory.define("hallway", {
        bounds = {20, 8, 6},      -- width (x), height (y), depth (z)
        origin = "corner",        -- where {0,0,0} is in local space
        class = "hallway interior",

        walls = {
            { id = "north", from = {0, 0}, to = {20, 0}, height = 8 },
            { id = "south", from = {0, 6}, to = {20, 6}, height = 8 },
        },
        floors = {
            { id = "floor", position = {10, 0, 3}, size = {20, 6} },
        },
    })

    -- Use in a map definition
    local mapDef = {
        areas = {
            { template = "hallway", id = "hall1", position = {0, 0, 0} },
            { template = "hallway", id = "hall2", anchor = "#hall1", surface = "+x" },
        },
    }
    ```

    ============================================================================
    ORIGIN OPTIONS
    ============================================================================

    "corner" (default):
        {0,0,0} is at the minimum corner (minX, minY, minZ)
        Bounds extend in +X, +Y, +Z directions

    "center":
        {0,0,0} is at the center of the bounds
        Bounds extend equally in all directions

    "floor-center":
        {0,0,0} is at the center of the floor (centerX, minY, centerZ)
        Good for room definitions where Y=0 is the floor

--]]

local AreaFactory = {}

-- Registered area templates
local templates = {}

-- Origin offset calculators
local ORIGIN_OFFSETS = {
    -- Corner: no offset, {0,0,0} is at min corner
    ["corner"] = function(bounds)
        return Vector3.new(0, 0, 0)
    end,

    -- Center: offset so {0,0,0} is at center
    ["center"] = function(bounds)
        return Vector3.new(bounds[1] / 2, bounds[2] / 2, bounds[3] / 2)
    end,

    -- Floor-center: centered on X/Z, but Y=0 is floor
    ["floor-center"] = function(bounds)
        return Vector3.new(bounds[1] / 2, 0, bounds[3] / 2)
    end,
}

--[[
    Validate an area template definition.

    @param name: Template name
    @param definition: Template definition table
    @return: true if valid, or false and error message
--]]
local function validateTemplate(name, definition)
    if not name or type(name) ~= "string" or name == "" then
        return false, "Area template name must be a non-empty string"
    end

    if not definition then
        return false, string.format("Area template '%s' has no definition", name)
    end

    if not definition.bounds then
        return false, string.format("Area template '%s' missing required 'bounds' property", name)
    end

    local bounds = definition.bounds
    if type(bounds) ~= "table" or #bounds < 3 then
        return false, string.format("Area template '%s' bounds must be {width, height, depth}", name)
    end

    for i, dim in ipairs({bounds[1], bounds[2], bounds[3]}) do
        if type(dim) ~= "number" or dim <= 0 then
            local dimNames = {"width", "height", "depth"}
            return false, string.format(
                "Area template '%s' bounds %s must be a positive number, got: %s",
                name, dimNames[i], tostring(dim)
            )
        end
    end

    -- Validate origin if specified
    if definition.origin then
        if not ORIGIN_OFFSETS[definition.origin] then
            local validOrigins = {}
            for k in pairs(ORIGIN_OFFSETS) do
                table.insert(validOrigins, '"' .. k .. '"')
            end
            return false, string.format(
                "Area template '%s' has invalid origin '%s'. Valid options: %s",
                name, definition.origin, table.concat(validOrigins, ", ")
            )
        end
    end

    return true
end

--[[
    Define and register an area template.

    @param name: Unique template name
    @param definition: Template definition table
        - bounds: {width, height, depth} - required
        - origin: "corner" | "center" | "floor-center" - default "corner"
        - class: CSS-like class string
        - scale: Optional scale override for this area
        - walls, platforms, floors, etc.: Geometry definitions
        - areas: Nested area definitions or instances
--]]
function AreaFactory.define(name, definition)
    local valid, err = validateTemplate(name, definition)
    if not valid then
        error("[AreaFactory] " .. err, 2)
    end

    if templates[name] then
        warn(string.format("[AreaFactory] Redefining area template '%s'", name))
    end

    -- Store with defaults
    templates[name] = {
        name = name,
        bounds = {
            definition.bounds[1],
            definition.bounds[2],
            definition.bounds[3],
        },
        origin = definition.origin or "corner",
        class = definition.class,
        scale = definition.scale,

        -- Geometry categories
        walls = definition.walls,
        platforms = definition.platforms,
        boxes = definition.boxes,
        floors = definition.floors,
        cylinders = definition.cylinders,
        spheres = definition.spheres,
        wedges = definition.wedges,
        elements = definition.elements,

        -- Nested areas
        areas = definition.areas,
    }

    return templates[name]
end

--[[
    Get a registered template by name.

    @param name: Template name
    @return: Template definition or nil
--]]
function AreaFactory.get(name)
    return templates[name]
end

--[[
    Check if a template exists.

    @param name: Template name
    @return: boolean
--]]
function AreaFactory.exists(name)
    return templates[name] ~= nil
end

--[[
    Get the origin offset for an area's origin type.

    @param origin: Origin type string
    @param bounds: {width, height, depth}
    @return: Vector3 offset from corner to origin
--]]
function AreaFactory.getOriginOffset(origin, bounds)
    local calculator = ORIGIN_OFFSETS[origin or "corner"]
    if calculator then
        return calculator(bounds)
    end
    return Vector3.new(0, 0, 0)
end

--[[
    Create an instance definition from a template.
    Does NOT build geometry - just creates the instance data.

    @param templateName: Name of registered template
    @param instanceConfig: Instance-specific overrides
        - id: Required unique instance ID
        - position: World position or reference
        - anchor: Anchor configuration
        - class: Additional classes (appended to template class)
        - scale: Scale override
    @return: Instance definition table
--]]
function AreaFactory.createInstance(templateName, instanceConfig)
    local template = templates[templateName]
    if not template then
        error(string.format("[AreaFactory] Unknown template '%s'", templateName), 2)
    end

    if not instanceConfig.id then
        error("[AreaFactory] Instance must have an 'id'", 2)
    end

    -- Merge template with instance config
    local instance = {
        _isAreaInstance = true,
        _templateName = templateName,

        id = instanceConfig.id,
        bounds = template.bounds,
        origin = instanceConfig.origin or template.origin,
        scale = instanceConfig.scale or template.scale,

        -- Combine classes
        class = template.class,

        -- Position/anchor
        position = instanceConfig.position,
        anchor = instanceConfig.anchor,
        surface = instanceConfig.surface,
        offset = instanceConfig.offset,
        rotation = instanceConfig.rotation,

        -- Copy geometry from template (will be transformed during build)
        walls = template.walls,
        platforms = template.platforms,
        boxes = template.boxes,
        floors = template.floors,
        cylinders = template.cylinders,
        spheres = template.spheres,
        wedges = template.wedges,
        elements = template.elements,
        areas = template.areas,
    }

    -- Append additional classes if provided
    if instanceConfig.class then
        if instance.class then
            instance.class = instance.class .. " " .. instanceConfig.class
        else
            instance.class = instanceConfig.class
        end
    end

    return instance
end

--[[
    List all registered template names.

    @return: Array of template names
--]]
function AreaFactory.list()
    local names = {}
    for name in pairs(templates) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--[[
    Clear all registered templates.
--]]
function AreaFactory.clear()
    templates = {}
end

--[[
    Get the bounds as a Vector3.

    @param bounds: {width, height, depth} array
    @return: Vector3
--]]
function AreaFactory.boundsToVector3(bounds)
    return Vector3.new(bounds[1], bounds[2], bounds[3])
end

return AreaFactory
