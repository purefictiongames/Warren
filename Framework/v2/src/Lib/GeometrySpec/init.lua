--[[
    LibPureFiction Framework v2
    GeometrySpec/init.lua - Declarative Geometry Definition System

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    GeometrySpec is a declarative system for defining geometry using Lua tables.
    It provides a unified way to specify parts with positions, sizes, and
    class-based styling.

    Use cases:
    - Zone nodes: Map areas with mount points and player detection
    - Node geometry: Turrets, launchers, any node with generated parts
    - Mount point definitions: Named positions for spawning child nodes

    Think of it as a style sheet for 3D parts - define geometry as data,
    apply classes for shared attributes.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local GeometrySpec = require(game.ReplicatedStorage.Lib.GeometrySpec)

    local turretSpec = {
        bounds = {4, 6, 4},
        parts = {
            { id = "base", class = "frame", size = {4, 2, 4}, position = {0, 0, 0} },
            { id = "head", class = "frame", size = {3, 1.5, 3}, position = {0, 2, 0} },
            { id = "barrel", class = "accent", size = {0.5, 0.5, 3}, position = {0, 2.5, 1.5} },
        },
        classes = {
            frame = { Material = "DiamondPlate", Color = {80, 80, 85} },
            accent = { Material = "Metal", Color = {40, 40, 40} },
        },
    }

    local model = GeometrySpec.build(turretSpec)
    ```

    ============================================================================
    SPEC STRUCTURE
    ============================================================================

    {
        bounds = {width, height, depth},  -- Bounding volume (optional)
        origin = "corner",                -- "corner", "center", "floor-center"
        scale = "4:1",                    -- Scale factor (optional)

        defaults = { ... },               -- Default properties for all parts
        classes = { ... },                -- Class-based styling

        parts = {
            { id, position, size, class, shape, ... },
        },

        mounts = {
            { id, position, facing, class, ... },
        },
    }

--]]

local GeometrySpec = {
    _VERSION = "1.0.0",
}

-- Submodules
GeometrySpec.ClassResolver = require(script.ClassResolver)
GeometrySpec.Scanner = require(script.Scanner)

--------------------------------------------------------------------------------
-- REGISTRY (built-in)
--------------------------------------------------------------------------------

local registry = {}
local currentBuildId = 0

--[[
    Clear the registry before a new build.
--]]
function GeometrySpec.clear()
    registry = {}
    currentBuildId = currentBuildId + 1
end

--[[
    Register a part in the registry.
--]]
local function registerPart(id, instance, definition, geometry)
    if not id then return end

    registry[id] = {
        instance = instance,
        definition = definition,
        geometry = geometry,
        buildId = currentBuildId,
    }
end

--[[
    Get a registered element by ID.

    @param selector: ID string (with or without # prefix)
    @return: Registry entry or nil
--]]
function GeometrySpec.get(selector)
    local id = selector
    if type(selector) == "string" and selector:sub(1, 1) == "#" then
        id = selector:sub(2)
    end
    return registry[id]
end

--[[
    Get the Part/Model instance for an element.

    @param selector: ID string
    @return: Roblox instance or nil
--]]
function GeometrySpec.getInstance(selector)
    local entry = GeometrySpec.get(selector)
    return entry and entry.instance or nil
end

--------------------------------------------------------------------------------
-- SCALE CONVERSION
--------------------------------------------------------------------------------

local currentScale = 1

--[[
    Parse a scale value.
    "4:1" → 4, "1:2" → 0.5, 4 → 4

    @param scaleValue: Scale definition
    @return: Numeric scale factor
--]]
function GeometrySpec.parseScale(scaleValue)
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

--[[
    Get the current build scale factor.
--]]
function GeometrySpec.getScale()
    return currentScale
end

--[[
    Convert definition units to studs.
--]]
function GeometrySpec.toStuds(value)
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
-- PART CREATION
--------------------------------------------------------------------------------

--[[
    Apply resolved properties to a Part.
--]]
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

--[[
    Create a block Part.
--]]
local function createBlock(definition, properties, originOffset)
    local position = definition.position or {0, 0, 0}
    local size = definition.size or {4, 4, 4}

    -- Apply scale
    position = GeometrySpec.toStuds(position)
    size = GeometrySpec.toStuds(size)

    -- Convert to Vector3
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
        part:SetAttribute("GeometrySpecId", definition.id)
    end
    if definition.class then
        part:SetAttribute("GeometrySpecClass", definition.class)
    end

    return part, {
        type = "block",
        position = pos,
        size = sz,
        center = pos,
    }
end

--[[
    Create a cylinder Part.
--]]
local function createCylinder(definition, properties, originOffset)
    local position = definition.position or {0, 0, 0}
    local height = definition.height or 4
    local radius = definition.radius or 2

    -- Apply scale
    position = GeometrySpec.toStuds(position)
    height = GeometrySpec.toStuds(height)
    radius = GeometrySpec.toStuds(radius)

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
        part:SetAttribute("GeometrySpecId", definition.id)
    end
    if definition.class then
        part:SetAttribute("GeometrySpecClass", definition.class)
    end

    return part, {
        type = "cylinder",
        position = pos,
        height = height,
        radius = radius,
        center = pos,
    }
end

--[[
    Create a sphere Part.
--]]
local function createSphere(definition, properties, originOffset)
    local position = definition.position or {0, 0, 0}
    local radius = definition.radius or 2

    -- Apply scale
    position = GeometrySpec.toStuds(position)
    radius = GeometrySpec.toStuds(radius)

    local pos = Vector3.new(position[1], position[2], position[3]) + originOffset

    local part = Instance.new("Part")
    part.Name = definition.id or "Sphere"
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
    part.Position = pos
    part.Anchored = true

    applyProperties(part, properties)

    if definition.id then
        part:SetAttribute("GeometrySpecId", definition.id)
    end
    if definition.class then
        part:SetAttribute("GeometrySpecClass", definition.class)
    end

    return part, {
        type = "sphere",
        position = pos,
        radius = radius,
        center = pos,
    }
end

--[[
    Create a wedge Part.
--]]
local function createWedge(definition, properties, originOffset)
    local position = definition.position or {0, 0, 0}
    local size = definition.size or {4, 4, 4}

    -- Apply scale
    position = GeometrySpec.toStuds(position)
    size = GeometrySpec.toStuds(size)

    local pos = Vector3.new(position[1], position[2], position[3]) + originOffset
    local sz = Vector3.new(size[1], size[2], size[3])

    local part = Instance.new("WedgePart")
    part.Name = definition.id or "Wedge"
    part.Size = sz
    part.Position = pos
    part.Anchored = true

    -- Apply rotation if specified
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
        part:SetAttribute("GeometrySpecId", definition.id)
    end
    if definition.class then
        part:SetAttribute("GeometrySpecClass", definition.class)
    end

    return part, {
        type = "wedge",
        position = pos,
        size = sz,
        center = pos,
    }
end

--[[
    Create a part from definition.
--]]
local function createPart(definition, spec, originOffset)
    local properties = GeometrySpec.ClassResolver.resolve(definition, spec)
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
        warn("[GeometrySpec] Unknown shape:", shape)
        return createBlock(definition, properties, originOffset)
    end
end

--------------------------------------------------------------------------------
-- ORIGIN OFFSET
--------------------------------------------------------------------------------

--[[
    Calculate origin offset based on bounds and origin setting.

    @param origin: "corner", "center", or "floor-center"
    @param bounds: {width, height, depth}
    @return: Vector3 offset
--]]
local function getOriginOffset(origin, bounds)
    if not bounds then
        return Vector3.new(0, 0, 0)
    end

    local w, h, d = bounds[1] or 0, bounds[2] or 0, bounds[3] or 0

    if origin == "center" then
        return Vector3.new(0, 0, 0)
    elseif origin == "floor-center" then
        return Vector3.new(0, h / 2, 0)
    else -- "corner" (default)
        return Vector3.new(w / 2, h / 2, d / 2)
    end
end

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------

--[[
    Build geometry from a spec.

    @param spec: The geometry specification table
    @param parent: Optional parent instance (default: workspace)
    @return: Model containing all generated geometry
--]]
function GeometrySpec.build(spec, parent)
    parent = parent or workspace

    -- Set scale
    currentScale = GeometrySpec.parseScale(spec.scale)

    -- Calculate origin offset
    local origin = spec.origin or "corner"
    local bounds = spec.bounds
    if bounds then
        bounds = GeometrySpec.toStuds(bounds)
    end
    local originOffset = getOriginOffset(origin, bounds)

    -- Create container model
    local model = Instance.new("Model")
    model.Name = spec.name or "GeometrySpec"

    -- Build parts
    if spec.parts then
        for _, partDef in ipairs(spec.parts) do
            local part, geometry = createPart(partDef, spec, originOffset)
            if part then
                part.Parent = model
                registerPart(partDef.id, part, partDef, geometry)
            end
        end
    end

    -- Store mount points (no geometry created)
    if spec.mounts then
        for _, mountDef in ipairs(spec.mounts) do
            local position = mountDef.position or {0, 0, 0}
            position = GeometrySpec.toStuds(position)
            local pos = Vector3.new(position[1], position[2], position[3]) + originOffset

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

    model.Parent = parent
    return model
end

--------------------------------------------------------------------------------
-- SCANNER API (delegate to Scanner module)
--------------------------------------------------------------------------------

--[[
    Scan geometry and generate GeometrySpec config code.

    @param container: Model, Folder, etc. containing geometry
    @param options: Optional configuration
    @return: Lua code string
--]]
function GeometrySpec.scan(container, options)
    options = options or {}

    local code = GeometrySpec.Scanner.scanToCode(container, options)

    print("\n" .. string.rep("=", 70))
    print("-- GeometrySpec Scanner Output for: " .. container.Name)
    print("-- Copy the code below into your spec definition file")
    print(string.rep("=", 70))
    print(code)
    print(string.rep("=", 70) .. "\n")

    return code
end

--[[
    Scan geometry and get config table.

    @param container: Model, Folder, etc.
    @param options: Optional configuration
    @return: Config table
--]]
function GeometrySpec.scanToTable(container, options)
    return GeometrySpec.Scanner.scan(container, options)
end

--[[
    Scan a named area.

    @param areaName: Name of the area part
    @param container: Where to search (default: workspace)
    @param options: Optional configuration
    @return: Lua code string
--]]
function GeometrySpec.scanArea(areaName, container, options)
    container = container or workspace
    options = options or {}

    local config = GeometrySpec.Scanner.scanArea(areaName, container, options)
    if not config then
        return nil
    end

    local code = GeometrySpec.Scanner.generateCode(config, options)

    print("\n" .. string.rep("=", 70))
    print("-- GeometrySpec Scanner Output for area: " .. areaName)
    print("-- Copy the code below into your spec definition file")
    print(string.rep("=", 70))
    print(code)
    print(string.rep("=", 70) .. "\n")

    return code
end

--[[
    Mirror an area: scan and build a clean copy.

    @param areaName: Name of the area part
    @param container: Where to search (default: workspace)
    @param options: Optional configuration
    @return: { model, config, cleanup(), refresh() }
--]]
function GeometrySpec.mirror(areaName, container, options)
    return GeometrySpec.Scanner.mirrorArea(areaName, container, options)
end

--[[
    List all areas found in a container.

    @param container: Where to search (default: workspace)
--]]
function GeometrySpec.listAreas(container)
    local areas = GeometrySpec.Scanner.findAreas(container or workspace)

    print("\n=== GeometrySpec Areas ===")
    if #areas == 0 then
        print("  No areas found.")
        print("  Tag a part with GeometrySpecTag = 'area'")
    else
        for _, area in ipairs(areas) do
            local size = area.part.Size
            print(string.format("  %s: bounds {%.1f, %.1f, %.1f} at %s",
                area.name,
                size.X, size.Y, size.Z,
                tostring(area.part.Position)
            ))
        end
    end
    print("==========================\n")

    return areas
end

return GeometrySpec
