-- TimedEvaluator.LocalScript (Client)
-- Displays evaluation target and status above the TimedEvaluator

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Emoji stages from highest to lowest satisfaction
local EMOJI_STAGES = {
	{ min = 80, emoji = "😀" },  -- Grinning
	{ min = 60, emoji = "🙂" },  -- Smiling
	{ min = 40, emoji = "😐" },  -- Meh
	{ min = 20, emoji = "😢" },  -- Sad
	{ min = 0,  emoji = "😠" },  -- Angry
}

-- Toast colors from raw to burnt (0-100)
local TOAST_COLORS = {
	raw = Color3.fromRGB(255, 250, 240),    -- Off-white
	golden = Color3.fromRGB(210, 160, 60),  -- Golden brown
	burnt = Color3.fromRGB(60, 30, 10),     -- Dark brown
}

-- Satisfaction border colors (0-100)
local SATISFACTION_COLORS = {
	high = Color3.fromRGB(0, 255, 0),       -- Green
	mid = Color3.fromRGB(255, 255, 0),      -- Yellow
	low = Color3.fromRGB(255, 0, 0),        -- Red
}

local function getColorForSatisfaction(satisfaction)
	-- Interpolate: 100-50 = green→yellow, 50-0 = yellow→red
	if satisfaction >= 50 then
		local t = (satisfaction - 50) / 50
		return SATISFACTION_COLORS.mid:Lerp(SATISFACTION_COLORS.high, t)
	else
		local t = satisfaction / 50
		return SATISFACTION_COLORS.low:Lerp(SATISFACTION_COLORS.mid, t)
	end
end

local function getEmojiForSatisfaction(satisfaction)
	for _, stage in ipairs(EMOJI_STAGES) do
		if satisfaction >= stage.min then
			return stage.emoji
		end
	end
	return "😠" -- Fallback
end

local function getColorForToastLevel(toastLevel)
	-- Interpolate: 0-50 = raw→golden, 50-100 = golden→burnt
	if toastLevel <= 50 then
		local t = toastLevel / 50
		return TOAST_COLORS.raw:Lerp(TOAST_COLORS.golden, t)
	else
		local t = (toastLevel - 50) / 50
		return TOAST_COLORS.golden:Lerp(TOAST_COLORS.burnt, t)
	end
end

local function createBillboardGui(anchor)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "TimedEvaluatorDisplay"
	billboardGui.Adornee = anchor
	billboardGui.Size = UDim2.new(2.5, 0, 1.25, 0) -- Wider to fit both elements
	billboardGui.StudsOffset = Vector3.new(0, 5.5, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Parent = playerGui

	-- Container frame for horizontal layout
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = billboardGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.1, 0)
	layout.Parent = container

	-- Marshmallow viewport
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "MarshmallowPreview"
	viewport.Size = UDim2.new(1, 0, 1, 0)
	viewport.BackgroundTransparency = 1
	viewport.LayoutOrder = 0
	viewport.Parent = container

	-- Emoji label
	local emojiLabel = Instance.new("TextLabel")
	emojiLabel.Name = "Emoji"
	emojiLabel.Size = UDim2.new(1, 0, 1, 0)
	emojiLabel.BackgroundTransparency = 1
	emojiLabel.Text = "😀"
	emojiLabel.TextScaled = true
	emojiLabel.LayoutOrder = 1
	emojiLabel.Parent = container

	return billboardGui, emojiLabel, viewport
end

local function setupMarshmallowPreview(viewport)
	-- Get marshmallow template
	local templates = ReplicatedStorage:WaitForChild("Templates")
	local marshmallowTemplate = templates:FindFirstChild("Marshmallow")
	if not marshmallowTemplate then
		warn("TimedEvaluator: Marshmallow template not found")
		return nil
	end

	-- Find the Handle part
	local handle = marshmallowTemplate:FindFirstChild("Handle")
	if not handle then
		warn("TimedEvaluator: No Handle found in Marshmallow template")
		return nil
	end

	print("TimedEvaluator: Handle found -", handle.ClassName, "Size:", handle.Size)

	-- Clone just the handle for the viewport
	local previewPart = handle:Clone()
	previewPart.CFrame = CFrame.new(0, 0, 0)
	previewPart.Anchored = true
	previewPart.CanCollide = false
	previewPart.Parent = viewport

	-- Create camera - isometric angle
	local camera = Instance.new("Camera")
	camera.FieldOfView = 50
	camera.CFrame = CFrame.new(Vector3.new(0.8, 0.6, 0.8), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Add lighting
	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 10
	light.Parent = previewPart

	print("TimedEvaluator: Preview part parented to viewport")

	return previewPart
end

local function setupDisplay()
	local runtimeAssets = workspace:WaitForChild("RuntimeAssets")
	local model = runtimeAssets:WaitForChild("TimedEvaluator")
	local anchor = model:WaitForChild("Anchor")

	local billboardGui, emojiLabel, viewport = createBillboardGui(anchor)
	local previewPart = setupMarshmallowPreview(viewport)

	local function updateSatisfactionDisplay()
		local satisfaction = model:GetAttribute("Satisfaction") or 100
		emojiLabel.Text = getEmojiForSatisfaction(satisfaction)
	end

	local function updateToastPreview()
		if not previewPart then return end
		local targetValue = model:GetAttribute("TargetValue") or 50
		previewPart.Color = getColorForToastLevel(targetValue)
	end

	-- Initial updates
	updateSatisfactionDisplay()
	updateToastPreview()

	-- Listen for changes
	model:GetAttributeChangedSignal("Satisfaction"):Connect(updateSatisfactionDisplay)
	model:GetAttributeChangedSignal("TargetValue"):Connect(updateToastPreview)

	print("TimedEvaluator.LocalScript: Display ready")
end

setupDisplay()
