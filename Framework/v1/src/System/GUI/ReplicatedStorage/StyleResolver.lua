-- StyleResolver.ModuleScript
-- Resolves styles for an element using CSS-like cascade order:
--   1. Base styles (by element type)
--   2. Class styles (in order of class attribute string)
--   3. ID styles
--   4. Inline styles (properties in definition)
--
-- Later styles override earlier ones (cascade)

local StyleResolver = {}

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
}

-- Deep merge two tables (source into target)
-- Later values override earlier ones
local function merge(target, source)
	if not source then
		return target
	end

	for key, value in pairs(source) do
		target[key] = value
	end

	return target
end

-- Parse class string into array of class names
-- "hud-text gold centered" → {"hud-text", "gold", "centered"}
local function parseClasses(classString)
	if not classString or classString == "" then
		return {}
	end

	local classes = {}
	for class in classString:gmatch("%S+") do
		table.insert(classes, class)
	end
	return classes
end

-- Extract inline styles from definition (non-reserved keys)
local function extractInlineStyles(definition)
	local inline = {}

	for key, value in pairs(definition) do
		if not RESERVED_KEYS[key] then
			inline[key] = value
		end
	end

	return inline
end

-- Resolve all styles for a definition
-- @param definition: The element definition table
-- @param styles: The stylesheet { base = {}, classes = {}, ids = {} }
-- @return: Merged properties table
function StyleResolver.resolve(definition, styles)
	local resolved = {}

	-- Safety check
	if not styles then
		return extractInlineStyles(definition)
	end

	-- 1. Apply base styles (by element type)
	local elementType = definition.type
	if elementType and styles.base and styles.base[elementType] then
		merge(resolved, styles.base[elementType])
	end

	-- 2. Apply class styles (in order from class attribute)
	if definition.class then
		local classList = parseClasses(definition.class)
		for _, className in ipairs(classList) do
			if styles.classes and styles.classes[className] then
				merge(resolved, styles.classes[className])
			end
		end
	end

	-- 3. Apply ID styles
	if definition.id then
		if styles.ids and styles.ids[definition.id] then
			merge(resolved, styles.ids[definition.id])
		end
	end

	-- 4. Apply inline styles (highest priority)
	local inlineStyles = extractInlineStyles(definition)
	merge(resolved, inlineStyles)

	return resolved
end

-- Check if a definition has a specific class
function StyleResolver.hasClass(definition, className)
	if not definition.class then
		return false
	end

	for class in definition.class:gmatch("%S+") do
		if class == className then
			return true
		end
	end

	return false
end

-- Get all classes from a definition as an array
function StyleResolver.getClasses(definition)
	return parseClasses(definition.class)
end

return StyleResolver
