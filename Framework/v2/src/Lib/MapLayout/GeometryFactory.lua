--[[
    LibPureFiction Framework v2
    MapLayout/GeometryFactory.lua - Create Parts from Element Definitions

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Creates Roblox Parts from resolved element definitions. Handles:
    - Walls (from/to with height and thickness)
    - Platforms/boxes (position with size)
    - Cylinders, spheres, wedges
    - Applying material, color, and Part properties

    ============================================================================
    ELEMENT TYPES
    ============================================================================

    wall:
        from, to: 2D positions (x, z)
        height: Wall height
        thickness: Wall thickness (default 1)

    platform / box:
        position: 3D center position
        size: {x, y, z} dimensions

    cylinder:
        position: 3D center position
        height: Cylinder height
        radius: Cylinder radius

    sphere:
        position: 3D center position
        radius: Sphere radius

    wedge:
        position: 3D center position
        size: {x, y, z} dimensions

--]]

local GeometryFactory = {}

-- Material name to Enum mapping
local MATERIAL_MAP = {
    -- Common
    ["Plastic"] = Enum.Material.Plastic,
    ["SmoothPlastic"] = Enum.Material.SmoothPlastic,
    ["Neon"] = Enum.Material.Neon,
    ["Glass"] = Enum.Material.Glass,
    ["ForceField"] = Enum.Material.ForceField,

    -- Building materials
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

    -- Metal
    ["Metal"] = Enum.Material.Metal,
    ["DiamondPlate"] = Enum.Material.DiamondPlate,
    ["CorrodedMetal"] = Enum.Material.CorrodedMetal,

    -- Organic
    ["Grass"] = Enum.Material.Grass,
    ["LeafyGrass"] = Enum.Material.LeafyGrass,
    ["Sand"] = Enum.Material.Sand,
    ["Snow"] = Enum.Material.Snow,
    ["Mud"] = Enum.Material.Mud,
    ["Ground"] = Enum.Material.Ground,
    ["Ice"] = Enum.Material.Ice,
    ["Salt"] = Enum.Material.Salt,

    -- Fabric
    ["Fabric"] = Enum.Material.Fabric,
    ["Carpet"] = Enum.Material.Carpet,
    ["Leather"] = Enum.Material.Leather,

    -- Other
    ["Foil"] = Enum.Material.Foil,
    ["Rubber"] = Enum.Material.Rubber,
    ["Cardboard"] = Enum.Material.Cardboard,
}

--[[
    Convert a color value to Color3.
    Accepts:
    - Color3 (passthrough)
    - {r, g, b} array (0-255 range)
    - {r, g, b} array (0-1 range if all values <= 1)
    - BrickColor name string

    @param value: Color value
    @return: Color3
--]]
local function toColor3(value)
    if typeof(value) == "Color3" then
        return value
    end

    if type(value) == "table" and #value >= 3 then
        local r, g, b = value[1], value[2], value[3]
        -- If all values are <= 1, assume 0-1 range
        if r <= 1 and g <= 1 and b <= 1 then
            return Color3.new(r, g, b)
        else
            return Color3.fromRGB(r, g, b)
        end
    end

    if type(value) == "string" then
        local bc = BrickColor.new(value)
        return bc.Color
    end

    return Color3.fromRGB(163, 162, 165) -- Default gray
end

--[[
    Convert a material value to Enum.Material.

    @param value: Material name string or Enum
    @return: Enum.Material
--]]
local function toMaterial(value)
    if typeof(value) == "EnumItem" then
        return value
    end

    if type(value) == "string" then
        return MATERIAL_MAP[value] or Enum.Material.SmoothPlastic
    end

    return Enum.Material.SmoothPlastic
end

--[[
    Apply resolved properties to a Part.

    @param part: The Part instance
    @param properties: Resolved property table
--]]
local function applyProperties(part, properties)
    -- Color
    if properties.Color then
        part.Color = toColor3(properties.Color)
    end

    -- Material
    if properties.Material then
        part.Material = toMaterial(properties.Material)
    end

    -- Part properties
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

