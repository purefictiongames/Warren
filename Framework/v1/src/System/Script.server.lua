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

-- Deploy assets from ReplicatedStorage/Assets to RuntimeAssets
local function bootstrapAssets()
	-- Create RuntimeAssets folder
	local runtimeAssets = Instance.new("Folder")
	runtimeAssets.Name = "RuntimeAssets"
	runtimeAssets.Parent = Workspace

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")

	for _, asset in ipairs(assetsFolder:GetChildren()) do
		if asset:IsA("Model") then
			local clone = asset:Clone()
			local assetName = clone.Name

			-- Extract service folders from clone (ordered: events before scripts)
			for _, folderName in ipairs(SERVICE_ORDER) do
				local service = SERVICE_FOLDERS[folderName]
				local serviceFolder = clone:FindFirstChild(folderName)
				if serviceFolder then
					deployServiceFolder(serviceFolder, service, assetName)
					serviceFolder:Destroy()
				end
			end

			-- Parent cleaned clone to RuntimeAssets
			clone.Parent = runtimeAssets
		end
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

-- Get references to boot infrastructure (now deployed)
local System = require(ReplicatedStorage:WaitForChild("System.System"))
local BootStage = ReplicatedStorage:FindFirstChild("System.BootStage")
local ClientBoot = ReplicatedStorage:FindFirstChild("System.ClientBoot")

-- Wire up the stage event
System._stageEvent = BootStage

-- Set up client ping-pong handler
if ClientBoot then
	ClientBoot.OnServerEvent:Connect(function(player, message)
		if message == "PING" then
			-- Respond with current stage so client can catch up
			ClientBoot:FireClient(player, "PONG", System._currentStage)
		elseif message == "READY" then
			-- Client confirmed ready (useful for debugging)
			print("System: Client ready -", player.Name)
		end
	end)
end

-- Fire SYNC stage (System bootstrapped, boot events exist)
System:_setStage(System.Stages.SYNC)

-- Phase 2: Bootstrap Assets (deploys to all services)
bootstrapAssets()

-- Fire EVENTS stage (all events now exist in ReplicatedStorage)
System:_setStage(System.Stages.EVENTS)

-- Fire MODULES stage (all modules deployed and requireable)
System:_setStage(System.Stages.MODULES)

-- Fire SCRIPTS stage (server scripts can now initialize)
System:_setStage(System.Stages.SCRIPTS)

-- Fire READY stage (full boot complete)
System:_setStage(System.Stages.READY)

-- Re-enable character auto-loading and spawn waiting players
Players.CharacterAutoLoads = true
spawnWaitingPlayers()

print("System.Script: Boot complete")
