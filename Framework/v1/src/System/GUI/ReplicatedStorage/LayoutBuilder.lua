--[[
    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC

    This software, its architecture, and associated documentation are proprietary
    and confidential. All rights reserved.

    Unauthorized copying, modification, distribution, or use of this software,
    in whole or in part, is strictly prohibited without prior written permission.
--]]

-- LayoutBuilder.ModuleScript
-- Creates screen layouts from row/column grid definitions
-- Layouts define named regions that content can be assigned to

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ValueConverter = require(ReplicatedStorage:WaitForChild("GUI.ValueConverter"))

local LayoutBuilder = {}

-- Parse a percentage string like "50%" into a scale value (0.5)
local function parsePercent(value)
	if type(value) == "string" then
		local num = value:match("^(%d+)%%$")
		if num then
			return tonumber(num) / 100
		end
	elseif type(value) == "number" then
		-- Already a number, assume scale if <= 1, otherwise pixels
		if value <= 1 then
			return value
		else
			return nil, value  -- Return as offset
		end
	end
	return nil
end

-- Convert dimension value to UDim2 component
-- Supports: "50%" -> {0.5, 0}, 100 -> {0, 100}, {0.5, 10} -> {0.5, 10}
local function parseDimension(value, isWidth)
	if type(value) == "string" then
		local scale = parsePercent(value)
		if scale then
			return scale, 0
		end
	elseif type(value) == "number" then
		if value <= 1 then
			return value, 0  -- Treat as scale
		else
			return 0, value  -- Treat as pixels
		end
	elseif type(value) == "table" and #value == 2 then
		return value[1], value[2]
	end
	return 0, 0
end

-- Calculate alignment anchor and position adjustments
local function getAlignment(xalign, yalign)
	local anchorX, anchorY = 0, 0
	local posOffsetX, posOffsetY = 0, 0

	-- Horizontal alignment
	if xalign == "center" then
		anchorX = 0.5
	elseif xalign == "right" then
		anchorX = 1
	end

	-- Vertical alignment
	if yalign == "center" then
		anchorY = 0.5
	elseif yalign == "bottom" then
		anchorY = 1
	end

	return anchorX, anchorY
end

-- Build a single row frame
local function buildRow(rowDef, rowIndex, totalRows, yOffset)
	local heightScale, heightOffset = parseDimension(rowDef.height, false)

	local rowFrame = Instance.new("Frame")
	rowFrame.Name = "Row_" .. rowIndex
	rowFrame.BackgroundTransparency = 1  -- Rows are invisible containers
	rowFrame.Size = UDim2.new(1, 0, heightScale, heightOffset)
	rowFrame.Position = UDim2.new(0, 0, yOffset, 0)
	rowFrame.BorderSizePixel = 0

	return rowFrame, heightScale
end

-- Build a single column/cell frame within a row
local function buildColumn(colDef, colIndex, xOffset)
	local widthScale, widthOffset = parseDimension(colDef.width, true)

	local colFrame = Instance.new("Frame")
	colFrame.Name = colDef.id or ("Col_" .. colIndex)
	colFrame.BackgroundTransparency = 1  -- Columns are invisible containers
	colFrame.Size = UDim2.new(widthScale, widthOffset, 1, 0)  -- Full height of row
	colFrame.Position = UDim2.new(xOffset, 0, 0, 0)
	colFrame.BorderSizePixel = 0

	-- Apply alignment if specified
	local xalign = colDef.xalign or "left"
	local yalign = colDef.yalign or "top"
	local anchorX, anchorY = getAlignment(xalign, yalign)

	-- Store alignment info for content placement
	colFrame:SetAttribute("xalign", xalign)
	colFrame:SetAttribute("yalign", yalign)
	colFrame:SetAttribute("anchorX", anchorX)
	colFrame:SetAttribute("anchorY", anchorY)

	return colFrame, widthScale
end

-- Build a complete layout from definition
-- Returns: ScreenGui with region frames, and a regions table for content assignment
function LayoutBuilder.build(layoutDef, layoutName)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = layoutName or "Layout"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Container for all layout frames
	local container = Instance.new("Frame")
	container.Name = "LayoutContainer"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	-- Apply custom size if specified, otherwise full screen
	if layoutDef.size then
		local s = layoutDef.size
		container.Size = UDim2.new(s[1] or 1, s[2] or 0, s[3] or 1, s[4] or 0)
	else
		container.Size = UDim2.new(1, 0, 1, 0)
	end

	-- Apply custom position if specified
	if layoutDef.position then
		local p = layoutDef.position
		container.Position = UDim2.new(p[1] or 0, p[2] or 0, p[3] or 0, p[4] or 0)
	else
		container.Position = UDim2.new(0, 0, 0, 0)
	end

	container.Parent = screenGui

	-- Track regions by ID for content assignment
	local regions = {}

	-- Build rows
	local yOffset = 0
	local rows = layoutDef.rows or {}

	for rowIndex, rowDef in ipairs(rows) do
		local rowFrame, heightScale = buildRow(rowDef, rowIndex, #rows, yOffset)
		rowFrame.Parent = container

		-- Build columns within this row
		local xOffset = 0
		local columns = rowDef.columns or {}

		for colIndex, colDef in ipairs(columns) do
			local colFrame, widthScale = buildColumn(colDef, colIndex, xOffset)
			colFrame.Parent = rowFrame

			-- Register region by ID if specified
			if colDef.id then
				regions[colDef.id] = colFrame
			end

			xOffset = xOffset + widthScale
		end

		yOffset = yOffset + heightScale
	end

	return screenGui, regions
end

-- Assign content to a region
-- Content can be a definition table or an existing Instance
function LayoutBuilder.assignContent(region, content, gui, styles)
	if not region then
		warn("LayoutBuilder: Cannot assign content to nil region")
		return nil
	end

	local element

	if typeof(content) == "Instance" then
		-- Already an instance, just parent it
		element = content
	elseif type(content) == "table" then
		-- Create from definition
		local ElementFactory = require(ReplicatedStorage:WaitForChild("GUI.ElementFactory"))
		element = ElementFactory.createWithStyles(content, styles, gui)
	else
		warn("LayoutBuilder: Invalid content type")
		return nil
	end

	if element then
		-- Get alignment from region
		local xalign = region:GetAttribute("xalign") or "left"
		local yalign = region:GetAttribute("yalign") or "top"

		-- Apply alignment to content
		if element:IsA("GuiObject") then
			local anchorX = region:GetAttribute("anchorX") or 0
			local anchorY = region:GetAttribute("anchorY") or 0

			-- Position based on alignment
			local posX = anchorX  -- 0 for left, 0.5 for center, 1 for right
			local posY = anchorY  -- 0 for top, 0.5 for center, 1 for bottom

			element.AnchorPoint = Vector2.new(anchorX, anchorY)
			element.Position = UDim2.new(posX, 0, posY, 0)
		end

		element.Parent = region
	end

	return element
end

return LayoutBuilder
