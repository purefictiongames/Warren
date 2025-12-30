-- TimedEvaluator.LocalScript (Client)
-- Displays evaluation target and status above the TimedEvaluator

-- Guard: Only run if this is the deployed version
if not script.Name:match("^TimedEvaluator%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Dependencies (guaranteed to exist after READY stage)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local templates = ReplicatedStorage:WaitForChild("Templates")
local runtimeAssets = workspace:WaitForChild("RuntimeAssets")
local model = runtimeAssets:WaitForChild("TimedEvaluator")
local anchor = model:WaitForChild("Anchor")

local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Emoji stages from highest to lowest satisfaction
local EMOJI_STAGES = {
	{ min = 80, emoji = "😀" },
	{ min = 60, emoji = "🙂" },
	{ min = 40, emoji = "😐" },
	{ min = 20, emoji = "😢" },
	{ min = 0,  emoji = "😠" },
}

-- Toast colors from raw to burnt (0-100)
local TOAST_COLORS = {
	raw = Color3.fromRGB(255, 250, 240),
	golden = Color3.fromRGB(210, 160, 60),
	burnt = Color3.fromRGB(60, 30, 10),
}

-- Satisfaction border colors (0-100)
local SATISFACTION_COLORS = {
	high = Color3.fromRGB(0, 255, 0),
	mid = Color3.fromRGB(255, 255, 0),
	low = Color3.fromRGB(255, 0, 0),
}

local function getColorForSatisfaction(satisfaction)
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
	return "😠"
end

local function getColorForToastLevel(toastLevel)
	if toastLevel <= 50 then
		local t = toastLevel / 50
		return TOAST_COLORS.raw:Lerp(TOAST_COLORS.golden, t)
	else
		local t = (toastLevel - 50) / 50
		return TOAST_COLORS.golden:Lerp(TOAST_COLORS.burnt, t)
	end
end

-- Create BillboardGui using declarative system
local billboardGui = GUI:Create({
	type = "BillboardGui",
	name = "TimedEvaluatorDisplay",
	size = {2.5, 0, 1.25, 0},
	studsOffset = Vector3.new(0, 5.5, 0),
	alwaysOnTop = true,
	children = {
		{
			type = "Frame",
			name = "Container",
			size = {1, 0, 1, 0},
			backgroundTransparency = 1,
			listLayout = {
				direction = "Horizontal",
				hAlign = "Center",
				vAlign = "Center",
				padding = {0.1, 0},
				sortOrder = "LayoutOrder",
			},
			children = {
				{
					type = "ViewportFrame",
					id = "marshmallow-preview",
					name = "MarshmallowPreview",
					size = {1, 0, 1, 0},
					backgroundTransparency = 1,
					layoutOrder = 0,
				},
				{
					type = "TextLabel",
					id = "evaluator-emoji",
					name = "Emoji",
					size = {1, 0, 1, 0},
					backgroundTransparency = 1,
					text = "😀",
					textScaled = true,
					layoutOrder = 1,
				},
			}
		}
	}
})

-- Set adornee (needs runtime reference)
billboardGui.Adornee = anchor
billboardGui.Parent = playerGui

-- Get references
local viewport = GUI:GetById("marshmallow-preview")
local emojiLabel = GUI:GetById("evaluator-emoji")

-- Setup 3D preview in viewport (not part of GUI system)
local function setupMarshmallowPreview()
	local marshmallowTemplate = templates:FindFirstChild("Marshmallow")
	if not marshmallowTemplate then
		System.Debug:Warn("TimedEvaluator.client", "Marshmallow template not found")
		return nil
	end

	local handle = marshmallowTemplate:FindFirstChild("Handle")
	if not handle then
		System.Debug:Warn("TimedEvaluator.client", "No Handle found in Marshmallow template")
		return nil
	end

	System.Debug:Message("TimedEvaluator.client", "Handle found - Part Size:", handle.Size)

	local previewPart = handle:Clone()
	previewPart.CFrame = CFrame.new(0, 0, 0)
	previewPart.Anchored = true
	previewPart.CanCollide = false
	previewPart.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 50
	camera.CFrame = CFrame.new(Vector3.new(0.8, 0.6, 0.8), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 10
	light.Parent = previewPart

	System.Debug:Message("TimedEvaluator.client", "Preview part parented to viewport")

	return previewPart
end

local previewPart = setupMarshmallowPreview()

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

System.Debug:Message("TimedEvaluator.client", "Display ready")
