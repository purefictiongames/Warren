--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- ValueConverter.ModuleScript
-- Converts shorthand syntax to Roblox types
-- Examples:
--   {0.5, 0, 100, 0} → UDim2.new(0.5, 0, 100, 0)
--   {255, 170, 0} → Color3.fromRGB(255, 170, 0)
--   {0, 12} → UDim.new(0, 12)
--   {0.5, 0.5} → Vector2.new(0.5, 0.5)
--   "Bangers" → Enum.Font.Bangers

local ValueConverter = {}

-- Font name to Enum mapping
local FONT_MAP = {
	-- Common fonts
	Bangers = Enum.Font.Bangers,
	GothamBold = Enum.Font.GothamBold,
	GothamMedium = Enum.Font.GothamMedium,
	Gotham = Enum.Font.Gotham,
	SourceSans = Enum.Font.SourceSans,
	SourceSansBold = Enum.Font.SourceSansBold,
	SourceSansLight = Enum.Font.SourceSansLight,
	SourceSansSemibold = Enum.Font.SourceSansSemibold,
	Roboto = Enum.Font.Roboto,
	RobotoMono = Enum.Font.RobotoMono,
	Ubuntu = Enum.Font.Ubuntu,
	-- Legacy fonts
	Arial = Enum.Font.Arial,
	ArialBold = Enum.Font.ArialBold,
	Legacy = Enum.Font.Legacy,
}

-- Fill direction mapping
local FILL_DIRECTION_MAP = {
	Horizontal = Enum.FillDirection.Horizontal,
	Vertical = Enum.FillDirection.Vertical,
}

-- Horizontal alignment mapping
local HALIGN_MAP = {
	Left = Enum.HorizontalAlignment.Left,
	Center = Enum.HorizontalAlignment.Center,
	Right = Enum.HorizontalAlignment.Right,
}

-- Vertical alignment mapping
local VALIGN_MAP = {
	Top = Enum.VerticalAlignment.Top,
	Center = Enum.VerticalAlignment.Center,
	Bottom = Enum.VerticalAlignment.Bottom,
}

-- Sort order mapping
local SORT_ORDER_MAP = {
	LayoutOrder = Enum.SortOrder.LayoutOrder,
	Name = Enum.SortOrder.Name,
	Custom = Enum.SortOrder.Custom,
}

-- Text alignment mapping
local TEXT_XALIGN_MAP = {
	Left = Enum.TextXAlignment.Left,
	Center = Enum.TextXAlignment.Center,
	Right = Enum.TextXAlignment.Right,
}

local TEXT_YALIGN_MAP = {
	Top = Enum.TextYAlignment.Top,
	Center = Enum.TextYAlignment.Center,
	Bottom = Enum.TextYAlignment.Bottom,
}

-- Scale type mapping
local SCALE_TYPE_MAP = {
	Stretch = Enum.ScaleType.Stretch,
	Tile = Enum.ScaleType.Tile,
	Slice = Enum.ScaleType.Slice,
	Fit = Enum.ScaleType.Fit,
	Crop = Enum.ScaleType.Crop,
}

-- Check if value is an array (sequential table with numeric keys)
local function isArray(t)
	if type(t) ~= "table" then
		return false
	end
	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end
	for i = 1, count do
		if t[i] == nil then
			return false
		end
	end
	return count > 0
end

-- Convert a 4-element array to UDim2
function ValueConverter.toUDim2(value)
	if typeof(value) == "UDim2" then
		return value
	end
	if isArray(value) and #value == 4 then
		return UDim2.new(value[1], value[2], value[3], value[4])
	end
	return nil
end

-- Convert a 2-element array to UDim
function ValueConverter.toUDim(value)
	if typeof(value) == "UDim" then
		return value
	end
	if isArray(value) and #value == 2 then
		return UDim.new(value[1], value[2])
	end
	return nil
end

-- Convert a 2-element array to Vector2
function ValueConverter.toVector2(value)
	if typeof(value) == "Vector2" then
		return value
	end
	if isArray(value) and #value == 2 then
		return Vector2.new(value[1], value[2])
	end
	return nil
end

-- Convert a 3-element array to Vector3
function ValueConverter.toVector3(value)
	if typeof(value) == "Vector3" then
		return value
	end
	if isArray(value) and #value == 3 then
		return Vector3.new(value[1], value[2], value[3])
	end
	return nil
end

-- Convert a 3-element array to Color3 (assumes RGB 0-255)
function ValueConverter.toColor3(value)
	if typeof(value) == "Color3" then
		return value
	end
	if isArray(value) and #value == 3 then
		-- If values are > 1, assume 0-255 range
		if value[1] > 1 or value[2] > 1 or value[3] > 1 then
			return Color3.fromRGB(value[1], value[2], value[3])
		else
			-- 0-1 range
			return Color3.new(value[1], value[2], value[3])
		end
	end
	return nil
end

-- Convert string to Font enum
function ValueConverter.toFont(value)
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		return FONT_MAP[value] or Enum.Font.SourceSans
	end
	return nil
end

