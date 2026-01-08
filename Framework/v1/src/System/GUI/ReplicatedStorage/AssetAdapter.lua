--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- AssetAdapter.ModuleScript
-- Domain adapter for 3D asset instances (Model, BasePart, Attachment)
-- Handles transform properties: position, rotation, pivot, offset, scale

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DomainAdapter = require(ReplicatedStorage:WaitForChild("GUI.DomainAdapter"))

local AssetAdapter = {}

-- Asset-specific properties
local ASSET_PROPERTIES = {
	position = true,
	rotation = true,
	pivot = true,
	offset = true,
	scale = true,
}

--------------------------------------------------------------------------------
-- VALUE CONVERSION (Asset-specific)
--------------------------------------------------------------------------------

-- Convert array to Vector3
local function toVector3(value)
	if typeof(value) == "Vector3" then
		return value
	end
	if type(value) == "table" and #value == 3 then
		return Vector3.new(value[1], value[2], value[3])
	end
	return nil
end

-- Convert rotation degrees to radians Vector3
local function toRotationRadians(value)
	local vec = toVector3(value)
	if vec then
		return Vector3.new(
			math.rad(vec.X),
			math.rad(vec.Y),
			math.rad(vec.Z)
		)
	end
	return nil
end

-- Convert scale value (single number or Vector3)
local function toScaleValue(value)
	if type(value) == "number" then
		return Vector3.new(value, value, value)  -- Uniform scale
	end
	return toVector3(value)  -- Non-uniform scale
end

-- Convert explicit CFrame (advanced use)
local function toCFrame(value)
	if typeof(value) == "CFrame" then
		return value
	end
	-- Could support position + rotation table format here if needed
	return nil
end

--------------------------------------------------------------------------------
-- TRANSFORM APPLICATION
--------------------------------------------------------------------------------

-- Get baseline size for idempotent scaling
local function getBaselineSize(part)
	local baseline = part:GetAttribute("__StyleBaseSize")
	if baseline and type(baseline) == "table" and #baseline == 3 then
		return Vector3.new(baseline[1], baseline[2], baseline[3])
	end
	-- First time: store current size as baseline
	local size = part.Size
	part:SetAttribute("__StyleBaseSize", {size.X, size.Y, size.Z})
	return size
end

-- Apply scale to a BasePart (idempotent)
local function applyScale(part, scaleValue)
	-- Check if scaling is allowed
	if not part:GetAttribute("AllowScale") then
		warn("AssetAdapter: Scale blocked on " .. part:GetFullName() .. " (AllowScale attribute not set)")
		return
	end

	-- Get baseline size (stored on first application)
	local baseSize = getBaselineSize(part)

	-- Apply scale
	part.Size = Vector3.new(
		baseSize.X * scaleValue.X,
		baseSize.Y * scaleValue.Y,
		baseSize.Z * scaleValue.Z
	)
end

-- Apply transform to a Model
local function applyTransformToModel(model, position, rotation, offset, pivot)
	-- Start with current pivot or explicit pivot
	local baseCFrame = pivot or model:GetPivot()

	-- Apply position translation
	if position then
		baseCFrame = baseCFrame + position
	end

	-- Apply rotation
	if rotation then
		baseCFrame = baseCFrame * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
	end

	-- Apply local offset (in rotated space)
	if offset then
		baseCFrame = baseCFrame * CFrame.new(offset)
	end

	-- Apply the final transform
	model:PivotTo(baseCFrame)
end

-- Apply transform to a BasePart
local function applyTransformToPart(part, position, rotation, offset, pivot)
	-- Start with current CFrame or explicit pivot
	local baseCFrame = pivot or part.CFrame

	-- Apply position translation
	if position then
		baseCFrame = baseCFrame + position
	end

	-- Apply rotation
	if rotation then
		baseCFrame = baseCFrame * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
	end

	-- Apply local offset (in rotated space)
	if offset then
		baseCFrame = baseCFrame * CFrame.new(offset)
	end

	-- Apply the final transform
	part.CFrame = baseCFrame
end

-- Apply transform to an Attachment
local function applyTransformToAttachment(attachment, position, rotation, offset, pivot)
	-- Attachments use relative CFrame to parent
	local baseCFrame = pivot or attachment.CFrame

	-- Apply position translation
	if position then
		baseCFrame = baseCFrame + position
	end

	-- Apply rotation
	if rotation then
		baseCFrame = baseCFrame * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
	end

	-- Apply local offset (in rotated space)
	if offset then
		baseCFrame = baseCFrame * CFrame.new(offset)
	end

	-- Apply the final transform
	attachment.CFrame = baseCFrame
end

--------------------------------------------------------------------------------
-- DOMAIN ADAPTER IMPLEMENTATION
--------------------------------------------------------------------------------

-- Extract node identity information for selector matching
function AssetAdapter.getNodeInfo(node)
	if not node or not node:IsA("Instance") then
		return nil
	end

	-- Get class list from attribute (space-separated)
	local classString = node:GetAttribute("StyleClass") or ""
	local classList = {}
	for class in classString:gmatch("%S+") do
		table.insert(classList, class)
	end

	-- Get ID from attribute (or fallback to Name)
	local id = node:GetAttribute("StyleId") or node.Name

	-- Get attributes for selector matching
	local attributes = {}
	for name, value in pairs(node:GetAttributes()) do
		attributes[name] = value
	end

	return {
		domain = "asset",
		type = node.ClassName,
		classList = classList,
		id = id,
		attributes = attributes,
		parent = node.Parent,
		children = node:GetChildren(),
	}
end

-- Check if property is supported by Asset domain
function AssetAdapter.supportsProperty(propName)
	return ASSET_PROPERTIES[propName] == true
end

-- Convert raw style value to appropriate type
function AssetAdapter.computeProperty(propName, rawValue, node)
	if propName == "position" then
		return toVector3(rawValue)
	elseif propName == "rotation" then
		return toRotationRadians(rawValue)  -- Degrees -> Radians
	elseif propName == "pivot" then
		return toCFrame(rawValue)
	elseif propName == "offset" then
		return toVector3(rawValue)
	elseif propName == "scale" then
		return toScaleValue(rawValue)
	end

	return nil
end

-- Apply a single property to an asset node
function AssetAdapter.applyProperty(node, propName, convertedValue)
	-- Scale is handled separately (special case for BasePart only)
	if propName == "scale" then
		if node:IsA("BasePart") then
			applyScale(node, convertedValue)
		else
			warn("AssetAdapter: Scale only supported on BasePart instances")
		end
		return
	end

	-- Other properties are deferred to applyComputedStyle for batched transform
end

-- Apply all computed styles to a node (batched transform application)
function AssetAdapter.applyComputedStyle(node, computedStyle)
	if not node or not computedStyle then
		return
	end

	-- Extract transform properties
	local position = computedStyle.position
	local rotation = computedStyle.rotation
	local offset = computedStyle.offset
	local pivot = computedStyle.pivot
	local scale = computedStyle.scale

	-- Apply scale separately (BasePart only, idempotent)
	if scale and node:IsA("BasePart") then
		applyScale(node, scale)
	end

	-- Apply transforms based on node type
	if node:IsA("Model") then
		applyTransformToModel(node, position, rotation, offset, pivot)
	elseif node:IsA("BasePart") then
		applyTransformToPart(node, position, rotation, offset, pivot)
	elseif node:IsA("Attachment") then
		applyTransformToAttachment(node, position, rotation, offset, pivot)
	else
		warn("AssetAdapter: Unsupported node type for transforms: " .. node.ClassName)
	end
end

return AssetAdapter
