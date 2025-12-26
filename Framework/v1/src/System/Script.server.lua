-- System.Script (Server)
-- Self-bootstrapping script - extracts own service folders, then deploys assets

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

-- Get reference to self (System folder in ServerScriptService)
local System = script.Parent

-- Service folder mappings
local SERVICE_FOLDERS = {
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	StarterPlayerScripts = StarterPlayer.StarterPlayerScripts,
}

-- Deploy contents of a service folder to actual service
local function deployServiceFolder(sourceFolder, targetService, namePrefix)
	for _, child in ipairs(sourceFolder:GetChildren()) do
		local clone = child:Clone()
		if namePrefix then
			clone.Name = namePrefix .. "." .. child.Name
		end
		clone.Parent = targetService
		print("System: Deployed", clone.Name, "to", targetService.Name)
	end
end

-- Bootstrap a module (extract its service folders)
local function bootstrapModule(module, moduleName)
	for folderName, service in pairs(SERVICE_FOLDERS) do
		local serviceFolder = module:FindFirstChild(folderName)
		if serviceFolder then
			deployServiceFolder(serviceFolder, service, moduleName)
			serviceFolder:Destroy()
		end
	end
end

-- Bootstrap System and its child modules
local function bootstrapSelf()
	-- Bootstrap System's own service folders
	bootstrapModule(System, "System")

	-- Bootstrap child modules (Folders inside System, excluding service folders)
	for _, child in ipairs(System:GetChildren()) do
		if child:IsA("Folder") and not SERVICE_FOLDERS[child.Name] then
			bootstrapModule(child, child.Name)
			print("System: Bootstrapped module", child.Name)
		end
	end

	print("System: Self-bootstrap complete")
end

-- Deploy assets from ReplicatedStorage/Assets to RuntimeAssets
local function bootstrapAssets()
	-- Create RuntimeAssets folder
	local runtimeAssets = Instance.new("Folder")
	runtimeAssets.Name = "RuntimeAssets"
	runtimeAssets.Parent = Workspace

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		warn("System: Assets folder not found in ReplicatedStorage")
		return
	end

	for _, asset in ipairs(assetsFolder:GetChildren()) do
		if asset:IsA("Model") then
			local clone = asset:Clone()
			local assetName = clone.Name

			-- Extract service folders from clone
			for folderName, service in pairs(SERVICE_FOLDERS) do
				local serviceFolder = clone:FindFirstChild(folderName)
				if serviceFolder then
					deployServiceFolder(serviceFolder, service, assetName)
					serviceFolder:Destroy()
				end
			end

			-- Parent cleaned clone to RuntimeAssets
			clone.Parent = runtimeAssets
			print("System: Deployed", assetName, "to RuntimeAssets")
		end
	end
end

-- Run bootstrap
bootstrapSelf()
bootstrapAssets()

print("System.Script loaded")
