--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- Visibility.lua (ReplicatedStorage)
-- Shared visibility utilities for model hide/show
-- Handles:
--   BaseParts: Transparency, CanCollide, CanTouch
--   Decals/Textures: Transparency
--   Particles/Fire/Smoke/Sparkles: Enabled
--   Lights: Enabled
--   Sounds: Playing state
-- Uses attributes to store original values for restoration

local Visibility = {}

--- Hide all visual/audio elements in a model
--- Stores original values in attributes for later restoration
---@param model Instance The model to hide
function Visibility.hideModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			-- Store original values if not already stored
			if descendant:GetAttribute("VisibleTransparency") == nil then
				descendant:SetAttribute("VisibleTransparency", descendant.Transparency)
			end
			if descendant:GetAttribute("VisibleCanCollide") == nil then
				descendant:SetAttribute("VisibleCanCollide", descendant.CanCollide)
			end
			if descendant:GetAttribute("VisibleCanTouch") == nil then
				descendant:SetAttribute("VisibleCanTouch", descendant.CanTouch)
			end
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false

		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			if descendant:GetAttribute("VisibleTransparency") == nil then
				descendant:SetAttribute("VisibleTransparency", descendant.Transparency)
			end
			descendant.Transparency = 1

		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Fire")
			or descendant:IsA("Smoke") or descendant:IsA("Sparkles") then
			if descendant:GetAttribute("VisibleEnabled") == nil then
				descendant:SetAttribute("VisibleEnabled", descendant.Enabled)
			end
			descendant.Enabled = false

		elseif descendant:IsA("Light") then
			if descendant:GetAttribute("VisibleEnabled") == nil then
				descendant:SetAttribute("VisibleEnabled", descendant.Enabled)
			end
			descendant.Enabled = false

		elseif descendant:IsA("Sound") then
			-- Store original state
			if descendant:GetAttribute("VisiblePlaying") == nil then
				descendant:SetAttribute("VisiblePlaying", descendant.Playing or descendant.Looped)
			end
			if descendant:GetAttribute("VisibleVolume") == nil then
				descendant:SetAttribute("VisibleVolume", descendant.Volume)
			end
			if descendant:GetAttribute("VisibleSpeed") == nil then
				descendant:SetAttribute("VisibleSpeed", descendant.PlaybackSpeed)
			end
			-- Silence completely: stop, mute, and freeze
			descendant:Stop()
			descendant.Playing = false
			descendant.Volume = 0
			descendant.PlaybackSpeed = 0
		end
	end
end

--- Show all visual/audio elements in a model by restoring from stored attributes
---@param model Instance The model to show
function Visibility.showModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local visible = descendant:GetAttribute("VisibleTransparency")
			local canCollide = descendant:GetAttribute("VisibleCanCollide")
			local canTouch = descendant:GetAttribute("VisibleCanTouch")
			descendant.Transparency = visible or 0
			descendant.CanCollide = canCollide ~= nil and canCollide or true
			descendant.CanTouch = canTouch ~= nil and canTouch or true

		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			local visible = descendant:GetAttribute("VisibleTransparency")
			descendant.Transparency = visible or 0

		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Fire")
			or descendant:IsA("Smoke") or descendant:IsA("Sparkles") then
			local enabled = descendant:GetAttribute("VisibleEnabled")
			descendant.Enabled = enabled ~= nil and enabled or true

		elseif descendant:IsA("Light") then
			local enabled = descendant:GetAttribute("VisibleEnabled")
			descendant.Enabled = enabled ~= nil and enabled or true

		elseif descendant:IsA("Sound") then
			-- Restore all properties before playing
			local volume = descendant:GetAttribute("VisibleVolume")
			local speed = descendant:GetAttribute("VisibleSpeed")
			descendant.Volume = volume or 0.5
			descendant.PlaybackSpeed = speed or 1
			local wasPlaying = descendant:GetAttribute("VisiblePlaying")
			if wasPlaying then
				descendant:Play()
			end
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
