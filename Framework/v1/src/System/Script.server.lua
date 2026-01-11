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

-- Apply attributes from manifest entry to clone
local function applyManifestAttributes(clone, entry, System, alias)
	-- Legacy attribute mappings (for backward compatibility)
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

	-- New grammar: extension and model paths
	if entry.extension then
		clone:SetAttribute("_ExtensionPath", entry.extension)
	end
	if entry.model then
		clone:SetAttribute("_ModelPath", entry.model)
	end

	-- New grammar: attributes table (generic key-value pairs)
	if entry.attributes then
		for key, value in pairs(entry.attributes) do
			clone:SetAttribute(key, value)
		end
	end
end

-- Create standardized events for an asset
local function createAssetEvents(alias)
	local eventTypes = {"Input", "Output", "Debug"}
	for _, eventType in ipairs(eventTypes) do
		local event = Instance.new("BindableEvent")
		event.Name = alias .. "." .. eventType
		event.Parent = ReplicatedStorage
	end
end

-- Swap model parts from a Game folder override
-- Replaces visual parts in clone with parts from the game-specific model
local function swapModelParts(clone, gameModelFolder, System, alias)
	if not gameModelFolder then return end

	-- Find all .rbxm files in the game model folder (they become children)
	for _, gameChild in ipairs(gameModelFolder:GetChildren()) do
		-- Find matching part in clone by name
		local clonePart = clone:FindFirstChild(gameChild.Name)

		if clonePart then
			-- Store the position/CFrame from the original
			local originalCFrame = nil
			if clonePart:IsA("BasePart") then
				originalCFrame = clonePart.CFrame
			elseif clonePart:IsA("Model") then
				originalCFrame = clonePart:GetPivot()
			end

			-- Clone the game-specific part
			local newPart = gameChild:Clone()

			-- Preserve position from original if applicable
			if originalCFrame then
				if newPart:IsA("BasePart") then
					newPart.CFrame = originalCFrame
				elseif newPart:IsA("Model") then
					newPart:PivotTo(originalCFrame)
				end
			end

			-- Replace the part
			newPart.Parent = clone
			clonePart:Destroy()

			System.Debug:Message("System.Script", alias, "- swapped model part:", gameChild.Name)
		else
			-- No matching part, just add it
			local newPart = gameChild:Clone()
			newPart.Parent = clone
			System.Debug:Message("System.Script", alias, "- added model part:", gameChild.Name)
		end
	end
end

