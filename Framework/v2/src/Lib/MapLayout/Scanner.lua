--[[
    LibPureFiction Framework v2
    MapLayout/Scanner.lua - Scan Geometry and Generate MapLayout Config

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Scanner provides a reverse workflow: take existing Roblox geometry and
    generate MapLayout Lua configuration code from it.

    Workflow:
    1. Build rough geometry in Roblox Studio (drag and drop)
    2. Run Scanner on the Model/Folder
    3. Get generated MapLayout config code
    4. Clean up in text editor
    5. Delete original parts, rebuild from config

    This enables rapid visual prototyping with Studio's tools, then
    "freezing" the layout into version-controlled declarative config.

    ============================================================================
    USAGE
    ============================================================================

    AREA SCANNING (Recommended):
    1. Create a Part, name it (e.g., "testArea")
    2. Add attribute: MapLayoutTag = "area"
    3. Nest geometry parts as CHILDREN under it in Explorer
    4. Run:

    ```lua
    require(game.ReplicatedStorage.Lib.MapLayout).scanArea("testArea")
    ```

    Explorer structure:
        workspace
            testArea (Part with MapLayoutTag = "area")
                ├── northWall (Part)
                ├── southWall (Part)
                └── floor (Part)

    GENERAL SCANNING:
    ```lua
    local Scanner = require(game.ReplicatedStorage.Lib.MapLayout.Scanner)

    -- Scan a model/folder
    local config = Scanner.scan(workspace.MyLayout)

    -- Get as Lua code string
    local code = Scanner.generateCode(config)
    print(code)

    -- Or do both at once
    local code = Scanner.scanToCode(workspace.MyLayout)
    ```

    ============================================================================
    ATTRIBUTES
    ============================================================================

    Tag parts with these attributes to guide the scanner:

    MapLayoutId / MapLayoutName: string
        - Becomes the element's 'id' in config
        - (Both attribute names are supported)

    MapLayoutClass / MapLayoutTag: string
        - Becomes the element's 'class' in config
        - (Both attribute names are supported)

    MapLayoutType: string
        - Override inferred type ("wall", "floor", "platform", etc.)

    MapLayoutArea: string
        - Group parts into a named area

    MapLayoutIgnore: boolean
        - Skip this part entirely

    ============================================================================
    AUTO-CLEANUP / SNAPPING
    ============================================================================

    The scanner automatically cleans up small geometry gaps:

    - Wall endpoints within 0.5 studs of area boundaries snap to the boundary
    - Wall endpoints within 0.5 studs of other wall endpoints snap together
    - Floor/platform edges within 0.5 studs of boundaries expand to fill the gap
    - Wall heights within 0.5 studs of area height snap to match

    This prevents disjointed geometry from minor placement inaccuracies in Studio.

    ============================================================================
    MIRROR PREVIEW
    ============================================================================

    For iterative development, use mirrorArea to build a live preview:

    ```lua
    local MapLayout = require(game.ReplicatedStorage.Lib.MapLayout)

    -- Create mirror next to original
    local mirror = MapLayout.mirrorArea("testArea")

    -- Adjust original parts in Studio...
    -- Then refresh the mirror:
    mirror = mirror.refresh()

    -- When satisfied, cleanup and export:
    mirror.cleanup()
    MapLayout.scanArea("testArea")
    ```

    Options:
        offset: Direction to place mirror ("x", "-x", "z", "-z")
        gap: Studs between original and mirror (default: 2)
        styles: Style definitions for the mirror geometry

--]]

local Scanner = {}

--------------------------------------------------------------------------------
-- TYPE INFERENCE
--------------------------------------------------------------------------------

-- Thresholds for type detection
local WALL_ASPECT_RATIO = 3      -- Height/thickness ratio to be considered a wall
local FLOOR_ASPECT_RATIO = 4     -- Width/height ratio to be considered a floor
local FLOOR_MAX_HEIGHT = 2       -- Max height (studs) to be considered a floor

-- Snapping threshold for auto-cleanup
local SNAP_THRESHOLD = 0.5       -- Snap geometry within this distance (studs)

--------------------------------------------------------------------------------
-- SNAPPING / AUTO-CLEANUP
--------------------------------------------------------------------------------

--[[
    Snap a value to a target if within threshold.

    @param value: The value to potentially snap
    @param target: The target value to snap to
    @param threshold: Distance threshold (default SNAP_THRESHOLD)
    @return: Snapped value (target if close enough, otherwise original)
--]]
local function snapValue(value, target, threshold)
    threshold = threshold or SNAP_THRESHOLD
    if math.abs(value - target) <= threshold then
        return target
    end
    return value
end

--[[
    Snap a value to the nearest target in a list.

    @param value: The value to potentially snap
    @param targets: Array of target values
    @param threshold: Distance threshold
    @return: Snapped value and whether it was snapped
--]]
local function snapToNearest(value, targets, threshold)
    threshold = threshold or SNAP_THRESHOLD
    local closestDist = threshold + 1
    local closestTarget = nil

    for _, target in ipairs(targets) do
        local dist = math.abs(value - target)
        if dist <= threshold and dist < closestDist then
            closestDist = dist
            closestTarget = target
        end
    end

    if closestTarget then
        return closestTarget, true
    end
    return value, false
end

--[[
    Snap a 2D point {x, z} to area boundaries and other reference points.

    @param point: {x, z} point to snap
    @param bounds: {width, height, depth} of the area
    @param referencePoints: Array of {x, z} points to snap to
    @param threshold: Distance threshold
    @return: Snapped {x, z} point
--]]
local function snapPoint2D(point, bounds, referencePoints, threshold)
    threshold = threshold or SNAP_THRESHOLD
    local x, z = point[1], point[2]

    -- Build list of X and Z snap targets from area boundaries
    local xTargets = {0, bounds[1]}  -- Left and right edges
    local zTargets = {0, bounds[3]}  -- Front and back edges

    -- Add reference points to targets
    for _, ref in ipairs(referencePoints or {}) do
        table.insert(xTargets, ref[1])
        table.insert(zTargets, ref[2])
    end

    -- Snap X and Z independently
    x = snapToNearest(x, xTargets, threshold)
    z = snapToNearest(z, zTargets, threshold)

    return {x, z}
end

