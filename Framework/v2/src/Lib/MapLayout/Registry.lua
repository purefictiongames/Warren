--[[
    LibPureFiction Framework v2
    MapLayout/Registry.lua - Element Registry for ID Lookups and Targeting

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    The Registry tracks all created map elements by their IDs, storing:
    - The Roblox instance (Part/Model)
    - The original definition
    - Resolved geometry data (positions, dimensions, surfaces)

    This enables:
    - Selector-based lookups (#wallA, .exterior)
    - Relative positioning (reference other elements)
    - Runtime targeting for attachments

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Register an element
    Registry.register("wallA", {
        instance = wallPart,
        definition = wallDef,
        geometry = {
            from = Vector3.new(0, 0, 0),
            to = Vector3.new(20, 0, 0),
            height = 12,
            thickness = 1,
        },
    })

    -- Look up by ID
    local wall = Registry.get("#wallA")  -- or Registry.get("wallA")

    -- Get position references
    local startPos = Registry.getPoint("#wallA", "start")
    local endPos = Registry.getPoint("#wallA", "end")
    local centerPos = Registry.getPoint("#wallA", "center")
    ```

--]]

local Registry = {}

-- Storage for registered elements
-- { [id] = { instance, definition, geometry, class } }
local elements = {}

-- Storage for elements by class (for future class selectors)
-- { [className] = { id1, id2, ... } }
local classMappings = {}

--[[
    Parse a selector string.

    @param selector: Selector string (e.g., "#wallA", "wallA", ".exterior")
    @return: { type = "id"|"class", value = string }
--]]
local function parseSelector(selector)
    if type(selector) ~= "string" then
        return nil
    end

    local firstChar = selector:sub(1, 1)

    if firstChar == "#" then
        return { type = "id", value = selector:sub(2) }
    elseif firstChar == "." then
        return { type = "class", value = selector:sub(2) }
    else
        -- Assume bare ID
        return { type = "id", value = selector }
    end
end

--[[
    Register an element in the registry.

    @param id: Unique identifier for the element
    @param data: Table containing:
        - instance: The Roblox Part/Model
        - definition: The original definition table
        - geometry: Resolved geometry data (positions, dimensions)
--]]
function Registry.register(id, data)
    if not id then
        return
    end

    elements[id] = data

    -- Also index by class
    if data.definition and data.definition.class then
        for className in data.definition.class:gmatch("%S+") do
            if not classMappings[className] then
                classMappings[className] = {}
            end
            table.insert(classMappings[className], id)
        end
    end
end

--[[
    Get an element by selector.

    @param selector: ID selector ("#wallA" or "wallA") or class selector (".exterior")
    @return: The element data table, or nil if not found
--]]
function Registry.get(selector)
    local parsed = parseSelector(selector)
    if not parsed then
        return nil
    end

    if parsed.type == "id" then
        return elements[parsed.value]
    elseif parsed.type == "class" then
        -- Return first element with this class (for now)
        local ids = classMappings[parsed.value]
        if ids and #ids > 0 then
            return elements[ids[1]]
        end
    end

    return nil
end

--[[
    Get all elements with a specific class.

    @param className: Class name (without the dot prefix)
    @return: Array of element data tables
--]]
function Registry.getByClass(className)
    local ids = classMappings[className]
    if not ids then
        return {}
    end

    local results = {}
    for _, id in ipairs(ids) do
        if elements[id] then
            table.insert(results, elements[id])
        end
    end
    return results
end

--[[
    Get all registered element IDs.

    @return: Array of ID strings
--]]
function Registry.getAllIds()
    local ids = {}
    for id in pairs(elements) do
        table.insert(ids, id)
    end
    return ids
end

--[[
    Check if an element exists.

    @param selector: ID or class selector
    @return: boolean
--]]
function Registry.exists(selector)
    return Registry.get(selector) ~= nil
end

--[[
    Get the Roblox instance for an element.

    @param selector: ID or class selector
    @return: The Part/Model instance, or nil
--]]
function Registry.getInstance(selector)
    local entry = Registry.get(selector)
    return entry and entry.instance or nil
end

--[[
    Get a specific reference point from an element.

    For walls/linear elements:
        - "start", "from" - Starting position
        - "end", "to" - Ending position
        - "center" - Midpoint
        - "farX", "farZ" - Endpoint with larger X or Z
        - "nearX", "nearZ" - Endpoint with smaller X or Z

    For box elements:
        - "center" - Center position
        - "top", "bottom" - Center of top/bottom faces
        - Corners (future): "nw", "ne", "sw", "se"

    @param selector: ID or class selector
    @param pointName: Reference point name
    @return: Vector3 position, or nil if not found
--]]
function Registry.getPoint(selector, pointName)
    local entry = Registry.get(selector)
    if not entry or not entry.geometry then
        return nil
    end

    local geo = entry.geometry
    pointName = pointName or "center"

    -- Handle walls/linear elements
    if geo.from and geo.to then
        local fromVec = geo.from
        local toVec = geo.to

        if pointName == "start" or pointName == "from" then
            return fromVec
        elseif pointName == "end" or pointName == "to" then
            return toVec
        elseif pointName == "center" then
            return (fromVec + toVec) / 2
        elseif pointName == "farX" then
            return fromVec.X > toVec.X and fromVec or toVec
        elseif pointName == "nearX" then
            return fromVec.X < toVec.X and fromVec or toVec
        elseif pointName == "farZ" then
            return fromVec.Z > toVec.Z and fromVec or toVec
        elseif pointName == "nearZ" then
            return fromVec.Z < toVec.Z and fromVec or toVec
        end
    end

    -- Handle box/positioned elements
    if geo.position then
        local pos = geo.position
        local size = geo.size or Vector3.new(1, 1, 1)

        if pointName == "center" then
            return pos
        elseif pointName == "top" then
            return pos + Vector3.new(0, size.Y / 2, 0)
        elseif pointName == "bottom" then
            return pos - Vector3.new(0, size.Y / 2, 0)
        elseif pointName == "+x" or pointName == "right" then
            return pos + Vector3.new(size.X / 2, 0, 0)
        elseif pointName == "-x" or pointName == "left" then
            return pos - Vector3.new(size.X / 2, 0, 0)
        elseif pointName == "+z" or pointName == "front" then
            return pos + Vector3.new(0, 0, size.Z / 2)
        elseif pointName == "-z" or pointName == "back" then
            return pos - Vector3.new(0, 0, size.Z / 2)
        end
    end

    return nil
end

--[[
    Get the surface normal for a specific surface of an element.

    @param selector: ID or class selector
    @param surfaceName: Surface name (+x, -x, +y, -y, +z, -z, or aliases)
    @return: Vector3 normal, or nil if not found
--]]
function Registry.getSurfaceNormal(selector, surfaceName)
    local surfaceNormals = {
        ["+x"] = Vector3.new(1, 0, 0),
        ["-x"] = Vector3.new(-1, 0, 0),
        ["+y"] = Vector3.new(0, 1, 0),
        ["-y"] = Vector3.new(0, -1, 0),
        ["+z"] = Vector3.new(0, 0, 1),
        ["-z"] = Vector3.new(0, 0, -1),
        -- Aliases
        ["top"] = Vector3.new(0, 1, 0),
        ["bottom"] = Vector3.new(0, -1, 0),
        ["right"] = Vector3.new(1, 0, 0),
        ["left"] = Vector3.new(-1, 0, 0),
        ["front"] = Vector3.new(0, 0, 1),
        ["back"] = Vector3.new(0, 0, -1),
    }

    return surfaceNormals[surfaceName]
end

--[[
    Get geometry data for computing positions along an element.

    @param selector: ID or class selector
    @return: Geometry table with from, to, length, direction, etc.
--]]
function Registry.getGeometry(selector)
    local entry = Registry.get(selector)
    return entry and entry.geometry or nil
end

--[[
    Clear all registered elements.
    Call this before rebuilding a map.
--]]
function Registry.clear()
    elements = {}
    classMappings = {}
end

--[[
    Get count of registered elements.

    @return: number
--]]
function Registry.count()
    local count = 0
    for _ in pairs(elements) do
        count = count + 1
    end
    return count
end

--[[
    Debug: Print all registered elements.
--]]
function Registry.dump()
    print("=== MapLayout Registry ===")
    print("Total elements:", Registry.count())
    for id, entry in pairs(elements) do
        print(string.format("  #%s: %s (class: %s)",
            id,
            entry.instance and entry.instance.Name or "no instance",
            entry.definition and entry.definition.class or "none"
        ))
    end
    print("=== End Registry ===")
end

return Registry
