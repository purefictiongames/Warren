--[[
    LibPureFiction Framework v2
    Factory/Geometry.lua - 3D Part Builder

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    Builds 3D Parts from declarative specs. Used by Factory.geometry().
--]]

local Geometry = {}

-- Get ClassResolver from parent
local ClassResolver = require(script.Parent.Parent.ClassResolver)

--------------------------------------------------------------------------------
-- REGISTRY
--------------------------------------------------------------------------------

local registry = {}
local currentBuildId = 0

function Geometry.clear()
    registry = {}
    currentBuildId = currentBuildId + 1
end

local function registerPart(id, instance, definition, geometry)
    if not id then return end
    registry[id] = {
        instance = instance,
        definition = definition,
        geometry = geometry,
        buildId = currentBuildId,
    }
end

function Geometry.get(selector)
    local id = selector
    if type(selector) == "string" and selector:sub(1, 1) == "#" then
        id = selector:sub(2)
    end
    return registry[id]
end

function Geometry.getInstance(selector)
    local entry = Geometry.get(selector)
    return entry and entry.instance or nil
end

function Geometry.updateInstance(id, newInstance, compiled)
    if registry[id] then
        registry[id].instance = newInstance
        if compiled then
            registry[id].compiled = true
        end
    end
end

--------------------------------------------------------------------------------
-- SCALE CONVERSION
--------------------------------------------------------------------------------

local currentScale = 1

function Geometry.parseScale(scaleValue)
    if type(scaleValue) == "number" then
        return scaleValue
    end
    if type(scaleValue) == "string" then
        local a, b = scaleValue:match("^(%d+%.?%d*):(%d+%.?%d*)$")
        if a and b then
            return tonumber(a) / tonumber(b)
        end
    end
    return 1
end

function Geometry.getScale()
    return currentScale
end

function Geometry.toStuds(value)
    if type(value) == "number" then
        return value * currentScale
    elseif type(value) == "table" then
        local result = {}
        for i, v in ipairs(value) do
            result[i] = v * currentScale
        end
        return result
    end
    return value
end

--------------------------------------------------------------------------------
-- MATERIAL / COLOR CONVERSION
--------------------------------------------------------------------------------

local MATERIAL_MAP = {
    ["Plastic"] = Enum.Material.Plastic,
    ["SmoothPlastic"] = Enum.Material.SmoothPlastic,
    ["Neon"] = Enum.Material.Neon,
    ["Glass"] = Enum.Material.Glass,
    ["ForceField"] = Enum.Material.ForceField,
    ["Wood"] = Enum.Material.Wood,
    ["WoodPlanks"] = Enum.Material.WoodPlanks,
    ["Brick"] = Enum.Material.Brick,
    ["Concrete"] = Enum.Material.Concrete,
    ["Cobblestone"] = Enum.Material.Cobblestone,
    ["Granite"] = Enum.Material.Granite,
    ["Marble"] = Enum.Material.Marble,
    ["Slate"] = Enum.Material.Slate,
    ["Limestone"] = Enum.Material.Limestone,
    ["Sandstone"] = Enum.Material.Sandstone,
    ["Basalt"] = Enum.Material.Basalt,
    ["CrackedLava"] = Enum.Material.CrackedLava,
    ["Pavement"] = Enum.Material.Pavement,
    ["Metal"] = Enum.Material.Metal,
    ["DiamondPlate"] = Enum.Material.DiamondPlate,
    ["CorrodedMetal"] = Enum.Material.CorrodedMetal,
    ["Grass"] = Enum.Material.Grass,
    ["LeafyGrass"] = Enum.Material.LeafyGrass,
    ["Sand"] = Enum.Material.Sand,
    ["Snow"] = Enum.Material.Snow,
    ["Mud"] = Enum.Material.Mud,
    ["Ground"] = Enum.Material.Ground,
    ["Ice"] = Enum.Material.Ice,
    ["Salt"] = Enum.Material.Salt,
    ["Fabric"] = Enum.Material.Fabric,
    ["Carpet"] = Enum.Material.Carpet,
    ["Leather"] = Enum.Material.Leather,
    ["Foil"] = Enum.Material.Foil,
    ["Rubber"] = Enum.Material.Rubber,
    ["Cardboard"] = Enum.Material.Cardboard,
}

local function toColor3(value)
    if typeof(value) == "Color3" then
        return value
    end
    if type(value) == "table" and #value >= 3 then
        local r, g, b = value[1], value[2], value[3]
        if r <= 1 and g <= 1 and b <= 1 then
            return Color3.new(r, g, b)
        else
            return Color3.fromRGB(r, g, b)
        end
    end
    if type(value) == "string" then
        return BrickColor.new(value).Color
    end
    return Color3.fromRGB(163, 162, 165)
end