--[[
    Snap a 3D point {x, y, z} to area boundaries and other reference points.

    @param point: {x, y, z} point to snap
    @param bounds: {width, height, depth} of the area
    @param referencePoints: Array of {x, y, z} points to snap to
    @param threshold: Distance threshold
    @return: Snapped {x, y, z} point
--]]
local function snapPoint3D(point, bounds, referencePoints, threshold)
    threshold = threshold or SNAP_THRESHOLD
    local x, y, z = point[1], point[2], point[3]

    -- Build snap targets from area boundaries
    local xTargets = {0, bounds[1]}
    local yTargets = {0, bounds[2]}
    local zTargets = {0, bounds[3]}

    -- Add reference points
    for _, ref in ipairs(referencePoints or {}) do
        table.insert(xTargets, ref[1])
        table.insert(yTargets, ref[2])
        table.insert(zTargets, ref[3])
    end

    -- Snap each axis independently
    x = snapToNearest(x, xTargets, threshold)
    y = snapToNearest(y, yTargets, threshold)
    z = snapToNearest(z, zTargets, threshold)

    return {x, y, z}
end

--[[
    Snap element edges (position +/- half size) to boundaries and adjust size.

    For platforms/floors, we want to snap edges to boundaries and expand
    the element slightly to fill gaps.

    @param position: {x, y, z} center position
    @param size: {x, y, z} dimensions
    @param bounds: Area bounds
    @param threshold: Snap threshold
    @return: Adjusted position, adjusted size
--]]
local function snapEdges(position, size, bounds, threshold)
    threshold = threshold or SNAP_THRESHOLD

    local px, py, pz = position[1], position[2], position[3]
    local sx, sy, sz = size[1], size[2], size[3]

    -- Calculate current edges
    local minX, maxX = px - sx/2, px + sx/2
    local minY, maxY = py - sy/2, py + sy/2
    local minZ, maxZ = pz - sz/2, pz + sz/2

    -- Snap edges to boundaries
    local newMinX = snapToNearest(minX, {0, bounds[1]}, threshold)
    local newMaxX = snapToNearest(maxX, {0, bounds[1]}, threshold)
    local newMinY = snapToNearest(minY, {0, bounds[2]}, threshold)
    local newMaxY = snapToNearest(maxY, {0, bounds[2]}, threshold)
    local newMinZ = snapToNearest(minZ, {0, bounds[3]}, threshold)
    local newMaxZ = snapToNearest(maxZ, {0, bounds[3]}, threshold)

    -- Recalculate position and size from snapped edges
    local newSx = newMaxX - newMinX
    local newSy = newMaxY - newMinY
    local newSz = newMaxZ - newMinZ

    local newPx = (newMinX + newMaxX) / 2
    local newPy = (newMinY + newMaxY) / 2
    local newPz = (newMinZ + newMaxZ) / 2

    return {newPx, newPy, newPz}, {newSx, newSy, newSz}
end

--[[
    Infer the element type from a Part's shape and dimensions.

    @param part: BasePart to analyze
    @return: "wall", "floor", "platform", "cylinder", "sphere", "wedge"
--]]
local function inferType(part)
    -- Check for explicit override
    local override = part:GetAttribute("MapLayoutType")
    if override then
        return override:lower()
    end

    -- Check part class/shape
    if part:IsA("WedgePart") then
        return "wedge"
    end

    if part:IsA("Part") then
        if part.Shape == Enum.PartType.Ball then
            return "sphere"
        elseif part.Shape == Enum.PartType.Cylinder then
            return "cylinder"
        end
    end

    -- For blocks, infer from dimensions
    local size = part.Size
    local x, y, z = size.X, size.Y, size.Z

    -- Floor: flat and wide (Y is small relative to X and Z)
    if y <= FLOOR_MAX_HEIGHT and (x / y >= FLOOR_ASPECT_RATIO or z / y >= FLOOR_ASPECT_RATIO) then
        return "floor"
    end

    -- Wall: tall and thin in one horizontal dimension
    -- Check if Y is the dominant dimension and one of X/Z is thin
    local minHorizontal = math.min(x, z)
    local maxHorizontal = math.max(x, z)

    if y / minHorizontal >= WALL_ASPECT_RATIO and maxHorizontal > minHorizontal * 2 then
        return "wall"
    end

    -- Default to platform
    return "platform"
end

--[[
    Determine wall orientation and extract from/to points.

    Walls extend along their longest horizontal dimension.
    Returns from/to as 2D {x, z} coordinates.

    @param part: Part identified as a wall
    @return: from {x, z}, to {x, z}, height, thickness
--]]
local function extractWallGeometry(part)
    local pos = part.Position
    local size = part.Size
    local cframe = part.CFrame

    -- Get the wall's local axes in world space
    local rightVector = cframe.RightVector  -- Local X
    local lookVector = cframe.LookVector    -- Local Z

    -- Determine which local axis is the "length" (longest horizontal)
    -- and which is the "thickness" (shortest horizontal)
    local localX, localZ = size.X, size.Z
    local height = size.Y

    local lengthAxis, thicknessAxis, length, thickness

    if localX >= localZ then
        -- Length is along local X
        lengthAxis = rightVector
        length = localX
        thickness = localZ
    else
        -- Length is along local Z
        lengthAxis = lookVector
        length = localZ
        thickness = localX
    end

    -- Calculate from/to points (endpoints of the wall centerline)
    local halfLength = length / 2
    local fromPoint = pos - lengthAxis * halfLength
    local toPoint = pos + lengthAxis * halfLength

    return {
        from = { math.floor(fromPoint.X * 100) / 100, math.floor(fromPoint.Z * 100) / 100 },
        to = { math.floor(toPoint.X * 100) / 100, math.floor(toPoint.Z * 100) / 100 },
        height = math.floor(height * 100) / 100,
        thickness = math.floor(thickness * 100) / 100,
    }
end

--[[
    Extract platform/box geometry.

    @param part: Part identified as platform
    @return: position {x, y, z}, size {x, y, z}
--]]
local function extractPlatformGeometry(part)
    local pos = part.Position
    local size = part.Size

    return {
        position = {
            math.floor(pos.X * 100) / 100,
            math.floor(pos.Y * 100) / 100,
            math.floor(pos.Z * 100) / 100,
        },
        size = {
            math.floor(size.X * 100) / 100,
            math.floor(size.Y * 100) / 100,
            math.floor(size.Z * 100) / 100,
        },
    }
end

--[[
    Extract floor geometry.

    @param part: Part identified as floor
    @return: position {x, y, z}, size {x, y, z}
--]]
local function extractFloorGeometry(part)
    local pos = part.Position
    local size = part.Size

    return {
        position = {
            math.floor(pos.X * 100) / 100,
            math.floor(pos.Y * 100) / 100,
            math.floor(pos.Z * 100) / 100,
        },
        size = {
            math.floor(size.X * 100) / 100,
            math.floor(size.Y * 100) / 100,
            math.floor(size.Z * 100) / 100,
        },
    }
