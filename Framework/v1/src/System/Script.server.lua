--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- System.Script (Server)
-- Self-bootstrapping script - extracts own service folders, then deploys assets
-- Implements staged boot system with player spawn control

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

-- CRITICAL: Disable character auto-loading IMMEDIATELY
-- This prevents players from spawning before the system is ready
Players.CharacterAutoLoads = false

-- Get reference to self (System folder in ServerScriptService)
local SystemFolder = script.Parent

-- Service folder mappings (order matters: deploy events before scripts)
-- Folder names use underscore prefix to prevent auto-run of nested scripts
local SERVICE_FOLDERS = {
	ReplicatedStorage = ReplicatedStorage,
	_ServerScriptService = ServerScriptService,
	StarterPlayerScripts = StarterPlayer.StarterPlayerScripts,
	StarterGui = StarterGui,
}

-- Ordered list for deterministic deployment (ReplicatedStorage first, then scripts)
local SERVICE_ORDER = {
	"ReplicatedStorage",
	"StarterGui",
	"StarterPlayerScripts",
	"_ServerScriptService",  -- Scripts last, after events exist
}

-- Deploy contents of a service folder to actual service
local function deployServiceFolder(sourceFolder, targetService, namePrefix)
	for _, child in ipairs(sourceFolder:GetChildren()) do
		local clone = child:Clone()
		if namePrefix then
			clone.Name = namePrefix .. "." .. child.Name
		end
		clone.Parent = targetService
	end
end

-- Bootstrap a module (extract its service folders)
-- skipServerScripts: true if module already lives in ServerScriptService (e.g., System as Package)
local function bootstrapModule(module, moduleName, skipServerScripts)
	for _, folderName in ipairs(SERVICE_ORDER) do
		-- Skip ServerScriptService extraction for modules already there
		if skipServerScripts and folderName == "_ServerScriptService" then
			continue
		end

		local service = SERVICE_FOLDERS[folderName]
		local serviceFolder = module:FindFirstChild(folderName)
		if serviceFolder then
			deployServiceFolder(serviceFolder, service, moduleName)
			serviceFolder:Destroy()
		end
	end
end

