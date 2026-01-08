--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Modal.lua (ReplicatedStorage)
-- Reusable modal dialog system with automatic input capture
-- Integrates with InputManager for input state coordination

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modal = {}
Modal.__index = Modal

-- Get GUI system (lazy load to avoid circular dependencies)
local GUI = nil
local function getGUI()
	if not GUI then
		GUI = require(ReplicatedStorage:WaitForChild("GUI.GUI"))
	end
	return GUI
end

-- Modal counter for unique IDs
local modalCounter = 0

-----------------------------------------------------------
-- Modal Instance Methods
-----------------------------------------------------------

--- Create a new modal dialog
---@param config table Modal configuration
---   config.id: string (optional) - Unique ID, auto-generated if not provided
---   config.title: string - Modal title
---   config.body: string or table - Body text or GUI definition
---   config.buttons: table - Array of button configs {id, label, primary, callback}
---   config.onClose: function (optional) - Called when modal is closed
---   config.width: number (optional) - Modal width in pixels (default 400)
---   config.closeOnOverlay: boolean (optional) - Close when clicking overlay (default false)
---@return Modal instance
function Modal.new(config)
	local self = setmetatable({}, Modal)

	modalCounter = modalCounter + 1
	self.id = config.id or ("modal_" .. modalCounter)
	self.config = config
	self.isShown = false
	self.screenGui = nil
	self.primaryButton = nil
	self.onClose = config.onClose

	return self
end

--- Build the modal UI
function Modal:_build()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "Modal." .. self.id
	screenGui.DisplayOrder = 200 -- Above other UI
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false

	-- Overlay (darkened background)
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui

	-- Close on overlay click if configured
	if self.config.closeOnOverlay then
		local overlayButton = Instance.new("TextButton")
		overlayButton.Name = "OverlayButton"
		overlayButton.Size = UDim2.new(1, 0, 1, 0)
		overlayButton.BackgroundTransparency = 1
		overlayButton.Text = ""
		overlayButton.Parent = overlay
		overlayButton.Activated:Connect(function()
			self:Hide()
		end)
	end

	-- Modal container (centered)
	local width = self.config.width or 400
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0, width, 0, 0) -- Height auto-calculated
	container.Position = UDim2.new(0.5, 0, 0.5, 0)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	container.BorderSizePixel = 0
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = overlay

	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container

	-- Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = container

	-- Layout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 15)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = container

	-- Title
	if self.config.title then
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 30)
		title.BackgroundTransparency = 1
		title.Text = self.config.title
		title.TextColor3 = Color3.new(1, 1, 1)
		title.TextSize = 24
		title.Font = Enum.Font.GothamBold
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.LayoutOrder = 1
		title.Parent = container
	end

	-- Body
	if self.config.body then
		local body
		if type(self.config.body) == "string" then
			body = Instance.new("TextLabel")
			body.Name = "Body"
			body.Size = UDim2.new(1, 0, 0, 0)
			body.AutomaticSize = Enum.AutomaticSize.Y
			body.BackgroundTransparency = 1
			body.Text = self.config.body
			body.TextColor3 = Color3.fromRGB(200, 200, 200)
			body.TextSize = 16
			body.Font = Enum.Font.Gotham
			body.TextWrapped = true
			body.TextXAlignment = Enum.TextXAlignment.Center
			body.LayoutOrder = 2
			body.Parent = container
		elseif type(self.config.body) == "table" then
			-- Body is a GUI definition, use GUI:Create
			local gui = getGUI()
			if gui then
				body = gui:Create(self.config.body)
				body.LayoutOrder = 2
				body.Parent = container
			end
		end
	end

	-- Buttons container
	if self.config.buttons and #self.config.buttons > 0 then
		local buttonContainer = Instance.new("Frame")
		buttonContainer.Name = "Buttons"
		buttonContainer.Size = UDim2.new(1, 0, 0, 45)
		buttonContainer.BackgroundTransparency = 1
		buttonContainer.LayoutOrder = 3
		buttonContainer.Parent = container

		local buttonLayout = Instance.new("UIListLayout")
		buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
		buttonLayout.FillDirection = Enum.FillDirection.Horizontal
		buttonLayout.Padding = UDim.new(0, 10)
		buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		buttonLayout.Parent = buttonContainer

		for i, btnConfig in ipairs(self.config.buttons) do
			local button = Instance.new("TextButton")
			button.Name = btnConfig.id or ("Button" .. i)
			button.Size = UDim2.new(0, 120, 0, 40)
			button.Text = btnConfig.label or "Button"
			button.TextSize = 16
			button.Font = Enum.Font.GothamBold
			button.LayoutOrder = i

			-- Style based on primary
			if btnConfig.primary then
				button.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
				button.TextColor3 = Color3.new(1, 1, 1)
				self.primaryButton = button
			else
				button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
				button.TextColor3 = Color3.fromRGB(200, 200, 200)
			end

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 4)
			btnCorner.Parent = button

			-- Button click handler
			button.Activated:Connect(function()
				if btnConfig.callback then
					btnConfig.callback(btnConfig.id)
				end
				-- Default behavior: close modal after button click
				if btnConfig.closeOnClick ~= false then
					self:Hide()
				end
			end)

			button.Parent = buttonContainer
		end

		-- If no primary button specified, use first button
		if not self.primaryButton and buttonContainer:FindFirstChildOfClass("TextButton") then
			self.primaryButton = buttonContainer:FindFirstChildOfClass("TextButton")
		end
	end

	screenGui.Parent = playerGui
	self.screenGui = screenGui
