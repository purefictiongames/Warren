-- GUI.ModuleScript
-- Main API module for the declarative GUI system
-- Provides element creation, style management, and element lookup

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- After deployment, modules are prefixed: GUI.GUI, GUI.ElementFactory, GUI.ValueConverter
local ElementFactory = require(ReplicatedStorage:WaitForChild("GUI.ElementFactory"))
local LayoutBuilder = require(ReplicatedStorage:WaitForChild("GUI.LayoutBuilder"))
local StyleResolver = require(ReplicatedStorage:WaitForChild("GUI.StyleResolver"))
local ValueConverter = require(ReplicatedStorage:WaitForChild("GUI.ValueConverter"))

local GUI = {
	-- Internal state
	_styles = nil,
	_layouts = nil,
	_elements = {},           -- Track elements by ID
	_initialized = false,
	_currentBreakpoint = nil, -- Current breakpoint name (desktop/tablet/phone)
	_breakpointCallbacks = {}, -- Callbacks for breakpoint changes
}

--------------------------------------------------------------------------------
-- STYLE LOADING
--------------------------------------------------------------------------------

-- Load styles from ReplicatedFirst (lazy, cached)
function GUI:_loadStyles()
	if self._styles then
		return self._styles
	end

	local success, styles = pcall(function()
		-- GUI folder is deployed to ReplicatedFirst via Rojo
		local guiFolder = ReplicatedFirst:FindFirstChild("GUI")
		if guiFolder then
			local stylesModule = guiFolder:FindFirstChild("Styles")
			if stylesModule then
				return require(stylesModule)
			end
		end
		return nil
	end)

	if success and styles then
		self._styles = styles
	else
		-- Fallback: empty styles
		self._styles = {
			base = {},
			classes = {},
			ids = {},
		}
	end

	return self._styles
end

-- Load layouts from ReplicatedFirst (lazy, cached)
function GUI:_loadLayouts()
	if self._layouts then
		return self._layouts
	end

	local success, layouts = pcall(function()
		local guiFolder = ReplicatedFirst:FindFirstChild("GUI")
		if guiFolder then
			local layoutsModule = guiFolder:FindFirstChild("Layouts")
			if layoutsModule then
				return require(layoutsModule)
			end
		end
		return nil
	end)

	if success and layouts then
		self._layouts = layouts
	else
		-- Fallback: empty layouts
		self._layouts = {
			breakpoints = { desktop = 1200, tablet = 768, phone = 0 },
		}
	end

	return self._layouts
end

--------------------------------------------------------------------------------
-- RESPONSIVE BREAKPOINTS
--------------------------------------------------------------------------------

-- Get breakpoint name for a given viewport size
function GUI:_getBreakpointForSize(width, height)
	local layouts = self:_loadLayouts()
	local breakpoints = layouts.breakpoints or { desktop = 1200, tablet = 768, phone = 0 }
	local aspectRatio = width / height

	-- Sort breakpoints by threshold descending (for width-based)
	local sorted = {}
	for name, config in pairs(breakpoints) do
		-- Support both simple format (desktop = 1200) and table format (desktop = { minWidth = 1200 })
		local threshold = type(config) == "number" and config or (config.minWidth or 0)
		table.insert(sorted, {
			name = name,
			threshold = threshold,
			config = type(config) == "table" and config or { minWidth = config }
		})
	end
	table.sort(sorted, function(a, b) return a.threshold > b.threshold end)

	-- Find matching breakpoint (must satisfy all conditions)
	for _, bp in ipairs(sorted) do
		local config = bp.config
		local matches = true

		-- Check minWidth
		if config.minWidth and width < config.minWidth then
			matches = false
		end

		-- Check maxWidth
		if config.maxWidth and width > config.maxWidth then
			matches = false
		end

		-- Check minAspect (width/height ratio)
		if config.minAspect and aspectRatio < config.minAspect then
			matches = false
		end

		-- Check maxAspect
		if config.maxAspect and aspectRatio > config.maxAspect then
			matches = false
		end

		if matches then
			return bp.name
		end
	end

	return "phone"  -- Default fallback
end

-- Get current breakpoint name
function GUI:GetBreakpoint()
	return self._currentBreakpoint or "desktop"
end

-- Update breakpoint based on viewport size
-- Returns true if breakpoint changed
function GUI:_updateBreakpoint(width, height)
	local newBreakpoint = self:_getBreakpointForSize(width, height or width)

	if newBreakpoint ~= self._currentBreakpoint then
		local oldBreakpoint = self._currentBreakpoint
		self._currentBreakpoint = newBreakpoint

		-- Fire callbacks
		for _, callback in ipairs(self._breakpointCallbacks) do
			task.spawn(callback, newBreakpoint, oldBreakpoint)
		end

		return true
	end

	return false