end

--[[
    Extract cylinder geometry.

    @param part: Part identified as cylinder
    @return: position, height, radius
--]]
local function extractCylinderGeometry(part)
    local pos = part.Position
    local size = part.Size

    -- Cylinder: Size.X is height along axis, Size.Y/Z are diameter
    -- But orientation matters - we need to figure out which way it's pointing

    return {
        position = {
            math.floor(pos.X * 100) / 100,
            math.floor(pos.Y * 100) / 100,
            math.floor(pos.Z * 100) / 100,
        },
        height = math.floor(size.X * 100) / 100,
        radius = math.floor((size.Y / 2) * 100) / 100,
    }
end

--[[
    Extract sphere geometry.

    @param part: Part identified as sphere
    @return: position, radius
--]]
local function extractSphereGeometry(part)
    local pos = part.Position
    local size = part.Size

    return {
        position = {
            math.floor(pos.X * 100) / 100,
            math.floor(pos.Y * 100) / 100,
            math.floor(pos.Z * 100) / 100,
        },
        radius = math.floor((size.X / 2) * 100) / 100,
    }
end

--[[
    Extract common properties from a part.

    @param part: BasePart
    @return: Table of properties
--]]
local function extractProperties(part)
    local props = {}

    -- ID from attributes (support multiple attribute names)
    local id = part:GetAttribute("MapLayoutId")
        or part:GetAttribute("MapLayoutName")
        or nil

    -- Fall back to part name if it's not generic
    if not id or id == "" then
        if part.Name ~= "Part" and part.Name ~= "" then
            id = part.Name
        end
    end

    if id and id ~= "" then
        props.id = id
    end

    -- Class from attributes (support multiple attribute names)
    local class = part:GetAttribute("MapLayoutClass")
        or part:GetAttribute("MapLayoutTag")

    if class and class ~= "" then
        props.class = class
    end

    -- Material (only if not default)
    if part.Material ~= Enum.Material.Plastic then
        props.Material = part.Material.Name
    end

    -- Color (only if not default gray)
    local color = part.Color
    local defaultGray = Color3.fromRGB(163, 162, 165)
    if (math.abs(color.R - defaultGray.R) > 0.01 or
        math.abs(color.G - defaultGray.G) > 0.01 or
        math.abs(color.B - defaultGray.B) > 0.01) then
        props.Color = {
            math.floor(color.R * 255),
            math.floor(color.G * 255),
            math.floor(color.B * 255),
        }
    end

    -- Transparency (only if not 0)
    if part.Transparency > 0 then
        props.Transparency = math.floor(part.Transparency * 100) / 100
    end

    -- Anchored (only if false, since true is default for MapLayout)
    if not part.Anchored then
        props.Anchored = false
    end

    -- CanCollide (only if false)
    if not part.CanCollide then
        props.CanCollide = false
    end

    return props
end

--------------------------------------------------------------------------------
-- SCANNING
--------------------------------------------------------------------------------

--[[
    Scan a container and extract all geometry.

    @param container: Model, Folder, or similar container
    @param options: Optional configuration
        - inferTypes: boolean (default true) - Auto-detect element types
        - includeChildren: boolean (default true) - Recurse into child models
    @return: Scanned config table
--]]
function Scanner.scan(container, options)
    options = options or {}
    local inferTypes = options.inferTypes ~= false
    local includeChildren = options.includeChildren ~= false

    local config = {
        name = container.Name,
        walls = {},
        floors = {},
        platforms = {},
        cylinders = {},
        spheres = {},
        wedges = {},
        areas = {},
    }

    -- Track areas for grouping
    local areaGroups = {}  -- { [areaName] = { parts... } }

    -- Collect all parts
    local parts = {}
    if includeChildren then
        for _, descendant in ipairs(container:GetDescendants()) do
            if descendant:IsA("BasePart") then
                table.insert(parts, descendant)
            end
        end
    else
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("BasePart") then
                table.insert(parts, child)
            end
        end
    end

    -- Process each part
    for _, part in ipairs(parts) do
        -- Skip if marked to ignore
        if part:GetAttribute("MapLayoutIgnore") then
            continue
        end

        -- Check if part belongs to an area
        local areaName = part:GetAttribute("MapLayoutArea")
        if areaName and areaName ~= "" then
            if not areaGroups[areaName] then
                areaGroups[areaName] = {}
            end
            table.insert(areaGroups[areaName], part)
            continue  -- Will process with area
        end

        -- Infer or get type
        local elementType = inferTypes and inferType(part) or "platform"

        -- Extract geometry based on type
        local element = extractProperties(part)

        if elementType == "wall" then
            local geo = extractWallGeometry(part)
            element.from = geo.from
            element.to = geo.to
            element.height = geo.height
            element.thickness = geo.thickness
            table.insert(config.walls, element)

        elseif elementType == "floor" then
            local geo = extractFloorGeometry(part)
            element.position = geo.position
            element.size = geo.size
            table.insert(config.floors, element)

        elseif elementType == "platform" then
            local geo = extractPlatformGeometry(part)
            element.position = geo.position
            element.size = geo.size
            table.insert(config.platforms, element)

        elseif elementType == "cylinder" then
            local geo = extractCylinderGeometry(part)
            element.position = geo.position
            element.height = geo.height
            element.radius = geo.radius
            table.insert(config.cylinders, element)

        elseif elementType == "sphere" then
            local geo = extractSphereGeometry(part)
            element.position = geo.position
            element.radius = geo.radius
            table.insert(config.spheres, element)

        elseif elementType == "wedge" then
            local geo = extractPlatformGeometry(part)
            element.position = geo.position
            element.size = geo.size
            table.insert(config.wedges, element)
        end
    end

    -- Process area groups
    for areaName, areaParts in pairs(areaGroups) do
        -- Calculate bounds from parts
        local minX, minY, minZ = math.huge, math.huge, math.huge
        local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

        for _, part in ipairs(areaParts) do
            local pos = part.Position
            local size = part.Size
            local halfSize = size / 2

            minX = math.min(minX, pos.X - halfSize.X)
            minY = math.min(minY, pos.Y - halfSize.Y)
            minZ = math.min(minZ, pos.Z - halfSize.Z)
            maxX = math.max(maxX, pos.X + halfSize.X)
            maxY = math.max(maxY, pos.Y + halfSize.Y)
            maxZ = math.max(maxZ, pos.Z + halfSize.Z)
        end

        local areaConfig = {
            id = areaName,
            bounds = {
                math.floor((maxX - minX) * 100) / 100,
                math.floor((maxY - minY) * 100) / 100,
                math.floor((maxZ - minZ) * 100) / 100,
            },
            position = {
                math.floor(minX * 100) / 100,
                math.floor(minY * 100) / 100,
                math.floor(minZ * 100) / 100,
            },
            origin = "corner",
            walls = {},
            floors = {},
            platforms = {},
        }

        -- Process parts within area (convert to local coordinates)
        local areaOrigin = Vector3.new(minX, minY, minZ)

        for _, part in ipairs(areaParts) do
            local elementType = inferTypes and inferType(part) or "platform"
            local element = extractProperties(part)

            -- Remove area-level ID from element if it matches
            if element.id == areaName then
                element.id = nil
            end

            if elementType == "wall" then
                local geo = extractWallGeometry(part)
                -- Convert to local coordinates
                element.from = {
                    geo.from[1] - areaOrigin.X,
                    geo.from[2] - areaOrigin.Z,
                }
                element.to = {
                    geo.to[1] - areaOrigin.X,
                    geo.to[2] - areaOrigin.Z,
                }
                element.height = geo.height
                element.thickness = geo.thickness
                table.insert(areaConfig.walls, element)

            elseif elementType == "floor" then
                local geo = extractFloorGeometry(part)
                element.position = {
                    geo.position[1] - areaOrigin.X,
                    geo.position[2] - areaOrigin.Y,
                    geo.position[3] - areaOrigin.Z,
                }
                element.size = geo.size
                table.insert(areaConfig.floors, element)

            else  -- platform, etc.
                local geo = extractPlatformGeometry(part)
                element.position = {
                    geo.position[1] - areaOrigin.X,
                    geo.position[2] - areaOrigin.Y,
                    geo.position[3] - areaOrigin.Z,
                }
                element.size = geo.size
                table.insert(areaConfig.platforms, element)
            end
        end

        -- Clean up empty categories
        if #areaConfig.walls == 0 then areaConfig.walls = nil end
        if #areaConfig.floors == 0 then areaConfig.floors = nil end
        if #areaConfig.platforms == 0 then areaConfig.platforms = nil end

        table.insert(config.areas, areaConfig)
    end

    -- Clean up empty categories in main config
    if #config.walls == 0 then config.walls = nil end
    if #config.floors == 0 then config.floors = nil end
    if #config.platforms == 0 then config.platforms = nil end
    if #config.cylinders == 0 then config.cylinders = nil end
    if #config.spheres == 0 then config.spheres = nil end
    if #config.wedges == 0 then config.wedges = nil end
    if #config.areas == 0 then config.areas = nil end

    return config
