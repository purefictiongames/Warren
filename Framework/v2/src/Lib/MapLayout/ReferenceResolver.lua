--[[
    LibPureFiction Framework v2
    MapLayout/ReferenceResolver.lua - Resolve Relative Position References

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Resolves position references that depend on other elements:
    - Simple references: "#wallA:end"
    - Along positioning: { along = "#wallA", at = 20 }
    - Offset math: "#wallA:end + {5, 0}"
    - Surface-relative: { along = "#wallA", at = 20, surface = "-z" }

    The resolver uses the Registry to look up already-created elements,
    which means elements must be created in dependency order.

    ============================================================================
    REFERENCE SYNTAX
    ============================================================================

    String references:
        "#wallA"           - Center of element
        "#wallA:start"     - Starting point
        "#wallA:end"       - Ending point
        "#wallA:center"    - Center point
        "#wallA:farX"      - Endpoint with larger X
        "#wallA:nearZ"     - Endpoint with smaller Z

    Table references:
        { ref = "#wallA", point = "end" }
        { ref = "#wallA", point = "end", offset = {5, 0} }
        { along = "#wallA", at = 20 }              - 20 studs from start
        { along = "#wallA", at = "50%" }           - 50% along length
        { along = "#wallA", at = 20, surface = "-z" }  - On specific surface

    Offset math (in string):
        "#wallA:end + {5, 0}"                      - Offset by {5, 0}

--]]

local ReferenceResolver = {}

-- Forward declaration for Registry (injected or required)
local Registry = nil

--[[
    Initialize with Registry reference.
    Called by MapBuilder before resolving.
--]]
function ReferenceResolver.init(registryModule)
    Registry = registryModule
end

--[[
    Check if a value is a reference that needs resolution.

    @param value: Any value
    @return: boolean
--]]
function ReferenceResolver.isReference(value)
    if type(value) == "string" then
        return value:sub(1, 1) == "#"
    elseif type(value) == "table" then
        return value.ref ~= nil or value.along ~= nil
    end
    return false
end

--[[
    Parse a string reference like "#wallA:end" or "#wallA:end + {5, 0}"

    @param refString: Reference string
    @return: { selector, point, offset } or nil
--]]
local function parseStringReference(refString)
    -- Check for offset: "#wallA:end + {5, 0}"
    local baseRef, offsetStr = refString:match("^([^%+]+)%s*%+%s*(%b{})")

    if not baseRef then
        baseRef = refString
    end

    -- Parse selector and point: "#wallA:end" → selector="#wallA", point="end"
    local selector, point = baseRef:match("^(#[^:]+):?(.*)$")

    if not selector then
        -- Maybe it's just "#wallA" without a point
        selector = baseRef:match("^(#%S+)$")
        point = "center"
    end

    if not selector then
        return nil
    end

    point = (point and point ~= "") and point or "center"

    -- Parse offset if present: "{5, 0}" → {5, 0}
    local offset = nil
    if offsetStr then
        -- Extract numbers from "{5, 0}" or "{5, 0, 3}"
        local numbers = {}
        for num in offsetStr:gmatch("%-?[%d%.]+") do
            table.insert(numbers, tonumber(num))
        end
        if #numbers >= 2 then
            offset = numbers
        end
    end

    return {
        selector = selector,
        point = point,
        offset = offset,
    }
end