end

-- Register a callback for breakpoint changes
-- @param callback: function(newBreakpoint, oldBreakpoint)
function GUI:OnBreakpointChanged(callback)
	table.insert(self._breakpointCallbacks, callback)
end

-- Get breakpoint-aware style key
-- e.g., "hud-text" at tablet breakpoint checks for "hud-text@tablet" first
function GUI:_getResponsiveStyleKey(baseKey, breakpoint)
	return baseKey .. "@" .. breakpoint
end

--------------------------------------------------------------------------------
-- ELEMENT CREATION
--------------------------------------------------------------------------------

-- Create a GUI element from a declarative table definition
-- @param definition: Table with type, properties, and optional children
-- @return: Roblox GUI instance
function GUI:Create(definition)
	self:_loadStyles()

	local element = ElementFactory.createWithStyles(definition, self._styles, self)

	return element
end

-- Create multiple elements and return them in a table
-- @param definitions: Array of definition tables
-- @return: Array of Roblox GUI instances
function GUI:CreateMany(definitions)
	local elements = {}
	for i, definition in ipairs(definitions) do
		elements[i] = self:Create(definition)
	end
	return elements
end

--------------------------------------------------------------------------------
-- LAYOUT CREATION
--------------------------------------------------------------------------------

-- Active layouts tracking (layoutName -> { screenGui, regions })
GUI._activeLayouts = {}

-- Create a layout from a named layout definition
-- @param layoutName: Name of layout in Layouts.lua (e.g., "hud")
-- @param content: Table mapping region IDs to content definitions
-- @return: ScreenGui instance
function GUI:CreateLayout(layoutName, content)
	self:_loadStyles()
	self:_loadLayouts()

	-- Get layout definition
	local layoutDef = self._layouts[layoutName]
	if not layoutDef then
		warn("GUI: Layout not found:", layoutName)
		return nil
	end

	-- Build the layout structure
	local screenGui, regions = LayoutBuilder.build(layoutDef, layoutName)

	-- Assign content to regions
	if content then
		for regionId, contentDef in pairs(content) do
			local region = regions[regionId]
			if region then
				LayoutBuilder.assignContent(region, contentDef, self, self._styles)
			else
				warn("GUI: Region not found in layout:", regionId)
			end
		end
	end

	-- Store regions for later access
	screenGui:SetAttribute("layoutName", layoutName)

	-- Register as active layout
	self._activeLayouts[layoutName] = {
		screenGui = screenGui,
		regions = regions,
	}

	return screenGui, regions
end

-- Get a region frame from an active layout
-- Allows modular assets to place themselves in layout regions
-- @param layoutName: Name of the active layout
-- @param regionId: ID of the region within the layout
-- @return: Frame (region container) or nil if not found
function GUI:GetRegion(layoutName, regionId)
	local layout = self._activeLayouts[layoutName]
	if not layout then
		return nil
	end
	return layout.regions[regionId]
end

-- Check if a layout is active
-- @param layoutName: Name of the layout to check
-- @return: boolean
function GUI:HasLayout(layoutName)
	return self._activeLayouts[layoutName] ~= nil
end

-- Place content into a layout region
-- Handles alignment from region attributes and applies styles
-- @param layoutName: Name of the active layout
-- @param regionId: ID of the region within the layout
-- @param content: Definition table or Instance to place
-- @return: The created/placed element, or nil if region not found
function GUI:PlaceInRegion(layoutName, regionId, content)
	local region = self:GetRegion(layoutName, regionId)
	if not region then
		return nil
	end

	self:_loadStyles()
	return LayoutBuilder.assignContent(region, content, self, self._styles)
end

-- Create a layout from an inline definition (not from Layouts.lua)
-- @param layoutDef: Layout definition table with rows/columns
-- @param content: Table mapping region IDs to content definitions
-- @param name: Optional name for the ScreenGui
-- @return: ScreenGui instance
function GUI:CreateLayoutFromDef(layoutDef, content, name)
	self:_loadStyles()

	-- Build the layout structure
	local screenGui, regions = LayoutBuilder.build(layoutDef, name or "CustomLayout")

	-- Assign content to regions
	if content then
		for regionId, contentDef in pairs(content) do
			local region = regions[regionId]
			if region then
				LayoutBuilder.assignContent(region, contentDef, self, self._styles)
			else
				warn("GUI: Region not found in layout:", regionId)
			end
		end
	end

	return screenGui, regions
end