end

--------------------------------------------------------------------------------
-- CODE GENERATION
--------------------------------------------------------------------------------

--[[
    Serialize a value to Lua code.

    @param value: Value to serialize
    @param indent: Current indentation level
    @return: Lua code string
--]]
local function serializeValue(value, indent)
    indent = indent or 0
    local indentStr = string.rep("    ", indent)
    local nextIndent = string.rep("    ", indent + 1)

    if type(value) == "nil" then
        return "nil"
    elseif type(value) == "boolean" then
        return tostring(value)
    elseif type(value) == "number" then
        -- Clean up floating point
        if value == math.floor(value) then
            return tostring(math.floor(value))
        else
            return string.format("%.2f", value)
        end
    elseif type(value) == "string" then
        return string.format("%q", value)
    elseif type(value) == "table" then
        -- Check if it's an array (sequential integer keys)
        local isArray = true
        local maxIndex = 0
        for k, v in pairs(value) do
            if type(k) == "number" and k == math.floor(k) and k > 0 then
                maxIndex = math.max(maxIndex, k)
            else
                isArray = false
                break
            end
        end
        isArray = isArray and maxIndex == #value

        if isArray then
            -- Check if it's a simple array (numbers only, short)
            local isSimple = #value <= 4
            for _, v in ipairs(value) do
                if type(v) ~= "number" then
                    isSimple = false
                    break
                end
            end

            if isSimple then
                -- Inline array: {1, 2, 3}
                local parts = {}
                for _, v in ipairs(value) do
                    table.insert(parts, serializeValue(v, 0))
                end
                return "{" .. table.concat(parts, ", ") .. "}"
            else
                -- Multi-line array
                local lines = {"{"}
                for _, v in ipairs(value) do
                    table.insert(lines, nextIndent .. serializeValue(v, indent + 1) .. ",")
                end
                table.insert(lines, indentStr .. "}")
                return table.concat(lines, "\n")
            end
        else
            -- Object/dictionary
            local lines = {"{"}

            -- Sort keys for consistent output
            local keys = {}
            for k in pairs(value) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b)
                -- Put 'id' first, then 'class', then alphabetical
                if a == "id" then return true end
                if b == "id" then return false end
                if a == "class" then return true end
                if b == "class" then return false end
                return tostring(a) < tostring(b)
            end)

            for _, k in ipairs(keys) do
                local v = value[k]
                local keyStr
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    keyStr = k
                else
                    keyStr = "[" .. serializeValue(k, 0) .. "]"
                end
                table.insert(lines, nextIndent .. keyStr .. " = " .. serializeValue(v, indent + 1) .. ",")
            end

            table.insert(lines, indentStr .. "}")
            return table.concat(lines, "\n")
        end
    else
        return "nil -- unsupported type: " .. type(value)
    end
end

--[[
    Generate Lua code from a scanned config.

    @param config: Scanned config table
    @param options: Optional configuration
        - varName: Variable name (default "mapDefinition")
        - includeStyles: boolean - Generate style template (default false)
    @return: Lua code string
--]]
function Scanner.generateCode(config, options)
    options = options or {}
    local varName = options.varName or "mapDefinition"

    local lines = {
        "-- Generated by MapLayout Scanner",
        "-- Clean up IDs, classes, and structure as needed",
        "",
        "local " .. varName .. " = " .. serializeValue(config, 0),
        "",
        "return " .. varName,
    }

    if options.includeStyles then
        -- Insert styles template before the config
        local stylesTemplate = [[

-- Style template (customize as needed)
local styles = {
    defaults = {
        Anchored = true,
        CanCollide = true,
        Material = "SmoothPlastic",
    },
    classes = {
        -- Add your classes here
        -- ["exterior"] = { Material = "Concrete" },
        -- ["interior"] = { Material = "SmoothPlastic" },
    },
    ids = {
        -- Add ID-specific styles here
    },
}
]]
        table.insert(lines, 3, stylesTemplate)
    end

    return table.concat(lines, "\n")
