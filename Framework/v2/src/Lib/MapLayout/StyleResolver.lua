--[[
    LibPureFiction Framework v2
    MapLayout/StyleResolver.lua - CSS-like Cascade Resolution for 3D Elements

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Resolves properties for map elements using CSS-like cascade order:
        1. Base defaults (applied to all elements)
        2. Type defaults (by element type: wall, platform, etc.)
        3. Class styles (in order of class attribute string)
        4. ID styles
        5. Inline properties (highest priority)

    Later styles override earlier ones (cascade).

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local styles = {
        defaults = {
            Anchored = true,
            CanCollide = true,
            Material = "SmoothPlastic",
        },
        types = {
            wall = { thickness = 1 },
            platform = { thickness = 2 },
        },
        classes = {
            ["exterior"] = { Material = "Concrete" },
            ["brick"] = { Material = "Brick", Color = {180, 120, 100} },
            ["metal"] = { Material = "DiamondPlate" },
            ["trigger"] = { CanCollide = false, Transparency = 1 },
        },
        ids = {
            ["mainEntrance"] = { Color = {200, 50, 50} },
        },
    }

    local resolved = StyleResolver.resolve(elementDef, styles)
    ```

--]]

local StyleResolver = {}

-- Reserved keys that should not be treated as style properties
local RESERVED_KEYS = {
    -- Structural
    type = true,
    id = true,
    class = true,

    -- Geometry definition
    from = true,
    to = true,
    position = true,
    size = true,
    height = true,
    length = true,
    direction = true,
    angle = true,
    radius = true,

    -- Reference/positioning
    along = true,
    at = true,
    surface = true,
    anchor = true,
    target = true,
    offset = true,
    weld = true,

    -- Openings
    openings = true,

    -- Children/nesting
    children = true,
}

--[[
    Deep merge source table into target table.
    Later values override earlier ones.

    @param target: Table to merge into
    @param source: Table to merge from
    @return: The target table (modified in place)
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
    "exterior brick metal" → {"exterior", "brick", "metal"}

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

    @param definition: Element definition table
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
    Resolve all styles for an element definition.

    Cascade order (lowest to highest priority):
        1. defaults - Applied to all elements
        2. types[elementType] - Applied by element type
        3. classes[className] - Applied by class (in order)
        4. ids[elementId] - Applied by ID
        5. inline - Direct properties on the definition

    @param definition: The element definition table
    @param styles: The stylesheet { defaults, types, classes, ids }
    @return: Merged properties table
--]]
function StyleResolver.resolve(definition, styles)
    local resolved = {}

    -- Safety check
    if not styles then
        return extractInlineStyles(definition)
    end

    -- 1. Apply base defaults
    if styles.defaults then
        merge(resolved, styles.defaults)
    end

    -- 2. Apply type-specific defaults
    local elementType = definition.type
    if elementType and styles.types and styles.types[elementType] then
        merge(resolved, styles.types[elementType])
    end

    -- 3. Apply class styles (in order from class attribute)
    if definition.class and styles.classes then
        local classList = parseClasses(definition.class)
        for _, className in ipairs(classList) do
            if styles.classes[className] then
                merge(resolved, styles.classes[className])
            end
        end
    end

    -- 4. Apply ID styles
    if definition.id and styles.ids and styles.ids[definition.id] then
        merge(resolved, styles.ids[definition.id])
    end

    -- 5. Apply inline styles (highest priority)
    local inlineStyles = extractInlineStyles(definition)
    merge(resolved, inlineStyles)

    return resolved
end

--[[
    Check if a definition has a specific class.

    @param definition: Element definition table
    @param className: Class name to check for
    @return: boolean
--]]
function StyleResolver.hasClass(definition, className)
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

    @param definition: Element definition table
    @return: Array of class name strings
--]]
function StyleResolver.getClasses(definition)
    return parseClasses(definition.class)
end

--[[
    Add a class to a definition's class string.

    @param definition: Element definition table
    @param className: Class name to add
--]]
function StyleResolver.addClass(definition, className)
    if StyleResolver.hasClass(definition, className) then
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

    @param definition: Element definition table
    @param className: Class name to remove
--]]
function StyleResolver.removeClass(definition, className)
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

return StyleResolver
