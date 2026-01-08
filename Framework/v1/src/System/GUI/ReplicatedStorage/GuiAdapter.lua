--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- GuiAdapter.ModuleScript
-- Domain adapter for Roblox GUI instances
-- Handles GuiObject property conversion and application

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ValueConverter = require(ReplicatedStorage:WaitForChild("GUI.ValueConverter"))
local DomainAdapter = require(ReplicatedStorage:WaitForChild("GUI.DomainAdapter"))

local GuiAdapter = {}

-- Reserved keys that should not be treated as style properties
local RESERVED_KEYS = {
	type = true,
	children = true,
	class = true,
	id = true,
	ref = true,
	actions = true,
	onHover = true,
	onActive = true,
	onClick = true,
	-- UI modifier keys (handled specially)
	cornerRadius = true,
	listLayout = true,
	padding = true,
	stroke = true,
	gradient = true,
	aspectRatio = true,
	-- Z-index (handled specially)
	zIndex = true,
}

-- Property name mapping for dynamic style application
local PROPERTY_MAP = {
	backgroundColor = "BackgroundColor3",
	backgroundTransparency = "BackgroundTransparency",
	textColor = "TextColor3",
	textSize = "TextSize",
	borderColor = "BorderColor3",
	borderSizePixel = "BorderSizePixel",
	size = "Size",
	position = "Position",
	anchorPoint = "AnchorPoint",
	visible = "Visible",
	font = "Font",
	text = "Text",
	image = "Image",
	imageColor = "ImageColor3",
	imageTransparency = "ImageTransparency",
}

--------------------------------------------------------------------------------
-- DOMAIN ADAPTER IMPLEMENTATION
--------------------------------------------------------------------------------

-- Extract node identity information for selector matching
function GuiAdapter.getNodeInfo(node)
	if not node or not node:IsA("Instance") then
		return nil
	end

	-- Get class list from attribute
	local classString = node:GetAttribute("guiClass") or ""
	local classList = {}
	for class in classString:gmatch("%S+") do
		table.insert(classList, class)
	end

	-- Get ID from attribute
	local id = node:GetAttribute("guiId")

	-- Get attributes for selector matching
	local attributes = {}
	for _, attr in ipairs(node:GetAttributes()) do
		attributes[attr] = node:GetAttribute(attr)
	end

	return {
		domain = "gui",
		type = node.ClassName,
		classList = classList,
		id = id,
		attributes = attributes,
		parent = node.Parent,
		children = node:GetChildren(),
	}
end

-- Check if property is supported by GUI domain
function GuiAdapter.supportsProperty(propName)
	-- Reserved keys are not properties
	if RESERVED_KEYS[propName] then
		return false
	end

	-- Check if it's a known GUI property
	local robloxProp = PROPERTY_MAP[propName] or ValueConverter.getPropertyName(propName)

	-- GUI properties we know about (from ValueConverter)
	local guiProps = {
		-- UDim2 properties
		Size = true, Position = true,
		-- Color properties
		BackgroundColor3 = true, TextColor3 = true, ImageColor3 = true,
		TextStrokeColor3 = true, BorderColor3 = true,
		-- Transparency
		BackgroundTransparency = true, TextTransparency = true,
		ImageTransparency = true, TextStrokeTransparency = true,
		-- Text
		Text = true, TextSize = true, Font = true,
		TextXAlignment = true, TextYAlignment = true,
		TextScaled = true, TextWrapped = true, RichText = true,
		-- Other
		Visible = true, ZIndex = true, LayoutOrder = true,
		AnchorPoint = true, BorderSizePixel = true,
		Image = true, ScaleType = true,
		Name = true, DisplayOrder = true,
		Active = true, ClipsDescendants = true,
		Selectable = true, Interactable = true,
		Adornee = true, StudsOffset = true,
	}

	return guiProps[robloxProp] == true
end

-- Convert raw style value to Roblox type
function GuiAdapter.computeProperty(propName, rawValue, node)
	-- Get the Roblox property name
	local propertyName = PROPERTY_MAP[propName] or ValueConverter.getPropertyName(propName)

	-- Use ValueConverter to convert the value
	return ValueConverter.convert(propertyName, rawValue)
end

-- Apply a single property to a GUI element
function GuiAdapter.applyProperty(node, propName, convertedValue)
	-- Skip reserved keys
	if RESERVED_KEYS[propName] then
		return
	end

	-- Get the Roblox property name
	local propertyName = PROPERTY_MAP[propName] or ValueConverter.getPropertyName(propName)

	-- Try to set the property
	pcall(function()
		node[propertyName] = convertedValue
	end)
end

