--[[
    LibPureFiction Framework v2
    MapLayout/BoundsValidator.lua - Geometry Bounds Validation

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    BoundsValidator ensures all geometry stays within defined area bounds.
    If any geometry exceeds bounds, it produces detailed error messages and
    causes the build to fail. The game should NOT run with broken geometry.

    Validation happens BEFORE geometry is created, so errors are caught early
    with clear messages about what needs to be fixed.

    ============================================================================
    ERROR FORMAT
    ============================================================================

    Errors include:
    - Which area contains the violation
    - Which element (by ID or index) is invalid
    - What specifically is out of bounds (position, endpoint, dimension)
    - The actual value vs. the allowed bounds
    - Suggestions for fixing

    Example:
    ```
    [MapLayout] BOUNDS VIOLATION in area 'libraryHallway':
      Element: wall 'northWall'
      Problem: Endpoint exceeds area width
      Value: X = 25
      Bounds: 0 to 20 (width)
      Fix: Reduce wall length or increase area bounds
    ```

--]]

local BoundsValidator = {}

-- Validation result accumulator
local ValidationResult = {}
ValidationResult.__index = ValidationResult

function ValidationResult.new(areaId)
    return setmetatable({
        areaId = areaId,
        errors = {},
        warnings = {},
        isValid = true,
    }, ValidationResult)
end

function ValidationResult:addError(elementType, elementId, problem, value, boundsInfo, suggestion)
    self.isValid = false
    table.insert(self.errors, {
        elementType = elementType,
        elementId = elementId or "(unnamed)",
        problem = problem,
        value = value,
        boundsInfo = boundsInfo,
        suggestion = suggestion,
    })
end

function ValidationResult:addWarning(message)
    table.insert(self.warnings, message)
end

function ValidationResult:merge(other)
    for _, err in ipairs(other.errors) do
        table.insert(self.errors, err)
    end
    for _, warn in ipairs(other.warnings) do
        table.insert(self.warnings, warn)
    end
    if not other.isValid then
        self.isValid = false
    end
end

