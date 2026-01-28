--[[
    LibPureFiction Framework v2
    GeometrySpec/Scanner.lua - Scan Geometry and Generate Spec Config

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Scanner provides a reverse workflow: take existing Roblox geometry and
    generate GeometrySpec Lua configuration code from it.

    Workflow:
    1. Build rough geometry in Roblox Studio (drag and drop)
    2. Run Scanner on the container
    3. Get generated GeometrySpec config code
    4. Apply classes in text editor
    5. Delete original parts, rebuild from config

    ============================================================================
    USAGE
    ============================================================================

    AREA SCANNING (Recommended):
    1. Create a Part, name it (e.g., "testArea")
    2. Add attribute: GeometrySpecTag = "area"
    3. Nest geometry parts as CHILDREN under it in Explorer
    4. Run:

    ```lua
    require(game.ReplicatedStorage.Lib.GeometrySpec).scanArea("testArea")
    ```

    Explorer structure:
        workspace
            testArea (Part with GeometrySpecTag = "area")
                ├── base (Part)
                ├── pillar (Part)
                └── platform (Part)

    ============================================================================
    ATTRIBUTES
    ============================================================================

    GeometrySpecId: string - Element's 'id' in config
    GeometrySpecClass: string - Element's 'class' in config
    GeometrySpecTag: string - Set to "area" for bounding boxes
    GeometrySpecIgnore: boolean - Skip this part

    KNOWN ISSUES
    ============================================================================

    - Output may contain decimal values despite integer rounding. Values are
      correct but serializer formatting needs investigation.

--]]

