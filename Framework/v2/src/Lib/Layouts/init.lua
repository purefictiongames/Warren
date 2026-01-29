--[[
    LibPureFiction Framework v2
    Layouts - Standalone Map Geometry Definitions

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This folder contains standalone map/zone layouts created with the
    GeometrySpec scanner. Each layout is a ModuleScript that returns a
    table with name and spec:

        return {
            name = "MyZone",
            spec = { bounds, parts, classes, ... }
        }

    For node component geometry, define specs inline in the component's
    config file for portability.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Lib = require(game.ReplicatedStorage.Lib)

    -- Access a layout by name
    local layout = Lib.Layouts.DefenseZone

    -- Build it (returns a Part container with child geometry)
    local container = Lib.GeometrySpec.build(layout)
    ```

    ============================================================================
    CREATING LAYOUTS
    ============================================================================

    1. Create a Part in Studio - this defines the bounding area
    2. Name the Part (e.g., "DefenseZone") - this becomes the layout name
    3. Add attribute: GeometrySpecTag = "area"
    4. Add child parts for geometry (rough placement is fine)
    5. Run scanner:
       ```lua
       local Lib = require(game.ReplicatedStorage.Lib)
       Lib.GeometrySpec.scanArea("DefenseZone")
       ```
    6. Copy output into: Lib/Layouts/DefenseZone.lua
    7. Fine-tune values and apply classes as needed

--]]

local Layouts = {}

-- Cache for loaded layouts
local cache = {}

-- Lazy loader: require layout on first access
setmetatable(Layouts, {
    __index = function(_, name)
        -- Check cache first
        if cache[name] then
            return cache[name]
        end

        -- Try to require the layout
        local layoutModule = script:FindFirstChild(name)
        if layoutModule then
            local spec = require(layoutModule)
            cache[name] = spec
            return spec
        end

        -- Not found
        warn("[Layouts] Layout not found: " .. tostring(name))
        return nil
    end,
})

--[[
    Get all available layout names.

    @return: Array of layout name strings
--]]
function Layouts.list()
    local names = {}
    for _, child in ipairs(script:GetChildren()) do
        if child:IsA("ModuleScript") then
            table.insert(names, child.Name)
        end
    end
    table.sort(names)
    return names
end

--[[
    Check if a layout exists.

    @param name: Layout name
    @return: boolean
--]]
function Layouts.has(name)
    return script:FindFirstChild(name) ~= nil
end

--[[
    Clear the layout cache. Forces re-require on next access.
--]]
function Layouts.clearCache()
    cache = {}
end

--[[
    Preload all layouts into cache.
    Use sparingly - lazy loading is usually preferred.
--]]
function Layouts.preloadAll()
    for _, child in ipairs(script:GetChildren()) do
        if child:IsA("ModuleScript") then
            cache[child.Name] = require(child)
        end
    end
end

return Layouts
