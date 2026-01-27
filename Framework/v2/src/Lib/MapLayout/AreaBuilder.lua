--[[
    LibPureFiction Framework v2
    MapLayout/AreaBuilder.lua - Area Instantiation and Coordinate Transforms

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    AreaBuilder handles:
    - Instantiating areas from templates (prefab system)
    - Transforming local coordinates to world coordinates
    - Handling nested areas (recursive building)
    - ID namespacing (instance IDs are prefixed to avoid collisions)
    - Integration with MapBuilder for geometry creation

    ============================================================================
    COORDINATE TRANSFORMS
    ============================================================================

    When an area is placed at a world position, all geometry within it
    must be transformed from local coordinates to world coordinates:

        worldPos = areaWorldPosition + localPos - originOffset

    For nested areas, transforms stack:

        worldPos = parentAreaWorldPos + childAreaLocalPos + geometryLocalPos

    ============================================================================
    ID NAMESPACING
    ============================================================================

    When instancing areas, element IDs are namespaced to avoid collisions:

        Template: wall with id = "north"
        Instance: id = "hallway1", wall id becomes "hallway1/north"

    Nested areas stack namespaces:

        "building1/floor2/hallway/north"

--]]

local AreaBuilder = {}

-- Dependencies
local AreaFactory = require(script.Parent.AreaFactory)
local BoundsValidator = require(script.Parent.BoundsValidator)
local StyleResolver = require(script.Parent.StyleResolver)
local Registry = require(script.Parent.Registry)
local ReferenceResolver = require(script.Parent.ReferenceResolver)
local GeometryFactory = require(script.Parent.GeometryFactory)

--[[
    Deep copy a table, transforming element IDs with a namespace prefix.

    @param tbl: Table to copy
    @param namespace: ID prefix (e.g., "hallway1")
    @return: Deep copy with namespaced IDs
--]]
local function deepCopyWithNamespace(tbl, namespace)
    if type(tbl) ~= "table" then
        return tbl
    end

    local copy = {}
    for k, v in pairs(tbl) do
        if k == "id" and type(v) == "string" then
            -- Namespace the ID
            copy[k] = namespace .. "/" .. v
        elseif type(v) == "table" then
            copy[k] = deepCopyWithNamespace(v, namespace)
        else
            copy[k] = v
        end
    end
    return copy
end

--[[
    Transform a 2D position from local to world coordinates.

    @param localPos: {x, z} local position
    @param worldOrigin: Vector3 world position of area origin
    @param originOffset: Vector3 offset from area corner to origin
    @return: {x, z} world position
--]]
local function transformPosition2D(localPos, worldOrigin, originOffset)
    if type(localPos) ~= "table" or type(localPos[1]) ~= "number" then
        return localPos  -- Not a literal position, return as-is
    end

    return {
        localPos[1] + worldOrigin.X - originOffset.X,
        localPos[2] + worldOrigin.Z - originOffset.Z,
    }
end

--[[
    Transform a 3D position from local to world coordinates.

    @param localPos: {x, y, z} local position
    @param worldOrigin: Vector3 world position
    @param originOffset: Vector3 offset from corner to origin
    @return: {x, y, z} world position
--]]
local function transformPosition3D(localPos, worldOrigin, originOffset)
    if type(localPos) ~= "table" or type(localPos[1]) ~= "number" then
        return localPos
    end

    if #localPos == 2 then
        -- 2D position
        return transformPosition2D(localPos, worldOrigin, originOffset)
    end

    return {
        localPos[1] + worldOrigin.X - originOffset.X,
        localPos[2] + worldOrigin.Y - originOffset.Y,
        localPos[3] + worldOrigin.Z - originOffset.Z,
    }
end

