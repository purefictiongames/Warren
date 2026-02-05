--[[
    LibPureFiction Framework v2
    PixelFont.lua - 8x8 NES-style Pixel Font Renderer

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    local PixelFont = require(path.to.PixelFont)

    -- Create a text label (returns a Frame containing ImageLabels)
    local textFrame = PixelFont.createText("HELLO WORLD", {
        scale = 4,              -- 4x scale = 32x32 pixel characters
        color = Color3.new(1, 1, 1),  -- White text
        spacing = 0,            -- Extra spacing between characters (pixels at base scale)
    })
    textFrame.Parent = someGui

    -- Update existing text
    PixelFont.updateText(textFrame, "NEW TEXT")

    ============================================================================
    SUPPORTED CHARACTERS
    ============================================================================

    Uses DOS Codepage 437 (256 characters) via ASCII byte values:
    - Standard ASCII: A-Z, a-z, 0-9, punctuation, symbols (0-127)
    - Extended ASCII: Box drawing, accented chars, Greek, math symbols (128-255)

    Font spritesheet: DOS 8x8 font from OpenGameArt.org (CC-BY-SA 3.0)
    https://opengameart.org/content/dos-8x8-font

--]]

local TweenService = game:GetService("TweenService")

local PixelFont = {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Asset ID for the spritesheet (update after uploading to Roblox)
-- Use the DOS 8x8 font from OpenGameArt: https://opengameart.org/content/dos-8x8-font
local SPRITESHEET_ASSET = "rbxassetid://128496795370434"

-- Glyph dimensions
local GLYPH_WIDTH = 8
local GLYPH_HEIGHT = 8

-- Grid layout: 16 characters per row (standard for 256-char fonts)
-- The DOS font has a 1px yellow grid border, so stride is 9px (8 + 1)
local GRID_COLUMNS = 16
local GRID_STRIDE = 9  -- 8px glyph + 1px grid line

-- Helper: Get glyph position from character (uses ASCII code directly)
-- Returns xOffset, yOffset or nil if character not supported
local function getGlyphOffset(char)
    local byte = string.byte(char)
    if not byte or byte > 255 then
        return nil
    end

    local col = byte % GRID_COLUMNS
    local row = math.floor(byte / GRID_COLUMNS)

    -- Account for 1px grid offset at start, then 9px stride
    local xOffset = 1 + col * GRID_STRIDE
    local yOffset = 1 + row * GRID_STRIDE

    return xOffset, yOffset
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--- Set the spritesheet asset ID
---@param assetId string The rbxassetid:// URL
function PixelFont.setAsset(assetId: string)
    SPRITESHEET_ASSET = assetId
end

--- Calculate the width of text in pixels at a given scale
---@param text string The text to measure
---@param scale number? Scale factor (default 1)
---@param spacing number? Extra spacing between characters (default 0)
---@return number The total width in pixels
function PixelFont.getTextWidth(text: string, scale: number?, spacing: number?): number
    scale = scale or 1
    spacing = spacing or 0
    local charWidth = GLYPH_WIDTH * scale
    local totalSpacing = spacing * scale
    local textLen = utf8.len(text) or 0
    return textLen * charWidth + math.max(0, textLen - 1) * totalSpacing
end

--- Calculate the integer scale needed to achieve a target character height
---@param targetHeight number The desired character height in pixels
---@return number The integer scale factor (minimum 1)
function PixelFont.calculateScale(targetHeight: number): number
    return math.max(1, math.floor(targetHeight / GLYPH_HEIGHT))
end

--- Create a text display from a string
---@param text string The text to display
---@param options table? Optional settings: scale, color, spacing, alignment
---@return Frame The container frame with character ImageLabels
function PixelFont.createText(text: string, options: {
    scale: number?,
    color: Color3?,
    spacing: number?,
    alignment: string?,  -- "left" (default), "center", or "right"
}?): Frame
    options = options or {}
    local scale = options.scale or 1
    local color = options.color or Color3.new(1, 1, 1)
    local spacing = options.spacing or 0
    local alignment = options.alignment or "left"

    local charWidth = GLYPH_WIDTH * scale
    local charHeight = GLYPH_HEIGHT * scale
    local totalSpacing = spacing * scale
    local textLen = utf8.len(text) or 0
    local totalWidth = textLen * charWidth + math.max(0, textLen - 1) * totalSpacing

    -- Create container frame
    local container = Instance.new("Frame")
    container.Name = "PixelText"
    container.BackgroundTransparency = 1
    container.Size = UDim2.fromOffset(totalWidth, charHeight)
    container.ZIndex = 100  -- High ZIndex to ensure visibility

    -- Store text for updates
    container:SetAttribute("PixelFontText", text)
    container:SetAttribute("PixelFontScale", scale)
    container:SetAttribute("PixelFontSpacing", spacing)
    container:SetAttribute("PixelFontAlignment", alignment)

    -- Create character labels
    local charIndex = 0
    for _, codepoint in utf8.codes(text) do
        charIndex = charIndex + 1
        local char = utf8.char(codepoint)
        local xOffset, yOffset = getGlyphOffset(char)

        local charLabel = Instance.new("ImageLabel")
        charLabel.Name = "Char" .. charIndex
        charLabel.BackgroundTransparency = 1
        charLabel.Size = UDim2.fromOffset(charWidth, charHeight)
        charLabel.Position = UDim2.fromOffset((charIndex - 1) * (charWidth + totalSpacing), 0)
        charLabel.Image = SPRITESHEET_ASSET
        charLabel.ImageColor3 = color
        charLabel.ResampleMode = Enum.ResamplerMode.Pixelated
        charLabel.ScaleType = Enum.ScaleType.Crop
        charLabel.ZIndex = 100  -- High ZIndex to ensure visibility

        if xOffset and yOffset then
            charLabel.ImageRectOffset = Vector2.new(xOffset, yOffset)
            charLabel.ImageRectSize = Vector2.new(GLYPH_WIDTH, GLYPH_HEIGHT)
        else
            -- Unknown character - show blank
            charLabel.ImageTransparency = 1
        end

        charLabel.Parent = container
    end

    return container
end

--- Update an existing text display with new text
---@param container Frame The container frame from createText
---@param newText string The new text to display
function PixelFont.updateText(container: Frame, newText: string)
    local scale = container:GetAttribute("PixelFontScale") or 1
    local spacing = container:GetAttribute("PixelFontSpacing") or 0

    local charWidth = GLYPH_WIDTH * scale
    local charHeight = GLYPH_HEIGHT * scale
    local totalSpacing = spacing * scale

    -- Get existing character labels
    local existingLabels = {}
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("ImageLabel") and string.match(child.Name, "^Char%d+$") then
            table.insert(existingLabels, child)
        end
    end

    -- Sort by name to maintain order
    table.sort(existingLabels, function(a, b)
        local numA = tonumber(string.match(a.Name, "%d+")) or 0
        local numB = tonumber(string.match(b.Name, "%d+")) or 0
        return numA < numB
    end)

    -- Update or create labels as needed
    local charIndex = 0
    for _, codepoint in utf8.codes(newText) do
        charIndex = charIndex + 1
        local char = utf8.char(codepoint)
        local xOffset, yOffset = getGlyphOffset(char)

        local charLabel = existingLabels[charIndex]
        if not charLabel then
            -- Create new label
            charLabel = Instance.new("ImageLabel")
            charLabel.Name = "Char" .. charIndex
            charLabel.BackgroundTransparency = 1
            charLabel.Size = UDim2.fromOffset(charWidth, charHeight)
            charLabel.Image = SPRITESHEET_ASSET
            charLabel.ImageColor3 = existingLabels[1] and existingLabels[1].ImageColor3 or Color3.new(1, 1, 1)
            charLabel.ResampleMode = Enum.ResamplerMode.Pixelated
            charLabel.ScaleType = Enum.ScaleType.Crop
            charLabel.ZIndex = 100  -- High ZIndex to ensure visibility
            charLabel.Parent = container
        end

        charLabel.Position = UDim2.fromOffset((charIndex - 1) * (charWidth + totalSpacing), 0)

        if xOffset and yOffset then
            charLabel.ImageRectOffset = Vector2.new(xOffset, yOffset)
            charLabel.ImageRectSize = Vector2.new(GLYPH_WIDTH, GLYPH_HEIGHT)
            charLabel.ImageTransparency = 0
        else
            charLabel.ImageTransparency = 1
        end
    end

    -- Remove extra labels
    local textLen = utf8.len(newText)
    for i = textLen + 1, #existingLabels do
        existingLabels[i]:Destroy()
    end

    -- Update container size
    container.Size = UDim2.fromOffset(
        textLen * charWidth + math.max(0, textLen - 1) * totalSpacing,
        charHeight
    )

    container:SetAttribute("PixelFontText", newText)
end

--- Set the color of all characters in a text display
---@param container Frame The container frame from createText
---@param color Color3 The new color
function PixelFont.setColor(container: Frame, color: Color3)
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("ImageLabel") then
            child.ImageColor3 = color
        end
    end
end

--- Set the transparency of all characters in a text display
---@param container Frame The container frame from createText
---@param transparency number 0 = opaque, 1 = invisible
function PixelFont.setTransparency(container: Frame, transparency: number)
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("ImageLabel") then
            child.ImageTransparency = transparency
        end
    end
end

--- Create a clickable button with pixel text
---@param text string The button text
---@param options table? Optional settings: scale, color, spacing, alignment, backgroundColor, backgroundTransparency, padding
---@return TextButton The clickable button wrapper
---@return Frame The pixel text container (for updateText)
function PixelFont.createButton(text: string, options: {
    scale: number?,
    color: Color3?,
    spacing: number?,
    alignment: string?,
    backgroundColor: Color3?,
    backgroundTransparency: number?,
    padding: number?,
}?): (TextButton, Frame)
    options = options or {}
    local scale = options.scale or 1
    local color = options.color or Color3.new(1, 1, 1)
    local spacing = options.spacing or 0
    local alignment = options.alignment or "center"
    local bgColor = options.backgroundColor or Color3.fromRGB(40, 40, 50)
    local bgTransparency = options.backgroundTransparency or 0
    local padding = options.padding or 8

    -- Create the text first to get dimensions
    local textFrame = PixelFont.createText(text, {
        scale = scale,
        color = color,
        spacing = spacing,
        alignment = alignment,
    })

    local textWidth = textFrame.Size.X.Offset
    local textHeight = textFrame.Size.Y.Offset

    -- Create button wrapper
    local button = Instance.new("TextButton")
    button.Name = "PixelButton"
    button.Text = ""  -- We use pixel text, not native text
    button.AutoButtonColor = false
    button.BackgroundColor3 = bgColor
    button.BackgroundTransparency = bgTransparency
    button.BorderSizePixel = 0
    button.Size = UDim2.fromOffset(textWidth + padding * 2, textHeight + padding * 2)

    -- Position text based on alignment
    if alignment == "center" then
        textFrame.Position = UDim2.fromOffset(padding, padding)
        textFrame.AnchorPoint = Vector2.new(0, 0)
    elseif alignment == "right" then
        textFrame.Position = UDim2.new(1, -padding, 0, padding)
        textFrame.AnchorPoint = Vector2.new(1, 0)
    else  -- left
        textFrame.Position = UDim2.fromOffset(padding, padding)
        textFrame.AnchorPoint = Vector2.new(0, 0)
    end

    textFrame.Parent = button

    return button, textFrame
end

--- Fade in a pixel text container (tweens ImageTransparency on all characters)
---@param container Frame The container frame from createText
---@param duration number? Fade duration in seconds (default 0.5)
---@param callback function? Optional callback when complete
function PixelFont.fadeIn(container, duration, callback)
    duration = duration or 0.5

    -- Set all characters to transparent first
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("ImageLabel") then
            child.ImageTransparency = 1
        end
    end

    -- Tween to visible
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local lastTween = nil

    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("ImageLabel") then
            local tween = TweenService:Create(child, tweenInfo, { ImageTransparency = 0 })
            tween:Play()
            lastTween = tween
        end
    end

    if callback and lastTween then
        lastTween.Completed:Connect(callback)
    elseif callback then
        callback()
    end
end

--- Fade out a pixel text container (tweens ImageTransparency on all characters)
---@param container Frame The container frame from createText
---@param duration number? Fade duration in seconds (default 0.5)
---@param callback function? Optional callback when complete
function PixelFont.fadeOut(container, duration, callback)
    duration = duration or 0.5

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local lastTween = nil

    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("ImageLabel") then
            local tween = TweenService:Create(child, tweenInfo, { ImageTransparency = 1 })
            tween:Play()
            lastTween = tween
        end
    end

    if callback and lastTween then
        lastTween.Completed:Connect(callback)
    elseif callback then
        callback()
    end
end

return PixelFont
