--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- StyleEngine.ModuleScript
-- Unified style resolution and application engine
-- Works with domain adapters (GUI, Asset) to apply styles
--
-- Resolution order (cascade): base → class (in order) → id → inline
-- Domain-agnostic: selector matching and cascade work the same for all domains

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StyleResolver = require(ReplicatedStorage:WaitForChild("GUI.StyleResolver"))

local StyleEngine = {}

--------------------------------------------------------------------------------
-- STYLE RESOLUTION (Domain-Agnostic)
--------------------------------------------------------------------------------

-- Resolve styles for a node using its identity info
-- Uses existing StyleResolver logic (unchanged cascade algorithm)
-- @param nodeInfo: Node identity from adapter.getNodeInfo()
-- @param styles: Stylesheet table { base = {}, classes = {}, ids = {} }
-- @param breakpoint: Optional responsive breakpoint name
-- @return: Computed style properties table
function StyleEngine.Resolve(nodeInfo, styles, breakpoint)
	if not nodeInfo or not styles then
		return {}
	end

	-- Build a definition table for StyleResolver (uses existing code)
	local definition = {
		type = nodeInfo.type,
		class = table.concat(nodeInfo.classList, " "),
		id = nodeInfo.id,
	}

	-- Use existing StyleResolver (same cascade algorithm)
	return StyleResolver.resolve(definition, styles, breakpoint)
end

--------------------------------------------------------------------------------
-- STYLE APPLICATION (Domain-Specific via Adapter)
--------------------------------------------------------------------------------

-- Apply styles to a single node
-- @param node: Roblox Instance (GuiObject, Model, BasePart, etc.)
-- @param styles: Stylesheet table
-- @param adapter: Domain adapter (GuiAdapter or AssetAdapter)
-- @param breakpoint: Optional responsive breakpoint name
-- @param inlineStyles: Optional inline style overrides
function StyleEngine.ApplyNode(node, styles, adapter, breakpoint, inlineStyles)
	if not node or not adapter then
		return
	end

	-- Get node identity from adapter
	local nodeInfo = adapter.getNodeInfo(node)
	if not nodeInfo then
		return
	end

	-- Resolve computed style (cascade)
	local computedStyle = StyleEngine.Resolve(nodeInfo, styles, breakpoint)

	-- Merge inline style overrides (highest priority)
	if inlineStyles then
		for key, value in pairs(inlineStyles) do
			computedStyle[key] = value
		end
	end

	-- Filter properties: only keep those supported by this domain
	local filteredStyle = {}
	for propName, value in pairs(computedStyle) do
		if adapter.supportsProperty(propName) then
			-- Compute the property value
			local convertedValue = adapter.computeProperty(propName, value, node)
			if convertedValue ~= nil then
				filteredStyle[propName] = convertedValue
			end
		end
	end

	-- Apply computed style via adapter
	adapter.applyComputedStyle(node, filteredStyle)
end

-- Apply styles to an entire tree (node + all descendants)
-- @param rootNode: Root instance to start from
-- @param styles: Stylesheet table
-- @param adapter: Domain adapter
-- @param breakpoint: Optional responsive breakpoint name
-- @param inlineStyles: Optional inline styles for root node only
function StyleEngine.ApplyTree(rootNode, styles, adapter, breakpoint, inlineStyles)
	if not rootNode or not adapter then
		return
	end

	-- Apply to root node
	StyleEngine.ApplyNode(rootNode, styles, adapter, breakpoint, inlineStyles)

	-- Recursively apply to descendants
	for _, child in ipairs(rootNode:GetDescendants()) do
		-- Each descendant gets its own style resolution (no inline styles)
		StyleEngine.ApplyNode(child, styles, adapter, breakpoint)
	end
end

return StyleEngine
