--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Tutorial.module (Client - StarterGui)
-- Client-side HUD rendering for the Tutorial system
-- Discovered and loaded by System.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- Wait for System module
local System = require(ReplicatedStorage:WaitForChild("System.System"))

--------------------------------------------------------------------------------
-- MODULE STATE
--------------------------------------------------------------------------------

local GUI
local Modal
local tutorialCommand
local config
local player
local playerGui
local currentState = "inactive"
local currentPopup = nil
local completedTasks = {}
local taskListGui
local taskContent
local taskContainer

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Create popup window using Modal system
local function createPopup(popupConfig)
	if currentPopup then
		currentPopup:Destroy()
		currentPopup = nil
	end

	if not popupConfig then
		return
	end

	local modalButtons = {}
	for i, btn in ipairs(popupConfig.buttons or {}) do
		local isPrimary = btn.primary or (i == 1)
		table.insert(modalButtons, {
			id = btn.id,
			label = btn.text,
			primary = isPrimary,
			closeOnClick = false,
			callback = function(buttonId)
				System.Debug:Message("Tutorial Client", "Button activated:", buttonId)
				tutorialCommand:FireServer({
					action = "button_click",
					buttonId = buttonId,
				})
			end,
		})
	end

	currentPopup = Modal.new({
		id = "tutorial-popup",
		title = popupConfig.title,
		body = popupConfig.body,
		buttons = modalButtons,
		width = 500,
	})
	currentPopup:Show()

	System.Debug:Message("Tutorial Client", "Created popup with Modal system")
end

-- Build and display task list content
local function rebuildTaskList()
	if taskContainer then
		taskContainer:Destroy()
	end

	local taskChildren = {
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
		local checkClass = isCompleted and "task-checkbox task-checkbox-complete" or "task-checkbox"

		table.insert(taskChildren, {
			type = "TextLabel",
			class = checkClass,
			text = checkmark,
			size = { 0, 30, 0, 24 },
			position = { 0, 10, 0, yOffset },
			textXAlignment = "Left",
		})

		local itemClass = isCompleted and "task-item task-item-complete" or "task-item"
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

	taskContainer = GUI:Create({
		type = "Frame",
		class = "task-panel",
		size = { 0.9, -10, 0.7, 0 },
		children = taskChildren,
	})
	taskContainer.Parent = taskContent
end

local function setTaskListVisible(visible)
	taskContent.Visible = visible
end

local function updateTaskList(taskId)
	completedTasks[taskId] = true
	rebuildTaskList()
end

-- Handle state changes
local function onStateChanged(oldState, newState)
	currentState = newState
	System.Debug:Message("Tutorial Client", "State changed:", oldState, "->", newState)

	if currentPopup then
		currentPopup:Destroy()
		currentPopup = nil
	end

	if newState == "welcome" then
		createPopup(config.welcome)
	elseif newState == "rules" then
		createPopup(config.rules)
	elseif newState == "mode_select" then
		createPopup(config.modeSelect)
	end

	if newState == "practice" or newState == "playing" then
		completedTasks = {}
		rebuildTaskList()
		setTaskListVisible(true)
	elseif newState == "completed" or newState == "inactive" then
		setTaskListVisible(false)
	end
end

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

return {
	dependencies = { "GUI.Script" },  -- Depends on GUI.Script for Modal and Create

	init = function(self)
		-- Load dependencies
		GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
		Modal = require(ReplicatedStorage:WaitForChild("GUI.Modal"))
		tutorialCommand = ReplicatedStorage:WaitForChild("Tutorial.TutorialCommand")

		-- Load config
		local configModule = ReplicatedFirst:FindFirstChild("Tutorial")
		if configModule then
			configModule = configModule:FindFirstChild("TutorialConfig")
		end
		if configModule then
			config = require(configModule)
		else
			local deployed = ReplicatedFirst:FindFirstChild("TutorialConfig")
			if deployed then
				config = require(deployed)
			end
		end

		if not config then
			System.Debug:Warn("Tutorial Client", "Config not found")
			return
		end

		player = Players.LocalPlayer
		playerGui = player:WaitForChild("PlayerGui")

		-- Create task list UI
		taskListGui = Instance.new("ScreenGui")
		taskListGui.Name = "Tutorial.TaskList"
		taskListGui.DisplayOrder = 50
		taskListGui.ResetOnSpawn = false
		taskListGui.Enabled = false

		taskContent = Instance.new("Frame")
		taskContent.Name = "Content"
		taskContent.Size = UDim2.new(1, 0, 1, 0)
		taskContent.BackgroundTransparency = 1
		taskContent.Visible = false
		taskContent.Parent = taskListGui

		taskListGui.Parent = playerGui

		rebuildTaskList()
	end,

	start = function(self)
		if not config then
			return
		end

		tutorialCommand.OnClientEvent:Connect(function(data)
			local command = data.command

			if command == "state_changed" then
				onStateChanged(data.oldState, data.newState)
			elseif command == "task_complete" then
				updateTaskList(data.taskId)
			end
		end)

		System.Debug:Message("Tutorial Client", "Started")
	end,
}
