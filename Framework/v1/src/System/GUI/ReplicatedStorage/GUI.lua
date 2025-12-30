-- GUI.ModuleScript
-- Main API module for the declarative GUI system
-- Provides element creation, style management, and element lookup

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- After deployment, modules are prefixed: GUI.GUI, GUI.ElementFactory, GUI.ValueConverter
local ElementFactory = require(ReplicatedStorage:WaitForChild("GUI.ElementFactory"))
local LayoutBuilder = require(ReplicatedStorage:WaitForChild("GUI.LayoutBuilder"))

local GUI = {
	-- Internal state
	_styles = nil,
	_layouts = nil,
	_elements = {},           -- Track elements by ID
	_initialized = false,
	_currentBreakpoint = nil, -- For Phase 5: responsive
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

	return screenGui, regions
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
-- PHASE 2+ STUBS (implemented in later phases)
--------------------------------------------------------------------------------

-- Apply/update class on an element (Phase 9)
function GUI:SetClass(element, newClass)
	-- Stub for Phase 9: Dynamic runtime updates
	element:SetAttribute("guiClass", newClass)
end

-- Add a class to an element (Phase 9)
function GUI:AddClass(element, className)
	-- Stub for Phase 9: Dynamic runtime updates
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
	element:SetAttribute("guiClass", table.concat(classList, " "))
end

-- Remove a class from an element (Phase 9)
function GUI:RemoveClass(element, className)
	-- Stub for Phase 9: Dynamic runtime updates
	local currentClass = element:GetAttribute("guiClass") or ""
	local newClasses = {}
	for class in currentClass:gmatch("%S+") do
		if class ~= className then
			table.insert(newClasses, class)
		end
	end
	element:SetAttribute("guiClass", table.concat(newClasses, " "))
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

-- Toggle a class on an element (Phase 9)
function GUI:ToggleClass(element, className)
	if self:HasClass(element, className) then
		self:RemoveClass(element, className)
	else
		self:AddClass(element, className)
	end
end

return GUI
