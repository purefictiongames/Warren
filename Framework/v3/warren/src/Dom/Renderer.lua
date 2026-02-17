--[[
    Warren DOM Architecture v2.5
    Renderer.lua - DOM-to-Instance Materializer

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Maps DOM nodes to Roblox Instances. When a node is mounted, the Renderer
    creates the corresponding Instance, applies attributes, and parents it.
    Attribute changes on mounted nodes sync immediately.

    Type registry maps DOM types to Roblox classes.
    Property map handles conversions (table -> Vector3, table -> Color3, etc.).

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    Renderer.mount(node, parentInstance)   -- Create Instance, recurse children
    Renderer.unmount(node)                 -- Destroy Instance bottom-up
    Renderer.applyAttribute(node, key, val) -- Update single property
    Renderer.applyAllAttributes(node)      -- Full re-apply (after style change)
    ```
--]]

local Renderer = {}

--------------------------------------------------------------------------------
-- TYPE REGISTRY: DOM type -> Roblox ClassName
--------------------------------------------------------------------------------

local TYPE_MAP = {
    Part = "Part",
    WedgePart = "WedgePart",
    CornerWedgePart = "CornerWedgePart",
    TrussPart = "TrussPart",
    Model = "Model",
    Folder = "Folder",
    SpawnLocation = "SpawnLocation",
    PointLight = "PointLight",
    SpotLight = "SpotLight",
    Sound = "Sound",
}

--------------------------------------------------------------------------------
-- PROPERTY MAP: Attribute key -> conversion function
--------------------------------------------------------------------------------

local function toVector3(t)
    if typeof(t) == "Vector3" then return t end
    if type(t) == "table" then
        return Vector3.new(t[1] or 0, t[2] or 0, t[3] or 0)
    end
    return nil
end

local function toColor3(t)
    if typeof(t) == "Color3" then return t end
    if type(t) == "table" then
        return Color3.fromRGB(t[1] or 0, t[2] or 0, t[3] or 0)
    end
    return nil
end

local function toMaterial(str)
    if typeof(str) == "EnumItem" then return str end
    if type(str) == "string" then
        return Enum.Material[str] or Enum.Material.SmoothPlastic
    end
    return nil
end

-- Properties that need conversion
local CONVERTERS = {
    Size = toVector3,
    Position = toVector3,
    Color = toColor3,
    Material = toMaterial,
}

-- Properties that pass through directly (no conversion needed)
local PASSTHROUGH = {
    Transparency = true,
    Anchored = true,
    CanCollide = true,
    CanTouch = true,
    CanQuery = true,
    CFrame = true,
    Orientation = true,
    Brightness = true,
    Range = true,
    Angle = true,
    Shadows = true,
    Name = true,
    Neutral = true,
}

--------------------------------------------------------------------------------
-- STYLE RESOLVER (optional, set externally)
--------------------------------------------------------------------------------

-- StyleBridge.resolve function, set by Dom/init when StyleBridge is available
Renderer._styleResolver = nil

--[[
    Set the style resolver function.
    Called as: resolver(node) -> table of resolved properties
]]
function Renderer.setStyleResolver(fn)
    Renderer._styleResolver = fn
end

--------------------------------------------------------------------------------
-- PROPERTY APPLICATION
--------------------------------------------------------------------------------

--[[
    Apply a single key/value to a Roblox Instance.
    Handles conversion and falls back to SetAttribute for unknown keys.

    @param instance Instance - Target Roblox Instance
    @param key string - Property/attribute name
    @param value any - Value to set
]]
local function applyProperty(instance, key, value)
    if value == nil then return end

    -- Check converter
    local converter = CONVERTERS[key]
    if converter then
        local converted = converter(value)
        if converted ~= nil then
            instance[key] = converted
        end
        return
    end

    -- Check passthrough
    if PASSTHROUGH[key] then
        instance[key] = value
        return
    end

    -- Skip internal/metadata keys
    if key == "Name" then
        instance.Name = value
        return
    end

    -- Unknown key -> Instance attribute
    local ok = pcall(function()
        instance:SetAttribute(key, value)
    end)
    -- Silently ignore attribute failures (e.g., unsupported types)
end

--[[
    Get resolved properties for a node.
    If a style resolver is set, uses it. Otherwise uses raw attributes.

    @param node table - DomNode
    @return table - Resolved properties
]]
local function getResolvedProperties(node)
    if Renderer._styleResolver then
        return Renderer._styleResolver(node)
    end
    -- No style resolver: use raw attributes
    return node._attributes
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
    Mount a DOM node, creating a real Roblox Instance.
    Recursively mounts children.

    @param node table - DomNode to mount
    @param parentInstance Instance - Parent Roblox Instance
]]
function Renderer.mount(node, parentInstance)
    local className = TYPE_MAP[node._type]
    if not className then
        -- Unknown type (e.g., Fragment) — skip creating instance, still recurse
        node._mounted = true
        for _, child in ipairs(node._children) do
            Renderer.mount(child, parentInstance)
        end
        return
    end

    -- Create the Roblox Instance
    local instance = Instance.new(className)

    -- Apply name from attributes or generate from type + id
    local props = getResolvedProperties(node)
    if props.Name then
        instance.Name = props.Name
    else
        instance.Name = node._type .. "_" .. node._id
    end

    -- Apply all resolved properties
    for key, value in pairs(props) do
        if key ~= "Name" then
            applyProperty(instance, key, value)
        end
    end

    -- Store backing instance on node
    node._instance = instance
    node._mounted = true

    -- Parent the instance (do this after setting properties for efficiency)
    instance.Parent = parentInstance

    -- Recurse children
    for _, child in ipairs(node._children) do
        Renderer.mount(child, instance)
    end
end

--[[
    Unmount a DOM node, destroying its Roblox Instance.
    Works bottom-up to avoid parent destruction issues.

    @param node table - DomNode to unmount
]]
function Renderer.unmount(node)
    -- Recurse children first (bottom-up)
    for _, child in ipairs(node._children) do
        Renderer.unmount(child)
    end

    -- Destroy the Instance
    if node._instance then
        node._instance:Destroy()
        node._instance = nil
    end

    node._mounted = false
end

--[[
    Apply a single attribute change to a mounted node's Instance.

    @param node table - DomNode (must be mounted)
    @param key string - Attribute key
    @param value any - New value
]]
function Renderer.applyAttribute(node, key, value)
    if not node._mounted or not node._instance then
        return
    end
    applyProperty(node._instance, key, value)
end

--[[
    Re-apply all resolved properties to a mounted node.
    Used after style class changes (addClass/removeClass).

    @param node table - DomNode (must be mounted)
]]
function Renderer.applyAllAttributes(node)
    if not node._mounted or not node._instance then
        return
    end

    local props = getResolvedProperties(node)
    for key, value in pairs(props) do
        applyProperty(node._instance, key, value)
    end
end

--[[
    Reparent a mounted node's Instance under a new parent Instance.

    @param node table - DomNode (must be mounted)
    @param newParentInstance Instance - New parent
]]
function Renderer.reparent(node, newParentInstance)
    if node._instance and newParentInstance then
        node._instance.Parent = newParentInstance
    end
end

return Renderer
