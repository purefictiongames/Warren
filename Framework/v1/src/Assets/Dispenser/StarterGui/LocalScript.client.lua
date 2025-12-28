-- Dispenser.LocalScript (Client)
-- Updates BillboardGui to show remaining count

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function createBillboardGui(anchor)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "DispenserDisplay"
	billboardGui.Adornee = anchor
	billboardGui.Size = UDim2.new(0, 96, 0, 32)
	billboardGui.StudsOffset = Vector3.new(0, 4.2, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0.8
	frame.Parent = billboardGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = frame

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 32, 0, 32)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://97382091340704"
	icon.LayoutOrder = 0
	icon.Parent = frame

	local xLabel = Instance.new("TextLabel")
	xLabel.Size = UDim2.new(0, 20, 1, 0)
	xLabel.BackgroundTransparency = 1
	xLabel.Text = "x"
	xLabel.TextColor3 = Color3.new(1, 0.667, 0)
	xLabel.Font = Enum.Font.GothamBold
	xLabel.TextSize = 28
	xLabel.LayoutOrder = 1
	xLabel.Parent = frame

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(0, 40, 1, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "0"
	countLabel.TextColor3 = Color3.new(1, 0.667, 0)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 28
	countLabel.LayoutOrder = 2
	countLabel.Parent = frame

	return billboardGui, countLabel
end

local function setupDisplay()
	local runtimeAssets = workspace:WaitForChild("RuntimeAssets")
	local model = runtimeAssets:WaitForChild("Dispenser")
	local anchor = model:WaitForChild("Anchor")

	local billboardGui, countLabel = createBillboardGui(anchor)

	local function updateDisplay()
		local remaining = model:GetAttribute("Remaining") or 0
		countLabel.Text = tostring(remaining)
	end

	-- Initial update
	updateDisplay()

	-- Listen for changes
	model:GetAttributeChangedSignal("Remaining"):Connect(updateDisplay)

	print("Dispenser.LocalScript: Display ready")
end

setupDisplay()
