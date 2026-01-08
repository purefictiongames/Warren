--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- DomainAdapter.ModuleScript
-- Base interface for domain-specific style adapters
-- Each domain (GUI, Asset) implements this interface to handle:
--   - Node identity (for selector matching)
--   - Property support checking
--   - Value conversion
--   - Property application to instances

local DomainAdapter = {}

--[[
    Domain Adapter Interface

    All adapters must implement:

    getNodeInfo(node) -> nodeInfo
        Extract identity information for selector matching
        Returns: {
            domain = "gui" | "asset",
            type = string,              -- ClassName (Frame, Model, BasePart, etc.)
            classList = {string},       -- Array of class names
            id = string | nil,          -- Unique ID
            attributes = {[string] = any}, -- Attribute map
            parent = Instance | nil,
            children = {Instance},
        }

    supportsProperty(propName) -> boolean
        Check if this domain handles the given property name
        Examples: GUI supports "size", "textColor"; Asset supports "position", "rotation"

    computeProperty(propName, rawValue, node) -> convertedValue | nil
        Convert raw style value to Roblox type for this domain
        Returns nil if property not supported or conversion fails
        Examples: {255, 0, 0} -> Color3.fromRGB(255, 0, 0)
                 {0.5, 0, 100, 0} -> UDim2.new(0.5, 0, 100, 0)
                 {10, 20, 30} -> Vector3.new(10, 20, 30)

    applyProperty(node, propName, convertedValue) -> void
        Apply the converted value to the instance
        May involve setting properties, creating child instances (UICorner),
        or complex transforms (CFrame manipulation for assets)

    applyComputedStyle(node, computedStyle) -> void
        Apply all properties from a computed style table
        Called after style resolution cascade completes
--]]

-- Create a new domain adapter instance
-- @param implementation: Table with required methods
-- @return: DomainAdapter instance
function DomainAdapter.new(implementation)
    local adapter = {}

    -- Validate required methods
    local requiredMethods = {
        "getNodeInfo",
        "supportsProperty",
        "computeProperty",
        "applyProperty",
        "applyComputedStyle"
    }

    for _, methodName in ipairs(requiredMethods) do
        if not implementation[methodName] then
            error("DomainAdapter: missing required method '" .. methodName .. "'")
        end
        adapter[methodName] = implementation[methodName]
    end

    return adapter
end

return DomainAdapter