local function toMaterial(value)
    if typeof(value) == "EnumItem" then
        return value
    end
    if type(value) == "string" then
        return MATERIAL_MAP[value] or Enum.Material.SmoothPlastic
    end
    return Enum.Material.SmoothPlastic
end

--------------------------------------------------------------------------------
-- PROPERTY APPLICATION
--------------------------------------------------------------------------------

local function applyProperties(part, properties)
    if properties.Color then
        part.Color = toColor3(properties.Color)
    end
    if properties.Material then
        part.Material = toMaterial(properties.Material)
    end
    if properties.Anchored ~= nil then
        part.Anchored = properties.Anchored
    end
    if properties.CanCollide ~= nil then
        part.CanCollide = properties.CanCollide
    end
    if properties.CanTouch ~= nil then
        part.CanTouch = properties.CanTouch
    end
    if properties.CanQuery ~= nil then
        part.CanQuery = properties.CanQuery
    end
    if properties.Transparency ~= nil then
        part.Transparency = properties.Transparency
    end
    if properties.Reflectance ~= nil then
        part.Reflectance = properties.Reflectance
    end
    if properties.CastShadow ~= nil then
        part.CastShadow = properties.CastShadow
    end
    if properties.Massless ~= nil then
        part.Massless = properties.Massless
    end
end

--------------------------------------------------------------------------------
-- SHAPE CREATION
--------------------------------------------------------------------------------

local function createBlock(definition, properties, originOffset)
    local position = definition.position or {0, 0, 0}
    local size = definition.size or {4, 4, 4}

    position = Geometry.toStuds(position)
    size = Geometry.toStuds(size)

    local pos = Vector3.new(position[1], position[2], position[3]) + originOffset
    local sz = Vector3.new(size[1], size[2], size[3])

    local part = Instance.new("Part")
    part.Name = definition.id or "Part"
    part.Shape = Enum.PartType.Block
    part.Size = sz
    part.Position = pos
    part.Anchored = true

    applyProperties(part, properties)

    if definition.id then
        part:SetAttribute("FactoryId", definition.id)
    end
    if definition.class then
        part:SetAttribute("FactoryClass", definition.class)
    end

    return part, {
        type = "block",
        position = pos,
        size = sz,
        center = pos,
    }
end

local function createCylinder(definition, properties, originOffset)
    local position = definition.position or {0, 0, 0}
    local height = definition.height or 4
    local radius = definition.radius or 2

    position = Geometry.toStuds(position)
    height = Geometry.toStuds(height)
    radius = Geometry.toStuds(radius)

    local pos = Vector3.new(position[1], position[2], position[3]) + originOffset

    local part = Instance.new("Part")
    part.Name = definition.id or "Cylinder"
    part.Shape = Enum.PartType.Cylinder
    part.Size = Vector3.new(height, radius * 2, radius * 2)
    part.Position = pos
    part.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
    part.Anchored = true

    applyProperties(part, properties)

    if definition.id then
        part:SetAttribute("FactoryId", definition.id)
    end
    if definition.class then
        part:SetAttribute("FactoryClass", definition.class)
    end

    return part, {
        type = "cylinder",
        position = pos,
        height = height,
        radius = radius,
        center = pos,
    }
end

local function createSphere(definition, properties, originOffset)
    local position = definition.position or {0, 0, 0}
    local radius = definition.radius or 2

    position = Geometry.toStuds(position)
    radius = Geometry.toStuds(radius)

    local pos = Vector3.new(position[1], position[2], position[3]) + originOffset

    local part = Instance.new("Part")
    part.Name = definition.id or "Sphere"
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
    part.Position = pos
    part.Anchored = true

    applyProperties(part, properties)

    if definition.id then
        part:SetAttribute("FactoryId", definition.id)
    end
    if definition.class then
        part:SetAttribute("FactoryClass", definition.class)
    end

    return part, {
        type = "sphere",
        position = pos,
        radius = radius,
        center = pos,
    }
end

local function createWedge(definition, properties, originOffset)
    local position = definition.position or {0, 0, 0}
    local size = definition.size or {4, 4, 4}

    position = Geometry.toStuds(position)
    size = Geometry.toStuds(size)

    local pos = Vector3.new(position[1], position[2], position[3]) + originOffset
    local sz = Vector3.new(size[1], size[2], size[3])

    local part = Instance.new("WedgePart")
    part.Name = definition.id or "Wedge"
    part.Size = sz
    part.Position = pos
    part.Anchored = true

    if definition.rotation then
        local rot = definition.rotation
        part.CFrame = CFrame.new(pos) * CFrame.Angles(
            math.rad(rot[1] or 0),
            math.rad(rot[2] or 0),
            math.rad(rot[3] or 0)
        )
    end

    applyProperties(part, properties)

    if definition.id then
        part:SetAttribute("FactoryId", definition.id)
    end
    if definition.class then
        part:SetAttribute("FactoryClass", definition.class)
    end

    return part, {
        type = "wedge",
        position = pos,
        size = sz,
        center = pos,
    }
