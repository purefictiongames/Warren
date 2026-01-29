--[[
    LibPureFiction Framework v2
    Geometry.lua - Geometry Adapter for the Resolver System

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Geometry is an adapter that uses the generic Resolver pattern to build
    Roblox Parts from declarative definitions.

    The Resolver is a formula solver:
        1. Create stubs (workspace for solutions)
        2. Order by dependency (solve parents first)
        3. Apply cascade formula (compute properties)
        4. Resolve references (substitute values)

    See docs/RESOLVER.md for the full mental model.

    ============================================================================
    BUILD PHASES
    ============================================================================

    RESOLVE Phase 1: Create stubs for all parts
    RESOLVE Phase 2: Populate values in tree order
    INSTANTIATE:     Create Roblox Parts from resolved table

    ============================================================================
    CASCADE FORMULA
    ============================================================================

    Properties are computed using ClassResolver:
        parent → defaults → base[type] → classes → id → inline

    Tree inheritance (parent → child) is handled here.
    Per-element cascade is delegated to ClassResolver.

    ============================================================================
    REFERENCES
    ============================================================================

    Function-based layouts enable references between parts:

        return function(parts)
            return {
                parts = {
                    Floor1 = {
                        geometry = { origin = {0, 0, 0}, scale = {80, 18, 65} },
                    },
                    Floor2 = {
                        parent = "Floor1",
                        geometry = {
                            origin = {0, parts.Floor1.Size[2], 0},  -- Chain positioning
                            scale = {80, 18, 65},
                        },
                    },
                },
            }
        end

    Available:
        parts.{id}.Size[1|2|3]      - Scale X/Y/Z
        parts.{id}.Position[1|2|3]  - Origin X/Y/Z
        parts.{id}.Rotation[1|2|3]  - Rotation X/Y/Z

    Arithmetic:
        parts.Floor1.Size[2] + 10
        parts.Wall.Size[1] * 0.5

--]]

--##############################################################################
-- PHASE 1: LOAD
--##############################################################################

local Geometry = {}

-- State
local registry = {}
local Styles = nil
local ClassResolver = nil

-- Forward declarations (defined in PHASE 2)
local getStyles
local getClassResolver
local merge
local deepCopy
local normalizeVector
local buildTreeOrder
local resolvePartProperties
local resolvePartGeometry
local resolveReferences
local toColor3
local applyProperties
local createPart
local registerPart
local valueToCode
local tableToCode
local createRefMarker
local createPropertyProxy
local createPartStub

--##############################################################################
-- PHASE 2: DEFINE
--##############################################################################

--------------------------------------------------------------------------------
-- Dependencies
--------------------------------------------------------------------------------

getStyles = function()
    if not Styles then
        local success, result = pcall(function()
            return require(script.Parent.Parent.Styles)
        end)
        if success then
            Styles = result
        else
            warn("[Geometry] Could not load Styles:", result)
            Styles = { base = {}, classes = {}, ids = {} }
        end
    end
    return Styles
end

getClassResolver = function()
    if not ClassResolver then
        local success, result = pcall(function()
            return require(script.Parent.Parent.ClassResolver)
        end)
        if success then
            ClassResolver = result
        else
            warn("[Geometry] Could not load ClassResolver:", result)
            ClassResolver = nil
        end
    end
    return ClassResolver
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

merge = function(target, source)
    if not source then return target end
    for k, v in pairs(source) do
        target[k] = v
    end
    return target
end

