-- ElementFactory.ModuleScript
-- Creates Roblox GUI instances from declarative table definitions
-- Handles type mapping, property conversion, and recursive children

-- After deployment, modules are prefixed: GUI.GUI, GUI.ElementFactory, GUI.ValueConverter
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ValueConverter = require(ReplicatedStorage:WaitForChild("GUI.ValueConverter"))
local StyleResolver = require(ReplicatedStorage:WaitForChild("GUI.StyleResolver"))

local ElementFactory = {}

-- Map declarative type names to Roblox class names
local TYPE_MAP = {
	-- Screen containers
	ScreenGui = "ScreenGui",
	BillboardGui = "BillboardGui",
	SurfaceGui = "SurfaceGui",

	-- Basic elements
	Frame = "Frame",
	TextLabel = "TextLabel",
	TextButton = "TextButton",
	TextBox = "TextBox",
	ImageLabel = "ImageLabel",
	ImageButton = "ImageButton",

	-- Advanced elements
	ScrollingFrame = "ScrollingFrame",
	ViewportFrame = "ViewportFrame",
	CanvasGroup = "CanvasGroup",
	VideoFrame = "VideoFrame",

	-- UI modifiers (handled specially)
	UICorner = "UICorner",
	UIListLayout = "UIListLayout",
	UIGridLayout = "UIGridLayout",
	UIPageLayout = "UIPageLayout",
	UITableLayout = "UITableLayout",
	UIPadding = "UIPadding",
	UIStroke = "UIStroke",
	UIGradient = "UIGradient",
	UIAspectRatioConstraint = "UIAspectRatioConstraint",
	UISizeConstraint = "UISizeConstraint",
	UITextSizeConstraint = "UITextSizeConstraint",
	UIScale = "UIScale",
	UIFlexItem = "UIFlexItem",
}

-- Reserved keys that are not Roblox properties
local RESERVED_KEYS = {
	type = true,
	children = true,
	class = true,
	id = true,
	ref = true,
	actions = true,     -- For Phase 8: built-in actions
	onHover = true,     -- For Phase 7: pseudo-classes
	onActive = true,
	onClick = true,
}

-- Apply a single property to an element
local function applyProperty(element, key, value)
	-- Skip reserved keys
	if RESERVED_KEYS[key] then
		return
	end

	-- Get the Roblox property name
	local propertyName = ValueConverter.getPropertyName(key)

	-- Convert the value to appropriate Roblox type
	local convertedValue = ValueConverter.convert(propertyName, value)

	-- Try to set the property
	local success, err = pcall(function()
		element[propertyName] = convertedValue
	end)

	if not success then
		-- Silently fail for invalid properties in Phase 1
		-- Can add debug logging later
	end
end

-- Apply properties from a table to an element
local function applyProperties(element, properties)
	for key, value in pairs(properties) do
		applyProperty(element, key, value)
	end
end

-- Create a single element from a definition
function ElementFactory.create(definition, styles, guiRef)
	-- Get the element type
	local elementType = definition.type
	if not elementType then
		warn("ElementFactory: definition missing 'type' field")
		return nil
	end

	-- Get the Roblox class name
	local className = TYPE_MAP[elementType] or elementType

	-- Create the instance
	local element = Instance.new(className)

	-- Apply properties from definition
	applyProperties(element, definition)

	-- Store ID for lookup (if GUI reference provided)
	if definition.id and guiRef then
		guiRef._elements[definition.id] = element
	end

	-- Store class attribute on the element for future style updates
	if definition.class then
		element:SetAttribute("guiClass", definition.class)
	end
	if definition.id then
		element:SetAttribute("guiId", definition.id)
	end

	-- Create children recursively
	if definition.children then
		for _, childDef in ipairs(definition.children) do
			local child = ElementFactory.create(childDef, styles, guiRef)
			if child then
				child.Parent = element
			end
		end
	end

	return element
end

-- Create element with styles applied
-- Resolves styles in cascade order: base → class → id → inline
function ElementFactory.createWithStyles(definition, styles, guiRef)
	-- Get the element type
	local elementType = definition.type
	if not elementType then
		warn("ElementFactory: definition missing 'type' field")
		return nil
	end

	-- Get the Roblox class name
	local className = TYPE_MAP[elementType] or elementType

	-- Create the instance
	local element = Instance.new(className)

	-- Resolve styles using cascade order
	local resolvedProps = StyleResolver.resolve(definition, styles)

	-- Apply resolved properties to element
	applyProperties(element, resolvedProps)

	-- Store ID for lookup (if GUI reference provided)
	if definition.id and guiRef then
		guiRef._elements[definition.id] = element
	end

	-- Store class/id attributes on the element for future style updates
	if definition.class then
		element:SetAttribute("guiClass", definition.class)
	end
	if definition.id then
		element:SetAttribute("guiId", definition.id)
	end

	-- Create children recursively (with styles)
	if definition.children then
		for _, childDef in ipairs(definition.children) do
			local child = ElementFactory.createWithStyles(childDef, styles, guiRef)
			if child then
				child.Parent = element
			end
		end
	end

	return element
end

return ElementFactory