--[[
    Create a wall Part from a definition.

    Wall geometry:
    - from/to define the wall's footprint (x, z plane)
    - height defines the Y dimension
    - thickness defines the perpendicular width

    @param definition: Wall definition with from, to, height, thickness
    @param properties: Resolved style properties
    @return: Part, geometry data
--]]
function GeometryFactory.createWall(definition, properties)
    local from = definition._resolvedFrom
    local to = definition._resolvedTo

    if not from or not to then
        warn("[GeometryFactory] Wall missing resolved from/to positions")
        return nil, nil
    end

    local height = properties.height or definition.height or 10
    local thickness = properties.thickness or definition.thickness or 1

    -- Calculate wall dimensions and position
    local direction = (to - from)
    local length = direction.Magnitude

    if length == 0 then
        warn("[GeometryFactory] Wall has zero length")
        return nil, nil
    end

    local dirNorm = direction.Unit
    local center2D = (from + to) / 2
    local centerY = height / 2

    -- Create the part
    local part = Instance.new("Part")
    part.Name = definition.id or "Wall"
    part.Shape = Enum.PartType.Block

    -- Size: length along wall direction, thickness perpendicular, height vertical
    part.Size = Vector3.new(length, height, thickness)

    -- Position at center
    part.Position = Vector3.new(center2D.X, centerY, center2D.Z)

    -- Rotate to align with wall direction
    -- Wall extends along X axis by default, so we rotate to match from→to direction
    local angle = math.atan2(dirNorm.Z, dirNorm.X)
    part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, -angle, 0)

    -- Apply properties
    part.Anchored = true -- Default for map geometry
    applyProperties(part, properties)

    -- Store ID and class as attributes
    if definition.id then
        part:SetAttribute("MapLayoutId", definition.id)
    end
    if definition.class then
        part:SetAttribute("MapLayoutClass", definition.class)
    end

    -- Build geometry data for registry
    local geometry = {
        type = "wall",
        from = from,
        to = to,
        height = height,
        thickness = thickness,
        length = length,
        direction = dirNorm,
        center = part.Position,
    }

    return part, geometry
end

--[[
    Create a platform/box Part from a definition.

    @param definition: Platform definition with position, size
    @param properties: Resolved style properties
    @return: Part, geometry data
--]]
function GeometryFactory.createPlatform(definition, properties)
    local position = definition._resolvedPosition

    if not position then
        warn("[GeometryFactory] Platform missing resolved position")
        return nil, nil
    end

    local size = definition.size
    if type(size) == "table" then
        size = Vector3.new(size[1] or 4, size[2] or 1, size[3] or 4)
    else
        size = Vector3.new(4, 1, 4) -- Default size
    end

    -- Create the part
    local part = Instance.new("Part")
    part.Name = definition.id or "Platform"
    part.Shape = Enum.PartType.Block
    part.Size = size
    part.Position = position

    -- Apply properties
    part.Anchored = true
    applyProperties(part, properties)

    -- Store ID and class as attributes
    if definition.id then
        part:SetAttribute("MapLayoutId", definition.id)
    end
    if definition.class then
        part:SetAttribute("MapLayoutClass", definition.class)
    end

    -- Build geometry data
    local geometry = {
        type = "platform",
        position = position,
        size = size,
        center = position,
    }

    return part, geometry
end

--[[
    Create a cylinder Part from a definition.

    @param definition: Cylinder definition with position, height, radius
    @param properties: Resolved style properties
    @return: Part, geometry data
--]]
function GeometryFactory.createCylinder(definition, properties)
    local position = definition._resolvedPosition

    if not position then
        warn("[GeometryFactory] Cylinder missing resolved position")
        return nil, nil
    end

    local height = properties.height or definition.height or 4
    local radius = properties.radius or definition.radius or 2

    -- Create the part
    local part = Instance.new("Part")
    part.Name = definition.id or "Cylinder"
    part.Shape = Enum.PartType.Cylinder

    -- Cylinder: Size.X is height (along axis), Size.Y and Size.Z are diameter
    part.Size = Vector3.new(height, radius * 2, radius * 2)
    part.Position = position

    -- Rotate so cylinder stands upright (axis along Y)
    part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

    -- Apply properties
    part.Anchored = true
    applyProperties(part, properties)

    -- Store attributes
    if definition.id then
        part:SetAttribute("MapLayoutId", definition.id)
    end
    if definition.class then
        part:SetAttribute("MapLayoutClass", definition.class)
    end

    -- Build geometry data
    local geometry = {
        type = "cylinder",
        position = position,
        height = height,
        radius = radius,
        center = position,
    }

    return part, geometry
end