end

--[[
    Scan and generate code in one call.

    @param container: Model, Folder, etc.
    @param options: Options for both scan and generateCode
    @return: Lua code string
--]]
function Scanner.scanToCode(container, options)
    local config = Scanner.scan(container, options)
    return Scanner.generateCode(config, options)
end

--[[
    Print scanned code to output (convenience for Studio command bar).

    @param container: Model, Folder, etc.
    @param options: Options
--]]
function Scanner.printCode(container, options)
    local code = Scanner.scanToCode(container, options)
    print("\n" .. string.rep("=", 60))
    print("-- MapLayout Scanner Output")
    print(string.rep("=", 60))
    print(code)
    print(string.rep("=", 60) .. "\n")
end

--[[
    Find a part by name (Roblox Name property).

    @param name: The part name to search for
    @param container: Where to search (default: workspace)
    @return: Part or nil
--]]
function Scanner.findByName(name, container)
    container = container or workspace

    -- First check direct children
    local direct = container:FindFirstChild(name)
    if direct and direct:IsA("BasePart") then
        return direct
    end

    -- Then search descendants
    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Name == name then
            return descendant
        end
    end

    return nil
end

--[[
    Find all parts tagged as areas (MapLayoutTag = "area").

    @param container: Where to search (default: workspace)
    @return: Array of { part, name } tables
--]]
function Scanner.findAreas(container)
    container = container or workspace
    local areas = {}

    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local tag = descendant:GetAttribute("MapLayoutTag")
            if tag and tag:lower() == "area" then
                table.insert(areas, { part = descendant, name = descendant.Name })
            end
        end
    end

    return areas
end