deepCopy = function(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deepCopy(v)
    end
    return copy
end

parseClasses = function(classStr)
    if not classStr or classStr == "" then return {} end
    local classes = {}
    for class in classStr:gmatch("%S+") do
        table.insert(classes, class)
    end
    return classes
end

normalizeVector = function(v)
    if not v then return {0, 0, 0} end
    if v.x then
        return {v.x, v.y, v.z}
    end
    return {v[1] or 0, v[2] or 0, v[3] or 0}
end

--------------------------------------------------------------------------------
-- Reference System (metatables for lazy property access)
--------------------------------------------------------------------------------

--[[
    Reference markers capture property access for deferred resolution.

    Usage in layouts:
        return function(parts)
            return {
                parts = {
                    Floor2 = {
                        geometry = {
                            origin = {0, parts.Floor1.Size[2], 0},  -- Reference!
                        },
                    },
                },
            }
        end

    When parts.Floor1.Size[2] is accessed, it returns a marker:
        { __isRef = true, partId = "Floor1", property = "Size", index = 2 }

    During resolution, markers are replaced with actual values.
--]]

-- Expression marker for arithmetic on references
local ExprMT = {}

local function createExprMarker(op, left, right)
    return setmetatable({
        __isExpr = true,
        op = op,
        left = left,
        right = right,
    }, ExprMT)
end

-- Arithmetic metamethods for expressions
ExprMT.__add = function(a, b) return createExprMarker("+", a, b) end
ExprMT.__sub = function(a, b) return createExprMarker("-", a, b) end
ExprMT.__mul = function(a, b) return createExprMarker("*", a, b) end
ExprMT.__div = function(a, b) return createExprMarker("/", a, b) end
ExprMT.__unm = function(a) return createExprMarker("*", a, -1) end

-- Reference marker with arithmetic support
local RefMT = {}
RefMT.__add = function(a, b) return createExprMarker("+", a, b) end
RefMT.__sub = function(a, b) return createExprMarker("-", a, b) end
RefMT.__mul = function(a, b) return createExprMarker("*", a, b) end
RefMT.__div = function(a, b) return createExprMarker("/", a, b) end
RefMT.__unm = function(a) return createExprMarker("*", a, -1) end

createRefMarker = function(partId, property, index)
    return setmetatable({
        __isRef = true,
        partId = partId,
        property = property,  -- "Size", "Position", "Rotation"
        index = index,        -- 1, 2, 3 (X, Y, Z)
    }, RefMT)
end

createPropertyProxy = function(partId, property)
    -- Returns a proxy that captures index access (e.g., Size[2])
    return setmetatable({}, {
        __index = function(_, index)
            if type(index) == "number" and index >= 1 and index <= 3 then
                return createRefMarker(partId, property, index)
            end
            return nil
        end,
    })
end

createPartStub = function(partId)
    -- Returns a stub that captures property access (e.g., Floor1.Size)
    return setmetatable({}, {
        __index = function(_, property)
            -- Mirror Roblox property names
            if property == "Size" or property == "Position" or property == "Rotation" then
                return createPropertyProxy(partId, property)
            end
            return nil
        end,
    })
end

function Geometry.createPartsProxy()
    -- Returns a proxy table that generates part stubs on access
    return setmetatable({}, {
        __index = function(t, partId)
            local stub = createPartStub(partId)
            rawset(t, partId, stub)  -- Cache for repeated access
            return stub
        end,
    })
end

resolveReferences = function(value, resolvedParts)
    if type(value) ~= "table" then
        return value
    end

    -- Check if this is a reference marker
    if value.__isRef then
        local target = resolvedParts[value.partId]
        if not target then
            warn("[Geometry] Unresolved reference to part:", value.partId)
            return 0
        end

        local prop = value.property
        local idx = value.index

        if prop == "Size" then
            return target.geometry.scale[idx] or 0
        elseif prop == "Position" then
            return target.geometry.origin[idx] or 0
        elseif prop == "Rotation" then
            return target.geometry.rotation[idx] or 0
        end

        warn("[Geometry] Unknown reference property:", prop)
        return 0
    end

    -- Check if this is an expression marker
    if value.__isExpr then
        local left = resolveReferences(value.left, resolvedParts)
        local right = resolveReferences(value.right, resolvedParts)

        if value.op == "+" then return left + right end
        if value.op == "-" then return left - right end
        if value.op == "*" then return left * right end
        if value.op == "/" then return left / right end

        warn("[Geometry] Unknown expression operator:", value.op)
        return 0
    end

    -- Recurse into table
    local result = {}
    for k, v in pairs(value) do
        result[k] = resolveReferences(v, resolvedParts)
    end
    return result
end

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

registerPart = function(id, instance, entry)
    if not id then return end
    registry[id] = {
        id = id,
        instance = instance,
        entry = entry,
    }
end

function Geometry.get(selector)
    if not selector then return nil end
    local id = selector:match("^#?(.+)$")
    return registry[id]
end

function Geometry.getInstance(selector)
    local entry = Geometry.get(selector)
    return entry and entry.instance or nil
end

function Geometry.clear()
    registry = {}
end

--------------------------------------------------------------------------------
-- Resolve: Build Tree Order
--------------------------------------------------------------------------------

buildTreeOrder = function(parts)
    local depths = {}

    local function getDepth(id, visited)
        if depths[id] then return depths[id] end
        if visited[id] then
            warn("[Geometry] Circular parent reference:", id)
            return 0
        end

        visited[id] = true
        local part = parts[id]
        if not part or not part.parent or part.parent == "root" then
            depths[id] = 0
            return 0
        end

        local parentDepth = getDepth(part.parent, visited)
        depths[id] = parentDepth + 1
        return depths[id]
    end

    for id, _ in pairs(parts) do
        getDepth(id, {})
    end

    local order = {}
    for id, depth in pairs(depths) do
        table.insert(order, {id = id, depth = depth})
    end
    table.sort(order, function(a, b) return a.depth < b.depth end)

    return order
end

--------------------------------------------------------------------------------
-- Resolve: Properties Cascade
--------------------------------------------------------------------------------

--[[
    Properties cascade uses ClassResolver for per-element resolution.
    Tree inheritance (parent → child) is handled here.

    Full cascade order:
        1. parent properties (tree inheritance)
        2. defaults (applied to all)
        3. base[type] (by element type)
        4. classes (in order)
        5. id (by element ID)
        6. inline properties
--]]
resolvePartProperties = function(partDef, parentResolved, styles)
    local resolved = {}

    -- 1. Inherit from parent (tree-level, handled here)
    if parentResolved and parentResolved.properties then
        merge(resolved, deepCopy(parentResolved.properties))
    end

    -- 2-6. Use ClassResolver for the rest of the cascade
    local resolver = getClassResolver()
    if resolver then
        -- Build definition for ClassResolver
        local definition = {
            type = partDef.shape == "wedge" and "WedgePart" or "Part",
            class = partDef.class,
            id = partDef.id,
        }

        -- Add inline properties (non-reserved keys from partDef)
        if partDef.properties then
            for k, v in pairs(partDef.properties) do
                definition[k] = v
            end
        end

        -- Resolve using ClassResolver
        local cascaded = resolver.resolve(definition, styles, {
            reservedKeys = {
                -- Geometry-specific reserved keys
                parent = true,
                geometry = true,
                shape = true,
                class = true,
                id = true,
                type = true,
                name = true,
                properties = true,
            }
        })

        merge(resolved, cascaded)
    else
        -- Fallback: manual cascade if ClassResolver not available
        local partType = partDef.shape == "wedge" and "WedgePart" or "Part"
        if styles.base and styles.base[partType] then
            merge(resolved, deepCopy(styles.base[partType]))
        end

        if partDef.class then
            for class in partDef.class:gmatch("%S+") do
                if styles.classes and styles.classes[class] then
                    merge(resolved, deepCopy(styles.classes[class]))
                end
            end
        end

        if partDef.id and styles.ids and styles.ids[partDef.id] then
            merge(resolved, deepCopy(styles.ids[partDef.id]))
        end

        if partDef.properties then
            merge(resolved, deepCopy(partDef.properties))
        end
    end

    return resolved
end

--------------------------------------------------------------------------------
-- Resolve: Geometry Transform
--------------------------------------------------------------------------------

resolvePartGeometry = function(partDef, parentResolved, resolvedParts)
    local geom = partDef.geometry or {}

    -- Resolve any reference markers in geometry values
    local resolvedGeom = resolveReferences(geom, resolvedParts)

    local origin = normalizeVector(resolvedGeom.origin)
    local scale = normalizeVector(resolvedGeom.scale or resolvedGeom.dims)
    local rotation = normalizeVector(resolvedGeom.rotation)

    if scale[1] == 0 and scale[2] == 0 and scale[3] == 0 then
        scale = {4, 4, 4}
    end

    -- Accumulate origin from parent
    if parentResolved and parentResolved.geometry then
        local parentOrigin = parentResolved.geometry.origin or {0, 0, 0}
        origin = {
            origin[1] + parentOrigin[1],
            origin[2] + parentOrigin[2],
            origin[3] + parentOrigin[3],
        }
    end

    return {
        origin = origin,
        scale = scale,
        rotation = rotation,
    }
end

--------------------------------------------------------------------------------
-- Resolve: Main (Two-Phase)
--------------------------------------------------------------------------------

function Geometry.resolve(layout)
    local styles = getStyles()

    -- Support function-based layouts for reference resolution
    local layoutData = layout
    if type(layout) == "function" then
        local partsProxy = Geometry.createPartsProxy()
        layoutData = layout(partsProxy)
    end

    local parts = layoutData.parts or {}

    --------------------------------------------------------------------------
    -- PHASE 1: Define tree (create empty stubs for all parts)
    --------------------------------------------------------------------------
    local stubs = {}
    for id, partDef in pairs(parts) do
        stubs[id] = {
            id = id,
            name = partDef.name or id,
            parent = partDef.parent,
            shape = partDef.shape or "block",
            geometry = nil,
            properties = nil,
            _def = partDef,  -- Keep reference to definition for phase 2
        }
    end

    --------------------------------------------------------------------------
    -- PHASE 2: Populate values (tree order, parents before children)
    --------------------------------------------------------------------------
    local order = buildTreeOrder(parts)

    for _, entry in ipairs(order) do
        local id = entry.id
        local stub = stubs[id]
        local partDef = stub._def

        local parentStub = nil
        if partDef.parent and partDef.parent ~= "root" then
            parentStub = stubs[partDef.parent]
        end

        -- Resolve geometry (references can now look up any stub)
        stub.geometry = resolvePartGeometry(partDef, parentStub, stubs)

        -- Resolve properties (cascade from parent)
        stub.properties = resolvePartProperties(partDef, parentStub, styles)

        -- Clean up definition reference
        stub._def = nil
    end

    -- Attach metadata for scanner/debug
    stubs._meta = {
        name = layoutData.name,
    }

    return stubs
end

--------------------------------------------------------------------------------
-- Instantiate: Helpers
--------------------------------------------------------------------------------

toColor3 = function(color)
    if not color then return nil end
    if typeof(color) == "Color3" then return color end
    if type(color) == "table" then
        local max = math.max(color[1] or 0, color[2] or 0, color[3] or 0)
        if max > 1 then
            return Color3.fromRGB(color[1] or 0, color[2] or 0, color[3] or 0)
        else
            return Color3.new(color[1] or 0, color[2] or 0, color[3] or 0)
        end
    end
    if type(color) == "string" then
        return BrickColor.new(color).Color
    end
    return nil
end

applyProperties = function(part, properties)
    for key, value in pairs(properties) do
        if key == "Color" then
            local color = toColor3(value)
            if color then part.Color = color end
        elseif key == "Material" then
            if type(value) == "string" then
                local success = pcall(function()
                    part.Material = Enum.Material[value]
                end)
                if not success then
                    warn("[Geometry] Unknown material:", value)
                end
            else
                part.Material = value
            end
        else
            local success = pcall(function()
                part[key] = value
            end)
            if not success then
                part:SetAttribute(key, value)
            end
        end
    end
end

createPart = function(entry)
    local geom = entry.geometry
    local shape = entry.shape

    local part
    if shape == "wedge" then
        part = Instance.new("WedgePart")
    elseif shape == "cylinder" then
        part = Instance.new("Part")
        part.Shape = Enum.PartType.Cylinder
    elseif shape == "sphere" then
        part = Instance.new("Part")
        part.Shape = Enum.PartType.Ball
    else
        part = Instance.new("Part")
    end

    part.Name = entry.name or entry.id
    part.Size = Vector3.new(geom.scale[1], geom.scale[2], geom.scale[3])

    local pos = geom.origin
    part.Position = Vector3.new(pos[1], pos[2] + geom.scale[2]/2, pos[3])

    if geom.rotation then
        local rot = geom.rotation
        part.CFrame = part.CFrame * CFrame.Angles(
            math.rad(rot[1] or 0),
            math.rad(rot[2] or 0),
            math.rad(rot[3] or 0)
        )
    end

    applyProperties(part, entry.properties)

    return part
end

--------------------------------------------------------------------------------
-- Instantiate: Main
--------------------------------------------------------------------------------

function Geometry.instantiate(resolved, parent)
    parent = parent or workspace

    -- Calculate bounds (skip _meta)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

    for id, entry in pairs(resolved) do
        if id ~= "_meta" then
            local g = entry.geometry
            local o, s = g.origin, g.scale
            minX = math.min(minX, o[1])
            minY = math.min(minY, o[2])
            minZ = math.min(minZ, o[3])
            maxX = math.max(maxX, o[1] + s[1])
            maxY = math.max(maxY, o[2] + s[2])
            maxZ = math.max(maxZ, o[3] + s[3])
        end
    end

    local bounds = {maxX - minX, maxY - minY, maxZ - minZ}

    -- Create container
    local container = Instance.new("Part")
    container.Name = resolved._meta and resolved._meta.name or "GeometryContainer"
    container.Size = Vector3.new(bounds[1], bounds[2], bounds[3])
    container.Position = Vector3.new(
        (minX + maxX) / 2,
        (minY + maxY) / 2,
        (minZ + maxZ) / 2
    )
    container.Anchored = true
    container.CanCollide = false
    container.CanQuery = false
    container.Transparency = 1

    -- Create parts (skip _meta)
    for id, entry in pairs(resolved) do
        if id ~= "_meta" then
            local part = createPart(entry)
            part.Parent = container
            registerPart(id, part, entry)
        end
    end

    container.Parent = parent
    return container
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Geometry.build(layout, parent)
    local resolved = Geometry.resolve(layout)
    return Geometry.instantiate(resolved, parent)
end

function Geometry.debug(layout)
    local resolved = Geometry.resolve(layout)

    print("=== RESOLVED LAYOUT ===")
    for id, entry in pairs(resolved) do
        if id ~= "_meta" then
            print(string.format("  %s:", id))
            print(string.format("    parent: %s", entry.parent or "root"))
            print(string.format("    geometry: origin={%s} scale={%s}",
                table.concat(entry.geometry.origin, ","),
                table.concat(entry.geometry.scale, ",")))
            for k, v in pairs(entry.properties) do
                print(string.format("    %s = %s", k, tostring(v)))
            end
        end
    end
    print("=======================")

    return resolved
end

--------------------------------------------------------------------------------
-- Scanner: Code Generation
--------------------------------------------------------------------------------

valueToCode = function(value, indent)
    indent = indent or ""
    local t = type(value)

    if t == "string" then
        return string.format('"%s"', value)
    elseif t == "number" then
        -- Clean up floats
        if value == math.floor(value) then
            return tostring(math.floor(value))
        else
            return string.format("%.2f", value):gsub("%.?0+$", "")
        end
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        return tableToCode(value, indent)
    else
        return tostring(value)
    end
end

tableToCode = function(tbl, indent)
    indent = indent or ""
    local nextIndent = indent .. "    "
    local lines = {}

    -- Check if array-like (sequential integer keys starting at 1)
    local isArray = true
    local maxIndex = 0
    for k, _ in pairs(tbl) do
        if type(k) == "number" and k == math.floor(k) and k > 0 then
            maxIndex = math.max(maxIndex, k)
        else
            isArray = false
            break
        end
    end
    if isArray and maxIndex > 0 then
        -- Check for gaps
        for i = 1, maxIndex do
            if tbl[i] == nil then
                isArray = false
                break
            end
        end
    end

    if isArray and maxIndex > 0 then
        -- Array format: {1, 2, 3}
        local values = {}
        for i = 1, maxIndex do
            table.insert(values, valueToCode(tbl[i], nextIndent))
        end
        -- Short arrays on one line
        local oneLine = "{" .. table.concat(values, ", ") .. "}"
        if #oneLine < 60 then
            return oneLine
        end
        -- Long arrays multiline
        table.insert(lines, "{")
        for i, v in ipairs(values) do
            table.insert(lines, nextIndent .. v .. ",")
        end
        table.insert(lines, indent .. "}")
        return table.concat(lines, "\n")
    else
        -- Dictionary format
        table.insert(lines, "{")

        -- Sort keys for consistent output
        local keys = {}
        for k, _ in pairs(tbl) do
            table.insert(keys, k)
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)

        for _, k in ipairs(keys) do
            local v = tbl[k]
            local keyStr
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k
            else
                keyStr = "[" .. valueToCode(k, nextIndent) .. "]"
            end
            local valStr = valueToCode(v, nextIndent)
            table.insert(lines, nextIndent .. keyStr .. " = " .. valStr .. ",")
        end

        table.insert(lines, indent .. "}")
        return table.concat(lines, "\n")
    end
