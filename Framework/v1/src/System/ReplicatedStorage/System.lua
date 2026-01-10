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

-- Debug is a separate module, loaded early before other modules
-- We require it here and re-export as System.Debug for convenience
local Debug = require(script.Parent:WaitForChild("System.Debug"))

-- Router is the central message routing system
-- Loaded early, initialized by System.Script with wiring from GameManifest
local Router = require(script.Parent:WaitForChild("System.Router"))

local System = {
	-- Re-export Debug for convenient access via System.Debug
	Debug = Debug,
	-- Re-export Router for convenient access via System.Router
	Router = Router,
	-- Boot stages (in order)
	Stages = {
		SYNC        = 1,  -- Assets cloned to RuntimeAssets, folders extracted
		EVENTS      = 2,  -- All BindableEvents/RemoteEvents created and registered
		MODULES     = 3,  -- ModuleScripts deployed and requireable
		REGISTER    = 4,  -- All scripts register their modules via RegisterModule
		SCRIPTS     = 4,  -- DEPRECATED: Alias for REGISTER (backward compat)
		INIT        = 5,  -- All module:init() called, wait for completion
		START       = 6,  -- All module:start() called, wait for completion
		ASSETS      = 6,  -- DEPRECATED: Alias for START (backward compat)
		ORCHESTRATE = 7,  -- Orchestrator applies initial mode config
		READY       = 8,  -- Full boot complete, clients can interact
	},

	-- Internal state
	_currentStage = 0,
	_stageEvent = nil,  -- BindableEvent for stage transitions
	_isClient = RunService:IsClient(),
	_registeredModules = {},  -- [name] = { module, options, initComplete, startComplete }
	_registeredAssets = {},   -- [name] = { init = fn, initialized = bool } (legacy compat)
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
-- MODULE REGISTRATION (Two-Phase Initialization Pattern)
--------------------------------------------------------------------------------

--[[
    Register a module for two-phase initialization.

    Modules should have:
    - init() - Phase 1: Setup (create events, state). NO connections to other modules.
    - start() - Phase 2: Start (connect events, begin logic). Safe to call other modules.
    - stop() (optional) - Cleanup for hot reload

    @param name string - Module name (e.g., "Input", "RunModes", "Campfire")
    @param module table - Module table with init/start methods
    @param options table (optional) - { type = "system"|"asset", priority = number, dependencies = {} }
--]]
function System:RegisterModule(name, module, options)
	if self._registeredModules[name] then
		System.Debug:Warn("System", "Module already registered:", name)
		return
	end

	options = options or {}

	self._registeredModules[name] = {
		module = module,
		options = options,
		initComplete = false,
		startComplete = false,
	}

	local moduleType = options.type or "unknown"
	System.Debug:Message("System", "Registered module:", name, "(" .. moduleType .. ")")
end

--[[
    Get a registered module by name.
    Useful for inter-module communication after START stage.

    @param name string - Module name
    @return table|nil - The module or nil if not found
--]]
function System:GetModule(name)
	local entry = self._registeredModules[name]
	if entry then
		return entry.module
	end
	return nil
end

--[[
    Check if a module is registered.
    @param name string - Module name
    @return boolean
--]]
function System:IsModuleRegistered(name)
	return self._registeredModules[name] ~= nil
end

--[[
    Get list of registered module names.
    @return table - Array of module names
--]]
function System:GetRegisteredModules()
	local names = {}
	for name in pairs(self._registeredModules) do
		table.insert(names, name)
	end
	return names
end

--[[
    Initialize all registered modules (Phase 1).
    Called by System.Script during INIT stage.
    Modules should create events/state but NOT connect to other modules.
--]]
function System:_initAllModules()
	local count = 0
	local failed = 0

	for name, entry in pairs(self._registeredModules) do
		if entry.module.init then
			System.Debug:Verbose("System", "Init:", name)
			local success, err = pcall(function()
				entry.module:init()
			end)
			if success then
				entry.initComplete = true
				count = count + 1
				System.Debug:Message("System", "Init:", name, "✓")
			else
				failed = failed + 1
				System.Debug:Alert("System", "Module init failed:", name, "-", tostring(err))
			end
		else
			-- No init method = auto-complete
			entry.initComplete = true
			count = count + 1
		end
	end

	System.Debug:Message("System", "Initialized", count, "modules" .. (failed > 0 and (", " .. failed .. " failed") or ""))
end

--[[
    Start all registered modules (Phase 2).
    Called by System.Script during START stage.
    Modules can now safely connect events and call other modules.
--]]
function System:_startAllModules()
	local count = 0
	local failed = 0

	for name, entry in pairs(self._registeredModules) do
		if not entry.initComplete then
			System.Debug:Warn("System", "Skipping start for module with failed init:", name)
			continue
		end

		if entry.module.start then
			System.Debug:Verbose("System", "Start:", name)
			local success, err = pcall(function()
				entry.module:start()
			end)
			if success then
				entry.startComplete = true
				count = count + 1
				System.Debug:Message("System", "Start:", name, "✓")
			else
				failed = failed + 1
				System.Debug:Alert("System", "Module start failed:", name, "-", tostring(err))
			end
		else
			-- No start method = auto-complete
			entry.startComplete = true
			count = count + 1
		end
	end

	System.Debug:Message("System", "Started", count, "modules" .. (failed > 0 and (", " .. failed .. " failed") or ""))
end

--------------------------------------------------------------------------------
-- ASSET REGISTRATION (Legacy Compatibility + Deferred Initialization)
--------------------------------------------------------------------------------

--[[
    Register an asset for two-phase initialization.

    Supports two patterns:

    1. NEW MODULE PATTERN (recommended):
       System:RegisterAsset("MyAsset", {
           init = function(self) ... end,
           start = function(self) ... end,
       })

    2. LEGACY FUNCTION PATTERN (backward compatible):
       System:RegisterAsset("MyAsset", function()
           -- All init code here (runs during START phase)
       end)

    @param name string - Asset name (e.g., "Dispenser", "GlobalTimer")
    @param moduleOrFn table|function - Module table or legacy init function
--]]
function System:RegisterAsset(name, moduleOrFn)
	if self._registeredAssets[name] then
		System.Debug:Warn("System", "Asset already registered:", name)
		return
	end

	local module

	if type(moduleOrFn) == "function" then
		-- Legacy pattern: wrap function in module-like structure
		-- Function runs during START phase (maintains backward compat timing)
		module = {
			init = function() end,  -- Empty init
			start = moduleOrFn,     -- Legacy init becomes start
		}
		System.Debug:Verbose("System", "Wrapped legacy asset function:", name)
	else
		-- New module pattern
		module = moduleOrFn
	end

	-- Track in legacy registry for compatibility
	self._registeredAssets[name] = {
		module = module,
		initialized = false,
	}

	-- Also register via new module system
	self:RegisterModule(name, module, { type = "asset" })
end

--[[
    Initialize all registered assets.
    DEPRECATED: Kept for backward compatibility, but assets now use module system.
    Called by System.Script during ASSETS stage (legacy).
--]]
function System:_initializeAssets()
	-- Assets are now initialized via _initAllModules and _startAllModules
	-- This function is kept for backward compatibility but does nothing
	System.Debug:Verbose("System", "_initializeAssets called (deprecated, assets use module system)")
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
	-- Ensure event reference exists before updating
	-- This prevents race condition where PONG arrives before WaitForStage is called
	self:_ensureEvent()

	if stage > self._currentStage then
		self._currentStage = stage
		System.Debug:Message("System.client", "Received server stage:", self:GetStageName(stage), "(" .. stage .. ")")

		-- Fire event to wake up any waiting client scripts
		if self._stageEvent then
			self._stageEvent:Fire(stage)
		end
	end
end

--------------------------------------------------------------------------------
-- CLIENT BOOT SYSTEM (Client-only)
--------------------------------------------------------------------------------

-- Client boot stages (separate from server stages)
System.ClientStages = {
	WAIT     = 1,  -- Waiting for server READY signal
	DISCOVER = 2,  -- System discovers all client modules
	INIT     = 3,  -- All client module:init() called (topologically sorted)
	START    = 4,  -- All client module:start() called (topologically sorted)
	READY    = 5,  -- Client fully ready
}

-- Client state (only used on client)
System._clientCurrentStage = 0
System._registeredClientModules = {}  -- [name] = { module, dependencies, initComplete, startComplete }
System._clientModuleOrder = {}        -- Topologically sorted module names
System._clientStageEvent = nil

--[[
    Register a client module for two-phase initialization.
    Only used on client side.

    @param name string - Module name
    @param module table - Module table with init/start methods
    @param options table (optional)
--]]
function System:RegisterClientModule(name, module, options)
	if not self._isClient then
		System.Debug:Warn("System", "RegisterClientModule called on server for:", name)
		return
	end

	if self._registeredClientModules[name] then
		System.Debug:Warn("System", "Client module already registered:", name)
		return
	end

	options = options or {}

	self._registeredClientModules[name] = {
		module = module,
		options = options,
		initComplete = false,
		startComplete = false,
	}

	System.Debug:Message("System", "Registered client module:", name)
end

--[[
    Get client boot stage name for debugging.
--]]
function System:GetClientStageName(stage)
	for name, value in pairs(self.ClientStages) do
		if value == stage then
			return name
		end
	end
	return "UNKNOWN"
end

--[[
    Wait for a specific client boot stage.
    Only used on client side.
--]]
function System:WaitForClientStage(stage)
	if not self._isClient then
		return
	end

	if self._clientCurrentStage >= stage then
		return
	end

	while self._clientCurrentStage < stage do
		if self._clientStageEvent then
			self._clientStageEvent.Event:Wait()
		else
			task.wait(0.1)
		end
	end
end

--[[
    Set client stage (internal, called by System.client).
--]]
function System:_setClientStage(stage)
	self._clientCurrentStage = stage
	System.Debug:Message("System.client", "Client stage", self:GetClientStageName(stage), "(" .. stage .. ")")

	if self._clientStageEvent then
		self._clientStageEvent:Fire(stage)
	end
end

--------------------------------------------------------------------------------
-- MODULE DISCOVERY AND DEPENDENCY RESOLUTION (Client-only)
--------------------------------------------------------------------------------

--[[
    Topological sort using Kahn's algorithm.
    Returns modules in dependency order (dependencies first).

    @param modules table - Map of name -> { module, dependencies }
    @return table - Array of module names in sorted order
--]]
function System:_topologicalSort(modules)
	-- Build in-degree count and adjacency list
	local inDegree = {}
	local dependents = {}  -- [name] = { modules that depend on this }

	for name in pairs(modules) do
		inDegree[name] = 0
		dependents[name] = {}
	end

	-- Count incoming edges (dependencies)
	for name, entry in pairs(modules) do
		local deps = entry.dependencies or {}
		for _, dep in ipairs(deps) do
			if modules[dep] then
				inDegree[name] = inDegree[name] + 1
				table.insert(dependents[dep], name)
			else
				-- Dependency not found - warn but continue
				System.Debug:Warn("System.client", "Module", name, "depends on unknown module:", dep)
			end
		end
	end

	-- Start with modules that have no dependencies (in-degree 0)
	local queue = {}
	for name, degree in pairs(inDegree) do
		if degree == 0 then
			table.insert(queue, name)
		end
	end

	-- Process queue
	local sorted = {}
	while #queue > 0 do
		-- Sort queue alphabetically for deterministic order
		table.sort(queue)
		local name = table.remove(queue, 1)
		table.insert(sorted, name)

		-- Reduce in-degree for dependents
		for _, dependent in ipairs(dependents[name]) do
			inDegree[dependent] = inDegree[dependent] - 1
			if inDegree[dependent] == 0 then
				table.insert(queue, dependent)
			end
		end
	end

	-- Check for cycles
	local moduleCount = 0
	for _ in pairs(modules) do moduleCount = moduleCount + 1 end

	if #sorted ~= moduleCount then
		local missing = {}
		for name in pairs(modules) do
			local found = false
			for _, s in ipairs(sorted) do
				if s == name then found = true break end
			end
			if not found then table.insert(missing, name) end
		end
		System.Debug:Alert("System.client", "Circular dependency detected! Modules in cycle:", table.concat(missing, ", "))
	end

	return sorted
end

--[[
    Discover all client modules from deployed locations.
    Finds all ModuleScripts in:
    - PlayerScripts (deployed System modules)
    - PlayerGui (deployed GUI/asset modules)

    Each module should return: { dependencies = {}, init = fn, start = fn }
    Module name is the instance name (e.g., "GUI.Script", "Tutorial.LocalScript")
--]]
function System:_discoverClientModules()
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerGui = player:WaitForChild("PlayerGui")

	-- Wait for character to load and StarterGui content to clone to PlayerGui
	-- This ensures ScreenGuis (and their ModuleScript children) are present
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("Humanoid", 5)  -- Ensure character is fully loaded

	-- Brief yield to allow all StarterGui content to clone
	task.wait(0.1)

	local discovered = 0

	-- Helper to discover modules in a container
	-- Uses GetDescendants to find ModuleScripts inside ScreenGuis and other containers
	local function discoverIn(container, containerName)
		for _, descendant in ipairs(container:GetDescendants()) do
			-- Find all ModuleScripts (instance name is the module name)
			if descendant:IsA("ModuleScript") then
				local moduleName = descendant.Name

				-- Skip if already registered (prevent duplicates)
				if self._registeredClientModules[moduleName] then
					continue
				end

				local success, moduleTable = pcall(require, descendant)
				if success and type(moduleTable) == "table" then
					self._registeredClientModules[moduleName] = {
						module = moduleTable,
						dependencies = moduleTable.dependencies or {},
						initComplete = false,
						startComplete = false,
					}
					discovered = discovered + 1
					local deps = moduleTable.dependencies or {}
					local depStr = #deps > 0 and (" [deps: " .. table.concat(deps, ", ") .. "]") or ""
					System.Debug:Message("System.client", "Discovered:", moduleName, "in", containerName .. depStr)
				else
					System.Debug:Alert("System.client", "Failed to require module:", descendant.Name, "-", tostring(moduleTable))
				end
			end
		end
	end

	-- Discover in both locations
	discoverIn(playerScripts, "PlayerScripts")
	discoverIn(playerGui, "PlayerGui")

	-- Topologically sort modules
	self._clientModuleOrder = self:_topologicalSort(self._registeredClientModules)

	System.Debug:Message("System.client", "Discovered", discovered, "modules")
	System.Debug:Message("System.client", "Init order:", table.concat(self._clientModuleOrder, " -> "))
end

--[[
    Get the client module initialization order.
    @return table - Array of module names in init order
--]]
function System:GetClientModuleOrder()
	return self._clientModuleOrder
end

--[[
    Check if a client module has completed initialization.
    @param name string - Module name
    @return boolean
--]]
function System:IsClientModuleReady(name)
	local entry = self._registeredClientModules[name]
	return entry and entry.startComplete == true
end

--[[
    Initialize all registered client modules (Phase 1).
    Modules are initialized in topologically sorted order (dependencies first).
--]]
function System:_initAllClientModules()
	local count = 0
	local failed = 0

	-- Use topologically sorted order
	for _, name in ipairs(self._clientModuleOrder) do
		local entry = self._registeredClientModules[name]
		if entry and entry.module.init then
			System.Debug:Verbose("System.client", "Init:", name)
			local success, err = pcall(function()
				entry.module:init()
			end)
			if success then
				entry.initComplete = true
				count = count + 1
				System.Debug:Message("System.client", "Init:", name, "✓")
			else
				failed = failed + 1
				System.Debug:Alert("System.client", "Client module init failed:", name, "-", tostring(err))
			end
		elseif entry then
			entry.initComplete = true
			count = count + 1
		end
	end

	System.Debug:Message("System.client", "Initialized", count, "client modules" .. (failed > 0 and (", " .. failed .. " failed") or ""))
end

--[[
    Start all registered client modules (Phase 2).
    Modules are started in topologically sorted order (dependencies first).
--]]
function System:_startAllClientModules()
	local count = 0
	local failed = 0

	-- Use topologically sorted order
	for _, name in ipairs(self._clientModuleOrder) do
		local entry = self._registeredClientModules[name]
		if not entry then continue end

		if not entry.initComplete then
			System.Debug:Warn("System.client", "Skipping start for client module with failed init:", name)
			continue
		end

		if entry.module.start then
			System.Debug:Verbose("System.client", "Start:", name)
			local success, err = pcall(function()
				entry.module:start()
			end)
			if success then
				entry.startComplete = true
				count = count + 1
				System.Debug:Message("System.client", "Start:", name, "✓")
			else
				failed = failed + 1
				System.Debug:Alert("System.client", "Client module start failed:", name, "-", tostring(err))
			end
		else
			entry.startComplete = true
			count = count + 1
		end
	end

	System.Debug:Message("System.client", "Started", count, "client modules" .. (failed > 0 and (", " .. failed .. " failed") or ""))
end

--[[
    Get list of registered client module names.
--]]
function System:GetRegisteredClientModules()
	local names = {}
	for name in pairs(self._registeredClientModules) do
		table.insert(names, name)
	end
	return names
end

return System