--[[
    Scan an area by name.

    Finds a part tagged as an area (MapLayoutTag = "area") with the given name,
    uses it as the bounding box, and scans its descendants for geometry.

    Hierarchy determines relative positioning:
        testArea (Part with MapLayoutTag = "area")
            ├── wallA (Part) → position relative to area origin
            │   └── wallB (Part) → position relative to #wallA
            └── floor1 (Part) → position relative to area origin

    All coordinates are LOCAL to the area origin, converted at runtime.

    @param areaName: Name of the area part (Roblox Name property)
    @param container: Where to search (default: workspace)
    @param options: Optional configuration
    @return: Config table for this area
--]]
function Scanner.scanArea(areaName, container, options)
    container = container or workspace
    options = options or {}

    -- Find the area bounding box part by name
    local areaPart = nil

    -- Check direct child first
    local direct = container:FindFirstChild(areaName)
    if direct and direct:IsA("BasePart") then
        local tag = direct:GetAttribute("MapLayoutTag")
        if tag and tag:lower() == "area" then
            areaPart = direct
        end
    end

    -- If not found, search descendants
    if not areaPart then
        for _, descendant in ipairs(container:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant.Name == areaName then
                local tag = descendant:GetAttribute("MapLayoutTag")
                if tag and tag:lower() == "area" then
                    areaPart = descendant
                    break
                end
            end
        end
    end

    if not areaPart then
        warn("[Scanner] Could not find area named '" .. areaName .. "' with MapLayoutTag = 'area'")
        warn("[Scanner] Make sure the part is named '" .. areaName .. "' and has attribute MapLayoutTag = 'area'")
        return nil
    end

    -- Get area bounds from the part (using corner as origin)
    local areaPos = areaPart.Position
    local areaSize = areaPart.Size
    local areaOrigin = areaPos - areaSize / 2  -- Corner origin

    -- Determine origin mode
    local origin = options.origin or "corner"

    -- Build area config
    local config = {
        id = areaName,
        bounds = {
            math.floor(areaSize.X * 100) / 100,
            math.floor(areaSize.Y * 100) / 100,
            math.floor(areaSize.Z * 100) / 100,
        },
        origin = origin,
        walls = {},
        floors = {},
        platforms = {},
        cylinders = {},
        spheres = {},
        wedges = {},
    }

    -- Helper to round numbers
    local function round(n)
        return math.floor(n * 100) / 100
    end

    -- Collect reference points for snapping (2D for walls, 3D for platforms)
    local referencePoints2D = {}  -- Wall endpoints
    local referencePoints3D = {}  -- Platform/floor positions

    -- Bounds as table for snapping functions
    local boundsTable = {config.bounds[1], config.bounds[2], config.bounds[3]}

    -- Helper to get element ID (for references)
    local function getElementId(part)
        return part:GetAttribute("MapLayoutId")
            or part:GetAttribute("MapLayoutName")
            or part.Name
    end

    -- Helper to determine the closest reference point on a parent wall
    local function getClosestWallReference(parentPart, childPos)
        local parentGeo = extractWallGeometry(parentPart)
        local fromVec = Vector3.new(parentGeo.from[1], 0, parentGeo.from[2])
        local toVec = Vector3.new(parentGeo.to[1], 0, parentGeo.to[2])
        local centerVec = (fromVec + toVec) / 2

        local childVec = Vector3.new(childPos.X, 0, childPos.Z)

        local distToStart = (childVec - fromVec).Magnitude
        local distToEnd = (childVec - toVec).Magnitude
        local distToCenter = (childVec - centerVec).Magnitude

        local minDist = math.min(distToStart, distToEnd, distToCenter)

        if minDist == distToStart then
            return "start", fromVec
        elseif minDist == distToEnd then
            return "end", toVec
        else
            return "center", centerVec
        end
    end

    -- Helper to determine closest reference point on a parent platform/floor
    local function getClosestPlatformReference(parentPart, childPos)
        local parentPos = parentPart.Position
        -- For now, just use center
        return "center", parentPos
    end

    -- Recursive function to scan parts
    local function scanPart(part, parentPart, parentId)
        if not part:IsA("BasePart") then return end
        if part:GetAttribute("MapLayoutIgnore") then return end

        local elementType = inferType(part)
        local element = extractProperties(part)
        local partId = getElementId(part)
        element.id = partId

        -- Determine position reference
        local isRelativeToParent = parentPart ~= nil and parentPart ~= areaPart

        if elementType == "wall" then
            local geo = extractWallGeometry(part)

            -- Convert to local coordinates first
            local localFrom = {
                geo.from[1] - areaOrigin.X,
                geo.from[2] - areaOrigin.Z,
            }
            local localTo = {
                geo.to[1] - areaOrigin.X,
                geo.to[2] - areaOrigin.Z,
            }

            -- Apply snapping to area boundaries and existing reference points
            localFrom = snapPoint2D(localFrom, boundsTable, referencePoints2D, SNAP_THRESHOLD)
            localTo = snapPoint2D(localTo, boundsTable, referencePoints2D, SNAP_THRESHOLD)

            -- Add these endpoints as reference points for future snapping
            table.insert(referencePoints2D, {localFrom[1], localFrom[2]})
            table.insert(referencePoints2D, {localTo[1], localTo[2]})

            if isRelativeToParent then
                -- Position relative to parent element
                local refPoint, refPos = getClosestWallReference(parentPart,
                    Vector3.new(geo.from[1], 0, geo.from[2]))
                local parentType = inferType(parentPart)

                if parentType == "wall" then
                    element.from = string.format("#%s:%s", parentId, refPoint)
                else
                    -- For non-wall parents, use offset from center
                    local parentPos = parentPart.Position
                    local parentLocal = {
                        parentPos.X - areaOrigin.X,
                        parentPos.Z - areaOrigin.Z,
                    }
                    element.from = {
                        round(localFrom[1] - parentLocal[1]),
                        round(localFrom[2] - parentLocal[2]),
                    }
                    element.anchor = "#" .. parentId
                end

                -- 'to' as offset from 'from'
                local dx = round(localTo[1] - localFrom[1])
                local dz = round(localTo[2] - localFrom[2])
                local length = round(math.sqrt(dx*dx + dz*dz))
                element.length = length

                -- Calculate direction angle if not axis-aligned
                if math.abs(dx) > 0.01 and math.abs(dz) > 0.01 then
                    element.angle = round(math.deg(math.atan2(dz, dx)))
                elseif math.abs(dz) > math.abs(dx) then
                    element.direction = dz > 0 and "+z" or "-z"
                else
                    element.direction = dx > 0 and "+x" or "-x"
                end
            else
                -- Position relative to area origin (already snapped)
                element.from = {round(localFrom[1]), round(localFrom[2])}
                element.to = {round(localTo[1]), round(localTo[2])}
            end

            -- Snap wall height to area height if close
            local snappedHeight = snapValue(geo.height, boundsTable[2], SNAP_THRESHOLD)
            element.height = round(snappedHeight)
            element.thickness = geo.thickness
            table.insert(config.walls, element)

        elseif elementType == "floor" then
            local geo = extractFloorGeometry(part)

            -- Convert to local coordinates
            local localPos = {
                geo.position[1] - areaOrigin.X,
                geo.position[2] - areaOrigin.Y,
                geo.position[3] - areaOrigin.Z,
            }
            local localSize = geo.size

            -- Apply edge snapping to boundaries (may adjust both position and size)
            localPos, localSize = snapEdges(localPos, localSize, boundsTable, SNAP_THRESHOLD)

            -- Add center as reference point
            table.insert(referencePoints3D, {localPos[1], localPos[2], localPos[3]})

            if isRelativeToParent then
                local parentPos = parentPart.Position
                local parentLocal = {
                    parentPos.X - areaOrigin.X,
                    parentPos.Y - areaOrigin.Y,
                    parentPos.Z - areaOrigin.Z,
                }
                element.position = {
                    round(localPos[1] - parentLocal[1]),
                    round(localPos[2] - parentLocal[2]),
                    round(localPos[3] - parentLocal[3]),
                }
                element.anchor = "#" .. parentId
            else
                element.position = {round(localPos[1]), round(localPos[2]), round(localPos[3])}
            end

            element.size = {round(localSize[1]), round(localSize[2]), round(localSize[3])}
            table.insert(config.floors, element)

        elseif elementType == "platform" then
            local geo = extractPlatformGeometry(part)

            -- Convert to local coordinates
            local localPos = {
                geo.position[1] - areaOrigin.X,
                geo.position[2] - areaOrigin.Y,
                geo.position[3] - areaOrigin.Z,
            }
            local localSize = geo.size

            -- Apply edge snapping to boundaries
            localPos, localSize = snapEdges(localPos, localSize, boundsTable, SNAP_THRESHOLD)

            -- Add center as reference point
            table.insert(referencePoints3D, {localPos[1], localPos[2], localPos[3]})

            if isRelativeToParent then
                local parentPos = parentPart.Position
                local parentLocal = {
                    parentPos.X - areaOrigin.X,
                    parentPos.Y - areaOrigin.Y,
                    parentPos.Z - areaOrigin.Z,
                }
                element.position = {
                    round(localPos[1] - parentLocal[1]),
                    round(localPos[2] - parentLocal[2]),
                    round(localPos[3] - parentLocal[3]),
                }
                element.anchor = "#" .. parentId
            else
                element.position = {round(localPos[1]), round(localPos[2]), round(localPos[3])}
            end

            element.size = {round(localSize[1]), round(localSize[2]), round(localSize[3])}
            table.insert(config.platforms, element)

        elseif elementType == "cylinder" then
            local geo = extractCylinderGeometry(part)

            -- Convert to local and snap position
            local localPos = {
                geo.position[1] - areaOrigin.X,
                geo.position[2] - areaOrigin.Y,
                geo.position[3] - areaOrigin.Z,
            }
            localPos = snapPoint3D(localPos, boundsTable, referencePoints3D, SNAP_THRESHOLD)
            table.insert(referencePoints3D, {localPos[1], localPos[2], localPos[3]})

            if isRelativeToParent then
                local parentPos = parentPart.Position
                local parentLocal = {
                    parentPos.X - areaOrigin.X,
                    parentPos.Y - areaOrigin.Y,
                    parentPos.Z - areaOrigin.Z,
                }
                element.position = {
                    round(localPos[1] - parentLocal[1]),
                    round(localPos[2] - parentLocal[2]),
                    round(localPos[3] - parentLocal[3]),
                }
                element.anchor = "#" .. parentId
            else
                element.position = {round(localPos[1]), round(localPos[2]), round(localPos[3])}
            end

            element.height = geo.height
            element.radius = geo.radius
            table.insert(config.cylinders, element)

        elseif elementType == "sphere" then
            local geo = extractSphereGeometry(part)

            -- Convert to local and snap position
            local localPos = {
                geo.position[1] - areaOrigin.X,
                geo.position[2] - areaOrigin.Y,
                geo.position[3] - areaOrigin.Z,
            }
            localPos = snapPoint3D(localPos, boundsTable, referencePoints3D, SNAP_THRESHOLD)
            table.insert(referencePoints3D, {localPos[1], localPos[2], localPos[3]})

            if isRelativeToParent then
                local parentPos = parentPart.Position
                local parentLocal = {
                    parentPos.X - areaOrigin.X,
                    parentPos.Y - areaOrigin.Y,
                    parentPos.Z - areaOrigin.Z,
                }
                element.position = {
                    round(localPos[1] - parentLocal[1]),
                    round(localPos[2] - parentLocal[2]),
                    round(localPos[3] - parentLocal[3]),
                }
                element.anchor = "#" .. parentId
            else
                element.position = {round(localPos[1]), round(localPos[2]), round(localPos[3])}
            end

            element.radius = geo.radius
            table.insert(config.spheres, element)

        elseif elementType == "wedge" then
            local geo = extractPlatformGeometry(part)

            -- Convert to local coordinates
            local localPos = {
                geo.position[1] - areaOrigin.X,
                geo.position[2] - areaOrigin.Y,
                geo.position[3] - areaOrigin.Z,
            }
            local localSize = geo.size

            -- Apply edge snapping
            localPos, localSize = snapEdges(localPos, localSize, boundsTable, SNAP_THRESHOLD)
            table.insert(referencePoints3D, {localPos[1], localPos[2], localPos[3]})

            if isRelativeToParent then
                local parentPos = parentPart.Position
                local parentLocal = {
                    parentPos.X - areaOrigin.X,
                    parentPos.Y - areaOrigin.Y,
                    parentPos.Z - areaOrigin.Z,
                }
                element.position = {
                    round(localPos[1] - parentLocal[1]),
                    round(localPos[2] - parentLocal[2]),
                    round(localPos[3] - parentLocal[3]),
                }
                element.anchor = "#" .. parentId
            else
                element.position = {round(localPos[1]), round(localPos[2]), round(localPos[3])}
            end

            element.size = {round(localSize[1]), round(localSize[2]), round(localSize[3])}
            table.insert(config.wedges, element)
        end

        -- Recursively scan children of this part
        for _, child in ipairs(part:GetChildren()) do
            scanPart(child, part, partId)
        end
    end

    -- Start scanning from direct children of the area
    for _, child in ipairs(areaPart:GetChildren()) do
        scanPart(child, nil, nil)
    end

    -- Clean up empty categories
    if #config.walls == 0 then config.walls = nil end
    if #config.floors == 0 then config.floors = nil end
    if #config.platforms == 0 then config.platforms = nil end
    if #config.cylinders == 0 then config.cylinders = nil end
    if #config.spheres == 0 then config.spheres = nil end
    if #config.wedges == 0 then config.wedges = nil end

    return config
end

--[[
    Scan an area by name and generate code.

    @param areaName: Name of the area
    @param container: Where to search (default: workspace)
    @param options: Optional configuration
    @return: Lua code string
--]]
function Scanner.scanAreaToCode(areaName, container, options)
    local config = Scanner.scanArea(areaName, container, options)
    if not config then
        return nil
    end
    return Scanner.generateCode(config, options)
end

--[[
    Mirror an area: scan it and build a clean copy adjacent to the original.

    This is a live preview tool for iterating on layouts:
    1. Build rough geometry in Studio
    2. Run mirrorArea
    3. See the snapped/cleaned version next to the original
    4. Adjust and repeat until satisfied
    5. Export the config with scanArea

    The mirror is placed adjacent to the original along the X axis by default.

    @param areaName: Name of the area part (Roblox Name property)
    @param container: Where to search (default: workspace)
    @param options: Optional configuration
        - offset: Direction to place mirror ("x", "-x", "z", "-z") default: "x"
        - gap: Studs between original and mirror (default: 2)
        - styles: Style definitions for building
    @return: { model: Model, config: table, cleanup: function }
--]]
function Scanner.mirrorArea(areaName, container, options)
    container = container or workspace
    options = options or {}

    local offsetDir = options.offset or "x"
    local gap = options.gap or 2
    local styles = options.styles

    -- Find the original area part
    local areaPart = nil
    local direct = container:FindFirstChild(areaName)
    if direct and direct:IsA("BasePart") then
        local tag = direct:GetAttribute("MapLayoutTag")
        if tag and tag:lower() == "area" then
            areaPart = direct
        end
    end

    if not areaPart then
        for _, descendant in ipairs(container:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant.Name == areaName then
                local tag = descendant:GetAttribute("MapLayoutTag")
                if tag and tag:lower() == "area" then
                    areaPart = descendant
                    break
                end
            end
        end
    end

    if not areaPart then
        warn("[Scanner.mirrorArea] Could not find area named '" .. areaName .. "'")
        return nil
    end

    -- Auto-cleanup: remove any existing mirror with the same name
    local existingMirror = workspace:FindFirstChild(areaName .. "_Mirror")
    if existingMirror then
        existingMirror:Destroy()
    end

    -- Scan the area to get cleaned config
    local config = Scanner.scanArea(areaName, container, options)
    if not config then
        return nil
    end

    -- Calculate mirror position based on offset direction
    local areaPos = areaPart.Position
    local areaSize = areaPart.Size
    local mirrorPos

    if offsetDir == "x" or offsetDir == "+x" then
        mirrorPos = Vector3.new(
            areaPos.X + areaSize.X + gap,
            areaPos.Y,
            areaPos.Z
        )
    elseif offsetDir == "-x" then
        mirrorPos = Vector3.new(
            areaPos.X - areaSize.X - gap,
            areaPos.Y,
            areaPos.Z
        )
    elseif offsetDir == "z" or offsetDir == "+z" then
        mirrorPos = Vector3.new(
            areaPos.X,
            areaPos.Y,
            areaPos.Z + areaSize.Z + gap
        )
    elseif offsetDir == "-z" then
        mirrorPos = Vector3.new(
            areaPos.X,
            areaPos.Y,
            areaPos.Z - areaSize.Z - gap
        )
    else
        mirrorPos = Vector3.new(
            areaPos.X + areaSize.X + gap,
            areaPos.Y,
            areaPos.Z
        )
    end

    -- Convert corner origin to position for building
    -- The scanned config uses corner origin, so mirrorPos should be corner-based
    local areaOrigin = areaPos - areaSize / 2  -- Original corner
    local mirrorOrigin = mirrorPos - areaSize / 2  -- Mirror corner

    -- Build the geometry using MapBuilder
    -- We need to require MapBuilder here (it's a sibling module)
    local MapBuilder = require(script.Parent.MapBuilder)
    local GeometryFactory = require(script.Parent.GeometryFactory)
    local StyleResolver = require(script.Parent.StyleResolver)

    -- Create a model for the mirror
    local mirrorModel = Instance.new("Model")
    mirrorModel.Name = areaName .. "_Mirror"

    -- Create a visual bounding box for the mirror area (semi-transparent)
    local mirrorBounds = Instance.new("Part")
    mirrorBounds.Name = "MirrorBounds"
    mirrorBounds.Size = areaSize
    mirrorBounds.Position = mirrorPos
    mirrorBounds.Anchored = true
    mirrorBounds.CanCollide = false
    mirrorBounds.Transparency = 0.9
    mirrorBounds.Color = Color3.fromRGB(100, 200, 100)  -- Light green tint
    mirrorBounds.Material = Enum.Material.ForceField
    mirrorBounds.Parent = mirrorModel

    -- Build each element type
    local function buildElements(elements, elementType)
        if not elements then return end

        for _, element in ipairs(elements) do
            -- Resolve styles
            local resolved = StyleResolver.resolve(element, styles, elementType)

            -- Calculate world position from local coordinates
            local part

            if elementType == "wall" then
                -- Walls use from/to coordinates
                local fromX, fromZ, toX, toZ

                if type(element.from) == "table" then
                    fromX = element.from[1] + mirrorOrigin.X
                    fromZ = element.from[2] + mirrorOrigin.Z
                else
                    -- Reference string - skip for now (would need registry)
                    return
                end

                if type(element.to) == "table" then
                    toX = element.to[1] + mirrorOrigin.X
                    toZ = element.to[2] + mirrorOrigin.Z
                else
                    -- Has length/direction instead of to
                    local length = element.length or 10
                    local angle = element.angle or 0
                    if element.direction == "+x" then angle = 0
                    elseif element.direction == "-x" then angle = 180
                    elseif element.direction == "+z" then angle = 90
                    elseif element.direction == "-z" then angle = -90
                    end
                    toX = fromX + length * math.cos(math.rad(angle))
                    toZ = fromZ + length * math.sin(math.rad(angle))
                end

                local height = element.height or 10
                local thickness = element.thickness or 1

                -- Create wall geometry
                local dx = toX - fromX
                local dz = toZ - fromZ
                local wallLength = math.sqrt(dx * dx + dz * dz)
                local centerX = (fromX + toX) / 2
                local centerZ = (fromZ + toZ) / 2
                local centerY = mirrorOrigin.Y + height / 2

                part = Instance.new("Part")
                part.Name = element.id or "wall"
                part.Anchored = true

                -- Determine orientation
                if math.abs(dx) > math.abs(dz) then
                    -- Runs along X
                    part.Size = Vector3.new(wallLength, height, thickness)
                else
                    -- Runs along Z
                    part.Size = Vector3.new(thickness, height, wallLength)
                end

                part.Position = Vector3.new(centerX, centerY, centerZ)

                -- Handle angled walls
                if math.abs(dx) > 0.01 and math.abs(dz) > 0.01 then
                    local angle = math.atan2(dz, dx)
                    part.Size = Vector3.new(wallLength, height, thickness)
                    part.CFrame = CFrame.new(centerX, centerY, centerZ) * CFrame.Angles(0, -angle, 0)
                end

            elseif elementType == "floor" or elementType == "platform" then
                local pos = element.position
                local size = element.size

                part = Instance.new("Part")
                part.Name = element.id or elementType
                part.Anchored = true
                part.Size = Vector3.new(size[1], size[2], size[3])
                part.Position = Vector3.new(
                    pos[1] + mirrorOrigin.X,
                    pos[2] + mirrorOrigin.Y,
                    pos[3] + mirrorOrigin.Z
                )

            elseif elementType == "cylinder" then
                local pos = element.position

                part = Instance.new("Part")
                part.Name = element.id or "cylinder"
                part.Shape = Enum.PartType.Cylinder
                part.Anchored = true
                part.Size = Vector3.new(element.height, element.radius * 2, element.radius * 2)
                part.Position = Vector3.new(
                    pos[1] + mirrorOrigin.X,
                    pos[2] + mirrorOrigin.Y,
                    pos[3] + mirrorOrigin.Z
                )

            elseif elementType == "sphere" then
                local pos = element.position
                local diameter = element.radius * 2

                part = Instance.new("Part")
                part.Name = element.id or "sphere"
                part.Shape = Enum.PartType.Ball
                part.Anchored = true
                part.Size = Vector3.new(diameter, diameter, diameter)
                part.Position = Vector3.new(
                    pos[1] + mirrorOrigin.X,
                    pos[2] + mirrorOrigin.Y,
                    pos[3] + mirrorOrigin.Z
                )

            elseif elementType == "wedge" then
                local pos = element.position
                local size = element.size

                part = Instance.new("WedgePart")
                part.Name = element.id or "wedge"
                part.Anchored = true
                part.Size = Vector3.new(size[1], size[2], size[3])
                part.Position = Vector3.new(
                    pos[1] + mirrorOrigin.X,
                    pos[2] + mirrorOrigin.Y,
                    pos[3] + mirrorOrigin.Z
                )
            end

            if part then
                -- Apply resolved properties
                if resolved.Material then
                    local mat = resolved.Material
                    if type(mat) == "string" then
                        mat = Enum.Material[mat]
                    end
                    if mat then part.Material = mat end
                end

                if resolved.Color then
                    local c = resolved.Color
                    if type(c) == "table" then
                        part.Color = Color3.fromRGB(c[1], c[2], c[3])
                    end
                end

                if resolved.Transparency then
                    part.Transparency = resolved.Transparency
                end

                if resolved.CanCollide ~= nil then
                    part.CanCollide = resolved.CanCollide
                end

                part.Parent = mirrorModel
            end
        end
    end

    -- Build all element types
    buildElements(config.walls, "wall")
    buildElements(config.floors, "floor")
    buildElements(config.platforms, "platform")
    buildElements(config.cylinders, "cylinder")
    buildElements(config.spheres, "sphere")
    buildElements(config.wedges, "wedge")

    -- Parent to workspace
    mirrorModel.Parent = workspace

    print(string.format("[Scanner.mirrorArea] Created mirror '%s' at offset %s (+%d studs gap)",
        mirrorModel.Name, offsetDir, gap))
    print(string.format("[Scanner.mirrorArea] Mirror contains %d parts", #mirrorModel:GetChildren()))

    -- Return handle with cleanup
    return {
        model = mirrorModel,
        config = config,
        cleanup = function()
            if mirrorModel and mirrorModel.Parent then
                mirrorModel:Destroy()
            end
        end,
        -- Convenience: regenerate the mirror (call after adjusting original)
        refresh = function()
            if mirrorModel and mirrorModel.Parent then
                mirrorModel:Destroy()
            end
            return Scanner.mirrorArea(areaName, container, options)
        end,
    }
end

return Scanner
