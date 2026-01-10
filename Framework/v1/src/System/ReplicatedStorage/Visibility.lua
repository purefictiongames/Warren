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

--- Bind model parts to follow the Anchor using physics constraints
--- Parts maintain their relative offset from the Anchor when it moves
--- For Humanoids: binds HumanoidRootPart/Torso (body follows via Motor6D)
--- For other models: binds all unanchored root parts
---@param model Instance The model containing an Anchor part
---@param options table? Optional config { responsiveness = 200, maxForce = math.huge }
---@return table Array of created constraints (for cleanup if needed)
function Visibility.bindToAnchor(model, options)
	options = options or {}
	local responsiveness = options.responsiveness or 200
	local maxForce = options.maxForce or math.huge

	local anchor = model:FindFirstChild("Anchor")
	if not anchor or not anchor:IsA("BasePart") then
		warn("[Visibility.bindToAnchor] No Anchor BasePart found in", model.Name)
		return {}
	end

	local constraints = {}

	-- Helper to bind a part to the anchor
	local function bindPart(part)
		if part == anchor then return end
		if part.Anchored then return end -- Don't bind anchored parts

		-- Calculate current offset from anchor
		local offset = anchor.CFrame:ToObjectSpace(part.CFrame)

		-- Create attachment on anchor at the offset position
		local anchorAttachment = Instance.new("Attachment")
		anchorAttachment.Name = part.Name .. "_AnchorAttachment"
		anchorAttachment.CFrame = offset
		anchorAttachment.Parent = anchor

		-- Create attachment on the target part (at its center)
		local partAttachment = Instance.new("Attachment")
		partAttachment.Name = "AnchorBindAttachment"
		partAttachment.Parent = part

		-- AlignPosition: pulls part toward anchor attachment
		local alignPos = Instance.new("AlignPosition")
		alignPos.Name = part.Name .. "_AlignPosition"
		alignPos.Mode = Enum.PositionAlignmentMode.TwoAttachment
		alignPos.Attachment0 = partAttachment
		alignPos.Attachment1 = anchorAttachment
		alignPos.MaxForce = maxForce
		alignPos.Responsiveness = responsiveness
		alignPos.RigidityEnabled = false -- Use force-based, not instant
		alignPos.Parent = part

		-- AlignOrientation: keeps part rotation aligned with anchor
		local alignOri = Instance.new("AlignOrientation")
		alignOri.Name = part.Name .. "_AlignOrientation"
		alignOri.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		alignOri.Attachment0 = partAttachment
		alignOri.Attachment1 = anchorAttachment
		alignOri.MaxTorque = maxForce
		alignOri.Responsiveness = responsiveness
		alignOri.RigidityEnabled = false
		alignOri.Parent = part

		table.insert(constraints, anchorAttachment)
		table.insert(constraints, partAttachment)
		table.insert(constraints, alignPos)
		table.insert(constraints, alignOri)
	end

	-- Check for Humanoid (bind root part only - body follows via Motor6D)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		-- Check descendants (humanoid might be nested in Walking NPC model)
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("Humanoid") then
				humanoid = desc
				break
			end
		end
	end

	if humanoid then
		-- Find the root part (HumanoidRootPart for R15, Torso for R6)
		local rootPart = humanoid.RootPart
		if not rootPart then
			-- Fallback: search for common root part names
			local humanoidModel = humanoid.Parent
			rootPart = humanoidModel:FindFirstChild("HumanoidRootPart")
				or humanoidModel:FindFirstChild("Torso")
		end

		if rootPart then
			bindPart(rootPart)
		else
			warn("[Visibility.bindToAnchor] Humanoid found but no root part in", model.Name)
		end
	else
		-- No humanoid - bind all unanchored BaseParts that are direct children
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and child ~= anchor then
				bindPart(child)
			elseif child:IsA("Model") then
				-- Check for nested models with unanchored parts
				local primaryPart = child.PrimaryPart or child:FindFirstChildOfClass("BasePart")
				if primaryPart and not primaryPart.Anchored then
					bindPart(primaryPart)
				end
			end
		end
	end

	return constraints
end

--- Remove all anchor bindings from a model
---@param model Instance The model to unbind
function Visibility.unbindFromAnchor(model)
	local anchor = model:FindFirstChild("Anchor")
	if anchor then
		-- Remove attachments from anchor
		for _, child in ipairs(anchor:GetChildren()) do
			if child:IsA("Attachment") and child.Name:match("_AnchorAttachment$") then
				child:Destroy()
			end
		end
	end

	-- Remove constraints and attachments from all parts
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Attachment") and desc.Name == "AnchorBindAttachment" then
			desc:Destroy()
		elseif desc:IsA("AlignPosition") and desc.Name:match("_AlignPosition$") then
			desc:Destroy()
		elseif desc:IsA("AlignOrientation") and desc.Name:match("_AlignOrientation$") then
			desc:Destroy()
		end
	end
end

return Visibility