end

--- Show the modal
function Modal:Show()
	if self.isShown then return end

	-- Build UI if not already built
	if not self.screenGui then
		self:_build()
	end

	self.isShown = true
	self.screenGui.Enabled = true

	-- Focus primary button for gamepad navigation
	if self.primaryButton then
		GuiService.SelectedObject = self.primaryButton
	end

	-- Notify InputManager via RemoteEvent (if available)
	local pushModalRemote = ReplicatedStorage:FindFirstChild("Input.PushModalRemote")
	if pushModalRemote then
		pushModalRemote:FireServer(self.id)
	end
end

--- Hide the modal
function Modal:Hide()
	if not self.isShown then return end

	self.isShown = false

	if self.screenGui then
		self.screenGui.Enabled = false
	end

	-- Clear GUI selection
	GuiService.SelectedObject = nil

	-- Notify InputManager via RemoteEvent (if available)
	local popModalRemote = ReplicatedStorage:FindFirstChild("Input.PopModalRemote")
	if popModalRemote then
		popModalRemote:FireServer(self.id)
	end

	-- Call onClose callback
	if self.onClose then
		self.onClose()
	end
end

--- Destroy the modal completely
function Modal:Destroy()
	self:Hide()

	if self.screenGui then
		self.screenGui:Destroy()
		self.screenGui = nil
	end

	self.primaryButton = nil
end

--- Check if modal is currently shown
function Modal:IsShown()
	return self.isShown
end

-----------------------------------------------------------
-- Static Methods
-----------------------------------------------------------

--- Quick alert dialog (single OK button)
---@param title string
---@param message string
---@param callback function (optional) Called when OK clicked
---@return Modal
function Modal.Alert(title, message, callback)
	local modal = Modal.new({
		title = title,
		body = message,
		buttons = {
			{ id = "ok", label = "OK", primary = true, callback = callback },
		},
	})
	modal:Show()
	return modal
end

--- Quick confirm dialog (OK and Cancel buttons)
---@param title string
---@param message string
---@param onConfirm function Called when OK clicked
---@param onCancel function (optional) Called when Cancel clicked
---@return Modal
function Modal.Confirm(title, message, onConfirm, onCancel)
	local modal = Modal.new({
		title = title,
		body = message,
		buttons = {
			{ id = "ok", label = "OK", primary = true, callback = onConfirm },
			{ id = "cancel", label = "Cancel", callback = onCancel },
		},
	})
	modal:Show()
	return modal
end

return Modal
