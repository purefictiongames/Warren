--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Visibility.lua (ReplicatedStorage)
-- Shared visibility utilities for model hide/show
-- Uses VisibleTransparency attribute as source of truth for original transparency values

local Visibility = {}

--- Hide all BaseParts in a model by setting transparency to 1
--- Stores original transparency in VisibleTransparency attribute for later restoration
---@param model Instance The model to hide
function Visibility.hideModel(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			-- Store original transparency if not already stored
			if part:GetAttribute("VisibleTransparency") == nil then
				part:SetAttribute("VisibleTransparency", part.Transparency)
			end
			part.Transparency = 1
		end
	end
end

--- Show all BaseParts in a model by restoring from VisibleTransparency attribute
---@param model Instance The model to show
function Visibility.showModel(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local visible = part:GetAttribute("VisibleTransparency")
			part.Transparency = visible or 0
		end
	end
end

--- Check if a model is currently hidden (transparency = 1 with stored original)
---@param model Instance The model to check
---@return boolean True if model appears to be hidden
function Visibility.isHidden(model)
	-- Check first BasePart descendant
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local stored = part:GetAttribute("VisibleTransparency")
			-- Hidden if we have a stored value and current transparency is 1
			return stored ~= nil and part.Transparency == 1
		end
	end
	return false
end

return Visibility