-- Convert string to FillDirection enum
function ValueConverter.toFillDirection(value)
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		return FILL_DIRECTION_MAP[value]
	end
	return nil
end

-- Convert string to HorizontalAlignment enum
function ValueConverter.toHorizontalAlignment(value)
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		return HALIGN_MAP[value]
	end
	return nil
end

-- Convert string to VerticalAlignment enum
function ValueConverter.toVerticalAlignment(value)
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		return VALIGN_MAP[value]
	end
	return nil
end

-- Convert string to SortOrder enum
function ValueConverter.toSortOrder(value)
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		return SORT_ORDER_MAP[value]
	end
	return nil
end

-- Convert string to TextXAlignment enum
function ValueConverter.toTextXAlignment(value)
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		return TEXT_XALIGN_MAP[value]
	end
	return nil
end

-- Convert string to TextYAlignment enum
function ValueConverter.toTextYAlignment(value)
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		return TEXT_YALIGN_MAP[value]
	end
	return nil
end

-- Convert string to ScaleType enum
function ValueConverter.toScaleType(value)
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		return SCALE_TYPE_MAP[value]
	end
	return nil
end

-- Property name to converter mapping
-- Maps lowercase property names to their converters
local PROPERTY_CONVERTERS = {
	-- UDim2 properties
	size = ValueConverter.toUDim2,
	position = ValueConverter.toUDim2,
	anchorpoint = ValueConverter.toVector2,

	-- Color properties
	backgroundcolor = ValueConverter.toColor3,
	backgroundcolor3 = ValueConverter.toColor3,
	textcolor = ValueConverter.toColor3,
	textcolor3 = ValueConverter.toColor3,
	textstrokecolor = ValueConverter.toColor3,
	textstrokecolor3 = ValueConverter.toColor3,
	imagecolor = ValueConverter.toColor3,
	imagecolor3 = ValueConverter.toColor3,
	bordercolor = ValueConverter.toColor3,
	bordercolor3 = ValueConverter.toColor3,
	color = ValueConverter.toColor3,

	-- Font
	font = ValueConverter.toFont,

	-- Alignment
	filldirection = ValueConverter.toFillDirection,
	horizontalalignment = ValueConverter.toHorizontalAlignment,
	verticalalignment = ValueConverter.toVerticalAlignment,
	sortorder = ValueConverter.toSortOrder,
	textxalignment = ValueConverter.toTextXAlignment,
	textyalignment = ValueConverter.toTextYAlignment,

	-- UDim properties
	cornerradius = ValueConverter.toUDim,
	padding = ValueConverter.toUDim,

	-- Vector3 properties
	studsoffset = ValueConverter.toVector3,

	-- ScaleType
	scaletype = ValueConverter.toScaleType,
}

-- Normalize property name (lowercase, no underscores)
local function normalizePropertyName(name)
	return name:lower():gsub("_", "")
end

-- Convert a value based on property name
-- Returns converted value, or original if no conversion needed
function ValueConverter.convert(propertyName, value)
	local normalized = normalizePropertyName(propertyName)
	local converter = PROPERTY_CONVERTERS[normalized]

	if converter then
		local converted = converter(value)
		if converted ~= nil then
			return converted
		end
	end

	-- Return original value if no conversion
	return value
end

-- Map shorthand property names to Roblox property names
local PROPERTY_NAME_MAP = {
	size = "Size",
	position = "Position",
	anchorpoint = "AnchorPoint",
	anchor = "AnchorPoint",
	backgroundcolor = "BackgroundColor3",
	bgcolor = "BackgroundColor3",
	backgroundtransparency = "BackgroundTransparency",
	bgtransparency = "BackgroundTransparency",
	textcolor = "TextColor3",
	texttransparency = "TextTransparency",
	textstrokecolor = "TextStrokeColor3",
	textstroketransparency = "TextStrokeTransparency",
	textsize = "TextSize",
	font = "Font",
	text = "Text",
	visible = "Visible",
	zindex = "ZIndex",
	layoutorder = "LayoutOrder",
	name = "Name",
	displayorder = "DisplayOrder",
	resetonspawn = "ResetOnSpawn",
	alwaysontop = "AlwaysOnTop",
	imagecolor = "ImageColor3",
	imagetransparency = "ImageTransparency",
	image = "Image",
	scaletype = "ScaleType",
	textscaled = "TextScaled",
	textwrapped = "TextWrapped",
	textxalignment = "TextXAlignment",
	textyalignment = "TextYAlignment",
	bordercolor = "BorderColor3",
	bordersize = "BorderSizePixel",
	maxvisiblegraphemes = "MaxVisibleGraphemes",
	richtext = "RichText",
	active = "Active",
	clipsdescendants = "ClipsDescendants",
	selectable = "Selectable",
	interactable = "Interactable",
	adornee = "Adornee",
	studsoffset = "StudsOffset",
}

-- Get the Roblox property name from a shorthand name
function ValueConverter.getPropertyName(shorthand)
	local normalized = normalizePropertyName(shorthand)
	return PROPERTY_NAME_MAP[normalized] or shorthand
end

return ValueConverter
