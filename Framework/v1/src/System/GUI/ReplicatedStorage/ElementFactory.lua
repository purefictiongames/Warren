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
	-- UI modifier keys (handled specially)
	cornerRadius = true,
	listLayout = true,
	padding = true,
	stroke = true,
	gradient = true,
	aspectRatio = true,
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

-- Apply UI modifiers (UICorner, UIListLayout, UIPadding, UIStroke, etc.)
local function applyModifiers(element, properties)
	-- UICorner from cornerRadius
	if properties.cornerRadius then
		local corner = Instance.new("UICorner")
		local radius = properties.cornerRadius
		-- Support shorthand: {0, 12} or just 12
		if type(radius) == "table" then
			corner.CornerRadius = ValueConverter.toUDim(radius) or UDim.new(0, 12)
		elseif type(radius) == "number" then
			corner.CornerRadius = UDim.new(0, radius)
		else
			corner.CornerRadius = radius  -- Already a UDim
		end
		corner.Parent = element
	end

	-- UIListLayout from listLayout
	if properties.listLayout then
		local layout = Instance.new("UIListLayout")
		local config = properties.listLayout

		if type(config) == "table" then
			-- Direction
			if config.direction then
				layout.FillDirection = ValueConverter.toFillDirection(config.direction) or Enum.FillDirection.Vertical
			end
			-- Horizontal alignment
			if config.hAlign then
				layout.HorizontalAlignment = ValueConverter.toHorizontalAlignment(config.hAlign) or Enum.HorizontalAlignment.Center
			end
			-- Vertical alignment
			if config.vAlign then
				layout.VerticalAlignment = ValueConverter.toVerticalAlignment(config.vAlign) or Enum.VerticalAlignment.Center
			end
			-- Padding
			if config.padding then
				if type(config.padding) == "table" then
					layout.Padding = ValueConverter.toUDim(config.padding) or UDim.new(0, 0)
				elseif type(config.padding) == "number" then
					layout.Padding = UDim.new(0, config.padding)
				else
					layout.Padding = config.padding
				end
			end
			-- Sort order
			if config.sortOrder then
				layout.SortOrder = ValueConverter.toSortOrder(config.sortOrder) or Enum.SortOrder.LayoutOrder
			end
			-- Wraps
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
			-- Support {top, right, bottom, left} or {top = ..., left = ...}
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
			-- Support uniform padding: padding = { all = 10 }
			if config.all then
				local allPad = type(config.all) == "number" and UDim.new(0, config.all)
					or ValueConverter.toUDim(config.all) or UDim.new(0, 0)
				pad.PaddingTop = allPad
				pad.PaddingRight = allPad
				pad.PaddingBottom = allPad
				pad.PaddingLeft = allPad
			end
		elseif type(config) == "number" then
			-- Uniform padding shorthand: padding = 10
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
			-- Shorthand: stroke = 2 means thickness 2
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
				-- Expect ColorSequence or create from two colors
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

	-- Get current breakpoint from GUI ref (if available)
	local breakpoint = nil
	if guiRef and guiRef.GetBreakpoint then
		breakpoint = guiRef:GetBreakpoint()
	end

	-- Resolve styles using cascade order (with responsive breakpoint)
	local resolvedProps = StyleResolver.resolve(definition, styles, breakpoint)

	-- Apply resolved properties to element
	applyProperties(element, resolvedProps)

	-- Apply UI modifiers (UICorner, UIListLayout, etc.)
	applyModifiers(element, resolvedProps)

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