--[[
    Resolve a simple point reference to a Vector3.

    @param selector: Element selector (#wallA)
    @param pointName: Point name (start, end, center, etc.)
    @return: Vector3 or nil
--]]
local function resolvePoint(selector, pointName)
    if not Registry then
        warn("[ReferenceResolver] Registry not initialized")
        return nil
    end

    return Registry.getPoint(selector, pointName)
end

--[[
    Convert a 2D offset {x, z} to Vector3.
    Assumes Y=0 for 2D offsets.

    @param offset: Array of 2 or 3 numbers
    @return: Vector3
--]]
local function offsetToVector3(offset)
    if not offset then
        return Vector3.new(0, 0, 0)
    end

    if #offset == 2 then
        -- 2D offset: {x, z}
        return Vector3.new(offset[1], 0, offset[2])
    elseif #offset == 3 then
        -- 3D offset: {x, y, z}
        return Vector3.new(offset[1], offset[2], offset[3])
    end

    return Vector3.new(0, 0, 0)
end

--[[
    Resolve an "along" reference.
    { along = "#wallA", at = 20 } - 20 studs from start
    { along = "#wallA", at = "50%" } - 50% along length

    @param alongRef: Table with along, at, surface, offset
    @return: Vector3 or nil
--]]
local function resolveAlong(alongRef)
    if not Registry then
        warn("[ReferenceResolver] Registry not initialized")
        return nil
    end

    local geo = Registry.getGeometry(alongRef.along)
    if not geo or not geo.from or not geo.to then
        warn("[ReferenceResolver] Cannot find geometry for:", alongRef.along)
        return nil
    end

    local fromVec = geo.from
    local toVec = geo.to
    local direction = (toVec - fromVec)
    local length = direction.Magnitude

    if length == 0 then
        return fromVec
    end

    direction = direction.Unit

    -- Parse "at" value
    local at = alongRef.at or 0
    local distance

    if type(at) == "string" then
        -- Percentage: "50%" or "center"
        if at == "center" then
            distance = length / 2
        else
            local percent = tonumber(at:match("^(%d+)%%$"))
            if percent then
                distance = length * (percent / 100)
            else
                distance = 0
            end
        end
    else
        -- Absolute studs
        distance = at
    end

    -- Clamp to wall length
    distance = math.max(0, math.min(distance, length))

    -- Calculate base position along the element
    local position = fromVec + direction * distance

    -- Apply surface offset if specified
    if alongRef.surface then
        local normal = Registry.getSurfaceNormal(alongRef.along, alongRef.surface)
        if normal and geo.thickness then
            -- Offset by half the thickness to get to the surface
            position = position + normal * (geo.thickness / 2)
        end
    end

    -- Apply additional offset
    if alongRef.offset then
        position = position + offsetToVector3(alongRef.offset)
    end

    return position
end

--[[
    Resolve any position reference to a Vector3.
    Handles:
    - Literal arrays: {10, 5} → Vector3(10, 0, 5)
    - String references: "#wallA:end"
    - Table references: { ref = "#wallA", point = "end" }
    - Along references: { along = "#wallA", at = 20 }

    @param value: Position value (array, string, or table)
    @return: Vector3 or nil if unresolvable
--]]
function ReferenceResolver.resolve(value)
    if value == nil then
        return nil
    end

    -- Already a Vector3
    if typeof(value) == "Vector3" then
        return value
    end

    -- Literal array: {10, 5} or {10, 5, 3}
    if type(value) == "table" and not value.ref and not value.along then
        -- Check if it's a simple number array
        if type(value[1]) == "number" then
            if #value == 2 then
                -- 2D: {x, z}
                return Vector3.new(value[1], 0, value[2])
            elseif #value == 3 then
                -- 3D: {x, y, z}
                return Vector3.new(value[1], value[2], value[3])
            end
        end
    end

    -- String reference: "#wallA:end"
    if type(value) == "string" then
        local parsed = parseStringReference(value)
        if parsed then
            local point = resolvePoint(parsed.selector, parsed.point)
            if point and parsed.offset then
                point = point + offsetToVector3(parsed.offset)
            end
            return point
        end
        return nil
    end

    -- Table reference: { ref = "#wallA", point = "end" }
    if type(value) == "table" and value.ref then
        local point = resolvePoint(value.ref, value.point or "center")
        if point and value.offset then
            point = point + offsetToVector3(value.offset)
        end
        return point
    end

    -- Along reference: { along = "#wallA", at = 20 }
    if type(value) == "table" and value.along then
        return resolveAlong(value)
    end

    return nil
end

--[[
    Resolve a 2D footprint position (x, z plane).
    Same as resolve() but ensures Y=0.

    @param value: Position value
    @return: Vector3 with Y=0
--]]
function ReferenceResolver.resolve2D(value)
    local resolved = ReferenceResolver.resolve(value)
    if resolved then
        return Vector3.new(resolved.X, 0, resolved.Z)
    end
    return nil
end

--[[
    Check if all references in a definition can be resolved.
    Useful for determining build order.

    @param definition: Element definition
    @return: boolean, array of unresolved reference strings
--]]
function ReferenceResolver.canResolve(definition)
    local unresolved = {}

    local function checkValue(value)
        if ReferenceResolver.isReference(value) then
            local resolved = ReferenceResolver.resolve(value)
            if not resolved then
                if type(value) == "string" then
                    table.insert(unresolved, value)
                elseif type(value) == "table" then
                    table.insert(unresolved, value.ref or value.along or "unknown")
                end
            end
        end
    end

    -- Check common position fields
    checkValue(definition.from)
    checkValue(definition.to)
    checkValue(definition.position)

    -- Check anchor if present
    if definition.anchor then
        checkValue(definition.anchor.target)
    end

    return #unresolved == 0, unresolved
end

--[[
    Extract dependencies from a definition.
    Returns list of element IDs this definition depends on.

    @param definition: Element definition
    @return: Array of ID strings (without # prefix)
--]]
function ReferenceResolver.getDependencies(definition)
    local deps = {}
    local seen = {}

    local function extractId(value)
        if type(value) == "string" and value:sub(1, 1) == "#" then
            local id = value:match("^#([^:]+)")
            if id and not seen[id] then
                seen[id] = true
                table.insert(deps, id)
            end
        elseif type(value) == "table" then
            if value.ref then
                local id = value.ref:match("^#?([^:]+)")
                if id and not seen[id] then
                    seen[id] = true
                    table.insert(deps, id)
                end
            end
            if value.along then
                local id = value.along:match("^#?([^:]+)")
                if id and not seen[id] then
                    seen[id] = true
                    table.insert(deps, id)
                end
            end
            if value.target then
                local id = value.target:match("^#?([^:]+)")
                if id and not seen[id] then
                    seen[id] = true
                    table.insert(deps, id)
                end
            end
        end
    end

    extractId(definition.from)
    extractId(definition.to)
    extractId(definition.position)
    if definition.anchor then
        extractId(definition.anchor)
        extractId(definition.anchor.target)
    end
    extractId(definition.weld)

    return deps
end

return ReferenceResolver