--[[
    Transform all positions in an element definition.

    @param element: Element definition (modified in place)
    @param worldOrigin: Vector3 world position of area
    @param originOffset: Vector3 origin offset
--]]
local function transformElement(element, worldOrigin, originOffset)
    -- Transform 'from' (2D)
    if element.from and type(element.from) == "table" and type(element.from[1]) == "number" then
        element.from = transformPosition2D(element.from, worldOrigin, originOffset)
    end

    -- Transform 'to' (2D)
    if element.to and type(element.to) == "table" and type(element.to[1]) == "number" then
        element.to = transformPosition2D(element.to, worldOrigin, originOffset)
    end

    -- Transform 'position' (3D)
    if element.position and type(element.position) == "table" and type(element.position[1]) == "number" then
        element.position = transformPosition3D(element.position, worldOrigin, originOffset)
    end

    -- Transform offsets in 'along' references
    if element.from and type(element.from) == "table" and element.from.offset then
        element.from.offset = transformPosition2D(element.from.offset, Vector3.new(0, 0, 0), originOffset)
    end
    if element.to and type(element.to) == "table" and element.to.offset then
        element.to.offset = transformPosition2D(element.to.offset, Vector3.new(0, 0, 0), originOffset)
    end

    -- Transform anchor offset
    if element.anchor and element.anchor.offset then
        element.anchor.offset = transformPosition3D(element.anchor.offset, Vector3.new(0, 0, 0), originOffset)
    end
end

--[[
    Transform all elements in a category.

    @param elements: Array of element definitions
    @param worldOrigin: Vector3
    @param originOffset: Vector3
    @return: Transformed elements (new array)
--]]
local function transformCategory(elements, worldOrigin, originOffset)
    if not elements then
        return nil
    end

    local transformed = {}
    for _, elem in ipairs(elements) do
        local copy = {}
        for k, v in pairs(elem) do
            if type(v) == "table" then
                copy[k] = deepCopyWithNamespace(v, "")
                -- Remove the namespace for non-ID tables
                if k ~= "id" then
                    copy[k] = {}
                    for kk, vv in pairs(v) do
                        copy[k][kk] = vv
                    end
                end
            else
                copy[k] = v
            end
        end
        transformElement(copy, worldOrigin, originOffset)
        table.insert(transformed, copy)
    end
    return transformed
end

