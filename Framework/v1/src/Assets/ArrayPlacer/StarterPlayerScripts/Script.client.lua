--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- ArrayPlacer.LocalScript (Client)
-- Watches for dynamically spawned TimedEvaluator instances and creates displays
-- Handles the full spawn hierarchy: ArrayPlacer → Dropper → TimedEvaluator

-- Guard: Only run if deployed
if not script.Name:match("%.") then
	return
end

local assetName = script.Name:match("^(.+)%.")
if not assetName then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Dependencies
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local templates = ReplicatedStorage:WaitForChild("Templates")
local runtimeAssets = workspace:WaitForChild("RuntimeAssets")
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))

-- Track displays
local displays = {} -- [model] = { billboardGui, connections }

-- Pattern to detect TimedEvaluator-type models from this ArrayPlacer's hierarchy
-- Matches: CampPlacer_Dropper_N_Drop_M
local hierarchyPattern = "^" .. assetName .. "_"

-- Emoji stages
local EMOJI_STAGES = {
	{ min = 80, emoji = "😀" },
	{ min = 60, emoji = "🙂" },
	{ min = 40, emoji = "😐" },
	{ min = 20, emoji = "😢" },
	{ min = 0,  emoji = "😠" },
}

-- Toast colors
local TOAST_COLORS = {
	raw = Color3.fromRGB(255, 250, 240),
	golden = Color3.fromRGB(210, 160, 60),
	burnt = Color3.fromRGB(60, 30, 10),
}

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

-- Check if model is a TimedEvaluator (has the right structure/attributes)
local function isTimedEvaluator(model)
	-- Must be in our hierarchy
	if not model.Name:match(hierarchyPattern) then
		return false
	end

	-- Must have Anchor with EvaluationComplete, or have Satisfaction attribute
	local anchor = model:FindFirstChild("Anchor")
	if anchor and anchor:FindFirstChild("EvaluationComplete") then
		return true
	end

	if model:GetAttribute("Satisfaction") ~= nil then
		return true
	end

	return false
end

-- Create display for a TimedEvaluator model
local function createDisplay(model)
	if displays[model] then return end -- Already have display

	local anchor = model:FindFirstChild("Anchor")
	if not anchor then return end

	local spawnName = model.Name
	local previewId = spawnName .. "-preview"
	local emojiId = spawnName .. "-emoji"

	-- Create BillboardGui
	local billboardGui = GUI:Create({
		type = "BillboardGui",
		name = spawnName .. "_Display",
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
						id = previewId,
						name = "MarshmallowPreview",
						size = {1, 0, 1, 0},
						backgroundTransparency = 1,
						layoutOrder = 0,
					},
					{
						type = "TextLabel",
						id = emojiId,
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

	billboardGui.Adornee = anchor
	billboardGui.Enabled = false
	billboardGui.Parent = playerGui

	local viewport = GUI:GetById(previewId)
	local emojiLabel = GUI:GetById(emojiId)

	-- Setup 3D preview
	local previewPart = nil
	local marshmallowTemplate = templates:FindFirstChild("Marshmallow")
	if marshmallowTemplate then
		local handle = marshmallowTemplate:FindFirstChild("Handle")
		if handle then
			previewPart = handle:Clone()
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
		end
	end

	-- Update functions
	local function updateSatisfaction()
		local satisfaction = model:GetAttribute("Satisfaction") or 100
		emojiLabel.Text = getEmojiForSatisfaction(satisfaction)
	end

	local function updateToastPreview()
		if not previewPart then return end
		local targetValue = model:GetAttribute("TargetValue") or 50
		previewPart.Color = getColorForToastLevel(targetValue)
	end

	local function updateVisibility()
		local visible = model:GetAttribute("HUDVisible")
		billboardGui.Enabled = visible == true
	end

	-- Initial updates
	updateSatisfaction()
	updateToastPreview()
	updateVisibility()

	-- Connect to changes
	local connections = {
		model:GetAttributeChangedSignal("Satisfaction"):Connect(updateSatisfaction),
		model:GetAttributeChangedSignal("TargetValue"):Connect(updateToastPreview),
		model:GetAttributeChangedSignal("HUDVisible"):Connect(updateVisibility),
	}

	displays[model] = {
		billboardGui = billboardGui,
		connections = connections,
	}

	System.Debug:Message(assetName .. ".client", "Created display for", spawnName)
end

-- Remove display
local function removeDisplay(model)
	local display = displays[model]
	if not display then return end

	for _, conn in ipairs(display.connections) do
		conn:Disconnect()
	end

	if display.billboardGui then
		display.billboardGui:Destroy()
	end

	displays[model] = nil
	System.Debug:Message(assetName .. ".client", "Removed display for", model.Name)
end

-- Watch for new models
runtimeAssets.ChildAdded:Connect(function(child)
	task.wait(0.1) -- Let model settle
	if isTimedEvaluator(child) then
		createDisplay(child)
	end
end)

-- Watch for removed models
runtimeAssets.ChildRemoved:Connect(function(child)
	if displays[child] then
		removeDisplay(child)
	end
end)

-- Check existing models
for _, child in ipairs(runtimeAssets:GetChildren()) do
	if isTimedEvaluator(child) and not displays[child] then
		createDisplay(child)
	end
end

System.Debug:Message(assetName .. ".client", "Watching for TimedEvaluator instances")
