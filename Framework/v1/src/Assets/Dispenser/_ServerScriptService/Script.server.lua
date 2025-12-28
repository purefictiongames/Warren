-- Dispenser.Script (Server)
-- Handles ProximityPrompt interaction and item dispensing
-- Synced

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispenser = require(ReplicatedStorage:WaitForChild("Dispenser.ModuleScript"))

-- MessageTicker loaded lazily to avoid blocking setup
local messageTicker = nil
task.spawn(function()
	messageTicker = ReplicatedStorage:WaitForChild("MessageTicker.MessageTicker", 10)
end)

-- Create Empty event for Orchestrator to listen to
local emptyEvent = Instance.new("BindableEvent")
emptyEvent.Name = "Dispenser.Empty"
emptyEvent.Parent = ReplicatedStorage

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
			-- Disable collision BEFORE parenting to prevent collision with player/dispenser
			-- Note: Don't anchor - just disable collision. Anchoring causes issues with Backpack.
			local handle = item:FindFirstChild("Handle")
			if handle then
				handle.CanCollide = false
			end

			local backpack = player.Backpack
			print("Dispenser: Putting", item.Name, "in backpack:", backpack:GetFullName())
			item.Parent = backpack
			model:SetAttribute("Remaining", dispenser.remaining)
			print("Dispenser: Gave", item.Name, "to", player.Name)

			-- Notify player
			if messageTicker then
				messageTicker:FireClient(player, "Roast your marshmallow over the campfire!")
			end

			-- Fire empty event if this was the last one
			if dispenser:isEmpty() then
				print("Dispenser: Now empty - firing event")
				emptyEvent:Fire()
			end
		else
			print("Dispenser: Empty")
			if messageTicker then
				messageTicker:FireClient(player, "The bag is empty!")
			end
		end
	end)

	-- Expose Reset via BindableFunction (for Orchestrator)
	local resetFunction = Instance.new("BindableFunction")
	resetFunction.Name = "Reset"
	resetFunction.OnInvoke = function()
		dispenser:refill()
		model:SetAttribute("Remaining", dispenser.remaining)
		print("Dispenser: Refilled to", dispenser.remaining)
		return true
	end
	resetFunction.Parent = model

	print("Dispenser: Set up", model.Name, "(DispenseItem:" .. itemType .. ", Capacity:" .. capacity .. ")")
end

-- Wait for model in RuntimeAssets
local runtimeAssets = game.Workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("Dispenser")
setupDispenser(model)

print("Dispenser.Script loaded")
