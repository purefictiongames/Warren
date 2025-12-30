-- System.ModuleScript (Shared)
-- Central module providing boot stage constants and wait helpers
-- Scripts can optionally use this to wait for stages, or continue using WaitForChild

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local System = {
	-- Boot stages (in order)
	Stages = {
		SYNC    = 1,  -- Assets cloned to RuntimeAssets, folders extracted
		EVENTS  = 2,  -- All BindableEvents/RemoteEvents created and registered
		MODULES = 3,  -- ModuleScripts deployed and requireable
		SCRIPTS = 4,  -- Server scripts can run
		READY   = 5,  -- Full boot complete, clients can interact
	},

	-- Internal state
	_currentStage = 0,
	_stageEvent = nil,  -- BindableEvent for stage transitions
	_isClient = RunService:IsClient(),
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
			end
		end
		return nil
	end)

	if success and config then
		self._debugConfig = config
	else
		-- Fallback: Level 2 (System + Subsystems) with no filter
		self._debugConfig = {
			Level = 2,
			Filter = { enabled = {}, disabled = {} }
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

-- Check if source should be logged at current level
local function shouldLog(source)
	local config = System:_loadDebugConfig()
	local level = config.Level

	-- Level 1: System only
	if level == 1 then
		return source == "System" or source == "System.Script" or source == "System.client"
	end

	-- Level 2: System + Subsystems
	if level == 2 then
		return source:match("^System") ~= nil
	end

	-- Level 3: Assets only (NOT System)
	if level == 3 then
		return source:match("^System") == nil
	end

	-- Level 4: Everything with filtering
	if level == 4 then
		local filter = config.Filter or {}
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

		-- Default: allow (permissive)
		return true
	end

	-- Unknown level: default allow
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

-- Debug:Message - regular output
function System.Debug:Message(source, ...)
	if shouldLog(source) then
		print(source .. ":", formatArgs(...))
	end
end

-- Debug:Warn - warning output
function System.Debug:Warn(source, ...)
	if shouldLog(source) then
		warn(source .. ":", formatArgs(...))
	end
end

-- Debug:Alert - error/alert output (prefixed with [ALERT])
function System.Debug:Alert(source, ...)
	if shouldLog(source) then
		warn("[ALERT] " .. source .. ":", formatArgs(...))
	end
end

return System