end

function Geometry.scan(layout)
    local resolved = Geometry.resolve(layout)

    -- Get name from metadata or fallback
    local layoutName = (resolved._meta and resolved._meta.name)
        or (type(layout) == "table" and layout.name)
        or "ScannedLayout"

    -- Build output structure matching layout format
    local output = {
        name = layoutName,
        parts = {},
    }

    for id, entry in pairs(resolved) do
        -- Skip metadata
        if id ~= "_meta" then
            output.parts[id] = {
                parent = entry.parent or "root",
                shape = entry.shape ~= "block" and entry.shape or nil,
                geometry = {
                    origin = entry.geometry.origin,
                    scale = entry.geometry.scale,
                    rotation = (entry.geometry.rotation[1] ~= 0 or
                               entry.geometry.rotation[2] ~= 0 or
                               entry.geometry.rotation[3] ~= 0)
                               and entry.geometry.rotation or nil,
                },
                properties = entry.properties,
            }
        end
    end

    -- Generate code
    local code = "--[[\n"
    code = code .. "    " .. layoutName .. "\n"
    code = code .. "    Generated by Geometry.scan()\n"
    code = code .. "    All values resolved - no class references\n"
    code = code .. "--]]\n\n"
    code = code .. "return " .. tableToCode(output)

    return code
