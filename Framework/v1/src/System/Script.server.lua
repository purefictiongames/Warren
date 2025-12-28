-- System.Script (Server)
-- Self-bootstrapping script - extracts own service folders, then deploys assets

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

-- Get reference to self (System folder in ServerScriptService)
local System = script.Parent

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
	local isInServerScriptService = System:IsDescendantOf(ServerScriptService)

	-- Bootstrap System's own service folders (skip SSS if already there)
	bootstrapModule(System, "System", isInServerScriptService)

	-- Bootstrap child modules (Folders inside System, excluding service folders)
	-- Child modules always need full deployment (don't skip SSS)
	for _, child in ipairs(System:GetChildren()) do
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

-- Run bootstrap
bootstrapSelf()
bootstrapAssets()

print("System.Script loaded")