--[[
    Create a sphere Part from a definition.

    @param definition: Sphere definition with position, radius
    @param properties: Resolved style properties
    @return: Part, geometry data
--]]
function GeometryFactory.createSphere(definition, properties)
    local position = definition._resolvedPosition

    if not position then
        warn("[GeometryFactory] Sphere missing resolved position")
        return nil, nil
    end

    local radius = properties.radius or definition.radius or 2

    -- Create the part
    local part = Instance.new("Part")
    part.Name = definition.id or "Sphere"
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
    part.Position = position

    -- Apply properties
    part.Anchored = true
    applyProperties(part, properties)

    -- Store attributes
    if definition.id then
        part:SetAttribute("MapLayoutId", definition.id)
    end
    if definition.class then
        part:SetAttribute("MapLayoutClass", definition.class)
    end

    -- Build geometry data
    local geometry = {
        type = "sphere",
        position = position,
        radius = radius,
        center = position,
    }

    return part, geometry
end

--[[
    Create a wedge Part from a definition.

    @param definition: Wedge definition with position, size
    @param properties: Resolved style properties
    @return: Part, geometry data
--]]
function GeometryFactory.createWedge(definition, properties)
    local position = definition._resolvedPosition

    if not position then
        warn("[GeometryFactory] Wedge missing resolved position")
        return nil, nil
    end

    local size = definition.size
    if type(size) == "table" then
        size = Vector3.new(size[1] or 4, size[2] or 4, size[3] or 4)
    else
        size = Vector3.new(4, 4, 4)
    end

    -- Create the part
    local part = Instance.new("WedgePart")
    part.Name = definition.id or "Wedge"
    part.Size = size
    part.Position = position

    -- Apply rotation if specified
    if definition.rotation then
        local rot = definition.rotation
        part.CFrame = CFrame.new(position) * CFrame.Angles(
            math.rad(rot[1] or 0),
            math.rad(rot[2] or 0),
            math.rad(rot[3] or 0)
        )
    end

    -- Apply properties
    part.Anchored = true
    applyProperties(part, properties)

    -- Store attributes
    if definition.id then
        part:SetAttribute("MapLayoutId", definition.id)
    end
    if definition.class then
        part:SetAttribute("MapLayoutClass", definition.class)
    end

    -- Build geometry data
    local geometry = {
        type = "wedge",
        position = position,
        size = size,
        center = position,
    }

    return part, geometry
end

--[[
    Create a floor Part (horizontal platform).

    @param definition: Floor definition with corners or position/size
    @param properties: Resolved style properties
    @return: Part, geometry data
--]]
function GeometryFactory.createFloor(definition, properties)
    local position = definition._resolvedPosition
    local thickness = properties.thickness or definition.thickness or 1

    local size
    if definition.size then
        if type(definition.size) == "table" then
            size = Vector3.new(definition.size[1], thickness, definition.size[2] or definition.size[3])
        else
            size = Vector3.new(definition.size, thickness, definition.size)
        end
    else
        size = Vector3.new(10, thickness, 10)
    end

    if not position then
        -- Default to origin at floor level
        position = Vector3.new(0, -thickness / 2, 0)
    end

    -- Create the part
    local part = Instance.new("Part")
    part.Name = definition.id or "Floor"
    part.Shape = Enum.PartType.Block
    part.Size = size
    part.Position = position

    -- Apply properties
    part.Anchored = true
    applyProperties(part, properties)

    -- Store attributes
    if definition.id then
        part:SetAttribute("MapLayoutId", definition.id)
    end
    if definition.class then
        part:SetAttribute("MapLayoutClass", definition.class)
    end

    -- Build geometry data
    local geometry = {
        type = "floor",
        position = position,
        size = size,
        center = position,
    }

    return part, geometry
end

--[[
    Create geometry from a generic definition.
    Dispatches to the appropriate creator based on type.

    @param definition: Element definition
    @param properties: Resolved style properties
    @return: Part/Model, geometry data
--]]
function GeometryFactory.create(definition, properties)
    local elementType = definition.type or "platform"

    if elementType == "wall" then
        return GeometryFactory.createWall(definition, properties)
    elseif elementType == "platform" or elementType == "box" then
        return GeometryFactory.createPlatform(definition, properties)
    elseif elementType == "cylinder" then
        return GeometryFactory.createCylinder(definition, properties)
    elseif elementType == "sphere" then
        return GeometryFactory.createSphere(definition, properties)
    elseif elementType == "wedge" then
        return GeometryFactory.createWedge(definition, properties)
    elseif elementType == "floor" then
        return GeometryFactory.createFloor(definition, properties)
    else
        warn("[GeometryFactory] Unknown element type:", elementType)
        return nil, nil
    end
end

return GeometryFactory