end

function Geometry.scanPrint(layout)
    local code = Geometry.scan(layout)

    print("\n" .. string.rep("=", 70))
    print("-- Geometry Scanner Output")
    print(string.rep("=", 70))
    print(code)
    print(string.rep("=", 70) .. "\n")

    return code
end

--------------------------------------------------------------------------------
-- Scanner: CSV/TSV Export
--------------------------------------------------------------------------------

function Geometry.toTSV(layout)
    local resolved = Geometry.resolve(layout)

    -- Collect all property keys (skip _meta)
    local propKeys = {}
    local propKeysSet = {}
    for id, entry in pairs(resolved) do
        if id ~= "_meta" and entry.properties then
            for k, _ in pairs(entry.properties) do
                if not propKeysSet[k] then
                    propKeysSet[k] = true
                    table.insert(propKeys, k)
                end
            end
        end
    end
    table.sort(propKeys)

    -- Build header
    local headers = {
        "id", "parent", "shape",
        "origin_x", "origin_y", "origin_z",
        "scale_x", "scale_y", "scale_z",
        "rot_x", "rot_y", "rot_z",
    }
    for _, k in ipairs(propKeys) do
        table.insert(headers, k)
    end

    local lines = { table.concat(headers, "\t") }

    -- Sort entries by id for consistent output (skip _meta)
    local ids = {}
    for id, _ in pairs(resolved) do
        if id ~= "_meta" then
            table.insert(ids, id)
        end
    end
    table.sort(ids)

    -- Build rows
    for _, id in ipairs(ids) do
        local entry = resolved[id]
        local g = entry.geometry
        local row = {
            id,
            entry.parent or "root",
            entry.shape or "block",
            g.origin[1], g.origin[2], g.origin[3],
            g.scale[1], g.scale[2], g.scale[3],
            g.rotation[1], g.rotation[2], g.rotation[3],
        }

        -- Add properties
        for _, k in ipairs(propKeys) do
            local v = entry.properties[k]
            if v == nil then
                table.insert(row, "")
            elseif type(v) == "table" then
                -- Format arrays like {255,128,0}
                local parts = {}
                for _, val in ipairs(v) do
                    table.insert(parts, tostring(val))
                end
                if #parts > 0 then
                    table.insert(row, "{" .. table.concat(parts, ",") .. "}")
                else
                    table.insert(row, "{}")
                end
            else
                table.insert(row, tostring(v))
            end
        end

        table.insert(lines, table.concat(row, "\t"))
    end

    return table.concat(lines, "\n")
end

function Geometry.toTSVPrint(layout)
    local tsv = Geometry.toTSV(layout)

    print("\n" .. string.rep("=", 70))
    print("-- Geometry TSV Export (paste into spreadsheet)")
    print(string.rep("=", 70))
    print(tsv)
    print(string.rep("=", 70) .. "\n")

    return tsv
end

--##############################################################################
-- PHASE 3: RETURN
--##############################################################################

return Geometry