function ValidationResult:format()
    if self.isValid then
        return nil
    end

    local lines = {
        string.format("[MapLayout] BOUNDS VALIDATION FAILED for area '%s':", self.areaId),
        string.format("  Found %d error(s):", #self.errors),
        "",
    }

    for i, err in ipairs(self.errors) do
        table.insert(lines, string.format("  --- Error %d ---", i))
        table.insert(lines, string.format("  Element: %s '%s'", err.elementType, err.elementId))
        table.insert(lines, string.format("  Problem: %s", err.problem))
        table.insert(lines, string.format("  Value: %s", tostring(err.value)))
        table.insert(lines, string.format("  Bounds: %s", err.boundsInfo))
        if err.suggestion then
            table.insert(lines, string.format("  Fix: %s", err.suggestion))
        end
        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

--[[
    Check if a 2D point is within XZ bounds.

    @param x: X coordinate
    @param z: Z coordinate
    @param bounds: {width, height, depth}
    @param originOffset: Vector3 offset from corner to origin
    @return: isValid, violationType, violationAxis
--]]
local function checkPoint2D(x, z, bounds, originOffset)
    local minX = -originOffset.X
    local maxX = bounds[1] - originOffset.X
    local minZ = -originOffset.Z
    local maxZ = bounds[3] - originOffset.Z

    if x < minX then
        return false, "below minimum", "X", x, minX
    elseif x > maxX then
        return false, "exceeds maximum", "X", x, maxX
    end

    if z < minZ then
        return false, "below minimum", "Z", z, minZ
    elseif z > maxZ then
        return false, "exceeds maximum", "Z", z, maxZ
    end

    return true
end

--[[
    Check if a 3D point is within bounds.

    @param x, y, z: Coordinates
    @param bounds: {width, height, depth}
    @param originOffset: Vector3 offset
    @return: isValid, violationType, axis, value, limit
--]]
local function checkPoint3D(x, y, z, bounds, originOffset)
    local minX = -originOffset.X
    local maxX = bounds[1] - originOffset.X
    local minY = -originOffset.Y
    local maxY = bounds[2] - originOffset.Y
    local minZ = -originOffset.Z
    local maxZ = bounds[3] - originOffset.Z

    if x < minX then
        return false, "below minimum", "X", x, minX
    elseif x > maxX then
        return false, "exceeds maximum", "X", x, maxX
    end

    if y < minY then
        return false, "below minimum", "Y", y, minY
    elseif y > maxY then
        return false, "exceeds maximum", "Y", y, maxY
    end

    if z < minZ then
        return false, "below minimum", "Z", z, minZ
    elseif z > maxZ then
        return false, "exceeds maximum", "Z", z, maxZ
    end

    return true
end

--[[
    Format bounds info for error message.
--]]
local function formatBoundsInfo(axis, bounds, originOffset)
    local min, max
    if axis == "X" then
        min = -originOffset.X
        max = bounds[1] - originOffset.X
    elseif axis == "Y" then
        min = -originOffset.Y
        max = bounds[2] - originOffset.Y
    else -- Z
        min = -originOffset.Z
        max = bounds[3] - originOffset.Z
    end
    return string.format("%s: %.2f to %.2f", axis, min, max)
end

--[[
    Validate a wall element.

    @param wall: Wall definition
    @param index: Element index (for unnamed elements)
    @param bounds: Area bounds
    @param originOffset: Origin offset
    @param result: ValidationResult to add errors to
--]]
local function validateWall(wall, index, bounds, originOffset, result)
    local id = wall.id or string.format("#%d", index)

    -- Check 'from' point (if it's a literal, not a reference)
    if wall.from and type(wall.from) == "table" and type(wall.from[1]) == "number" then
        local x, z = wall.from[1], wall.from[2]
        local valid, vType, axis, val, limit = checkPoint2D(x, z, bounds, originOffset)
        if not valid then
            result:addError(
                "wall", id,
                string.format("'from' point %s %s", axis, vType),
                string.format("%s = %.2f (limit: %.2f)", axis, val, limit),
                formatBoundsInfo(axis, bounds, originOffset),
                "Adjust wall start position or increase area bounds"
            )
        end
    end

    -- Check 'to' point
    if wall.to and type(wall.to) == "table" and type(wall.to[1]) == "number" then
        local x, z = wall.to[1], wall.to[2]
        local valid, vType, axis, val, limit = checkPoint2D(x, z, bounds, originOffset)
        if not valid then
            result:addError(
                "wall", id,
                string.format("'to' point %s %s", axis, vType),
                string.format("%s = %.2f (limit: %.2f)", axis, val, limit),
                formatBoundsInfo(axis, bounds, originOffset),
                "Adjust wall end position or increase area bounds"
            )
        end
    end

    -- Check height
    if wall.height then
        local maxY = bounds[2] - originOffset.Y
        if wall.height > bounds[2] then
            result:addError(
                "wall", id,
                "Height exceeds area height",
                string.format("height = %.2f", wall.height),
                string.format("Y: 0 to %.2f (area height)", bounds[2]),
                "Reduce wall height or increase area bounds"
            )
        end
    end
end

--[[
    Validate a platform/box element.
--]]
local function validatePlatform(platform, index, bounds, originOffset, result)
    local id = platform.id or string.format("#%d", index)

    if platform.position and type(platform.position) == "table" and type(platform.position[1]) == "number" then
        local pos = platform.position
        local size = platform.size or {1, 1, 1}
        if type(size) == "table" then
            size = {size[1] or 1, size[2] or 1, size[3] or size[2] or 1}
        else
            size = {size, size, size}
        end

        -- Check all corners of the bounding box
        local halfSize = {size[1] / 2, size[2] / 2, size[3] / 2}
        local corners = {
            {pos[1] - halfSize[1], pos[2] - halfSize[2], pos[3] - halfSize[3]},
            {pos[1] + halfSize[1], pos[2] + halfSize[2], pos[3] + halfSize[3]},
        }

        for _, corner in ipairs(corners) do
            local valid, vType, axis, val, limit = checkPoint3D(
                corner[1], corner[2], corner[3],
                bounds, originOffset
            )
            if not valid then
                result:addError(
                    "platform", id,
                    string.format("Bounding box %s %s", axis, vType),
                    string.format("%s = %.2f (limit: %.2f)", axis, val, limit),
                    formatBoundsInfo(axis, bounds, originOffset),
                    "Adjust position/size or increase area bounds"
                )
                break  -- Only report first violation per element
            end
        end
    end
end

--[[
    Validate a floor element.
--]]
local function validateFloor(floor, index, bounds, originOffset, result)
    local id = floor.id or string.format("#%d", index)

    if floor.position and type(floor.position) == "table" and type(floor.position[1]) == "number" then
        local pos = floor.position
        local size = floor.size or {1, 1}
        if type(size) == "table" then
            size = {size[1] or 1, size[2] or 1}
        else
            size = {size, size}
        end

        local thickness = floor.thickness or 0.5
        local halfX = size[1] / 2
        local halfZ = size[2] / 2

        -- Check floor corners (XZ plane)
        local corners = {
            {pos[1] - halfX, pos[3] - halfZ},
            {pos[1] + halfX, pos[3] + halfZ},
        }

        for _, corner in ipairs(corners) do
            local valid, vType, axis, val, limit = checkPoint2D(
                corner[1], corner[2],
                bounds, originOffset
            )
            if not valid then
                result:addError(
                    "floor", id,
                    string.format("Bounding box %s %s", axis, vType),
                    string.format("%s = %.2f (limit: %.2f)", axis, val, limit),
                    formatBoundsInfo(axis, bounds, originOffset),
                    "Adjust floor position/size or increase area bounds"
                )
                break
            end
        end
    end
end

--[[
    Validate a cylinder element.
--]]
local function validateCylinder(cyl, index, bounds, originOffset, result)
    local id = cyl.id or string.format("#%d", index)

    if cyl.position and type(cyl.position) == "table" and type(cyl.position[1]) == "number" then
        local pos = cyl.position
        local radius = cyl.radius or 2
        local height = cyl.height or 4

        -- Check bounding box of cylinder
        local corners = {
            {pos[1] - radius, pos[2] - height/2, pos[3] - radius},
            {pos[1] + radius, pos[2] + height/2, pos[3] + radius},
        }

        for _, corner in ipairs(corners) do
            local valid, vType, axis, val, limit = checkPoint3D(
                corner[1], corner[2], corner[3],
                bounds, originOffset
            )
            if not valid then
                result:addError(
                    "cylinder", id,
                    string.format("Bounding box %s %s", axis, vType),
                    string.format("%s = %.2f (limit: %.2f)", axis, val, limit),
                    formatBoundsInfo(axis, bounds, originOffset),
                    "Adjust position/radius/height or increase area bounds"
                )
                break
            end
        end
    end
end

--[[
    Validate a sphere element.
--]]
local function validateSphere(sphere, index, bounds, originOffset, result)
    local id = sphere.id or string.format("#%d", index)

    if sphere.position and type(sphere.position) == "table" and type(sphere.position[1]) == "number" then
        local pos = sphere.position
        local radius = sphere.radius or 2

        -- Check bounding box of sphere
        local corners = {
            {pos[1] - radius, pos[2] - radius, pos[3] - radius},
            {pos[1] + radius, pos[2] + radius, pos[3] + radius},
        }

        for _, corner in ipairs(corners) do
            local valid, vType, axis, val, limit = checkPoint3D(
                corner[1], corner[2], corner[3],
                bounds, originOffset
            )
            if not valid then
                result:addError(
                    "sphere", id,
                    string.format("Bounding box %s %s", axis, vType),
                    string.format("%s = %.2f (limit: %.2f)", axis, val, limit),
                    formatBoundsInfo(axis, bounds, originOffset),
                    "Adjust position/radius or increase area bounds"
                )
                break
            end
        end
    end
end

--[[
    Validate all geometry in an area definition.

    @param areaId: Area identifier for error messages
    @param areaDef: Area definition with bounds and geometry
    @param originOffset: Vector3 origin offset (or nil to calculate)
    @return: ValidationResult
--]]
function BoundsValidator.validate(areaId, areaDef, originOffset)
    local result = ValidationResult.new(areaId)

    if not areaDef.bounds then
        result:addError("area", areaId, "Missing bounds definition", "nil", "bounds = {width, height, depth}", "Add bounds to area definition")
        return result
    end

    local bounds = areaDef.bounds
    originOffset = originOffset or Vector3.new(0, 0, 0)

    -- Validate walls
    if areaDef.walls then
        for i, wall in ipairs(areaDef.walls) do
            validateWall(wall, i, bounds, originOffset, result)
        end
    end

    -- Validate platforms
    if areaDef.platforms then
        for i, platform in ipairs(areaDef.platforms) do
            validatePlatform(platform, i, bounds, originOffset, result)
        end
    end

    -- Validate boxes (same as platforms)
    if areaDef.boxes then
        for i, box in ipairs(areaDef.boxes) do
            validatePlatform(box, i, bounds, originOffset, result)
        end
    end

    -- Validate floors
    if areaDef.floors then
        for i, floor in ipairs(areaDef.floors) do
            validateFloor(floor, i, bounds, originOffset, result)
        end
    end

    -- Validate cylinders
    if areaDef.cylinders then
        for i, cyl in ipairs(areaDef.cylinders) do
            validateCylinder(cyl, i, bounds, originOffset, result)
        end
    end

    -- Validate spheres
    if areaDef.spheres then
        for i, sphere in ipairs(areaDef.spheres) do
            validateSphere(sphere, i, bounds, originOffset, result)
        end
    end

    -- Validate nested areas (recursively)
    if areaDef.areas then
        for i, nestedArea in ipairs(areaDef.areas) do
            local nestedId = nestedArea.id or string.format("%s/area#%d", areaId, i)
            if nestedArea.bounds then
                -- Nested area has its own bounds - validate recursively
                local nestedOriginOffset = Vector3.new(0, 0, 0)  -- Will be calculated based on nested origin
                local nestedResult = BoundsValidator.validate(nestedId, nestedArea, nestedOriginOffset)
                result:merge(nestedResult)
            end

            -- Also check that nested area position is within parent bounds
            if nestedArea.position and type(nestedArea.position) == "table" then
                local pos = nestedArea.position
                local nestedBounds = nestedArea.bounds or {0, 0, 0}

                -- Check if nested area fits within parent
                local corners = {
                    {pos[1], pos[2], pos[3]},
                    {pos[1] + nestedBounds[1], pos[2] + nestedBounds[2], pos[3] + nestedBounds[3]},
                }

                for _, corner in ipairs(corners) do
                    local valid, vType, axis, val, limit = checkPoint3D(
                        corner[1], corner[2], corner[3],
                        bounds, originOffset
                    )
                    if not valid then
                        result:addError(
                            "nested area", nestedId,
                            string.format("Nested area %s %s parent bounds", axis, vType),
                            string.format("%s = %.2f (limit: %.2f)", axis, val, limit),
                            formatBoundsInfo(axis, bounds, originOffset),
                            "Adjust nested area position or increase parent bounds"
                        )
                        break
                    end
                end
            end
        end
    end

    return result
end

--[[
    Validate and throw if invalid.
    This is the main entry point - call this before building.

    @param areaId: Area identifier
    @param areaDef: Area definition
    @param originOffset: Optional origin offset
    @throws: Error with detailed message if validation fails
--]]
function BoundsValidator.validateOrThrow(areaId, areaDef, originOffset)
    local result = BoundsValidator.validate(areaId, areaDef, originOffset)

    if not result.isValid then
        local errorMsg = result:format()
        error(errorMsg, 2)
    end

    return true
end

--[[
    Create a new ValidationResult for manual validation.
--]]
function BoundsValidator.createResult(areaId)
    return ValidationResult.new(areaId)
end

return BoundsValidator
