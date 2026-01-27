--[[
    LibPureFiction Framework v2
    GeometrySpec/ClassResolver.lua - 3-Level Cascade Resolution

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Resolves properties for parts using a simple 3-level cascade:

        1. defaults - Applied to all parts
        2. classes - Applied by class (space-separated, in order)
        3. inline - Direct properties on the definition (highest priority)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local spec = {
        defaults = {
            Anchored = true,
            Material = "SmoothPlastic",
        },
        classes = {
            frame = { Material = "DiamondPlate", Color = {80, 80, 85} },
            accent = { Material = "Metal", Color = {40, 40, 40} },
        },
        parts = {
            { id = "base", class = "frame", ... },
            { id = "trim", class = "frame accent", ... },  -- multiple classes
        },
    }

    local resolved = ClassResolver.resolve(partDef, spec)
    ```

--]]

local ClassResolver = {}

-- Reserved keys that should not be treated as style properties
local RESERVED_KEYS = {
    -- Structural
    id = true,
    class = true,
    shape = true,

    -- Geometry definition
    position = true,
    size = true,
    height = true,
    radius = true,
    rotation = true,

    -- Mount points
    facing = true,
}

--[[
    Merge source table into target table (shallow).
    Later values override earlier ones.

    @param target: Table to merge into
    @param source: Table to merge from
    @return: The target table
--]]
local function merge(target, source)
    if not source then
        return target
    end

    for key, value in pairs(source) do
        target[key] = value
    end

    return target
end

--[[
    Parse class string into array of class names.
    "frame accent metal" -> {"frame", "accent", "metal"}

    @param classString: Space-separated class names
    @return: Array of class name strings
--]]
local function parseClasses(classString)
    if not classString or classString == "" then
        return {}
    end

    local classes = {}
    for class in classString:gmatch("%S+") do
        table.insert(classes, class)
    end
    return classes
end

--[[
    Extract inline styles from definition (non-reserved keys).

    @param definition: Part definition table
    @return: Table of inline style properties
--]]
local function extractInlineStyles(definition)
    local inline = {}

    for key, value in pairs(definition) do
        if not RESERVED_KEYS[key] then
            inline[key] = value
        end
    end

    return inline
end

--[[
    Resolve all styles for a part definition.

    Cascade order (lowest to highest priority):
        1. defaults - Applied to all parts
        2. classes[className] - Applied by class (in order)
        3. inline - Direct properties on the definition

    @param definition: The part definition table
    @param spec: The full spec { defaults, classes, ... }
    @return: Merged properties table
--]]
function ClassResolver.resolve(definition, spec)
    local resolved = {}

    -- Safety check
    if not spec then
        return extractInlineStyles(definition)
    end

    -- 1. Apply defaults
    if spec.defaults then
        merge(resolved, spec.defaults)
    end

    -- 2. Apply class styles (in order from class attribute)
    if definition.class and spec.classes then
        local classList = parseClasses(definition.class)
        for _, className in ipairs(classList) do
            if spec.classes[className] then
                merge(resolved, spec.classes[className])
            end
        end
    end

    -- 3. Apply inline styles (highest priority)
    local inlineStyles = extractInlineStyles(definition)
    merge(resolved, inlineStyles)

    return resolved
end

--[[
    Check if a definition has a specific class.

    @param definition: Part definition table
    @param className: Class name to check for
    @return: boolean
--]]
function ClassResolver.hasClass(definition, className)
    if not definition.class then
        return false
    end

    for class in definition.class:gmatch("%S+") do
        if class == className then
            return true
        end
    end

    return false
end

--[[
    Get all classes from a definition as an array.

    @param definition: Part definition table
    @return: Array of class name strings
--]]
function ClassResolver.getClasses(definition)
    return parseClasses(definition.class)
end

--[[
    Add a class to a definition's class string.

    @param definition: Part definition table
    @param className: Class name to add
--]]
function ClassResolver.addClass(definition, className)
    if ClassResolver.hasClass(definition, className) then
        return
    end

    if definition.class and definition.class ~= "" then
        definition.class = definition.class .. " " .. className
    else
        definition.class = className
    end
end

--[[
    Remove a class from a definition's class string.

    @param definition: Part definition table
    @param className: Class name to remove
--]]
function ClassResolver.removeClass(definition, className)
    if not definition.class then
        return
    end

    local classes = parseClasses(definition.class)
    local newClasses = {}

    for _, class in ipairs(classes) do
        if class ~= className then
            table.insert(newClasses, class)
        end
    end

    definition.class = table.concat(newClasses, " ")
end

return ClassResolver
