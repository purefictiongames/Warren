--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- System.ModuleScript (Shared)
-- Central module providing boot stage constants and wait helpers
-- Scripts can optionally use this to wait for stages, or continue using WaitForChild

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local System = {
	-- Boot stages (in order)
	Stages = {
		SYNC        = 1,  -- Assets cloned to RuntimeAssets, folders extracted
		EVENTS      = 2,  -- All BindableEvents/RemoteEvents created and registered
		MODULES     = 3,  -- ModuleScripts deployed and requireable
		SCRIPTS     = 4,  -- Server scripts load, assets register init functions
		ASSETS      = 5,  -- All registered asset init() functions called
		ORCHESTRATE = 6,  -- Orchestrator applies initial mode config
		READY       = 7,  -- Full boot complete, clients can interact
	},

	-- Internal state
	_currentStage = 0,
	_stageEvent = nil,  -- BindableEvent for stage transitions
	_isClient = RunService:IsClient(),
	_registeredAssets = {},  -- [name] = { init = fn, initialized = bool }
}

-- Initialize event reference (called lazily on first use)
function System:_ensureEvent()
	if self._stageEvent then
		return
	end

	-- Wait for the boot stage event to be deployed
	self._stageEvent = ReplicatedStorage:WaitForChild("System.BootStage", 30)

	if not self._stageEvent then
		System.Debug:Warn("System", "BootStage event not found, boot system may not be initialized")
	end
end

-- Wait for a specific boot stage to be reached
-- Yields the calling thread until the stage is reached
function System:WaitForStage(stage)
	self:_ensureEvent()

	-- If already at or past the requested stage, return immediately
	if self._currentStage >= stage then
		return
	end

	-- Wait for stage transitions until we reach the requested stage
	while self._currentStage < stage do
		if self._stageEvent then
			self._stageEvent.Event:Wait()
		else
			-- Fallback: poll if event not available
			task.wait(0.1)
		end
	end
end

-- Get the current boot stage
function System:GetCurrentStage()
	return self._currentStage
end

-- Get the name of a stage for debugging
function System:GetStageName(stage)
	for name, value in pairs(self.Stages) do
		if value == stage then
			return name
		end
	end
	return "UNKNOWN"
end

-- Check if a stage has been reached (non-blocking)
function System:IsStageReached(stage)
	return self._currentStage >= stage
end

-- Internal: Set the current stage (called by System.Script on server)
function System:_setStage(stage)
	self._currentStage = stage
	System.Debug:Message("System", "Stage", self:GetStageName(stage), "(" .. stage .. ")")

	if self._stageEvent then
		self._stageEvent:Fire(stage)
	end
end

--------------------------------------------------------------------------------
-- ASSET REGISTRATION (Deferred Initialization Pattern)
--------------------------------------------------------------------------------

--[[
    Register an asset's init function for deferred initialization.
    Called by asset scripts during SCRIPTS stage.
    Init functions are called during ASSETS stage.

    @param name string - Asset name (e.g., "Dispenser", "GlobalTimer")
    @param initFn function - Initialization function that creates Enable/Disable/etc.
--]]
function System:RegisterAsset(name, initFn)
	if self._registeredAssets[name] then
		System.Debug:Warn("System", "Asset already registered:", name)
		return
	end

	self._registeredAssets[name] = {
		init = initFn,
		initialized = false,
	}

	System.Debug:Message("System", "Asset registered:", name)
end

--[[
    Initialize all registered assets.
    Called by System.Script during ASSETS stage.
--]]
function System:_initializeAssets()
	local count = 0
	for name, asset in pairs(self._registeredAssets) do
		if not asset.initialized then
			System.Debug:Message("System", "Initializing asset:", name)
			local success, err = pcall(asset.init)
			if success then
				asset.initialized = true
				count = count + 1
			else
				System.Debug:Warn("System", "Asset init failed:", name, "-", err)
			end
		end
	end
	System.Debug:Message("System", "Initialized", count, "assets")
end

--[[
    Check if an asset is registered.
    @param name string - Asset name
    @return boolean
--]]
function System:IsAssetRegistered(name)
	return self._registeredAssets[name] ~= nil
end

--[[
    Get list of registered asset names.
    @return table - Array of asset names
--]]
function System:GetRegisteredAssets()
	local names = {}
	for name in pairs(self._registeredAssets) do
		table.insert(names, name)
	end
	return names
end

-- Internal: Update stage from client ping-pong response
function System:_updateFromServer(stage)
	if stage > self._currentStage then
		self._currentStage = stage

		-- Fire event to wake up any waiting client scripts
		if self._stageEvent then
			self._stageEvent:Fire(stage)
		end
	end
end

--------------------------------------------------------------------------------
-- DEBUG LOGGING SYSTEM
--------------------------------------------------------------------------------

local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- Debug configuration (loaded lazily)
System._debugConfig = nil
System._debugConfigLoaded = false

-- Load debug config from ReplicatedFirst (lazy, cached)
function System:_loadDebugConfig()
	if self._debugConfigLoaded then
		return self._debugConfig
	end

	self._debugConfigLoaded = true

	local success, config = pcall(function()
		local configModule = ReplicatedFirst:FindFirstChild("System")
		if configModule then
			local debugConfig = configModule:FindFirstChild("DebugConfig")
			if debugConfig then
				return require(debugConfig)
			else
				warn("[Debug] DebugConfig not found in ReplicatedFirst.System")
			end
		else
			warn("[Debug] System folder not found in ReplicatedFirst")
		end
		return nil
	end)

	if success and config then
		self._debugConfig = config
		print("[Debug] Loaded config, Priority =", config.priorityThreshold or "Info")
	else
		-- Fallback: Info level, all categories enabled
		warn("[Debug] Using fallback config (Info level)")
		self._debugConfig = {
			priorityThreshold = "Info",
			categories = {},
			filter = { enabled = {}, disabled = {} }
		}
	end

	return self._debugConfig
end

-- Glob pattern matching (supports * for any sequence)
local function matchesGlob(str, pattern)
	-- Convert glob to Lua pattern
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
	local config = System:_loadDebugConfig()

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

-- Format arguments for output
local function formatArgs(...)
	local args = {...}
	local parts = {}
	for i, v in ipairs(args) do
		parts[i] = tostring(v)
	end
	return table.concat(parts, " ")
end

-- Debug namespace
System.Debug = {}

-- Debug:Critical - critical messages (always shown unless explicitly filtered)
-- Use for bootstrap, errors, important system events
function System.Debug:Critical(source, ...)
	if shouldLog(source, "Critical") then
		print(source .. ":", formatArgs(...))
	end
end

-- Debug:Message - regular info-level output
function System.Debug:Message(source, ...)
	if shouldLog(source, "Info") then
		print(source .. ":", formatArgs(...))
	end
end

-- Debug:Verbose - detailed debug output (only shown at Verbose priority threshold)
function System.Debug:Verbose(source, ...)
	if shouldLog(source, "Verbose") then
		print(source .. ":", formatArgs(...))
	end
end

-- Debug:Warn - warning output (Critical priority)
function System.Debug:Warn(source, ...)
	if shouldLog(source, "Critical") then
		warn(source .. ":", formatArgs(...))
	end
end

-- Debug:Alert - error/alert output (Critical priority, prefixed with [ALERT])
function System.Debug:Alert(source, ...)
	if shouldLog(source, "Critical") then
		warn("[ALERT] " .. source .. ":", formatArgs(...))
	end
end

return System