-- Apply UI modifiers (UICorner, UIListLayout, UIPadding, UIStroke, etc.)
local function applyModifiers(element, properties)
	-- UICorner from cornerRadius
	if properties.cornerRadius then
		local corner = Instance.new("UICorner")
		local radius = properties.cornerRadius
		if type(radius) == "table" then
			corner.CornerRadius = ValueConverter.toUDim(radius) or UDim.new(0, 12)
		elseif type(radius) == "number" then
			corner.CornerRadius = UDim.new(0, radius)
		else
			corner.CornerRadius = radius
		end
		corner.Parent = element
	end

	-- UIListLayout from listLayout
	if properties.listLayout then
		local layout = Instance.new("UIListLayout")
		local config = properties.listLayout

		if type(config) == "table" then
			if config.direction then
				layout.FillDirection = ValueConverter.toFillDirection(config.direction) or Enum.FillDirection.Vertical
			end
			if config.hAlign then
				layout.HorizontalAlignment = ValueConverter.toHorizontalAlignment(config.hAlign) or Enum.HorizontalAlignment.Center
			end
			if config.vAlign then
				layout.VerticalAlignment = ValueConverter.toVerticalAlignment(config.vAlign) or Enum.VerticalAlignment.Center
			end
			if config.padding then
				if type(config.padding) == "table" then
					layout.Padding = ValueConverter.toUDim(config.padding) or UDim.new(0, 0)
				elseif type(config.padding) == "number" then
					layout.Padding = UDim.new(0, config.padding)
				else
					layout.Padding = config.padding
				end
			end
			if config.sortOrder then
				layout.SortOrder = ValueConverter.toSortOrder(config.sortOrder) or Enum.SortOrder.LayoutOrder
			end
			if config.wraps ~= nil then
				layout.Wraps = config.wraps
			end
		end

		layout.Parent = element
	end

	-- UIPadding from padding
	if properties.padding then
		local pad = Instance.new("UIPadding")
		local config = properties.padding

		if type(config) == "table" then
			if config.top then
				pad.PaddingTop = type(config.top) == "number" and UDim.new(0, config.top)
					or ValueConverter.toUDim(config.top) or UDim.new(0, 0)
			end
			if config.right then
				pad.PaddingRight = type(config.right) == "number" and UDim.new(0, config.right)
					or ValueConverter.toUDim(config.right) or UDim.new(0, 0)
			end
			if config.bottom then
				pad.PaddingBottom = type(config.bottom) == "number" and UDim.new(0, config.bottom)
					or ValueConverter.toUDim(config.bottom) or UDim.new(0, 0)
			end
			if config.left then
				pad.PaddingLeft = type(config.left) == "number" and UDim.new(0, config.left)
					or ValueConverter.toUDim(config.left) or UDim.new(0, 0)
			end
			if config.all then
				local allPad = type(config.all) == "number" and UDim.new(0, config.all)
					or ValueConverter.toUDim(config.all) or UDim.new(0, 0)
				pad.PaddingTop = allPad
				pad.PaddingRight = allPad
				pad.PaddingBottom = allPad
				pad.PaddingLeft = allPad
			end
		elseif type(config) == "number" then
			local allPad = UDim.new(0, config)
			pad.PaddingTop = allPad
			pad.PaddingRight = allPad
			pad.PaddingBottom = allPad
			pad.PaddingLeft = allPad
		end

		pad.Parent = element
	end

	-- UIStroke from stroke
	if properties.stroke then
		local strokeInst = Instance.new("UIStroke")
		local config = properties.stroke

		if type(config) == "table" then
			if config.color then
				strokeInst.Color = ValueConverter.toColor3(config.color) or Color3.new(1, 1, 1)
			end
			if config.thickness then
				strokeInst.Thickness = config.thickness
			end
			if config.transparency then
				strokeInst.Transparency = config.transparency
			end
			if config.lineJoinMode then
				strokeInst.LineJoinMode = config.lineJoinMode
			end
			if config.applyStrokeMode then
				strokeInst.ApplyStrokeMode = config.applyStrokeMode
			end
		elseif type(config) == "number" then
			strokeInst.Thickness = config
		end

		strokeInst.Parent = element
	end

	-- UIGradient from gradient
	if properties.gradient then
		local grad = Instance.new("UIGradient")
		local config = properties.gradient

		if type(config) == "table" then
			if config.color then
				if typeof(config.color) == "ColorSequence" then
					grad.Color = config.color
				elseif type(config.color) == "table" and #config.color == 2 then
					local c1 = ValueConverter.toColor3(config.color[1]) or Color3.new(1, 1, 1)
					local c2 = ValueConverter.toColor3(config.color[2]) or Color3.new(0, 0, 0)
					grad.Color = ColorSequence.new(c1, c2)
				end
			end
			if config.rotation then
				grad.Rotation = config.rotation
			end
			if config.transparency then
				grad.Transparency = config.transparency
			end
			if config.offset then
				grad.Offset = ValueConverter.toVector2(config.offset) or Vector2.new(0, 0)
			end
		end

		grad.Parent = element
	end

	-- UIAspectRatioConstraint from aspectRatio
	if properties.aspectRatio then
		local aspect = Instance.new("UIAspectRatioConstraint")
		local config = properties.aspectRatio

		if type(config) == "number" then
			aspect.AspectRatio = config
		elseif type(config) == "table" then
			if config.ratio then
				aspect.AspectRatio = config.ratio
			end
			if config.type then
				aspect.AspectType = config.type
			end
			if config.dominantAxis then
				aspect.DominantAxis = config.dominantAxis
			end
		end

		aspect.Parent = element
	end
end

-- Apply zIndex to the appropriate property based on element type
local function applyZIndex(element, properties, elementType)
	if properties.zIndex == nil then
		return
	end

	local zValue = properties.zIndex

	-- ScreenGui, BillboardGui, SurfaceGui use DisplayOrder
	if elementType == "ScreenGui" or elementType == "BillboardGui" or elementType == "SurfaceGui" then
		element.DisplayOrder = zValue
	else
		-- All other GuiObjects use ZIndex
		element.ZIndex = zValue
	end
end

-- Apply all computed styles to a node
function GuiAdapter.applyComputedStyle(node, computedStyle)
	if not node or not computedStyle then
		return
	end

	local elementType = node.ClassName

	-- Apply regular properties
	for key, value in pairs(computedStyle) do
		if not RESERVED_KEYS[key] then
			GuiAdapter.applyProperty(node, key, value)
		end
	end

	-- Apply UI modifiers (UICorner, UIListLayout, etc.)
	applyModifiers(node, computedStyle)

	-- Apply z-index (maps to DisplayOrder for ScreenGui, ZIndex for others)
	applyZIndex(node, computedStyle, elementType)
end

return GuiAdapter
