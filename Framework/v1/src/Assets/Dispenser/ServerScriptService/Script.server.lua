-- Dispenser.Script (Server)
-- Handles ProximityPrompt interaction and item dispensing
-- Synced

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispenser = require(ReplicatedStorage:WaitForChild("Dispenser.ModuleScript"))

-- Set up a dispenser model
local function setupDispenser(model)
	-- Get config from model attributes
	local itemType = model:GetAttribute("DispenseItem") or "Marshmallow"
	local capacity = model:GetAttribute("Capacity") or 10

	-- Create dispenser instance
	local dispenser = Dispenser.new(itemType, capacity)

	-- Find Anchor
	local anchor = model:FindFirstChild("Anchor")
	if not anchor then
		warn("Dispenser: No Anchor found in", model.Name)
		return
	end

	-- Configure mesh from MeshName attribute
	local meshName = model:GetAttribute("MeshName")
	if meshName then
		local mesh = anchor:FindFirstChild(meshName)
		if mesh then
			mesh.Size = anchor.Size
			mesh.CFrame = anchor.CFrame
			mesh.Anchored = true
			-- Hide anchor, mesh is the visual
			anchor.Transparency = 1
		else
			warn("Dispenser: Mesh not found:", meshName)
		end
	end

	-- Find ProximityPrompt
	local prompt = anchor:FindFirstChild("ProximityPrompt")
	if not prompt then
		warn("Dispenser: No ProximityPrompt found in", model.Name)
		return
	end

	-- Set initial remaining count
	model:SetAttribute("Remaining", dispenser.remaining)

	-- Handle interaction
	prompt.Triggered:Connect(function(player)
		local item = dispenser:dispense()
		if item then
			item.Parent = ReplicatedStorage
			model:SetAttribute("Remaining", dispenser.remaining)
			print("Dispenser: Gave", item.Name, "to", player.Name)
		else
			print("Dispenser: Empty")
		end
	end)

	print("Dispenser: Set up", model.Name, "(DispenseItem:" .. itemType .. ", Capacity:" .. capacity .. ")")
end

-- Wait for model in RuntimeAssets
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("Dispenser")
setupDispenser(model)

print("Dispenser.Script loaded")
