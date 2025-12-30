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
-- @param breakpoint: Optional current breakpoint name (e.g., "tablet", "phone")
-- @return: Merged properties table
function StyleResolver.resolve(definition, styles, breakpoint)
	local resolved = {}

	-- Safety check
	if not styles then
		return extractInlineStyles(definition)
	end

	-- 1. Apply base styles (by element type)
	local elementType = definition.type
	if elementType and styles.base then
		-- Base style
		if styles.base[elementType] then
			merge(resolved, styles.base[elementType])
		end
		-- Responsive base style (e.g., TextLabel@tablet)
		if breakpoint then
			local responsiveKey = elementType .. "@" .. breakpoint
			if styles.base[responsiveKey] then
				merge(resolved, styles.base[responsiveKey])
			end
		end
	end

	-- 2. Apply class styles (in order from class attribute)
	if definition.class then
		local classList = parseClasses(definition.class)
		for _, className in ipairs(classList) do
			if styles.classes then
				-- Base class style
				if styles.classes[className] then
					merge(resolved, styles.classes[className])
				end
				-- Responsive class style (e.g., hud-text@tablet)
				if breakpoint then
					local responsiveKey = className .. "@" .. breakpoint
					if styles.classes[responsiveKey] then
						merge(resolved, styles.classes[responsiveKey])
					end
				end
			end
		end
	end

	-- 3. Apply ID styles
	if definition.id and styles.ids then
		-- Base ID style
		if styles.ids[definition.id] then
			merge(resolved, styles.ids[definition.id])
		end
		-- Responsive ID style (e.g., score@tablet)
		if breakpoint then
			local responsiveKey = definition.id .. "@" .. breakpoint
			if styles.ids[responsiveKey] then
				merge(resolved, styles.ids[responsiveKey])
			end
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
