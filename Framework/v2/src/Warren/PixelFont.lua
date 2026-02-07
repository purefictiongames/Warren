--[[
    Warren Framework v2
    PixelFont.lua - Retro-style Font Renderer using Arcade font

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    USAGE
    ============================================================================

    local PixelFont = require(path.to.PixelFont)

    -- Create a text label (returns a Frame containing TextLabel)
    local textFrame = PixelFont.createText("HELLO WORLD", {
        scale = 4,              -- 4x scale = ~32px text size
        color = Color3.new(1, 1, 1),  -- White text
        spacing = 0,            -- Extra letter spacing (not used with Arcade)
    })
    textFrame.Parent = someGui

    -- Update existing text
    PixelFont.updateText(textFrame, "NEW TEXT")

    ============================================================================
    NOTE
    ============================================================================

    This module was originally designed to use a custom spritesheet for
    NES-style 8x8 pixel fonts. Due to cross-platform rendering issues on PS4,
    it now uses Roblox's built-in Arcade font which provides a similar retro
    aesthetic with reliable rendering across all platforms.

    The spritesheet code is preserved below (commented) for potential future use.

--]]

local TweenService = game:GetService("TweenService")

local PixelFont = {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Base size for scale=1 (approximates 8px pixel font appearance)
local BASE_TEXT_SIZE = 8

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--- Calculate the width of text in pixels at a given scale
---@param text string The text to measure
---@param scale number? Scale factor (default 1)
---@param spacing number? Extra spacing between characters (default 0, not used)
---@return number The total width in pixels
function PixelFont.getTextWidth(text: string, scale: number?, spacing: number?): number
    scale = scale or 1
    local textSize = BASE_TEXT_SIZE * scale
    -- Approximate width: Arcade font is roughly 0.6x height per character
    local charWidth = textSize * 0.6
    local textLen = utf8.len(text) or 0
    return math.ceil(textLen * charWidth)
end

--- Calculate the integer scale needed to achieve a target character height
---@param targetHeight number The desired character height in pixels
---@return number The integer scale factor (minimum 1)
function PixelFont.calculateScale(targetHeight: number): number
    return math.max(1, math.floor(targetHeight / BASE_TEXT_SIZE))
end

--- Create a text display from a string
---@param text string The text to display
---@param options table? Optional settings: scale, color, spacing, alignment
---@return Frame The container frame with TextLabel
function PixelFont.createText(text: string, options: {
    scale: number?,
    color: Color3?,
    spacing: number?,
    alignment: string?,  -- "left" (default), "center", or "right"
}?): Frame
    options = options or {}
    local scale = options.scale or 1
    local color = options.color or Color3.new(1, 1, 1)
    local alignment = options.alignment or "left"

    local textSize = BASE_TEXT_SIZE * scale
    local estimatedWidth = PixelFont.getTextWidth(text, scale)

    -- Create container frame
    local container = Instance.new("Frame")
    container.Name = "PixelText"
    container.BackgroundTransparency = 1
    container.Size = UDim2.fromOffset(estimatedWidth, textSize)
    container.ZIndex = 100

    -- Store attributes for updates
    container:SetAttribute("PixelFontText", text)
    container:SetAttribute("PixelFontScale", scale)
    container:SetAttribute("PixelFontSpacing", 0)
    container:SetAttribute("PixelFontAlignment", alignment)

    -- Create TextLabel with Arcade font
    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "ArcadeText"
    textLabel.BackgroundTransparency = 1
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.Position = UDim2.new(0, 0, 0, 0)
    textLabel.Font = Enum.Font.Arcade
    textLabel.Text = text
    textLabel.TextSize = textSize
    textLabel.TextColor3 = color
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextYAlignment = Enum.TextYAlignment.Center
    textLabel.ZIndex = 100
    textLabel.Parent = container

    return container
end

--- Update an existing text display with new text
---@param container Frame The container frame from createText
---@param newText string The new text to display
function PixelFont.updateText(container: Frame, newText: string)
    local scale = container:GetAttribute("PixelFontScale") or 1
    local textSize = BASE_TEXT_SIZE * scale

    -- Find the TextLabel
    local textLabel = container:FindFirstChild("ArcadeText")
    if textLabel and textLabel:IsA("TextLabel") then
        textLabel.Text = newText
    end

    -- Update container size
    local estimatedWidth = PixelFont.getTextWidth(newText, scale)
    container.Size = UDim2.fromOffset(estimatedWidth, textSize)

    container:SetAttribute("PixelFontText", newText)
end

--- Set the color of text in a display
---@param container Frame The container frame from createText
---@param color Color3 The new color
function PixelFont.setColor(container: Frame, color: Color3)
    local textLabel = container:FindFirstChild("ArcadeText")
    if textLabel and textLabel:IsA("TextLabel") then
        textLabel.TextColor3 = color
    end
end

--- Set the transparency of text in a display
---@param container Frame The container frame from createText
---@param transparency number 0 = opaque, 1 = invisible
function PixelFont.setTransparency(container: Frame, transparency: number)
    local textLabel = container:FindFirstChild("ArcadeText")
    if textLabel and textLabel:IsA("TextLabel") then
        textLabel.TextTransparency = transparency
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
    local alignment = options.alignment or "center"
    local bgColor = options.backgroundColor or Color3.fromRGB(40, 40, 50)
    local bgTransparency = options.backgroundTransparency or 0
    local padding = options.padding or 8

    -- Create the text first to get dimensions
    local textFrame = PixelFont.createText(text, {
        scale = scale,
        color = color,
        alignment = alignment,
    })

    local textWidth = textFrame.Size.X.Offset
    local textHeight = textFrame.Size.Y.Offset

    -- Create button wrapper
    local button = Instance.new("TextButton")
    button.Name = "PixelButton"
    button.Text = ""
    button.AutoButtonColor = false
    button.BackgroundColor3 = bgColor
    button.BackgroundTransparency = bgTransparency
    button.BorderSizePixel = 0
    button.Size = UDim2.fromOffset(textWidth + padding * 2, textHeight + padding * 2)

    -- Position text
    textFrame.Position = UDim2.fromOffset(padding, padding)
    textFrame.Parent = button

    return button, textFrame
end

--- Fade in a pixel text container
---@param container Frame The container frame from createText
---@param duration number? Fade duration in seconds (default 0.5)
---@param callback function? Optional callback when complete
function PixelFont.fadeIn(container, duration, callback)
    duration = duration or 0.5

    local textLabel = container:FindFirstChild("ArcadeText")
    if textLabel and textLabel:IsA("TextLabel") then
        textLabel.TextTransparency = 1

        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tween = TweenService:Create(textLabel, tweenInfo, { TextTransparency = 0 })
        tween:Play()

        if callback then
            tween.Completed:Connect(callback)
        end
    elseif callback then
        callback()
    end
end

--- Fade out a pixel text container
---@param container Frame The container frame from createText
---@param duration number? Fade duration in seconds (default 0.5)
---@param callback function? Optional callback when complete
function PixelFont.fadeOut(container, duration, callback)
    duration = duration or 0.5

    local textLabel = container:FindFirstChild("ArcadeText")
    if textLabel and textLabel:IsA("TextLabel") then
        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tween = TweenService:Create(textLabel, tweenInfo, { TextTransparency = 1 })
        tween:Play()

        if callback then
            tween.Completed:Connect(callback)
        end
    elseif callback then
        callback()
    end
end

--[[
================================================================================
LEGACY SPRITESHEET CODE (preserved for future reference)
================================================================================

-- Asset ID for the spritesheet (update after uploading to Roblox)
-- Use the DOS 8x8 font from OpenGameArt: https://opengameart.org/content/dos-8x8-font
local SPRITESHEET_ASSET = "rbxassetid://72947775969584"

-- Glyph dimensions
local GLYPH_WIDTH = 8
local GLYPH_HEIGHT = 8

-- Grid layout: 16 characters per row (standard for 256-char fonts)
-- The DOS font has a 1px yellow grid border, so stride is 9px (8 + 1)
local GRID_COLUMNS = 16
local GRID_STRIDE = 9  -- 8px glyph + 1px grid line

-- Helper: Get glyph position from character (uses ASCII code directly)
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

-- To revert to spritesheet rendering:
-- 1. Uncomment the spritesheet constants above
-- 2. Change createText to use ImageLabel with:
--    charLabel.Image = SPRITESHEET_ASSET
--    charLabel.ImageRectOffset = Vector2.new(xOffset, yOffset)
--    charLabel.ImageRectSize = Vector2.new(GLYPH_WIDTH, GLYPH_HEIGHT)
--    charLabel.ResampleMode = Enum.ResamplerMode.Pixelated
--    charLabel.ScaleType = Enum.ScaleType.Crop
-- 3. Update setColor to use ImageColor3
-- 4. Update setTransparency to use ImageTransparency
-- 5. Update fadeIn/fadeOut to use ImageTransparency

================================================================================
--]]

return PixelFont
