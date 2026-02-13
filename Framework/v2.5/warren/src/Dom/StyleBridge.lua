--[[
    Warren DOM Architecture v2.5
    StyleBridge.lua - DOM-to-Style Resolution Bridge

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Maps semantic palette roles to concrete Instance properties. Given a
    DomNode's classes and attributes, resolves the full set of Instance-ready
    properties through ClassResolver.

    Cave palettes define abstract color roles (wallColor, floorColor, etc.).
    Element role classes (cave-wall, cave-floor, etc.) declare which role
    maps to the Instance's Color property. StyleBridge performs this mapping.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local resolver = StyleBridge.createResolver(Styles)
    Dom.setStyleResolver(resolver)
    -- Now Renderer.mount() resolves styles automatically
    ```
--]]

local StyleBridge = {}

--------------------------------------------------------------------------------
-- COLOR ROLE MAP
--------------------------------------------------------------------------------

-- Maps element role class -> which palette color property to use for Color
local COLOR_ROLE_MAP = {
    ["cave-wall"]           = "wallColor",
    ["cave-ceiling"]        = "wallColor",
    ["cave-floor"]          = "floorColor",
    ["cave-light-fixture"]  = "fixtureColor",
    ["cave-light-spacer"]   = "wallColor",
    ["cave-pad-base"]       = "floorColor",
    ["cave-point-light"]    = "lightColor",
}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function parseClasses(classString)
    if not classString or classString == "" then
        return {}
    end
    local classes = {}
    for c in classString:gmatch("%S+") do
        table.insert(classes, c)
    end
    return classes
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
    Create a style resolver function for use with Dom.setStyleResolver().

    The resolver takes a DomNode and returns a flat table of Instance-ready
    properties, resolved through the cascade:
        base[type] → classes → inline attributes

    Palette color roles are mapped to concrete Color values based on the
    element's role class.

    @param styles table - The Styles.lua stylesheet
    @param ClassResolver table? - ClassResolver module (optional, for DI)
    @return function(node) -> table
]]
function StyleBridge.createResolver(styles, ClassResolver)
    -- Lazy-require ClassResolver if not injected
    if not ClassResolver then
        ClassResolver = require(script.Parent.Parent.ClassResolver)
    end

    -- Reserved keys that should NOT be treated as style properties
    local reservedKeys = {
        id = true,
        class = true,
        type = true,
    }

    return function(node)
        -- Build a definition table ClassResolver can work with
        local definition = {
            type = node._type,
            class = node._classes,
            id = node._id,
        }

        -- Copy inline attributes as potential overrides
        for k, v in pairs(node._attributes) do
            definition[k] = v
        end

        -- Resolve through the cascade
        local resolved = ClassResolver.resolve(definition, styles, {
            reservedKeys = reservedKeys,
        })

        -- Map palette color roles to concrete Color property
        local classList = parseClasses(node._classes)
        local roleKey = nil

        for _, className in ipairs(classList) do
            if COLOR_ROLE_MAP[className] then
                roleKey = COLOR_ROLE_MAP[className]
                break
            end
        end

        -- If the element has a color role, look up the palette color
        if roleKey and resolved[roleKey] and not resolved.Color then
            resolved.Color = resolved[roleKey]
        end

        -- For PointLight: map lightColor to Color if cave-point-light role
        if roleKey == "lightColor" and resolved[roleKey] then
            resolved.Color = resolved[roleKey]
        end

        -- Clean up palette meta-properties (not real Instance properties)
        resolved.wallColor = nil
        resolved.floorColor = nil
        resolved.lightColor = nil
        resolved.fixtureColor = nil

        return resolved
    end
end

--[[
    Resolve palette properties for terrain painting.

    Returns a table with Color3 values for terrain material colors,
    resolved from the palette class.

    @param paletteClass string - Palette class name (e.g., "palette-classic-lava")
    @param styles table - The Styles.lua stylesheet
    @param ClassResolver table? - ClassResolver module (optional)
    @return table - { wallColor = Color3, floorColor = Color3, lightColor = Color3, fixtureColor = Color3 }
]]
function StyleBridge.resolvePalette(paletteClass, styles, ClassResolver)
    if not ClassResolver then
        ClassResolver = require(script.Parent.Parent.ClassResolver)
    end

    local definition = {
        class = paletteClass,
    }

    local resolved = ClassResolver.resolve(definition, styles, {
        reservedKeys = { id = true, class = true, type = true },
    })

    local function toColor3(t)
        if typeof(t) == "Color3" then return t end
        if type(t) == "table" then
            return Color3.fromRGB(t[1] or 0, t[2] or 0, t[3] or 0)
        end
        return Color3.fromRGB(128, 128, 128)
    end

    return {
        wallColor = toColor3(resolved.wallColor),
        floorColor = toColor3(resolved.floorColor),
        lightColor = toColor3(resolved.lightColor),
        fixtureColor = toColor3(resolved.fixtureColor),
    }
end

--[[
    Get the palette class name for a given region number.
    Cycles through the 10 palette classes.

    @param regionNum number - Region number (1-based)
    @return string - Palette class name
]]
function StyleBridge.getPaletteClass(regionNum)
    local PALETTE_NAMES = {
        "palette-classic-lava",
        "palette-blue-inferno",
        "palette-toxic-depths",
        "palette-void-abyss",
        "palette-golden-forge",
        "palette-frozen-fire",
        "palette-blood-sanctum",
        "palette-solar-furnace",
        "palette-nether-realm",
        "palette-spectral-cavern",
    }
    local index = ((regionNum - 1) % #PALETTE_NAMES) + 1
    return PALETTE_NAMES[index]
end

return StyleBridge