local Scanner = {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Default snapping threshold (2 studs - covers rough visual placement)
local SNAP_THRESHOLD = 2

-- Minimum size to prevent parts collapsing to zero
local MIN_SIZE = 0.5

--------------------------------------------------------------------------------
-- ROUNDING
--------------------------------------------------------------------------------

--[[
    Round to whole integer (no decimals).
    For finer units later, change this to round to desired precision.
--]]
local function round(n)
    return math.floor(n + 0.5)
end

--------------------------------------------------------------------------------
-- SNAPPING HELPERS
--------------------------------------------------------------------------------

--[[
    Snap a value to the nearest target in a list.
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
    Snap a 3D point to area boundaries.
--]]
local function snapPoint3D(point, bounds, threshold)
    threshold = threshold or SNAP_THRESHOLD
    local x, y, z = point[1], point[2], point[3]

    local xTargets = {0, bounds[1]}
    local yTargets = {0, bounds[2]}
    local zTargets = {0, bounds[3]}

    x = snapToNearest(x, xTargets, threshold)
    y = snapToNearest(y, yTargets, threshold)
    z = snapToNearest(z, zTargets, threshold)

    return {round(x), round(y), round(z)}
end

--[[
    Snap element edges to boundaries and adjust size.
--]]
local function snapEdges(position, size, bounds, threshold)
    threshold = threshold or SNAP_THRESHOLD

    local px, py, pz = position[1], position[2], position[3]
    local sx, sy, sz = size[1], size[2], size[3]

    local minX, maxX = px - sx/2, px + sx/2
    local minY, maxY = py - sy/2, py + sy/2
    local minZ, maxZ = pz - sz/2, pz + sz/2

    local newMinX = snapToNearest(minX, {0, bounds[1]}, threshold)
    local newMaxX = snapToNearest(maxX, {0, bounds[1]}, threshold)
    local newMinY = snapToNearest(minY, {0, bounds[2]}, threshold)
    local newMaxY = snapToNearest(maxY, {0, bounds[2]}, threshold)
    local newMinZ = snapToNearest(minZ, {0, bounds[3]}, threshold)
    local newMaxZ = snapToNearest(maxZ, {0, bounds[3]}, threshold)

    local newSx = math.max(newMaxX - newMinX, MIN_SIZE)
    local newSy = math.max(newMaxY - newMinY, MIN_SIZE)
    local newSz = math.max(newMaxZ - newMinZ, MIN_SIZE)

    local newPx = (newMinX + newMaxX) / 2
    local newPy = (newMinY + newMaxY) / 2
    local newPz = (newMinZ + newMaxZ) / 2

    return {round(newPx), round(newPy), round(newPz)}, {round(newSx), round(newSy), round(newSz)}
end

--------------------------------------------------------------------------------
-- ROTATION EXTRACTION
--------------------------------------------------------------------------------

--[[
    Extract rotation from a part's Orientation property.
    Returns nil if rotation is essentially zero (within threshold).

    @param part: BasePart to extract rotation from
    @param threshold: Angle threshold in degrees to consider "zero" (default: 0.5)
    @return: {rx, ry, rz} in degrees, or nil if no significant rotation
--]]
local function extractRotation(part, threshold)
    threshold = threshold or 0.5

    -- Use Orientation property directly (already in degrees)
    local orientation = part.Orientation
    local rx = round(orientation.X)
    local ry = round(orientation.Y)
    local rz = round(orientation.Z)

    -- Check if rotation is significant
    if math.abs(rx) < threshold and math.abs(ry) < threshold and math.abs(rz) < threshold then
        return nil
    end

    return {rx, ry, rz}
end

--------------------------------------------------------------------------------
-- TYPE INFERENCE
--------------------------------------------------------------------------------

--[[
    Infer the shape from a Part.

    @param part: BasePart to analyze
    @return: "block", "cylinder", "sphere", "wedge"
--]]
local function inferShape(part)
    -- Check for explicit override
    local override = part:GetAttribute("GeometrySpecShape")
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

    return "block"
end

--------------------------------------------------------------------------------
-- GEOMETRY EXTRACTION
--------------------------------------------------------------------------------

--[[
    Extract block geometry.
--]]
local function extractBlockGeometry(part)
    local pos = part.Position
    local size = part.Size

    return {
        position = { round(pos.X), round(pos.Y), round(pos.Z) },
        size = { round(size.X), round(size.Y), round(size.Z) },
    }
end

--[[
    Extract cylinder geometry.
--]]
local function extractCylinderGeometry(part)
    local pos = part.Position
    local size = part.Size

    return {
        position = { round(pos.X), round(pos.Y), round(pos.Z) },
        height = round(size.X),
        radius = round(size.Y / 2),
    }
end

--[[
    Extract sphere geometry.
--]]
local function extractSphereGeometry(part)
    local pos = part.Position
    local size = part.Size

    return {
        position = { round(pos.X), round(pos.Y), round(pos.Z) },
        radius = round(size.X / 2),
    }
end

--[[
    Extract common properties from a part.
--]]
local function extractProperties(part)
    local props = {}

    -- ID from attributes
    local id = part:GetAttribute("GeometrySpecId")
        or part:GetAttribute("GeometrySpecName")
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

    -- Class from attributes
    local class = part:GetAttribute("GeometrySpecClass")
        or part:GetAttribute("GeometrySpecTag")

    -- Don't use "area" tag as class
    if class and class:lower() == "area" then
        class = nil
    end

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
        props.Transparency = round(part.Transparency)
    end

    -- CanCollide (only if false)
    -- Note: Anchored is NOT output - built geometry is always anchored by default
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
    @return: Scanned config table
--]]
function Scanner.scan(container, options)
    options = options or {}
    local includeChildren = options.includeChildren ~= false

    local config = {
        name = container.Name,
        parts = {},
    }

    -- Read spec-level attributes if present (set by Factory.build)
    local specScale = container:GetAttribute("GeometrySpecScale")
    local specOrigin = container:GetAttribute("GeometrySpecOrigin")
    local specBoundsStr = container:GetAttribute("GeometrySpecBounds")

    local scale = 1
    if specScale then
        config.scale = specScale
        -- Parse scale (e.g., "5:1" means multiply by 5)
        local left, right = specScale:match("(%d+):(%d+)")
        if left and right then
            scale = tonumber(left) / tonumber(right)
        end
    end

    if specOrigin then
        config.origin = specOrigin
    end

    local bounds
    if specBoundsStr then
        local parts = {}
        for num in specBoundsStr:gmatch("([^,]+)") do
            table.insert(parts, tonumber(num))
        end
        if #parts == 3 then
            bounds = parts
            config.bounds = bounds
        end
    end

    -- Calculate origin offset to transform world coords back to spec coords
    local scaledBounds = bounds and {bounds[1] * scale, bounds[2] * scale, bounds[3] * scale} or {0, 0, 0}
    local containerCorner = container.Position - container.Size / 2
    local originOffset = Vector3.new(0, 0, 0)

    if specOrigin == "center" then
        originOffset = Vector3.new(-scaledBounds[1]/2, -scaledBounds[2]/2, -scaledBounds[3]/2)
    elseif specOrigin == "floor-center" then
        originOffset = Vector3.new(-scaledBounds[1]/2, 0, -scaledBounds[3]/2)
    end
    -- "corner" has no offset

    local worldToSpec = containerCorner + originOffset

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
        if part:GetAttribute("GeometrySpecIgnore") then
            continue
        end

        -- Skip if it's an area container
        local tag = part:GetAttribute("GeometrySpecTag")
        if tag and tag:lower() == "area" then
            continue
        end

        local shape = inferShape(part)
        local element = extractProperties(part)

        if shape == "block" then
            local geo = extractBlockGeometry(part)
            -- Transform world coords back to spec coords
            local worldPos = Vector3.new(geo.position[1], geo.position[2], geo.position[3])
            local specPos = (worldPos - worldToSpec) / scale
            element.position = {round(specPos.X), round(specPos.Y), round(specPos.Z)}
            element.size = {round(geo.size[1] / scale), round(geo.size[2] / scale), round(geo.size[3] / scale)}
            -- shape = "block" is default, don't include

        elseif shape == "cylinder" then
            local geo = extractCylinderGeometry(part)
            local worldPos = Vector3.new(geo.position[1], geo.position[2], geo.position[3])
            local specPos = (worldPos - worldToSpec) / scale
            element.position = {round(specPos.X), round(specPos.Y), round(specPos.Z)}
            element.height = round(geo.height / scale)
            element.radius = round(geo.radius / scale)
            element.shape = "cylinder"

        elseif shape == "sphere" then
            local geo = extractSphereGeometry(part)
            local worldPos = Vector3.new(geo.position[1], geo.position[2], geo.position[3])
            local specPos = (worldPos - worldToSpec) / scale
            element.position = {round(specPos.X), round(specPos.Y), round(specPos.Z)}
            element.radius = round(geo.radius / scale)
            element.shape = "sphere"

        elseif shape == "wedge" then
            local geo = extractBlockGeometry(part)
            local worldPos = Vector3.new(geo.position[1], geo.position[2], geo.position[3])
            local specPos = (worldPos - worldToSpec) / scale
            element.position = {round(specPos.X), round(specPos.Y), round(specPos.Z)}
            element.size = {round(geo.size[1] / scale), round(geo.size[2] / scale), round(geo.size[3] / scale)}
            element.shape = "wedge"
        end

        -- Extract rotation (only if significant)
        local rotation = extractRotation(part)
        if rotation then
            element.rotation = rotation
        end

        table.insert(config.parts, element)
    end

    if #config.parts == 0 then
        config.parts = nil
    end

    return config