--[[
    Build an area instance into geometry.

    @param instance: Area instance definition
    @param styles: Style definitions
    @param parentModel: Parent Model to add geometry to
    @param parentNamespace: Parent ID namespace (for nested areas)
    @param parentWorldPos: Parent's world position (for nested transforms)
    @return: Model containing area geometry
--]]
function AreaBuilder.build(instance, styles, parentModel, parentNamespace, parentWorldPos)
    parentNamespace = parentNamespace or ""
    parentWorldPos = parentWorldPos or Vector3.new(0, 0, 0)

    -- Determine the instance ID and namespace
    local instanceId = instance.id
    local namespace = parentNamespace ~= "" and (parentNamespace .. "/" .. instanceId) or instanceId

    -- Get bounds and origin
    local bounds = instance.bounds
    if not bounds then
        error(string.format("[AreaBuilder] Area '%s' has no bounds defined", instanceId), 2)
    end

    local origin = instance.origin or "corner"
    local originOffset = AreaFactory.getOriginOffset(origin, bounds)

    -- Calculate world position
    local worldPos
    if instance.position then
        if type(instance.position) == "table" and type(instance.position[1]) == "number" then
            if #instance.position == 2 then
                worldPos = Vector3.new(instance.position[1], 0, instance.position[2])
            else
                worldPos = Vector3.new(instance.position[1], instance.position[2], instance.position[3])
            end
        elseif typeof(instance.position) == "Vector3" then
            worldPos = instance.position
        else
            -- Reference - resolve it
            worldPos = ReferenceResolver.resolve(instance.position)
        end
    else
        worldPos = Vector3.new(0, 0, 0)
    end

    -- Add parent offset for nested areas
    worldPos = worldPos + parentWorldPos

    -- Handle anchor-based positioning
    if instance.anchor then
        local anchorTarget = instance.anchor.target or instance.anchor
        local anchorPos = ReferenceResolver.resolve(anchorTarget)
        if anchorPos then
            worldPos = anchorPos
            if instance.anchor.offset then
                local offset = instance.anchor.offset
                if type(offset) == "table" then
                    if #offset == 2 then
                        worldPos = worldPos + Vector3.new(offset[1], 0, offset[2])
                    else
                        worldPos = worldPos + Vector3.new(offset[1], offset[2], offset[3])
                    end
                end
            end
        end
    end

    -- Validate bounds BEFORE building
    BoundsValidator.validateOrThrow(namespace, instance, originOffset)

    -- Create a Model for this area
    local areaModel = Instance.new("Model")
    areaModel.Name = instanceId

    -- Set attributes for identification
    areaModel:SetAttribute("MapLayoutArea", true)
    areaModel:SetAttribute("MapLayoutId", namespace)
    if instance.class then
        areaModel:SetAttribute("MapLayoutClass", instance.class)
    end
    areaModel:SetAttribute("MapLayoutBounds", string.format("%d,%d,%d", bounds[1], bounds[2], bounds[3]))
    areaModel:SetAttribute("MapLayoutOrigin", origin)

    -- Register the area in the registry
    Registry.register(namespace, {
        instance = areaModel,
        definition = instance,
        geometry = {
            type = "area",
            position = worldPos,
            bounds = Vector3.new(bounds[1], bounds[2], bounds[3]),
            originOffset = originOffset,
        },
    })

    -- Also register with just the instance ID for simpler lookups
    if parentNamespace == "" then
        -- Top-level area, ID is already registered
    else
        -- Nested area, also register short name within parent context
        Registry.register(instanceId, {
            instance = areaModel,
            definition = instance,
            geometry = {
                type = "area",
                position = worldPos,
                bounds = Vector3.new(bounds[1], bounds[2], bounds[3]),
                originOffset = originOffset,
            },
        })
    end

    -- Build geometry categories
    local categories = {"walls", "platforms", "boxes", "floors", "cylinders", "spheres", "wedges", "elements"}

    for _, category in ipairs(categories) do
        if instance[category] then
            for i, elemDef in ipairs(instance[category]) do
                -- Deep copy and namespace the element
                local element = deepCopyWithNamespace(elemDef, namespace)

                -- Transform positions to world coordinates
                transformElement(element, worldPos, originOffset)

                -- Set default type based on category
                if not element.type then
                    local typeMap = {
                        walls = "wall",
                        platforms = "platform",
                        boxes = "platform",
                        floors = "floor",
                        cylinders = "cylinder",
                        spheres = "sphere",
                        wedges = "wedge",
                    }
                    element.type = typeMap[category] or "platform"
                end

                -- Resolve positions (handles references)
                if element.from then
                    element._resolvedFrom = ReferenceResolver.resolve(element.from)
                end
                if element.to then
                    element._resolvedTo = ReferenceResolver.resolve(element.to)
                end
                if element.position then
                    element._resolvedPosition = ReferenceResolver.resolve(element.position)
                end

                -- Resolve styles
                local properties = StyleResolver.resolve(element, styles)

                -- Create geometry
                local part, geometry = GeometryFactory.create(element, properties)

                if part then
                    part.Parent = areaModel

                    -- Register in registry with namespaced ID
                    if element.id then
                        Registry.register(element.id, {
                            instance = part,
                            definition = element,
                            geometry = geometry,
                        })
                    end
                end
            end
        end
    end

    -- Build nested areas (recursive)
    if instance.areas then
        for _, nestedAreaDef in ipairs(instance.areas) do
            local nestedInstance

            -- Check if it's a template reference or inline definition
            if nestedAreaDef.template then
                -- Create instance from template
                nestedInstance = AreaFactory.createInstance(nestedAreaDef.template, nestedAreaDef)
            else
                -- Inline area definition
                nestedInstance = nestedAreaDef
            end

            -- Recursively build nested area
            local nestedModel = AreaBuilder.build(
                nestedInstance,
                styles,
                areaModel,
                namespace,
                worldPos
            )

            if nestedModel then
                nestedModel.Parent = areaModel
            end
        end
    end

    -- Parent to the provided model
    if parentModel then
        areaModel.Parent = parentModel
    end

    return areaModel
end

--[[
    Build multiple area instances.

    @param areas: Array of area instance definitions
    @param styles: Style definitions
    @param parentModel: Parent Model
    @return: Array of created Models
--]]
function AreaBuilder.buildAll(areas, styles, parentModel)
    local models = {}

    for _, areaDef in ipairs(areas) do
        local instance

        if areaDef.template then
            -- Create from template
            instance = AreaFactory.createInstance(areaDef.template, areaDef)
        else
            -- Inline definition
            instance = areaDef
        end

        local model = AreaBuilder.build(instance, styles, parentModel)
        table.insert(models, model)
    end

    return models
end

--[[
    Validate an area without building it.

    @param instance: Area instance definition
    @return: ValidationResult
--]]
function AreaBuilder.validate(instance)
    local origin = instance.origin or "corner"
    local originOffset = AreaFactory.getOriginOffset(origin, instance.bounds or {0, 0, 0})
    return BoundsValidator.validate(instance.id or "unnamed", instance, originOffset)
end

return AreaBuilder
