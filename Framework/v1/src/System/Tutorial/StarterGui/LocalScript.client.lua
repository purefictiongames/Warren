--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Tutorial.LocalScript (StarterGui)
-- Client-side HUD rendering for the Tutorial system
-- Renders popups, task lists, and object highlights

-- Guard: Only run if this is the deployed version
if not script.Name:match("^Tutorial%.") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- Wait for boot system
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.READY)

-- Load dependencies
local GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
local tutorialCommand = ReplicatedStorage:WaitForChild("Tutorial.TutorialCommand")

-- Load config
local config = nil
local configModule = ReplicatedFirst:FindFirstChild("Tutorial")
if configModule then
	configModule = configModule:FindFirstChild("TutorialConfig")
end
if configModule then
	config = require(configModule)
else
	-- Try deployed location
	local deployed = ReplicatedFirst:FindFirstChild("TutorialConfig")
	if deployed then
		config = require(deployed)
	end
end

if not config then
	warn("[Tutorial Client] Config not found")
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Current state
local currentState = "inactive"
local currentPopup = nil
local completedTasks = {}

-- Create popup window
local function createPopup(popupConfig)
	-- Remove existing popup
	if currentPopup then
		currentPopup:Destroy()
		currentPopup = nil
	end

	if not popupConfig then
		return
	end

	-- Build button children with unique IDs for later wiring
	local buttonChildren = {}
	local buttonConfigs = {} -- Store button configs for wiring
	for i, btn in ipairs(popupConfig.buttons or {}) do
		local buttonClass = btn.primary and "popup-btn popup-btn-primary" or "popup-btn"
		local buttonId = "popup-btn-" .. btn.id
		table.insert(buttonChildren, {
			type = "TextButton",
			id = buttonId,
			class = buttonClass,
			text = btn.text,
			size = { 0, 120, 0, 40 },
			position = { 0, (i - 1) * 130, 0, 0 },
		})
		table.insert(buttonConfigs, { elementId = buttonId, buttonId = btn.id })
	end

	-- Create popup using GUI system
	currentPopup = GUI:Create({
		type = "ScreenGui",
		name = "Tutorial.Popup",
		displayOrder = 200,
		resetOnSpawn = false,
		children = {
			-- Dark overlay
			{
				type = "Frame",
				class = "popup-overlay",
				size = { 1, 0, 1, 0 },
				position = { 0, 0, 0, 0 },
			},
			-- Popup window
			{
				type = "Frame",
				class = "popup-window",
				size = { 0.5, 0, 0.4, 0 },
				position = { 0.5, 0, 0.5, 0 },
				anchorPoint = { 0.5, 0.5 },
				children = {
					-- Title
					{
						type = "TextLabel",
						class = "popup-title",
						text = popupConfig.title or "",
						size = { 0.9, 0, 0.15, 0 },
						position = { 0.5, 0, 0.08, 0 },
						anchorPoint = { 0.5, 0 },
						textXAlignment = "Center",
					},
					-- Body
					{
						type = "TextLabel",
						class = "popup-body",
						text = popupConfig.body or "",
						size = { 0.85, 0, 0.5, 0 },
						position = { 0.5, 0, 0.25, 0 },
						anchorPoint = { 0.5, 0 },
						textXAlignment = "Left",
						textYAlignment = "Top",
						textWrapped = true,
					},
					-- Buttons container
					{
						type = "Frame",
						class = "transparent",
						size = { 0.8, 0, 0.2, 0 },
						position = { 0.5, 0, 0.8, 0 },
						anchorPoint = { 0.5, 0 },
						children = buttonChildren,
					},
				},
			},
		},
	})

	if currentPopup then
		currentPopup.Parent = playerGui

		-- Wire up button click events manually (GUI system doesn't support events field)
		for _, btnConfig in ipairs(buttonConfigs) do
			local button = GUI:GetById(btnConfig.elementId)
			if button then
				button.MouseButton1Click:Connect(function()
					tutorialCommand:FireServer({
						action = "button_click",
						buttonId = btnConfig.buttonId,
					})
				end)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- CREATE TASK LIST UI (at init, hidden by default)
--------------------------------------------------------------------------------

-- Create ScreenGui manually (layout system will find and reposition if active)
local taskListGui = Instance.new("ScreenGui")
taskListGui.Name = "Tutorial.TaskList"
taskListGui.DisplayOrder = 50
taskListGui.ResetOnSpawn = false
taskListGui.Enabled = false -- Hidden by default

-- Content frame that layout can move
local taskContent = Instance.new("Frame")
taskContent.Name = "Content"
taskContent.Size = UDim2.new(1, 0, 1, 0)
taskContent.BackgroundTransparency = 1
taskContent.Parent = taskListGui

-- Container for task items (will be rebuilt when tasks change)
local taskContainer = nil

-- Build and display task list content
local function rebuildTaskList()
	-- Clear existing container
	if taskContainer then
		taskContainer:Destroy()
	end

	-- Build task item children
	local taskChildren = {
		-- Header
		{
			type = "TextLabel",
			class = "task-header",
			text = "OBJECTIVES",
			size = { 0.9, 0, 0, 30 },
			position = { 0.5, 0, 0, 5 },
			anchorPoint = { 0.5, 0 },
			textXAlignment = "Center",
		},
	}

	local yOffset = 40
	for _, task in ipairs(config.tasks or {}) do
		local isCompleted = completedTasks[task.id] == true
		local checkmark = isCompleted and "[x]" or "[ ]"
		local itemClass = isCompleted and "task-item task-item-complete" or "task-item"
		local checkClass = isCompleted and "task-checkbox task-checkbox-complete" or "task-checkbox"

		-- Checkbox
		table.insert(taskChildren, {
			type = "TextLabel",
			class = checkClass,
			text = checkmark,
			size = { 0, 30, 0, 24 },
			position = { 0, 10, 0, yOffset },
			textXAlignment = "Left",
		})

		-- Task text
		table.insert(taskChildren, {
			type = "TextLabel",
			class = itemClass,
			text = task.text,
			size = { 0.7, 0, 0, 24 },
			position = { 0, 40, 0, yOffset },
			textXAlignment = "Left",
		})

		yOffset = yOffset + 28
	end

	-- Create task panel
	taskContainer = GUI:Create({
		type = "Frame",
		class = "task-panel",
		size = { 0.9, -10, 0.7, 0 },
		children = taskChildren,
	})
	taskContainer.Parent = taskContent
end

-- Show/hide task list
local function setTaskListVisible(visible)
	taskListGui.Enabled = visible
end

-- Update task list when task is completed
local function updateTaskList(taskId)
	completedTasks[taskId] = true
	rebuildTaskList()
end

-- Parent to PlayerGui (layout system will position it)
taskListGui.Parent = playerGui

-- Build initial content (hidden)
rebuildTaskList()

-- Handle state changes
local function onStateChanged(oldState, newState)
	currentState = newState

	-- Hide popup for non-popup states
	if currentPopup then
		currentPopup:Destroy()
		currentPopup = nil
	end

	-- Show appropriate popup
	if newState == "welcome" then
		createPopup(config.welcome)
	elseif newState == "rules" then
		createPopup(config.rules)
	elseif newState == "mode_select" then
		createPopup(config.modeSelect)
	elseif newState == "find_camper" then
		-- No popup - server will send MessageTicker hint
		-- (Client cannot call FireClient, that's server-only)
	end

	-- Show/hide task list based on state
	if newState == "practice" or newState == "playing" then
		completedTasks = {} -- Reset for new game
		rebuildTaskList()
		setTaskListVisible(true)
	elseif newState == "completed" or newState == "inactive" then
		setTaskListVisible(false)
	end

	System.Debug:Message("Tutorial Client", "State changed:", oldState, "->", newState)
end

-- Listen for server commands
tutorialCommand.OnClientEvent:Connect(function(data)
	local command = data.command

	if command == "state_changed" then
		onStateChanged(data.oldState, data.newState)
	elseif command == "task_complete" then
		updateTaskList(data.taskId)
	end
end)

System.Debug:Message("Tutorial Client", "Script loaded")