end

--------------------------------------------------------------------------------
-- CODE GENERATION
--------------------------------------------------------------------------------

--[[
    Serialize a value to Lua code.
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
        -- Round to nearest integer if very close (handles floating point precision)
        local rounded = math.floor(value + 0.5)
        if math.abs(value - rounded) < 0.001 then
            return tostring(rounded)
        else
            return string.format("%.2f", value)
        end
    elseif type(value) == "string" then
        return string.format("%q", value)
    elseif type(value) == "table" then
        -- Check if it's an array
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
                local parts = {}
                for _, v in ipairs(value) do
                    table.insert(parts, serializeValue(v, 0))
                end
                return "{" .. table.concat(parts, ", ") .. "}"
            else
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
                -- Priority order for keys
                local priority = {
                    name = 1,      -- Layout name first
                    spec = 2,      -- Then spec block
                    scale = 3,     -- Spec-level settings
                    origin = 4,
                    bounds = 5,
                    defaults = 6,  -- Style definitions
                    classes = 7,
                    id = 8,        -- Part identity
                    class = 9,
                    shape = 10,
                    position = 11, -- Geometry
                    size = 12,
                    rotation = 13, -- Orientation
                    parts = 14,
                    mounts = 15,
                }
                local pa = priority[a] or 100
                local pb = priority[b] or 100
                if pa ~= pb then
                    return pa < pb
                end
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

    @param config: Scanned config table (from scan or scanArea)
    @param options: Optional configuration
        - layout: boolean - If true, output layout format with name/spec (default: true)
        - varName: string - Variable name if layout=false
        - includeClasses: boolean - Include classes template comment
        - includeHeader: boolean - Include header comment (default: true)
    @return: Lua code string
--]]
function Scanner.generateCode(config, options)
    options = options or {}
    local layoutMode = options.layout ~= false  -- Default to layout mode
    local includeHeader = options.includeHeader ~= false

    local lines = {}
    local layoutName = config.name or "Layout"

    if includeHeader then
        table.insert(lines, "--[[")
        table.insert(lines, "    " .. layoutName)
        table.insert(lines, "    Generated by GeometrySpec Scanner")
        table.insert(lines, "    Apply classes and fine-tune as needed")
        table.insert(lines, "--]]")
        table.insert(lines, "")
    end

    if layoutMode then
        -- Layout format: { name = "...", spec = { ... } }
        -- Extract name from config and put rest in spec
        local spec = {}
        for k, v in pairs(config) do
            if k ~= "name" then
                spec[k] = v
            end
        end

        local layout = {
            name = layoutName,
            spec = spec,
        }

        table.insert(lines, "return " .. serializeValue(layout, 0))
    else
        -- Variable format for other uses (raw config)
        local varName = options.varName or "spec"
        table.insert(lines, "local " .. varName .. " = " .. serializeValue(config, 0))
        table.insert(lines, "")
        table.insert(lines, "return " .. varName)
    end

    if options.includeClasses then
        local classesTemplate = [[

-- Classes template (customize as needed)
-- Add a 'classes' key inside spec:
--
-- spec = {
--     ...
--     classes = {
--         frame = { Material = "DiamondPlate", Color = {80, 80, 85} },
--         accent = { Material = "Metal", Color = {40, 40, 40} },
--         trigger = { CanCollide = false, Transparency = 1 },
--     },
-- },
]]
        table.insert(lines, classesTemplate)
    end

    return table.concat(lines, "\n")
