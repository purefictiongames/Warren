--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Debug.ModuleScript (Shared)
-- Centralized debug logging system with configurable filtering
-- Should be initialized before any other modules

local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Debug = {}

-- Configuration state
local _config = nil
local _initialized = false

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Default fallback config
local DEFAULT_CONFIG = {
	priorityThreshold = "Info",
	categories = {},
	filter = { enabled = {}, disabled = {} }
}

--[[
    Initialize the Debug system by loading configuration.
    Should be called early in the boot process, before other modules.
--]]
function Debug:Initialize()
	if _initialized then
		return
	end

	_initialized = true

	local success, config = pcall(function()
		local configModule = ReplicatedFirst:FindFirstChild("System")
		if configModule then
			local debugConfig = configModule:FindFirstChild("DebugConfig")
			if debugConfig then
				return require(debugConfig)
			end
		end
		return nil
	end)

	if success and config then
		_config = config
		print("[Debug] Initialized - Priority:", config.priorityThreshold or "Info")
	else
		_config = DEFAULT_CONFIG
		warn("[Debug] Using fallback config (DebugConfig not found)")
	end
end

-- Get config (lazy initialize if needed)
local function getConfig()
	if not _initialized then
		Debug:Initialize()
	end
	return _config or DEFAULT_CONFIG
end

--------------------------------------------------------------------------------
-- FILTERING LOGIC
--------------------------------------------------------------------------------

-- Glob pattern matching (supports * for any sequence)
local function matchesGlob(str, pattern)
	local luaPattern = pattern
		:gsub("([%.%+%-%^%$%(%)%%])", "%%%1")  -- Escape magic chars
		:gsub("%*", ".*")                       -- * -> .*
	luaPattern = "^" .. luaPattern .. "$"       -- Anchor pattern

	return str:match(luaPattern) ~= nil
end

-- Categorize source into a category
local function categorizeSource(source)
	-- System core
	if source == "System" or source == "System.System" or source == "System.Script" or source == "System.client" then
		return "System"
	end

	-- Subsystems (System.X where X is not Script/System/client)
	if source:match("^System%.") then
		return "Subsystems"
	end

	-- Special categories
	if source:match("^RunModes") then
		return "RunModes"
	end

	if source:match("^Tutorial") then
		return "Tutorial"
	end

	if source:match("^Input") then
		return "Input"
	end

	-- Default: Assets (anything else)
	return "Assets"
end

-- Check if source should be logged based on priority and category
local function shouldLog(source, priority)
	local config = getConfig()

	-- Priority check (higher priority always shows)
	local priorityLevels = { Critical = 3, Info = 2, Verbose = 1 }
	local threshold = config.priorityThreshold or "Info"
	local messagePriority = priorityLevels[priority] or 2
	local thresholdPriority = priorityLevels[threshold] or 2

	if messagePriority < thresholdPriority then
		return false
	end

	-- Advanced filter check (overrides category filtering)
	local filter = config.filter or {}
	local enabled = filter.enabled or {}
	local disabled = filter.disabled or {}

	-- Check enabled list first (if match, ALLOW)
	for _, pattern in ipairs(enabled) do
		if matchesGlob(source, pattern) then
			return true
		end
	end

	-- Check disabled list second (if match, BLOCK)
	for _, pattern in ipairs(disabled) do
		if matchesGlob(source, pattern) then
			return false
		end
	end

	-- Category filtering
	local category = categorizeSource(source)
	local categories = config.categories or {}

	-- If category is explicitly set, use that value
	-- Otherwise default to true (enabled)
	if categories[category] ~= nil then
		return categories[category]
	end

	return true
end

--------------------------------------------------------------------------------
-- OUTPUT FORMATTING
--------------------------------------------------------------------------------

-- Format arguments for output
local function formatArgs(...)
	local args = {...}
	local parts = {}
	for i, v in ipairs(args) do
		parts[i] = tostring(v)
	end
	return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- LOGGING METHODS
--------------------------------------------------------------------------------

--[[
    Critical - Always shown unless explicitly filtered
    Use for: bootstrap messages, errors, important system events
--]]
function Debug:Critical(source, ...)
	if shouldLog(source, "Critical") then
		print(source .. ":", formatArgs(...))
	end
end

--[[
    Message - Regular info-level output
    Use for: normal operational messages
--]]
function Debug:Message(source, ...)
	if shouldLog(source, "Info") then
		print(source .. ":", formatArgs(...))
	end
end

--[[
    Verbose - Detailed debug output (only at Verbose threshold)
    Use for: detailed debugging, step-by-step traces
--]]
function Debug:Verbose(source, ...)
	if shouldLog(source, "Verbose") then
		print(source .. ":", formatArgs(...))
	end
end

--[[
    Warn - Warning output (Critical priority)
    Use for: non-fatal issues, deprecation notices
--]]
function Debug:Warn(source, ...)
	if shouldLog(source, "Critical") then
		warn(source .. ":", formatArgs(...))
	end
end

--[[
    Alert - Error/alert output (Critical priority, prefixed with [ALERT])
    Use for: serious errors, failures
--]]
function Debug:Alert(source, ...)
	if shouldLog(source, "Critical") then
		warn("[ALERT] " .. source .. ":", formatArgs(...))
	end
end

return Debug