--------------------------------------------------------------------------------
-- ELEMENT LOOKUP
--------------------------------------------------------------------------------

-- Get an element by its ID
-- @param id: String ID assigned during creation
-- @return: Roblox GUI instance or nil
function GUI:GetById(id)
	return self._elements[id]
end

-- Get all elements with a specific class
-- @param className: String class name to search for
-- @return: Array of Roblox GUI instances
function GUI:GetByClass(className)
	local matches = {}
	for _, element in pairs(self._elements) do
		local elementClass = element:GetAttribute("guiClass")
		if elementClass then
			-- Check if class list contains the target class
			for class in elementClass:gmatch("%S+") do
				if class == className then
					table.insert(matches, element)
					break
				end
			end
		end
	end
	return matches
end

-- Register an element by ID (internal use)
function GUI:_registerElement(id, element)
	self._elements[id] = element
end

-- Unregister an element by ID (internal use)
function GUI:_unregisterElement(id)
	self._elements[id] = nil
end

--------------------------------------------------------------------------------
-- UTILITY METHODS
--------------------------------------------------------------------------------

-- Check if the GUI system is initialized
function GUI:IsInitialized()
	return self._initialized
end

-- Initialize the GUI system (called by client script)
function GUI:Initialize()
	if self._initialized then
		return
	end

	self:_loadStyles()
	self:_loadLayouts()

	self._initialized = true
end

-- Get current styles (for debugging/inspection)
function GUI:GetStyles()
	return self:_loadStyles()
end

-- Get current layouts (for debugging/inspection)
function GUI:GetLayouts()
	return self:_loadLayouts()
end

--------------------------------------------------------------------------------
-- DYNAMIC RUNTIME UPDATES (Phase 9)
--------------------------------------------------------------------------------

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

-- Apply a resolved style property to an element
local function applyStyleProperty(element, key, value)
	local propertyName = PROPERTY_MAP[key] or ValueConverter.getPropertyName(key)
	local convertedValue = ValueConverter.convert(propertyName, value)

	pcall(function()
		element[propertyName] = convertedValue
	end)
end

-- Recompute and apply styles based on current class/id
-- @param element: The GuiObject
-- @param newClass: Optional new class string (uses current if nil)
function GUI:_reapplyStyles(element, newClass)
	if not self._styles then
		return
	end

	-- Get element type from ClassName
	local elementType = element.ClassName

	-- Build a minimal definition for style resolution
	local definition = {
		type = elementType,
		class = newClass or element:GetAttribute("guiClass"),
		id = element:GetAttribute("guiId"),
	}

	-- Resolve styles with current breakpoint
	local resolved = StyleResolver.resolve(definition, self._styles, self._currentBreakpoint)

	-- Apply resolved properties to element
	for key, value in pairs(resolved) do
		applyStyleProperty(element, key, value)
	end
end

-- Apply/update class on an element (replaces all classes)
function GUI:SetClass(element, newClass)
	element:SetAttribute("guiClass", newClass)
	self:_reapplyStyles(element, newClass)
end

-- Add a class to an element
function GUI:AddClass(element, className)
	local currentClass = element:GetAttribute("guiClass") or ""
	local classes = {}
	for class in currentClass:gmatch("%S+") do
		classes[class] = true
	end
	classes[className] = true

	local classList = {}
	for class in pairs(classes) do
		table.insert(classList, class)
	end
	local newClass = table.concat(classList, " ")
	element:SetAttribute("guiClass", newClass)
	self:_reapplyStyles(element, newClass)
end

-- Remove a class from an element
function GUI:RemoveClass(element, className)
	local currentClass = element:GetAttribute("guiClass") or ""
	local newClasses = {}
	for class in currentClass:gmatch("%S+") do
		if class ~= className then
			table.insert(newClasses, class)
		end
	end
	local newClass = table.concat(newClasses, " ")
	element:SetAttribute("guiClass", newClass)
	self:_reapplyStyles(element, newClass)
end

-- Check if element has a class (utility)
function GUI:HasClass(element, className)
	local currentClass = element:GetAttribute("guiClass") or ""
	for class in currentClass:gmatch("%S+") do
		if class == className then
			return true
		end
	end
	return false
end

-- Toggle a class on an element
function GUI:ToggleClass(element, className)
	if self:HasClass(element, className) then
		self:RemoveClass(element, className)
	else
		self:AddClass(element, className)
	end
end

-- Refresh all tracked elements (useful after breakpoint change if needed)
function GUI:RefreshStyles()
	for id, element in pairs(self._elements) do
		if element and element.Parent then
			self:_reapplyStyles(element)
		end
	end
end

return GUI