end

--[[
    Scan and generate code in one call.
--]]
function Scanner.scanToCode(container, options)
    local config = Scanner.scan(container, options)
    return Scanner.generateCode(config, options)
end

--------------------------------------------------------------------------------
-- CLEANUP (PUBLIC)
--------------------------------------------------------------------------------

--[[
    Clean up a config by snapping and rounding values.

    Can be called standalone on any config:
        local cleaned = Scanner.cleanup(rawConfig, { threshold = 0.5 })

    @param config: Raw config table with parts
    @param options: Optional { threshold, bounds }
    @return: Cleaned config with integer values
--]]
function Scanner.cleanup(config, options)
    options = options or {}
    local threshold = options.threshold or SNAP_THRESHOLD
    local bounds = options.bounds or config.bounds

    if not bounds then
        -- No bounds, just round everything
        bounds = {math.huge, math.huge, math.huge}
    end

    local cleaned = {
        bounds = config.bounds and {round(config.bounds[1]), round(config.bounds[2]), round(config.bounds[3])},
        origin = config.origin,
        parts = {},
    }

    if config.parts then
        for _, part in ipairs(config.parts) do
            local cleanPart = {}

            -- Copy non-geometry properties (including rotation)
            for k, v in pairs(part) do
                if k ~= "position" and k ~= "size" and k ~= "height" and k ~= "radius" then
                    cleanPart[k] = v
                end
            end

            -- Keep rotation as-is (already in degrees, already rounded)
            if part.rotation then
                cleanPart.rotation = part.rotation
            end

            -- Clean geometry based on shape
            local shape = part.shape or "block"

            if shape == "block" or shape == "wedge" then
                local pos = part.position or {0, 0, 0}
                local size = part.size or {1, 1, 1}
                cleanPart.position, cleanPart.size = snapEdges(pos, size, bounds, threshold)

            elseif shape == "cylinder" then
                cleanPart.position = snapPoint3D(part.position or {0, 0, 0}, bounds, threshold)
                cleanPart.height = round(part.height or 1)
                cleanPart.radius = round(part.radius or 1)

            elseif shape == "sphere" then
                cleanPart.position = snapPoint3D(part.position or {0, 0, 0}, bounds, threshold)
                cleanPart.radius = round(part.radius or 1)
            end

            table.insert(cleaned.parts, cleanPart)
        end
    end

    if cleaned.parts and #cleaned.parts == 0 then
        cleaned.parts = nil
    end

    return cleaned
end

--------------------------------------------------------------------------------
-- AREA SCANNING
--------------------------------------------------------------------------------

--[[
    Find all parts tagged as areas.
--]]
function Scanner.findAreas(container)
    container = container or workspace
    local areas = {}

    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local tag = descendant:GetAttribute("GeometrySpecTag")
            if tag and tag:lower() == "area" then
                table.insert(areas, { part = descendant, name = descendant.Name })
            end
        end
    end

    return areas
end

