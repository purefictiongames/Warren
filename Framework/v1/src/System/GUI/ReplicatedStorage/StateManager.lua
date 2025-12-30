-- StateManager.ModuleScript
-- Handles pseudo-class states (:hover, :active, :disabled)
-- Wires up event handlers and applies/reverts style changes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ValueConverter = require(ReplicatedStorage:WaitForChild("GUI.ValueConverter"))

local StateManager = {}

-- Track original styles for revert
-- Structure: { [element] = { [propertyName] = originalValue, ... } }
local originalStyles = {}

-- Property name mapping for style application
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
}

-- Apply a style property to an element
local function applyStyleProperty(element, key, value)
	local propertyName = PROPERTY_MAP[key] or ValueConverter.getPropertyName(key)
	local convertedValue = ValueConverter.convert(propertyName, value)

	local success, err = pcall(function()
		element[propertyName] = convertedValue
	end)

	return success
end

-- Save original style values before applying pseudo-class styles
local function saveOriginalStyles(element, styleProps)
	if not originalStyles[element] then
		originalStyles[element] = {}
	end

	for key, _ in pairs(styleProps) do
		local propertyName = PROPERTY_MAP[key] or ValueConverter.getPropertyName(key)

		-- Only save if we haven't already (don't overwrite with hover value when activating active)
		if originalStyles[element][propertyName] == nil then
			local success, value = pcall(function()
				return element[propertyName]
			end)
			if success then
				originalStyles[element][propertyName] = value
			end
		end
	end
end

-- Restore original style values
local function restoreOriginalStyles(element, styleProps)
	if not originalStyles[element] then
		return
	end

	for key, _ in pairs(styleProps) do
		local propertyName = PROPERTY_MAP[key] or ValueConverter.getPropertyName(key)
		local originalValue = originalStyles[element][propertyName]

		if originalValue ~= nil then
			pcall(function()
				element[propertyName] = originalValue
			end)
		end
	end
end

-- Apply pseudo-class styles to an element
local function applyPseudoStyles(element, styleProps)
	saveOriginalStyles(element, styleProps)

	for key, value in pairs(styleProps) do
		applyStyleProperty(element, key, value)
	end
end

-- Revert pseudo-class styles
local function revertPseudoStyles(element, styleProps)
	restoreOriginalStyles(element, styleProps)
end

-- Clear saved original styles for an element
local function clearOriginalStyles(element)
	originalStyles[element] = nil
end

-- Get pseudo-class styles from stylesheet
-- @param styles: The stylesheet { classes = {...}, ids = {...} }
-- @param className: The base class name (e.g., "btn")
-- @param pseudoClass: The pseudo-class (e.g., "hover", "active")
-- @return: Style properties table or nil
local function getPseudoClassStyles(styles, className, pseudoClass)
	if not styles or not styles.classes then
		return nil
	end

	local pseudoKey = className .. ":" .. pseudoClass
	return styles.classes[pseudoKey]
end

-- Get pseudo-class ID styles from stylesheet
local function getPseudoIdStyles(styles, id, pseudoClass)
	if not styles or not styles.ids then
		return nil
	end

	local pseudoKey = id .. ":" .. pseudoClass
	return styles.ids[pseudoKey]
end

-- Collect all pseudo-class styles for an element
-- @param definition: Element definition with class/id
-- @param styles: The stylesheet
-- @param pseudoClass: The pseudo-class name
-- @return: Merged style properties table
local function collectPseudoStyles(definition, styles, pseudoClass)
	local collected = {}

	-- Collect from classes
	if definition.class then
		for className in definition.class:gmatch("%S+") do
			local pseudoStyles = getPseudoClassStyles(styles, className, pseudoClass)
			if pseudoStyles then
				for key, value in pairs(pseudoStyles) do
					collected[key] = value
				end
			end
		end
	end

	-- Collect from ID (higher priority)
	if definition.id then
		local pseudoStyles = getPseudoIdStyles(styles, definition.id, pseudoClass)
		if pseudoStyles then
			for key, value in pairs(pseudoStyles) do
				collected[key] = value
			end
		end
	end

	-- Return nil if no styles collected
	if next(collected) == nil then
		return nil
	end

	return collected
end

-- Wire up pseudo-class event handlers for an element
-- @param element: The Roblox GuiObject
-- @param definition: The element definition
-- @param styles: The stylesheet
function StateManager.wire(element, definition, styles)
	-- Skip if no styles or element doesn't support mouse events
	if not styles then
		return
	end

	-- Check if element is a GuiObject (has mouse events)
	if not element:IsA("GuiObject") then
		return
	end

	-- Track state
	local isHovered = false
	local isActive = false
	local isDisabled = false

	-- Collect pseudo-class styles
	local hoverStyles = collectPseudoStyles(definition, styles, "hover")
	local activeStyles = collectPseudoStyles(definition, styles, "active")
	local disabledStyles = collectPseudoStyles(definition, styles, "disabled")

	-- Skip if no pseudo-class styles defined
	if not hoverStyles and not activeStyles and not disabledStyles then
		return
	end

	-- Function to update visual state based on current flags
	local function updateVisualState()
		-- Priority: disabled > active > hover > normal
		if isDisabled and disabledStyles then
			applyPseudoStyles(element, disabledStyles)
		elseif isActive and activeStyles then
			applyPseudoStyles(element, activeStyles)
		elseif isHovered and hoverStyles then
			applyPseudoStyles(element, hoverStyles)
		else
			-- Revert to original (need to revert all pseudo styles)
			if disabledStyles then revertPseudoStyles(element, disabledStyles) end
			if activeStyles then revertPseudoStyles(element, activeStyles) end
			if hoverStyles then revertPseudoStyles(element, hoverStyles) end
		end
	end

	-- Wire hover events
	if hoverStyles then
		element.MouseEnter:Connect(function()
			isHovered = true
			updateVisualState()
		end)

		element.MouseLeave:Connect(function()
			isHovered = false
			isActive = false  -- Also clear active when mouse leaves
			updateVisualState()
		end)
	end

	-- Wire active events (mouse down/up)
	if activeStyles then
		element.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or
			   input.UserInputType == Enum.UserInputType.Touch then
				isActive = true
				updateVisualState()
			end
		end)

		element.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or
			   input.UserInputType == Enum.UserInputType.Touch then
				isActive = false
				updateVisualState()
			end
		end)
	end

	-- Store reference for cleanup
	element.Destroying:Connect(function()
		clearOriginalStyles(element)
	end)

	-- Store disabled state manager function on element for external control
	element:SetAttribute("__hasStateManager", true)
end

-- Set disabled state on an element
-- @param element: The GuiObject
-- @param disabled: Boolean
-- @param definition: Original definition (needed for styles)
-- @param styles: The stylesheet
function StateManager.setDisabled(element, disabled, definition, styles)
	if not element:IsA("GuiObject") then
		return
	end

	local disabledStyles = collectPseudoStyles(definition, styles, "disabled")
	if not disabledStyles then
		return
	end

	if disabled then
		applyPseudoStyles(element, disabledStyles)
	else
		revertPseudoStyles(element, disabledStyles)
	end

	-- Store state as attribute for reference
	element:SetAttribute("guiDisabled", disabled)
end

return StateManager
