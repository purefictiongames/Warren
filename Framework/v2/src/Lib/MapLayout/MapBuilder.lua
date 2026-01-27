--[[
    LibPureFiction Framework v2
    MapLayout/MapBuilder.lua - Main Orchestrator for Map Construction

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    MapBuilder is the main entry point for constructing maps from definitions.
    It orchestrates:
    1. Dependency ordering (elements referencing other elements)
    2. Reference resolution (converting "#wallA:end" to Vector3)
    3. Style resolution (cascade from defaults → class → id → inline)
    4. Geometry creation (creating Parts via GeometryFactory)
    5. Registry population (tracking elements for later lookups)

    ============================================================================
    SCALE
    ============================================================================

    Maps can define a scale factor that converts definition units to studs:

        scale = "5:1"    -- 5 studs per 1 definition unit (makes things bigger)
        scale = "1:2"    -- 1 stud per 2 definition units (makes things smaller)
        scale = 5        -- Same as "5:1"
        scale = 0.5      -- Same as "1:2"

    Scale applies to:
        - Literal positions (from, to, position)
        - Dimensions (height, thickness, size, radius, length)
        - Offsets in references

    Scale does NOT apply to:
        - Referenced positions (#wallA:end) - already in studs
        - Part properties (Transparency, etc.)

    Per-element scale override:
        { id = "wall", scale = "2:1", ... }  -- This element uses different scale

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local MapBuilder = require(path.to.MapBuilder)

    local definition = {
        scale = "4:1",  -- 4 studs per unit
        walls = {
            { id = "north", from = {0, 0}, to = {5, 0}, height = 3 },  -- becomes 20x12 studs
            { id = "east", from = "#north:end", to = {5, 4}, height = 3 },
        },
        platforms = {
            { id = "mount", position = {2.5, 3, 2}, size = {1, 0.25, 1} },  -- becomes 4x1x4 studs
        },
    }

    local styles = {
        defaults = { Anchored = true, Material = "Concrete" },
        classes = { ["metal"] = { Material = "DiamondPlate" } },
    }

    local map = MapBuilder.build(definition, styles)
    ```

--]]

local MapBuilder = {}

-- Module dependencies
local StyleResolver = require(script.Parent.StyleResolver)
local Registry = require(script.Parent.Registry)
local ReferenceResolver = require(script.Parent.ReferenceResolver)
local GeometryFactory = require(script.Parent.GeometryFactory)
local AreaBuilder = require(script.Parent.AreaBuilder)
local AreaFactory = require(script.Parent.AreaFactory)

-- Initialize ReferenceResolver with Registry
ReferenceResolver.init(Registry)

-- Current build context (scale, etc.)
local buildContext = {
    scale = 1,
}

--[[
    Parse a scale value into a numeric multiplier.

    Accepts:
        - Number: used directly (5 means 5 studs per unit)
        - String "A:B": A studs per B units (e.g., "5:1" = 5, "1:2" = 0.5)

    @param scaleValue: Scale definition (number or string)
    @return: Numeric scale factor
--]]
local function parseScale(scaleValue)
    if scaleValue == nil then
        return 1
    end

    if type(scaleValue) == "number" then
        return scaleValue
    end

    if type(scaleValue) == "string" then
        -- Parse "A:B" format
        local a, b = scaleValue:match("^([%d%.]+):([%d%.]+)$")
        if a and b then
            local numA = tonumber(a)
            local numB = tonumber(b)
            if numA and numB and numB ~= 0 then
                return numA / numB
            end
        end

        -- Try parsing as plain number
        local num = tonumber(scaleValue)
        if num then
            return num
        end
    end

    warn("[MapBuilder] Invalid scale value:", scaleValue, "- using 1:1")
    return 1
end

--[[
    Apply scale to a numeric value.

    @param value: Number to scale
    @param scale: Scale factor
    @return: Scaled number
--]]
local function scaleNumber(value, scale)
    if type(value) ~= "number" then
        return value
    end
    return value * scale
end

--[[
    Apply scale to a position array or Vector3.
    Only scales literal values, not references.

    @param value: Position value (array, Vector3, or reference)
    @param scale: Scale factor
    @return: Scaled value (same type as input)
--]]
local function scalePosition(value, scale)
    if scale == 1 then
        return value
    end

    -- Don't scale references - they resolve to already-scaled studs
    if ReferenceResolver.isReference(value) then
        return value
    end

    -- Scale arrays
    if type(value) == "table" and type(value[1]) == "number" then
        local scaled = {}
        for i, v in ipairs(value) do
            scaled[i] = v * scale
        end
        return scaled
    end

    -- Scale Vector3
    if typeof(value) == "Vector3" then
        return value * scale
    end

    return value
end

--[[
    Apply scale to a size value (array or single number).

    @param value: Size value
    @param scale: Scale factor
    @return: Scaled size
--]]
local function scaleSize(value, scale)
    if scale == 1 then
        return value
    end

    if type(value) == "number" then
        return value * scale
    end

    if type(value) == "table" then
        local scaled = {}
        for i, v in ipairs(value) do
            if type(v) == "number" then
                scaled[i] = v * scale
            else
                scaled[i] = v
            end
        end
        return scaled
    end

    if typeof(value) == "Vector3" then
        return value * scale
    end

    return value
end

--[[
    Apply scale to an element definition.
    Modifies the element in place, storing scaled values.

    @param element: Element definition
    @param mapScale: Map-level scale factor
--]]
local function applyScaleToElement(element, mapScale)
    -- Determine effective scale (element override or map default)
    local scale = parseScale(element.scale) or mapScale

    if scale == 1 then
        element._scale = 1
        return
    end

    element._scale = scale

    -- Scale positions (only literal values, not references)
    if element.from and not ReferenceResolver.isReference(element.from) then
        element.from = scalePosition(element.from, scale)
    end

    if element.to and not ReferenceResolver.isReference(element.to) then
        element.to = scalePosition(element.to, scale)
    end

    if element.position and not ReferenceResolver.isReference(element.position) then
        element.position = scalePosition(element.position, scale)
    end

    -- Scale dimensions
    if element.height then
        element.height = scaleNumber(element.height, scale)
    end

    if element.thickness then
        element.thickness = scaleNumber(element.thickness, scale)
    end

    if element.radius then
        element.radius = scaleNumber(element.radius, scale)
    end

    if element.length then
        element.length = scaleNumber(element.length, scale)
    end

    if element.size then
        element.size = scaleSize(element.size, scale)
    end

    -- Scale offsets in anchor references
    if element.anchor and element.anchor.offset then
        element.anchor.offset = scaleSize(element.anchor.offset, scale)
    end
end

--[[
    Topologically sort elements by their dependencies.
    Elements with no dependencies come first, then elements that depend on them.

    @param elements: Array of element definitions
    @return: Sorted array of elements
--]]
local function topologicalSort(elements)
    -- Build a map of id → element
    local byId = {}
    for _, elem in ipairs(elements) do
        if elem.id then
            byId[elem.id] = elem
        end
    end

    -- Calculate dependencies for each element
    local deps = {}
    local noDeps = {}

    for i, elem in ipairs(elements) do
        local elemDeps = ReferenceResolver.getDependencies(elem)
        deps[i] = { elem = elem, dependencies = elemDeps, index = i }

        if #elemDeps == 0 then
            table.insert(noDeps, deps[i])
        end
    end

    -- Kahn's algorithm for topological sort
    local sorted = {}
    local resolved = {}

    while #noDeps > 0 do
        local current = table.remove(noDeps, 1)
        table.insert(sorted, current.elem)

        if current.elem.id then
            resolved[current.elem.id] = true
        end

        -- Check if any elements now have all dependencies resolved
        for i, dep in ipairs(deps) do
            if not resolved[dep.elem.id or i] then
                local allResolved = true
                for _, depId in ipairs(dep.dependencies) do
                    if not resolved[depId] then
                        allResolved = false
                        break
                    end
                end

                if allResolved then
                    -- Mark as resolved so we don't add it again
                    resolved[dep.elem.id or i] = true
                    table.insert(noDeps, dep)
                end
            end
        end
    end

    -- Check for circular dependencies
    if #sorted < #elements then
        warn("[MapBuilder] Circular dependency detected! Some elements could not be sorted.")
        -- Add remaining elements anyway
        for _, elem in ipairs(elements) do
            local found = false
            for _, sortedElem in ipairs(sorted) do
                if sortedElem == elem then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(sorted, elem)
            end
        end
    end

    return sorted
end

--[[
    Collect all elements from all categories into a flat list.
    Assigns default types based on category.

    @param definition: Map definition with walls, platforms, etc.
    @return: Array of all element definitions
--]]
local function collectElements(definition)
    local elements = {}

    -- Category → default type mapping
    local categoryTypes = {
        walls = "wall",
        platforms = "platform",
        boxes = "platform",
        floors = "floor",
        cylinders = "cylinder",
        spheres = "sphere",
        wedges = "wedge",
    }

    for category, defaultType in pairs(categoryTypes) do
        if definition[category] then
            for _, elem in ipairs(definition[category]) do
                -- Set default type if not specified
                if not elem.type then
                    elem.type = defaultType
                end
                elem._category = category
                table.insert(elements, elem)
            end
        end
    end

    -- Also support a generic "elements" array
    if definition.elements then
        for _, elem in ipairs(definition.elements) do
            table.insert(elements, elem)
        end
    end

    return elements
end

--[[
    Resolve position references in an element definition.
    Adds _resolvedFrom, _resolvedTo, _resolvedPosition fields.

    @param element: Element definition
--]]
local function resolvePositions(element)
    -- Resolve from/to for walls
    if element.from then
        element._resolvedFrom = ReferenceResolver.resolve(element.from)
    end

    if element.to then
        element._resolvedTo = ReferenceResolver.resolve(element.to)
    end

    -- Resolve position for other elements
    if element.position then
        element._resolvedPosition = ReferenceResolver.resolve(element.position)
    end

    -- Handle anchor-based positioning
    if element.anchor then
        local anchor = element.anchor
        local targetPos = ReferenceResolver.resolve(anchor.target or anchor)

        if targetPos then
            local offset = Vector3.new(0, 0, 0)
            if anchor.offset then
                if #anchor.offset == 2 then
                    offset = Vector3.new(anchor.offset[1], 0, anchor.offset[2])
                elseif #anchor.offset == 3 then
                    offset = Vector3.new(anchor.offset[1], anchor.offset[2], anchor.offset[3])
                end
            end
            element._resolvedPosition = targetPos + offset
        end
    end
end

--[[
    Build a map from a definition.

    @param definition: Map definition table with walls, platforms, etc.
    @param styles: Optional stylesheet { defaults, types, classes, ids }
    @param parent: Optional parent instance (default: new Model in workspace)
    @return: Model containing all geometry
--]]
function MapBuilder.build(definition, styles, parent)
    -- Clear registry for fresh build
    Registry.clear()

    -- Parse map-level scale
    local mapScale = parseScale(definition.scale)
    buildContext.scale = mapScale

    -- Create container model
    local mapModel = Instance.new("Model")
    mapModel.Name = definition.name or "Map"

    -- Store scale on the model for reference
    if mapScale ~= 1 then
        mapModel:SetAttribute("MapLayoutScale", mapScale)
    end

    -- Collect all elements
    local elements = collectElements(definition)

    -- Sort by dependencies
    local sorted = topologicalSort(elements)

    -- Build each element
    for _, element in ipairs(sorted) do
        -- Apply scale to literal values (before resolving references)
        applyScaleToElement(element, mapScale)

        -- Resolve positions (may depend on previously built elements)
        resolvePositions(element)

        -- Resolve styles
        local properties = StyleResolver.resolve(element, styles)

        -- Create geometry
        local instance, geometry = GeometryFactory.create(element, properties)

        if instance then
            instance.Parent = mapModel

            -- Register in registry
            if element.id then
                Registry.register(element.id, {
                    instance = instance,
                    definition = element,
                    geometry = geometry,
                })
            end
        end
    end

    -- Build areas (after loose geometry so areas can reference it)
    if definition.areas then
        for _, areaDef in ipairs(definition.areas) do
            local areaInstance

            if areaDef.template then
                -- Create from registered template
                if not AreaFactory.exists(areaDef.template) then
                    error(string.format(
                        "[MapBuilder] Unknown area template '%s'. Register it with AreaFactory.define() first.",
                        areaDef.template
                    ), 2)
                end
                areaInstance = AreaFactory.createInstance(areaDef.template, areaDef)
            else
                -- Inline area definition (must have bounds)
                if not areaDef.bounds then
                    error(string.format(
                        "[MapBuilder] Inline area '%s' must have 'bounds' defined",
                        areaDef.id or "(unnamed)"
                    ), 2)
                end
                areaInstance = areaDef
            end

            -- Apply scale to area positions and dimensions
            if mapScale ~= 1 then
                if areaInstance.position and type(areaInstance.position) == "table" then
                    areaInstance.position = scalePosition(areaInstance.position, mapScale)
                end
                if areaInstance.bounds then
                    areaInstance.bounds = {
                        areaInstance.bounds[1] * mapScale,
                        areaInstance.bounds[2] * mapScale,
                        areaInstance.bounds[3] * mapScale,
                    }
                end
                -- Note: Geometry inside areas is NOT scaled here - AreaBuilder handles that
                -- based on the area's own scale setting
            end

            -- Build the area (validates bounds and creates geometry)
            local areaModel = AreaBuilder.build(areaInstance, styles, mapModel)
        end
    end

    -- Set parent
    if parent then
        mapModel.Parent = parent
    else
        mapModel.Parent = workspace
    end

    return mapModel
end

--[[
    Build a single element and add it to an existing map.

    @param element: Element definition
    @param styles: Optional stylesheet
    @param parent: Parent Model to add to
    @param scale: Optional scale factor (default: current build context scale)
    @return: The created Part/Model
--]]
function MapBuilder.addElement(element, styles, parent, scale)
    -- Apply scale
    local effectiveScale = scale or buildContext.scale or 1
    applyScaleToElement(element, effectiveScale)

    -- Resolve positions
    resolvePositions(element)

    -- Resolve styles
    local properties = StyleResolver.resolve(element, styles)

    -- Create geometry
    local instance, geometry = GeometryFactory.create(element, properties)

    if instance then
        instance.Parent = parent

        -- Register in registry
        if element.id then
            Registry.register(element.id, {
                instance = instance,
                definition = element,
                geometry = geometry,
            })
        end
    end

    return instance
end

--[[
    Remove an element by ID.

    @param id: Element ID
--]]
function MapBuilder.removeElement(id)
    local entry = Registry.get(id)
    if entry and entry.instance then
        entry.instance:Destroy()
    end
    -- Note: Registry doesn't have a remove function yet
    -- Would need to add that for full support
end

--[[
    Rebuild the entire map (clear and build again).

    @param definition: Map definition
    @param styles: Optional stylesheet
    @param parent: Optional parent instance
    @return: New Model
--]]
function MapBuilder.rebuild(definition, styles, parent)
    -- Find and destroy existing map if present
    local existingName = definition.name or "Map"
    local existing = workspace:FindFirstChild(existingName)
    if existing then
        existing:Destroy()
    end

    return MapBuilder.build(definition, styles, parent)
end

--[[
    Get the current build context scale.

    @return: Scale factor (number)
--]]
function MapBuilder.getScale()
    return buildContext.scale or 1
end

--[[
    Parse a scale string or number.
    Useful for external code that needs to work with scale values.

    @param scaleValue: Scale definition ("5:1", 5, 0.5, etc.)
    @return: Numeric scale factor
--]]
function MapBuilder.parseScale(scaleValue)
    return parseScale(scaleValue)
end

--[[
    Convert a value from definition units to studs using current scale.

    @param value: Number or array to convert
    @return: Scaled value
--]]
function MapBuilder.toStuds(value)
    local scale = buildContext.scale or 1
    if type(value) == "number" then
        return value * scale
    elseif type(value) == "table" then
        return scaleSize(value, scale)
    end
    return value
end

--[[
    Convert a value from studs to definition units using current scale.

    @param value: Number or array in studs
    @return: Value in definition units
--]]
function MapBuilder.fromStuds(value)
    local scale = buildContext.scale or 1
    if scale == 0 then return value end

    if type(value) == "number" then
        return value / scale
    elseif type(value) == "table" then
        local result = {}
        for i, v in ipairs(value) do
            result[i] = type(v) == "number" and v / scale or v
        end
        return result
    end
    return value
end

return MapBuilder