--[[
    Scan an area by name.

    Finds a part tagged as an area with the given name,
    uses it as the bounding box, and scans its children for geometry.

    @param areaName: Name of the area part
    @param container: Where to search (default: workspace)
    @param options: Optional configuration
    @return: Config table for this area
--]]
function Scanner.scanArea(areaName, container, options)
    container = container or workspace
    options = options or {}

    -- Find the area bounding box part by name
    local areaPart = nil

    local direct = container:FindFirstChild(areaName)
    if direct and direct:IsA("BasePart") then
        local tag = direct:GetAttribute("GeometrySpecTag")
        if tag and tag:lower() == "area" then
            areaPart = direct
        end
    end

    if not areaPart then
        for _, descendant in ipairs(container:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant.Name == areaName then
                local tag = descendant:GetAttribute("GeometrySpecTag")
                if tag and tag:lower() == "area" then
                    areaPart = descendant
                    break
                end
            end
        end
    end

    if not areaPart then
        warn("[Scanner] Could not find area named '" .. areaName .. "' with GeometrySpecTag = 'area'")
        return nil
    end

    -- Get area bounds from the part (using corner as origin)
    local areaPos = areaPart.Position
    local areaSize = areaPart.Size
    local areaOrigin = areaPos - areaSize / 2

    local origin = options.origin or "corner"

    local config = {
        bounds = { round(areaSize.X), round(areaSize.Y), round(areaSize.Z) },
        origin = origin,
        parts = {},
    }

    local boundsTable = {config.bounds[1], config.bounds[2], config.bounds[3]}

    -- Process children of the area
    for _, child in ipairs(areaPart:GetChildren()) do
        if not child:IsA("BasePart") then
            continue
        end

        if child:GetAttribute("GeometrySpecIgnore") then
            continue
        end

        local shape = inferShape(child)
        local element = extractProperties(child)

        -- Convert to local coordinates relative to area origin
        local worldPos = child.Position
        local localPos = {
            round(worldPos.X - areaOrigin.X),
            round(worldPos.Y - areaOrigin.Y),
            round(worldPos.Z - areaOrigin.Z),
        }

        -- Snap edges to bounds
        if shape == "block" or shape == "wedge" then
            local geo = extractBlockGeometry(child)
            local localSize = { round(child.Size.X), round(child.Size.Y), round(child.Size.Z) }

            -- Apply snapping
            localPos, localSize = snapEdges(localPos, localSize, boundsTable, SNAP_THRESHOLD)

            element.position = localPos
            element.size = localSize

            if shape == "wedge" then
                element.shape = "wedge"
            end

        elseif shape == "cylinder" then
            localPos = snapPoint3D(localPos, boundsTable, SNAP_THRESHOLD)
            element.position = localPos
            element.height = round(child.Size.X)
            element.radius = round(child.Size.Y / 2)
            element.shape = "cylinder"

        elseif shape == "sphere" then
            localPos = snapPoint3D(localPos, boundsTable, SNAP_THRESHOLD)
            element.position = localPos
            element.radius = round(child.Size.X / 2)
            element.shape = "sphere"
        end

        -- Extract rotation (only if significant)
        local rotation = extractRotation(child)
        if rotation then
            element.rotation = rotation
        end

        table.insert(config.parts, element)
    end

    if #config.parts == 0 then
        config.parts = nil
    end

    return config
end

--------------------------------------------------------------------------------
-- MIRROR PREVIEW
--------------------------------------------------------------------------------

--[[
    Mirror an area: scan and build a clean copy adjacent to the original.

    @param areaName: Name of the area part
    @param container: Where to search (default: workspace)
    @param options: Optional configuration
    @return: { model, config, cleanup(), refresh() }
--]]
function Scanner.mirrorArea(areaName, container, options)
    container = container or workspace
    options = options or {}

    local offsetDir = options.offset or "x"
    local gap = options.gap or 2

    -- Find the original area part
    local areaPart = nil
    local direct = container:FindFirstChild(areaName)
    if direct and direct:IsA("BasePart") then
        local tag = direct:GetAttribute("GeometrySpecTag")
        if tag and tag:lower() == "area" then
            areaPart = direct
        end
    end

    if not areaPart then
        for _, descendant in ipairs(container:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant.Name == areaName then
                local tag = descendant:GetAttribute("GeometrySpecTag")
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

    -- Auto-cleanup existing mirror
    local existingMirror = workspace:FindFirstChild(areaName .. "_Mirror")
    if existingMirror then
        existingMirror:Destroy()
    end

    -- Scan the area
    local config = Scanner.scanArea(areaName, container, options)
    if not config then
        return nil
    end

    -- Calculate mirror position
    local areaPos = areaPart.Position
    local areaSize = areaPart.Size
    local mirrorPos

    if offsetDir == "x" or offsetDir == "+x" then
        mirrorPos = Vector3.new(areaPos.X + areaSize.X + gap, areaPos.Y, areaPos.Z)
    elseif offsetDir == "-x" then
        mirrorPos = Vector3.new(areaPos.X - areaSize.X - gap, areaPos.Y, areaPos.Z)
    elseif offsetDir == "z" or offsetDir == "+z" then
        mirrorPos = Vector3.new(areaPos.X, areaPos.Y, areaPos.Z + areaSize.Z + gap)
    elseif offsetDir == "-z" then
        mirrorPos = Vector3.new(areaPos.X, areaPos.Y, areaPos.Z - areaSize.Z - gap)
    else
        mirrorPos = Vector3.new(areaPos.X + areaSize.X + gap, areaPos.Y, areaPos.Z)
    end

    local mirrorOrigin = mirrorPos - areaSize / 2

    -- Create mirror model
    local mirrorModel = Instance.new("Model")
    mirrorModel.Name = areaName .. "_Mirror"

    -- Create bounding box visualization
    local mirrorBounds = Instance.new("Part")
    mirrorBounds.Name = "MirrorBounds"
    mirrorBounds.Size = areaSize
    mirrorBounds.Position = mirrorPos
    mirrorBounds.Anchored = true
    mirrorBounds.CanCollide = false
    mirrorBounds.Transparency = 0.9
    mirrorBounds.Color = Color3.fromRGB(100, 200, 100)
    mirrorBounds.Material = Enum.Material.ForceField
    mirrorBounds.Parent = mirrorModel

    -- Build parts
    if config.parts then
        for _, element in ipairs(config.parts) do
            local part
            local shape = element.shape or "block"
            local pos = element.position

            local worldPos = Vector3.new(
                pos[1] + mirrorOrigin.X,
                pos[2] + mirrorOrigin.Y,
                pos[3] + mirrorOrigin.Z
            )

            if shape == "block" then
                local size = element.size
                part = Instance.new("Part")
                part.Shape = Enum.PartType.Block
                part.Size = Vector3.new(size[1], size[2], size[3])
                part.Position = worldPos

            elseif shape == "cylinder" then
                part = Instance.new("Part")
                part.Shape = Enum.PartType.Cylinder
                part.Size = Vector3.new(element.height, element.radius * 2, element.radius * 2)
                part.Position = worldPos
                part.CFrame = CFrame.new(worldPos) * CFrame.Angles(0, 0, math.rad(90))

            elseif shape == "sphere" then
                local diameter = element.radius * 2
                part = Instance.new("Part")
                part.Shape = Enum.PartType.Ball
                part.Size = Vector3.new(diameter, diameter, diameter)
                part.Position = worldPos

            elseif shape == "wedge" then
                local size = element.size
                part = Instance.new("WedgePart")
                part.Size = Vector3.new(size[1], size[2], size[3])
                part.Position = worldPos
            end

            if part then
                part.Name = element.id or shape
                part.Anchored = true

                -- Apply rotation if present (using Orientation property)
                if element.rotation then
                    local rot = element.rotation
                    part.Orientation = Vector3.new(rot[1] or 0, rot[2] or 0, rot[3] or 0)
                end

                -- Apply properties
                if element.Material then
                    local mat = Enum.Material[element.Material]
                    if mat then part.Material = mat end
                end

                if element.Color then
                    local c = element.Color
                    part.Color = Color3.fromRGB(c[1], c[2], c[3])
                end

                if element.Transparency then
                    part.Transparency = element.Transparency
                end

                if element.CanCollide ~= nil then
                    part.CanCollide = element.CanCollide
                end

                part.Parent = mirrorModel
            end
        end
    end

    mirrorModel.Parent = workspace

    print(string.format("[Scanner.mirrorArea] Created mirror '%s' at offset %s (+%d studs gap)",
        mirrorModel.Name, offsetDir, gap))

    return {
        model = mirrorModel,
        config = config,
        cleanup = function()
            if mirrorModel and mirrorModel.Parent then
                mirrorModel:Destroy()
            end
        end,
        refresh = function()
            if mirrorModel and mirrorModel.Parent then
                mirrorModel:Destroy()
            end
            return Scanner.mirrorArea(areaName, container, options)
        end,
    }
end

return Scanner