-- Bootstrap System and its child modules
local function bootstrapSelf()
	-- Check if System is already in ServerScriptService (running as Package)
	local isInServerScriptService = SystemFolder:IsDescendantOf(ServerScriptService)

	-- Bootstrap System's own service folders (skip SSS if already there)
	bootstrapModule(SystemFolder, "System", isInServerScriptService)

	-- Bootstrap child modules (Folders inside System, excluding service folders)
	-- Child modules always need full deployment (don't skip SSS)
	for _, child in ipairs(SystemFolder:GetChildren()) do
		if child:IsA("Folder") and not SERVICE_FOLDERS[child.Name] then
			bootstrapModule(child, child.Name, false)
		end
	end
end

-- Deep rename: Replace all occurrences of template name with alias in instance names
-- Walks instance tree and renames descendants
-- Scripts discover their deployed name dynamically - no source patching needed
local function deepRename(instance, templateName, alias)
	-- Escape special pattern characters for safe string matching
	local tEsc = templateName:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

	-- Recursively process all descendants
	for _, child in ipairs(instance:GetDescendants()) do
		-- Rename if it has the template prefix (e.g., "Dispenser.Script" → "MarshmallowBag.Script")
		if child.Name:match("^" .. tEsc .. "%.") then
			child.Name = child.Name:gsub("^" .. tEsc, alias)
		end
	end

	-- Rename the root instance if it matches the template name
	if instance.Name == templateName then
		instance.Name = alias
	end
end

-- Apply event wiring from manifest
-- Connects Output events to Input events based on manifest configuration
local function applyWiring(manifest, System)
	if not manifest.wiring then
		return
	end

	for _, wire in ipairs(manifest.wiring) do
		local fromPath = wire.from
		local toPath = wire.to

		-- Parse paths (format: "AssetName.EventName")
		local fromAsset, fromEvent = fromPath:match("^(.+)%.(.+)$")
		local toAsset, toEvent = toPath:match("^(.+)%.(.+)$")

		if not fromAsset or not toAsset then
			System.Debug:Warn("System.Script", "Invalid wiring format:", fromPath, "->", toPath)
			continue
		end

		-- Find source event (dot notation)
		local sourceEvent = ReplicatedStorage:FindFirstChild(fromAsset .. "." .. fromEvent)
		if not sourceEvent or not sourceEvent:IsA("BindableEvent") then
			System.Debug:Warn("System.Script", "Wiring source not found:", fromPath)
			continue
		end

		-- Find target event
		local targetEvent = ReplicatedStorage:FindFirstChild(toAsset .. "." .. toEvent)
		if not targetEvent or not targetEvent:IsA("BindableEvent") then
			System.Debug:Warn("System.Script", "Wiring target not found:", toPath)
			continue
		end

		-- Connect source output to target input
		sourceEvent.Event:Connect(function(...)
			targetEvent:Fire(...)
		end)

		System.Debug:Critical("System.Script", "Wired", fromPath, "->", toPath)
	end
end

-- Deploy assets from manifest
local function bootstrapAssets(System)
	System.Debug:Critical("System.Script", "=== BOOTSTRAP ASSETS START ===")

	-- Create RuntimeAssets folder in Workspace
	local runtimeAssets = Instance.new("Folder")
	runtimeAssets.Name = "RuntimeAssets"
	runtimeAssets.Parent = Workspace

	-- Load manifest
	local manifestModule = ReplicatedStorage:FindFirstChild("System.GameManifest")
	if not manifestModule then
		System.Debug:Warn("System.Script", "GameManifest not found - cannot deploy assets")
		return
	end

	local manifest = require(manifestModule)
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")

	if not assetsFolder then
		System.Debug:Warn("System.Script", "Assets folder not found")
		return
	end

	-- Track deployed aliases for validation
	local deployedAliases = {}

	-- Deploy each manifest entry
	for _, entry in ipairs(manifest.assets) do
		local templateName = entry.use
		local alias = entry.as

		-- Validation: Check for duplicate aliases
		if deployedAliases[alias] then
			System.Debug:Warn("System.Script", "Duplicate alias:", alias, "- skipping")
			continue
		end

		-- Find template in Assets folder
		local template = assetsFolder:FindFirstChild(templateName)
		if not template or not template:IsA("Model") then
			System.Debug:Warn("System.Script", "Template not found:", templateName, "- skipping")
			continue
		end

		-- Clone template
		local clone = template:Clone()

		-- Deep rename: Replace all occurrences of templateName with alias
		if templateName ~= alias then
			deepRename(clone, templateName, alias)
		end

		-- Extract service folders from renamed clone (ordered: events before scripts)
		for _, folderName in ipairs(SERVICE_ORDER) do
			local service = SERVICE_FOLDERS[folderName]
			local serviceFolder = clone:FindFirstChild(folderName)
			if serviceFolder then
				deployServiceFolder(serviceFolder, service, alias)
				serviceFolder:Destroy()
			end
		end

		-- Parent cleaned clone to RuntimeAssets
		clone.Parent = runtimeAssets
		deployedAliases[alias] = true

		-- Apply manifest configuration as attributes
		if entry.drops then
			clone:SetAttribute("DropTemplate", entry.drops)
			System.Debug:Message("System.Script", alias, "drops:", entry.drops)
		end
		if entry.spawns then
			clone:SetAttribute("Spawns", entry.spawns)
		end
		if entry.around then
			clone:SetAttribute("Around", entry.around)
		end
		if entry.count then
			clone:SetAttribute("Count", entry.count)
		end
		if entry.radius then
			clone:SetAttribute("Radius", entry.radius)
		end
		if entry.faceOffset then
			clone:SetAttribute("FaceOffset", entry.faceOffset)
		end
		if entry.centerOn then
			clone:SetAttribute("CenterOn", entry.centerOn)
		end
		if entry.anchorSizeX then
			clone:SetAttribute("AnchorSizeX", entry.anchorSizeX)
		end
		if entry.anchorSizeY then
			clone:SetAttribute("AnchorSizeY", entry.anchorSizeY)
		end
		if entry.anchorSizeZ then
			clone:SetAttribute("AnchorSizeZ", entry.anchorSizeZ)
		end

		-- Create standardized events for this asset
		local eventTypes = {"Input", "Output", "Debug"}
		for _, eventType in ipairs(eventTypes) do
			local event = Instance.new("BindableEvent")
			event.Name = alias .. "." .. eventType
			event.Parent = ReplicatedStorage
		end

		System.Debug:Critical("System.Script", "Deployed", templateName, "as", alias)
	end

	-- Apply wiring connections
	applyWiring(manifest, System)

	-- Set up message router for Orchestrator
	-- Routes commands with { target = "AssetName", command = "..." } to AssetName.Input
	local orchestratorOutput = ReplicatedStorage:FindFirstChild("Orchestrator.Output")
	if orchestratorOutput then
		orchestratorOutput.Event:Connect(function(message)
			if not message or type(message) ~= "table" then
				return
			end

			local target = message.target
			local command = message.command

			if target and command then
				-- Route to target asset's Input
				local targetInput = ReplicatedStorage:FindFirstChild(target .. ".Input")
				if targetInput then
					targetInput:Fire({ command = command })
					System.Debug:Verbose("System.Router", "Routed", command, "to", target)
				else
					System.Debug:Warn("System.Router", "Target not found:", target)
				end
			end
		end)
		System.Debug:Critical("System.Script", "Message router connected to Orchestrator.Output")
	else
		System.Debug:Warn("System.Script", "Orchestrator.Output not found - router not connected")
	end
end

-- Spawn all waiting players
local function spawnWaitingPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end

--------------------------------------------------------------------------------
-- STAGED BOOT SEQUENCE
--------------------------------------------------------------------------------

-- Phase 1: Bootstrap System (deploys ReplicatedStorage items including System.System module)
bootstrapSelf()

-- Initialize Debug first - it's infrastructure for all other modules
local Debug = require(ReplicatedStorage:WaitForChild("System.Debug"))
Debug:Initialize()

-- Get references to boot infrastructure (now deployed)
local System = require(ReplicatedStorage:WaitForChild("System.System"))
local BootStage = ReplicatedStorage:WaitForChild("System.BootStage", 5)
local ClientBoot = ReplicatedStorage:WaitForChild("System.ClientBoot", 5)

if not BootStage then
	System.Debug:Alert("System.Script", "System.BootStage not found after bootstrap!")
end
if not ClientBoot then
	System.Debug:Alert("System.Script", "System.ClientBoot not found after bootstrap!")
end

-- Wire up the stage event
System._stageEvent = BootStage

-- Set up client ping-pong handler
-- Note: We defer PONG response until READY stage to prevent race conditions
if ClientBoot then
	System.Debug:Message("System.Script", "ClientBoot handler registered")
	ClientBoot.OnServerEvent:Connect(function(player, message)
		if message == "PING" then
			-- Wait for READY stage before responding
			-- This prevents client from receiving an intermediate stage
			task.spawn(function()
				while System._currentStage < System.Stages.READY do
					task.wait(0.05)
				end
				System.Debug:Message("System.Script", "PING from", player.Name, "- responding with stage", System._currentStage)
				ClientBoot:FireClient(player, "PONG", System._currentStage)
			end)
		elseif message == "READY" then
			-- Client confirmed ready (useful for debugging)
			System.Debug:Message("System", "Client ready -", player.Name)
		end
	end)
else
	System.Debug:Warn("System.Script", "ClientBoot event not found - client sync disabled")
end

-- Fire SYNC stage (System bootstrapped, boot events exist)
System:_setStage(System.Stages.SYNC)

-- Phase 2: Bootstrap Assets (deploys to all services)
bootstrapAssets(System)

-- Fire EVENTS stage (all events now exist in ReplicatedStorage)
System:_setStage(System.Stages.EVENTS)

-- Fire MODULES stage (all modules deployed and requireable)
System:_setStage(System.Stages.MODULES)

-- Fire REGISTER stage (scripts load and register their modules)
System:_setStage(System.Stages.REGISTER)

-- Yield to allow all scripts to run and register modules
-- This ensures all RegisterModule/RegisterAsset calls complete before INIT stage
task.wait()

-- Fire INIT stage (Phase 1: all module:init() called)
-- Modules create events/state but do NOT connect to other modules yet
System:_setStage(System.Stages.INIT)
System:_initAllModules()

-- Fire START stage (Phase 2: all module:start() called)
-- Modules can now safely connect events and call other modules
System:_setStage(System.Stages.START)
System:_startAllModules()

-- Fire ORCHESTRATE stage (Orchestrator applies initial mode config)
System:_setStage(System.Stages.ORCHESTRATE)

-- Fire READY stage (full boot complete)
System:_setStage(System.Stages.READY)

-- Re-enable character auto-loading and spawn waiting players
Players.CharacterAutoLoads = true
spawnWaitingPlayers()

System.Debug:Message("System.Script", "Boot complete - all", #System:GetRegisteredModules(), "modules initialized")