end

local function createPart(definition, spec, originOffset)
    -- Add type = "part" so base.part styles apply via ClassResolver
    local defWithType = { type = "part" }
    for k, v in pairs(definition) do
        defWithType[k] = v
    end

    local properties = ClassResolver.resolve(defWithType, spec)
    local shape = definition.shape or "block"

    if shape == "block" then
        return createBlock(definition, properties, originOffset)
    elseif shape == "cylinder" then
        return createCylinder(definition, properties, originOffset)
    elseif shape == "sphere" then
        return createSphere(definition, properties, originOffset)
    elseif shape == "wedge" then
        return createWedge(definition, properties, originOffset)
    else
        warn("[Factory.Geometry] Unknown shape:", shape)
        return createBlock(definition, properties, originOffset)
    end
end

--------------------------------------------------------------------------------
-- ORIGIN OFFSET
--------------------------------------------------------------------------------

local function getOriginOffset(origin, bounds)
    if not bounds then
        return Vector3.new(0, 0, 0)
    end

    local w, h, d = bounds[1] or 0, bounds[2] or 0, bounds[3] or 0

    -- Convert from spec coordinate system to corner-relative coordinates
    if origin == "center" then
        -- Spec coords are relative to center, shift to corner
        return Vector3.new(w / 2, h / 2, d / 2)
    elseif origin == "floor-center" then
        -- Spec coords are relative to floor-center (XZ center, Y=0 at floor)
        return Vector3.new(w / 2, 0, d / 2)
    else -- "corner" (default)
        -- Spec coords already relative to corner, no shift needed
        return Vector3.new(0, 0, 0)
    end
end

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------

--[[
    Build geometry from a layout or spec.

    @param layout: Layout { name, spec } or raw spec { bounds, parts, ... }
    @param parent: Optional parent instance (default: workspace)
    @return: Part container with child geometry
--]]
function Geometry.build(layout, parent)
    parent = parent or workspace

    -- Handle both layout format { name, spec } and raw spec format
    local name, spec
    if layout.spec then
        name = layout.name or "Layout"
        spec = layout.spec
    else
        name = layout.name or "Geometry"
        spec = layout
    end

    -- Set scale
    currentScale = Geometry.parseScale(spec.scale)

    -- Calculate bounds and origin offset
    local origin = spec.origin or "corner"
    local bounds = spec.bounds or {4, 4, 4}
    local scaledBounds = Geometry.toStuds(bounds)

    -- Create container Part
    local container = Instance.new("Part")
    container.Name = name
    container.Size = Vector3.new(scaledBounds[1], scaledBounds[2], scaledBounds[3])
    container.Anchored = true
    container.CanCollide = false
    container.CanQuery = false
    container.Transparency = 1
    container.Position = Vector3.new(0, scaledBounds[2] / 2, 0)

    local containerCorner = container.Position - container.Size / 2
    local originOffset = getOriginOffset(origin, scaledBounds)

    -- Build spec with built-in base.part defaults
    local specWithDefaults = {
        defaults = spec.defaults,
        base = {
            part = { Anchored = true },
        },
        classes = spec.classes,
        ids = spec.ids,
    }
    if spec.base then
        for typeName, typeStyles in pairs(spec.base) do
            if specWithDefaults.base[typeName] then
                for k, v in pairs(typeStyles) do
                    specWithDefaults.base[typeName][k] = v
                end
            else
                specWithDefaults.base[typeName] = typeStyles
            end
        end
    end

    -- Build parts
    if spec.parts then
        for _, partDef in ipairs(spec.parts) do
            local part, geometry = createPart(partDef, specWithDefaults, containerCorner + originOffset)
            if part then
                part.Parent = container
                registerPart(partDef.id, part, partDef, geometry)
            end
        end
    end

    -- Store mount points
    if spec.mounts then
        for _, mountDef in ipairs(spec.mounts) do
            local position = mountDef.position or {0, 0, 0}
            position = Geometry.toStuds(position)
            local pos = Vector3.new(position[1], position[2], position[3]) + containerCorner + originOffset

            local facing = mountDef.facing
            if facing then
                facing = Vector3.new(facing[1], facing[2], facing[3])
            end

            registerPart(mountDef.id, nil, mountDef, {
                type = "mount",
                position = pos,
                facing = facing,
            })
        end
    end

    -- Register container
    registerPart(name, container, { id = name }, {
        type = "container",
        position = container.Position,
        size = container.Size,
        bounds = scaledBounds,
    })

    container.Parent = parent
    return container
end

return Geometry