-- Deploy a single asset template (shared logic for all deployment methods)
local function deployTemplate(template, templateName, alias, runtimeAssets, entry, System, deployedAliases, gameFolder)
	-- Validation: Check for duplicate aliases
	if deployedAliases[alias] then
		System.Debug:Warn("System.Script", "Duplicate alias:", alias, "- skipping")
		return false
	end

	if not template or not template:IsA("Model") then
		System.Debug:Warn("System.Script", "Template not found:", templateName, "- skipping")
		return false
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

	-- Swap model parts if game-specific model is specified
	if entry.model and gameFolder then
		-- Parse model path (e.g., "Game.MarshmallowBag.Model" -> Game/MarshmallowBag/Model)
		local modelPath = entry.model
		local parts = string.split(modelPath, ".")

		-- Navigate to the model folder (skip "Game" prefix if present)
		local modelFolder = gameFolder
		local startIndex = 1
		if parts[1] == "Game" then
			startIndex = 2
		end

		for i = startIndex, #parts do
			modelFolder = modelFolder:FindFirstChild(parts[i])
			if not modelFolder then
				System.Debug:Warn("System.Script", alias, "- model folder not found:", modelPath)
				break
			end
		end

		if modelFolder then
			swapModelParts(clone, modelFolder, System, alias)
		end
	end

	-- Parent cleaned clone to RuntimeAssets
	clone.Parent = runtimeAssets
	deployedAliases[alias] = true

	-- Apply manifest configuration as attributes
	applyManifestAttributes(clone, entry, System, alias)

	-- Create standardized events for this asset
	createAssetEvents(alias)

	return true
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

	-- Get folder references (new Lib/Game structure or legacy Assets)
	local libFolder = ReplicatedStorage:FindFirstChild("Lib")
	local gameFolder = ReplicatedStorage:FindFirstChild("Game")
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")  -- Legacy fallback

	-- Track deployed aliases for validation
	local deployedAliases = {}

	--------------------------------------------------------------------------------
	-- CONFIGURED TEMPLATES: Pre-merge Lib bases with game models/attributes
	-- Creates ready-to-clone templates in ReplicatedStorage._ConfiguredTemplates
	-- Uses underscore prefix to avoid Rojo sync overwriting these runtime templates
	-- These are NOT deployed to RuntimeAssets - they're for runtime spawning
	--------------------------------------------------------------------------------
	if manifest.configuredTemplates then
		-- Create _ConfiguredTemplates folder (separate from Rojo-synced Templates)
		local templatesFolder = ReplicatedStorage:FindFirstChild("_ConfiguredTemplates")
		if not templatesFolder then
			templatesFolder = Instance.new("Folder")
			templatesFolder.Name = "_ConfiguredTemplates"
			templatesFolder.Parent = ReplicatedStorage
		end

		System.Debug:Message("System.Script", "Processing", #manifest.configuredTemplates, "configured templates")

		for _, entry in ipairs(manifest.configuredTemplates) do
			local baseName = entry.base
			local alias = entry.alias or baseName

			if not libFolder then
				System.Debug:Warn("System.Script", "Lib folder not found - cannot create template:", baseName)
				continue
			end

			local baseTemplate = libFolder:FindFirstChild(baseName)
			if not baseTemplate then
				System.Debug:Warn("System.Script", "Base template not found in Lib:", baseName)
				continue
			end

			-- Clone the base template
			local clone = baseTemplate:Clone()
			clone.Name = alias

			-- Store the base template name for module lookup
			clone:SetAttribute("_BaseTemplate", baseName)

			-- Apply model swap if specified
			if entry.model and gameFolder then
				local parts = string.split(entry.model, ".")
				local current = gameFolder

				-- Skip "Game" prefix if present
				local startIndex = 1
				if parts[1] == "Game" then
					startIndex = 2
				end

				for i = startIndex, #parts do
					current = current:FindFirstChild(parts[i])
					if not current then break end
				end

				if current then
					swapModelParts(clone, current, System, alias)
					System.Debug:Message("System.Script", "Template", alias, "- applied model from", entry.model)
				else
					System.Debug:Warn("System.Script", "Template", alias, "- model path not found:", entry.model)
				end
			end

			-- Apply attributes if specified
			if entry.attributes then
				for attrName, attrValue in pairs(entry.attributes) do
					clone:SetAttribute(attrName, attrValue)
				end
				System.Debug:Message("System.Script", "Template", alias, "- applied",
					#(table.pack(pairs(entry.attributes))) - 1, "attributes")
			end

			-- Store in Templates folder (NOT RuntimeAssets)
			clone.Parent = templatesFolder
			System.Debug:Critical("System.Script", "Created template:", alias, "from base", baseName)
		end
	end

	--------------------------------------------------------------------------------
	-- NEW GRAMMAR: instances (Lib-based assets with optional extensions)
	--------------------------------------------------------------------------------
	if manifest.instances then
		System.Debug:Message("System.Script", "Processing", #manifest.instances, "Lib instances")

		for _, entry in ipairs(manifest.instances) do
			local libName = entry.lib
			local alias = entry.alias or libName

			if not libFolder then
				System.Debug:Warn("System.Script", "Lib folder not found - cannot deploy:", libName)
				continue
			end

			local template = libFolder:FindFirstChild(libName)
			if deployTemplate(template, libName, alias, runtimeAssets, entry, System, deployedAliases, gameFolder) then
				System.Debug:Critical("System.Script", "Deployed Lib", libName, "as", alias,
					entry.extension and ("+ extension " .. entry.extension) or "",
					entry.model and ("+ model " .. entry.model) or "")
			end
		end
	end

	--------------------------------------------------------------------------------
	-- NEW GRAMMAR: gameAssets (Game-specific assets, no Lib base)
	--------------------------------------------------------------------------------
	if manifest.gameAssets then
		System.Debug:Message("System.Script", "Processing", #manifest.gameAssets, "Game assets")

		for _, entry in ipairs(manifest.gameAssets) do
			local templateName = entry.use
			local alias = entry.as or templateName

			if not gameFolder then
				System.Debug:Warn("System.Script", "Game folder not found - cannot deploy:", templateName)
				continue
			end

			local template = gameFolder:FindFirstChild(templateName)
			if deployTemplate(template, templateName, alias, runtimeAssets, entry, System, deployedAliases, gameFolder) then
				System.Debug:Critical("System.Script", "Deployed Game asset", templateName, "as", alias)
			end
		end
	end

	--------------------------------------------------------------------------------
	-- LEGACY GRAMMAR: assets (backward compatibility with old manifest format)
	--------------------------------------------------------------------------------
	if manifest.assets then
		-- Determine source folder: prefer Lib, fallback to Assets
		local sourceFolder = libFolder or assetsFolder

		if not sourceFolder then
			System.Debug:Warn("System.Script", "No Lib or Assets folder found")
		else
			local folderName = libFolder and "Lib" or "Assets"
			System.Debug:Message("System.Script", "Processing", #manifest.assets, "legacy assets from", folderName)

			for _, entry in ipairs(manifest.assets) do
				local templateName = entry.use
				local alias = entry.as

				local template = sourceFolder:FindFirstChild(templateName)
				if deployTemplate(template, templateName, alias, runtimeAssets, entry, System, deployedAliases, gameFolder) then
					System.Debug:Critical("System.Script", "Deployed", templateName, "as", alias)
				end
			end
		end
	end

	-- Apply wiring connections (for static event forwarding)
	applyWiring(manifest, System)

	-- Initialize Router with wiring configuration
	-- Router handles targeted messages and provides filtering capabilities
	System.Router:Init({
		Debug = System.Debug,
		wiring = manifest.wiring or {},
	})

	System.Debug:Critical("System.Script", "Router initialized with", #(manifest.wiring or {}), "wires")
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
