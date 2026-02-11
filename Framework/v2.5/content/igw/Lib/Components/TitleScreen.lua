--[[
    LibPureFiction Framework v2
    TitleScreen.lua - Title Screen Component

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    TitleScreen is a client-side node that displays a title screen before the
    game loads. It waits for the player to press Start, then signals the server
    to begin the dungeon.

    ============================================================================
    SIGNAL FLOW
    ============================================================================

    1. Player joins -> TitleScreen shows (background image, start/options buttons)
    2. Roblox CoreGui is hidden during title screen
    3. Player clicks Start -> fires startPressed signal to server
    4. Server starts dungeon via RegionManager
    5. Server fires hideTitle signal to client
    6. TitleScreen fades out, CoreGui restored, UI destroyed

--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local Node = require(script.Parent.Parent.Node)
local System = require(script.Parent.Parent.System)
local PixelFont = require(script.Parent.Parent.PixelFont)

--------------------------------------------------------------------------------
-- TITLESCREEN NODE
--------------------------------------------------------------------------------

local TitleScreen = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE STATE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local ORANGE_BORDER = Color3.fromRGB(255, 140, 0)
    local FADE_DURATION = 0.5
    local BUILD_NUMBER = 207
    local TITLE_MUSIC_ID = "rbxassetid://115218802234328"
    local GAMEPLAY_MUSIC_ID = "rbxassetid://127750735513287"
    local PIXEL_SCALE = 5  -- 40px equivalent (8 * 5)
    local PIXEL_SCALE_SMALL = 2  -- 16px equivalent

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                isVisible = true,
                selectedIndex = 1,  -- 1 = Start, 2 = Options
                buttons = {},       -- { StartButton, OptionsButton }
                buttonTexts = {},   -- { StartText, OptionsText } PixelFont frames
                footerTexts = {},   -- { copyrightText, buildText } PixelFont frames
                inputConnection = nil,
                inputClaim = nil,   -- InputCapture claim for hiding CoreGui
                music = nil,        -- Background music Sound instance
                blinkLoop = nil,    -- Active button text blink animation
                menuPanel = nil,    -- Shared background panel for menu buttons
                -- Options menu state
                optionsMenuOpen = false,
                optionsFrame = nil,
                optionsConfirmOpen = false,
                optionsConfirmFrame = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            if state.inputConnection then
                state.inputConnection:Disconnect()
                state.inputConnection = nil
            end
            -- Release input claim (restores CoreGui)
            if state.inputClaim then
                state.inputClaim:release()
                state.inputClaim = nil
            end
            if state.music then
                state.music:Stop()
                state.music:Destroy()
                state.music = nil
            end
            if state.blinkLoop then
                task.cancel(state.blinkLoop)
                state.blinkLoop = nil
            end
            if state.screenGui then
                state.screenGui:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- BUTTON SELECTION
    ----------------------------------------------------------------------------

    local BRACKET_WIDTH = 1      -- Width of bracket bars
    local BRACKET_GAP = 3        -- Gap between bracket and button
    local BRACKET_COLOR = Color3.fromRGB(255, 255, 255)  -- White (matches text)
    local BLINK_RATE = 0.5       -- Seconds per blink cycle
    local PANEL_COLOR = Color3.fromRGB(40, 50, 70)  -- Dark blue-slate
    local PANEL_BORDER_COLOR = Color3.fromRGB(80, 100, 140)  -- Steel blue border

    -- Create bracket-style selection borders for a button
    -- Returns { left = Frame, right = Frame }
    local function createBracketBorders(button, textHeight)
        local bracketHeight = textHeight or button.Size.Y.Offset
        local buttonHeight = button.Size.Y.Offset
        local yOffset = (buttonHeight - bracketHeight) / 2  -- Center vertically

        -- Left bracket
        local leftBracket = Instance.new("Frame")
        leftBracket.Name = "LeftBracket"
        leftBracket.Size = UDim2.fromOffset(BRACKET_WIDTH, bracketHeight)
        leftBracket.Position = UDim2.fromOffset(-BRACKET_GAP - BRACKET_WIDTH, yOffset)
        leftBracket.BackgroundColor3 = BRACKET_COLOR
        leftBracket.BorderSizePixel = 0
        leftBracket.Visible = false
        leftBracket.ZIndex = button.ZIndex + 1
        leftBracket.Parent = button

        -- Right bracket
        local rightBracket = Instance.new("Frame")
        rightBracket.Name = "RightBracket"
        rightBracket.Size = UDim2.fromOffset(BRACKET_WIDTH, bracketHeight)
        rightBracket.Position = UDim2.new(1, BRACKET_GAP, 0, yOffset)
        rightBracket.BackgroundColor3 = BRACKET_COLOR
        rightBracket.BorderSizePixel = 0
        rightBracket.Visible = false
        rightBracket.ZIndex = button.ZIndex + 1
        rightBracket.Parent = button

        return { left = leftBracket, right = rightBracket }
    end

    -- Show/hide bracket borders on a button
    local function setBracketVisible(button, visible)
        local leftBracket = button:FindFirstChild("LeftBracket")
        local rightBracket = button:FindFirstChild("RightBracket")
        if leftBracket then leftBracket.Visible = visible end
        if rightBracket then rightBracket.Visible = visible end
    end

    -- Start blinking animation for active button text and brackets
    local function startBlinkLoop(state)
        if state.blinkLoop then return end

        state.blinkLoop = task.spawn(function()
            local blinkOn = true
            while state.isVisible and not state.optionsMenuOpen do
                -- Get active button text and brackets
                local activeText = state.buttonTexts[state.selectedIndex]
                local activeButton = state.buttons[state.selectedIndex]

                if activeText and activeButton then
                    -- Toggle visibility
                    blinkOn = not blinkOn
                    local transparency = blinkOn and 0 or 0.7

                    PixelFont.setTransparency(activeText, transparency)

                    -- Also blink brackets
                    local leftBracket = activeButton:FindFirstChild("LeftBracket")
                    local rightBracket = activeButton:FindFirstChild("RightBracket")
                    if leftBracket then leftBracket.BackgroundTransparency = transparency end
                    if rightBracket then rightBracket.BackgroundTransparency = transparency end
                end

                task.wait(BLINK_RATE)
            end
        end)
    end

    local function stopBlinkLoop(state)
        if state.blinkLoop then
            task.cancel(state.blinkLoop)
            state.blinkLoop = nil
        end
        -- Reset all text to fully visible
        if state.buttonTexts then
            for _, textFrame in ipairs(state.buttonTexts) do
                PixelFont.setTransparency(textFrame, 0)
            end
        end
        -- Reset all brackets to fully visible
        if state.buttons then
            for _, button in ipairs(state.buttons) do
                local leftBracket = button:FindFirstChild("LeftBracket")
                local rightBracket = button:FindFirstChild("RightBracket")
                if leftBracket then leftBracket.BackgroundTransparency = 0 end
                if rightBracket then rightBracket.BackgroundTransparency = 0 end
            end
        end
    end

    -- Options menu uses bracket borders on the clear data button (created in createOptionsMenu)

    ----------------------------------------------------------------------------
    -- OPTIONS MENU
    ----------------------------------------------------------------------------

    local function createOptionsMenu(state, screenGui, onClearDataClick)
        -- Options menu overlay
        local optionsFrame = Instance.new("Frame")
        optionsFrame.Name = "OptionsFrame"
        optionsFrame.Size = UDim2.new(1, 0, 1, 0)
        optionsFrame.Position = UDim2.new(0, 0, 0, 0)
        optionsFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        optionsFrame.BackgroundTransparency = 0.3
        optionsFrame.ZIndex = 50
        optionsFrame.Visible = false
        optionsFrame.Parent = screenGui

        -- Title
        local titleStr = "OPTIONS"
        local titleText = PixelFont.createText(titleStr, {
            scale = PIXEL_SCALE,
            color = Color3.fromRGB(255, 255, 255),
        })
        titleText.Name = "OptionsTitle"
        local titleWidth = PixelFont.getTextWidth(titleStr, PIXEL_SCALE, 0)
        titleText.Position = UDim2.new(0.5, -titleWidth / 2, 0.3, 0)
        titleText.ZIndex = 51
        titleText.Parent = optionsFrame

        -- Clear Data button
        local clearBtnText = PixelFont.createText("CLEAR SAVED DATA", {
            scale = PIXEL_SCALE,
            color = Color3.fromRGB(255, 255, 255),
        })
        local clearBtnWidth = clearBtnText.Size.X.Offset
        local clearBtnHeight = clearBtnText.Size.Y.Offset
        local padding = 16

        local clearBtn = Instance.new("TextButton")
        clearBtn.Name = "ClearDataButton"
        clearBtn.Text = ""
        clearBtn.AutoButtonColor = false
        clearBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        clearBtn.BackgroundTransparency = 0.5
        clearBtn.BorderSizePixel = 0
        clearBtn.Size = UDim2.fromOffset(clearBtnWidth + padding * 2, clearBtnHeight + padding * 2)
        clearBtn.Position = UDim2.new(0.5, -clearBtn.Size.X.Offset / 2, 0.45, 0)
        clearBtn.ZIndex = 51
        clearBtn.Parent = optionsFrame

        clearBtnText.Position = UDim2.fromOffset(padding, padding)
        clearBtnText.ZIndex = 52
        clearBtnText.Parent = clearBtn

        local clearCorner = Instance.new("UICorner")
        clearCorner.CornerRadius = UDim.new(0, 8)
        clearCorner.Parent = clearBtn

        local clearStroke = Instance.new("UIStroke")
        clearStroke.Name = "SelectionStroke"
        clearStroke.Color = ORANGE_BORDER
        clearStroke.Thickness = 2
        clearStroke.Enabled = true
        clearStroke.Parent = clearBtn

        -- Wire click handler
        clearBtn.Activated:Connect(function()
            if onClearDataClick then
                onClearDataClick()
            end
        end)

        -- Back hint
        local backStr = "B / CIRCLE TO GO BACK"
        local backText = PixelFont.createText(backStr, {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(150, 150, 150),
        })
        backText.Name = "BackHint"
        local backWidth = PixelFont.getTextWidth(backStr, PIXEL_SCALE_SMALL, 0)
        backText.Position = UDim2.new(0.5, -backWidth / 2, 0.85, 0)
        backText.ZIndex = 51
        backText.Parent = optionsFrame

        state.optionsFrame = optionsFrame
        state.optionsClearBtn = clearBtn
        state.optionsClearBtnText = clearBtnText

        return optionsFrame
    end

    local function createOptionsConfirm(state, screenGui, onConfirm)
        -- Confirmation overlay
        local confirmFrame = Instance.new("Frame")
        confirmFrame.Name = "OptionsConfirmFrame"
        confirmFrame.Size = UDim2.new(1, 0, 1, 0)
        confirmFrame.Position = UDim2.new(0, 0, 0, 0)
        confirmFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        confirmFrame.BackgroundTransparency = 0.2
        confirmFrame.ZIndex = 60
        confirmFrame.Visible = false
        confirmFrame.Parent = screenGui

        -- Confirmation text line 1
        local line1Str = "CLEAR SAVED DATA."
        local line1Text = PixelFont.createText(line1Str, {
            scale = PIXEL_SCALE,
            color = Color3.fromRGB(255, 255, 255),
        })
        line1Text.Name = "ConfirmLine1"
        local line1Width = PixelFont.getTextWidth(line1Str, PIXEL_SCALE, 0)
        line1Text.Position = UDim2.new(0.5, -line1Width / 2, 0.35, 0)
        line1Text.ZIndex = 61
        line1Text.Parent = confirmFrame

        -- Confirmation text line 2
        local line2Str = "ARE YOU SURE?"
        local line2Text = PixelFont.createText(line2Str, {
            scale = PIXEL_SCALE,
            color = Color3.fromRGB(255, 255, 255),
        })
        line2Text.Name = "ConfirmLine2"
        local line2Width = PixelFont.getTextWidth(line2Str, PIXEL_SCALE, 0)
        line2Text.Position = UDim2.new(0.5, -line2Width / 2, 0.42, 0)
        line2Text.ZIndex = 61
        line2Text.Parent = confirmFrame

        -- Yes button
        local yesBtnText = PixelFont.createText("YES", {
            scale = PIXEL_SCALE,
            color = Color3.fromRGB(255, 255, 255),
        })
        local yesBtnWidth = yesBtnText.Size.X.Offset
        local yesBtnHeight = yesBtnText.Size.Y.Offset
        local padding = 16

        local yesBtn = Instance.new("TextButton")
        yesBtn.Name = "YesButton"
        yesBtn.Text = ""
        yesBtn.AutoButtonColor = false
        yesBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
        yesBtn.BackgroundTransparency = 0.3
        yesBtn.BorderSizePixel = 0
        yesBtn.Size = UDim2.fromOffset(yesBtnWidth + padding * 2, yesBtnHeight + padding * 2)
        yesBtn.Position = UDim2.new(0.5, -yesBtn.Size.X.Offset / 2, 0.55, 0)
        yesBtn.ZIndex = 61
        yesBtn.Parent = confirmFrame

        yesBtnText.Position = UDim2.fromOffset(padding, padding)
        yesBtnText.ZIndex = 62
        yesBtnText.Parent = yesBtn

        local yesCorner = Instance.new("UICorner")
        yesCorner.CornerRadius = UDim.new(0, 8)
        yesCorner.Parent = yesBtn

        local yesStroke = Instance.new("UIStroke")
        yesStroke.Name = "SelectionStroke"
        yesStroke.Color = ORANGE_BORDER
        yesStroke.Thickness = 2
        yesStroke.Enabled = true
        yesStroke.Parent = yesBtn

        -- Wire click handler
        yesBtn.Activated:Connect(function()
            if onConfirm then
                onConfirm()
            end
        end)

        -- Gamepad hint
        local hintStr = "Y / TRIANGLE TO CONFIRM"
        local hintText = PixelFont.createText(hintStr, {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(150, 150, 150),
        })
        hintText.Name = "GamepadHint"
        local hintWidth = PixelFont.getTextWidth(hintStr, PIXEL_SCALE_SMALL, 0)
        hintText.Position = UDim2.new(0.5, -hintWidth / 2, 0.7, 0)
        hintText.ZIndex = 61
        hintText.Parent = confirmFrame

        -- Back hint
        local backStr = "B / CIRCLE TO CANCEL"
        local backText = PixelFont.createText(backStr, {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(150, 150, 150),
        })
        backText.Name = "BackHint"
        local backWidth = PixelFont.getTextWidth(backStr, PIXEL_SCALE_SMALL, 0)
        backText.Position = UDim2.new(0.5, -backWidth / 2, 0.75, 0)
        backText.ZIndex = 61
        backText.Parent = confirmFrame

        state.optionsConfirmFrame = confirmFrame
        state.optionsYesBtn = yesBtn

        return confirmFrame
    end

    local function showOptionsMenu(state)
        -- Stop blink animation
        stopBlinkLoop(state)
        -- Hide main menu buttons, text, and panel
        for _, button in ipairs(state.buttons or {}) do
            button.Visible = false
        end
        for _, textFrame in ipairs(state.buttonTexts or {}) do
            textFrame.Visible = false
        end
        if state.menuPanel then
            state.menuPanel.Visible = false
        end
        -- Show options frame
        if state.optionsFrame then
            state.optionsMenuOpen = true
            state.optionsFrame.Visible = true
        end
    end

    local function hideOptionsMenu(state)
        if state.optionsFrame then
            state.optionsMenuOpen = false
            state.optionsFrame.Visible = false
        end
        -- Also hide confirm if open
        if state.optionsConfirmFrame then
            state.optionsConfirmOpen = false
            state.optionsConfirmFrame.Visible = false
        end
        -- Show main menu buttons, text, and panel
        for _, button in ipairs(state.buttons or {}) do
            button.Visible = true
        end
        for _, textFrame in ipairs(state.buttonTexts or {}) do
            textFrame.Visible = true
        end
        if state.menuPanel then
            state.menuPanel.Visible = true
        end
        -- Restart blink animation
        startBlinkLoop(state)
    end

    local function showOptionsConfirm(state)
        -- Hide options menu (buttons already hidden from showOptionsMenu)
        if state.optionsFrame then
            state.optionsFrame.Visible = false
        end
        -- Show confirmation dialog
        if state.optionsConfirmFrame then
            state.optionsConfirmOpen = true
            state.optionsConfirmFrame.Visible = true
        end
    end

    local function hideOptionsConfirm(state)
        if state.optionsConfirmFrame then
            state.optionsConfirmOpen = false
            state.optionsConfirmFrame.Visible = false
        end
        -- Show options menu again (if still in options mode)
        if state.optionsFrame and state.optionsMenuOpen then
            state.optionsFrame.Visible = true
        end
    end

    local function updateButtonHighlight(state)
        for i, button in ipairs(state.buttons) do
            local textFrame = state.buttonTexts[i]
            if i == state.selectedIndex then
                -- Active: show brackets (button background is transparent, shared panel behind)
                setBracketVisible(button, true)
            else
                -- Inactive: hide brackets, reset text visibility
                setBracketVisible(button, false)
                -- Reset inactive button text to fully visible
                if textFrame then
                    PixelFont.setTransparency(textFrame, 0)
                end
            end
        end
    end

    local function selectButton(state, index)
        state.selectedIndex = math.clamp(index, 1, #state.buttons)
        updateButtonHighlight(state)
    end

    local function moveSelection(state, direction)
        local newIndex = state.selectedIndex + direction
        if newIndex < 1 then
            newIndex = #state.buttons
        elseif newIndex > #state.buttons then
            newIndex = 1
        end
        selectButton(state, newIndex)
    end

    local function activateSelectedButton(self)
        local state = getState(self)
        if not state.isVisible then return end

        local button = state.buttons[state.selectedIndex]
        local buttonText = state.buttonTexts[state.selectedIndex]
        if button then
            -- Trigger the button's click handler
            if button.Name == "StartButton" then
                -- Disable to prevent double-clicks
                button.Active = false
                if buttonText then
                    PixelFont.setTransparency(buttonText, 0.5)
                end

                -- Fire signal to server
                local player = Players.LocalPlayer
                self.Out:Fire("startPressed", {
                    _targetPlayer = player,
                    player = player,
                })
            elseif button.Name == "OptionsButton" then
                showOptionsMenu(state)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- GAMEPLAY MUSIC
    ----------------------------------------------------------------------------

    local function startGameplayMusic()
        -- Remove any existing gameplay music
        local existing = SoundService:FindFirstChild("GameplayMusic")
        if existing then
            existing:Destroy()
        end

        -- Create and play gameplay music after 2 second delay
        task.delay(2, function()
            local music = Instance.new("Sound")
            music.Name = "GameplayMusic"
            music.SoundId = GAMEPLAY_MUSIC_ID
            music.Volume = 0.5
            music.Looped = true
            music.Parent = SoundService
            music:Play()
        end)
    end

    ----------------------------------------------------------------------------
    -- FADE ANIMATIONS
    ----------------------------------------------------------------------------

    local function fadeInContent(self, callback)
        local state = getState(self)
        if not state.screenGui then
            if callback then callback() end
            return
        end

        local tweenInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tweens = {}

        -- Fade in menu panel (shared background for buttons)
        if state.menuPanel then
            state.menuPanel.BackgroundTransparency = 1  -- Start invisible
            table.insert(tweens, TweenService:Create(state.menuPanel, tweenInfo, {
                BackgroundTransparency = 0.3,
            }))
            -- Also fade in the border stroke
            local stroke = state.menuPanel:FindFirstChildOfClass("UIStroke")
            if stroke then
                stroke.Transparency = 1  -- Start invisible
                table.insert(tweens, TweenService:Create(stroke, tweenInfo, {
                    Transparency = 0,
                }))
            end
        end

        -- Fade in button pixel text
        for _, textFrame in ipairs(state.buttonTexts) do
            PixelFont.fadeIn(textFrame, FADE_DURATION)
        end

        -- Fade in footer pixel text
        for _, textFrame in ipairs(state.footerTexts) do
            PixelFont.fadeIn(textFrame, FADE_DURATION)
        end

        -- Fade in logo
        local logo = state.screenGui:FindFirstChild("Logo")
        if logo and logo:IsA("ImageLabel") then
            table.insert(tweens, TweenService:Create(logo, tweenInfo, {
                ImageTransparency = 0.3,
            }))
        end

        -- Fade in studio icon
        local studioIcon = state.screenGui:FindFirstChild("StudioIcon")
        if studioIcon and studioIcon:IsA("ImageLabel") then
            table.insert(tweens, TweenService:Create(studioIcon, tweenInfo, {
                ImageTransparency = 0,
            }))
        end

        -- Play all tweens
        for _, tween in ipairs(tweens) do
            tween:Play()
        end

        if #tweens > 0 then
            tweens[1].Completed:Connect(function()
                if callback then callback() end
            end)
        else
            task.delay(FADE_DURATION, function()
                if callback then callback() end
            end)
        end
    end

    local function fadeOutContent(self, callback)
        local state = getState(self)
        if not state.screenGui then
            if callback then callback() end
            return
        end

        local tweenInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tweens = {}

        -- Fade out menu panel (shared background for buttons)
        if state.menuPanel then
            table.insert(tweens, TweenService:Create(state.menuPanel, tweenInfo, {
                BackgroundTransparency = 1,
            }))
            -- Also fade the border stroke
            local stroke = state.menuPanel:FindFirstChildOfClass("UIStroke")
            if stroke then
                table.insert(tweens, TweenService:Create(stroke, tweenInfo, {
                    Transparency = 1,
                }))
            end
        end

        -- Fade out button pixel text
        for _, textFrame in ipairs(state.buttonTexts) do
            PixelFont.fadeOut(textFrame, FADE_DURATION)
        end

        -- Fade out footer pixel text
        for _, textFrame in ipairs(state.footerTexts) do
            PixelFont.fadeOut(textFrame, FADE_DURATION)
        end

        -- Fade out logo
        local logo = state.screenGui:FindFirstChild("Logo")
        if logo and logo:IsA("ImageLabel") then
            table.insert(tweens, TweenService:Create(logo, tweenInfo, {
                ImageTransparency = 1,
            }))
        end

        -- Fade out studio icon
        local studioIcon = state.screenGui:FindFirstChild("StudioIcon")
        if studioIcon and studioIcon:IsA("ImageLabel") then
            table.insert(tweens, TweenService:Create(studioIcon, tweenInfo, {
                ImageTransparency = 1,
            }))
        end

        -- Play all tweens
        for _, tween in ipairs(tweens) do
            tween:Play()
        end

        if #tweens > 0 then
            tweens[1].Completed:Connect(function()
                if callback then callback() end
            end)
        else
            task.delay(FADE_DURATION, function()
                if callback then callback() end
            end)
        end
    end

    local function fadeOutBackgroundImage(self, callback)
        local state = getState(self)
        if not state.screenGui then
            if callback then callback() end
            return
        end

        local background = state.screenGui:FindFirstChild("Background")
        if not background then
            if callback then callback() end
            return
        end

        -- Fade only the image, keep black background visible
        local tween = TweenService:Create(
            background,
            TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { ImageTransparency = 1 }
        )

        tween.Completed:Connect(function()
            if callback then callback() end
        end)

        tween:Play()
    end

    local function showLoadingText(self, callback)
        local state = getState(self)
        if not state.screenGui then
            if callback then callback() end
            return
        end

        -- Create loading text with PixelFont
        local loadingScale = 4  -- Larger for visibility
        local loadingText = PixelFont.createText("STARTING....", {
            scale = loadingScale,
            color = Color3.fromRGB(255, 255, 255),  -- White
        })
        loadingText.Name = "LoadingText"
        -- Center it on screen
        local loadingWidth = PixelFont.getTextWidth("STARTING....", loadingScale, 0)
        loadingText.Position = UDim2.new(0.5, -loadingWidth / 2, 0.5, -loadingScale * 4)
        loadingText.ZIndex = 10
        -- Start invisible
        PixelFont.setTransparency(loadingText, 1)
        loadingText.Parent = state.screenGui

        -- Fade in the text
        PixelFont.fadeIn(loadingText, 0.3, function()
            -- Fade out music over 2 seconds
            if state.music then
                local musicFadeTween = TweenService:Create(
                    state.music,
                    TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { Volume = 0 }
                )
                musicFadeTween:Play()
            end

            -- Wait 2 seconds (same as music fade)
            task.delay(2, function()
                -- Stop and cleanup music
                if state.music then
                    state.music:Stop()
                    state.music:Destroy()
                    state.music = nil
                end

                -- Fade out the text
                PixelFont.fadeOut(loadingText, 0.3, function()
                    loadingText:Destroy()
                    if callback then callback() end
                end)
            end)
        end)
    end

    local function fadeOutBlackBackground(self, callback)
        local state = getState(self)
        if not state.screenGui then
            if callback then callback() end
            return
        end

        local background = state.screenGui:FindFirstChild("Background")
        if not background then
            if callback then callback() end
            return
        end

        -- Fade out the black background to reveal gameplay
        local tween = TweenService:Create(
            background,
            TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 1 }
        )

        tween.Completed:Connect(function()
            if callback then callback() end
        end)

        tween:Play()
    end

    ----------------------------------------------------------------------------
    -- UI CREATION
    ----------------------------------------------------------------------------

    local function createUI(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        -- Clean up existing
        if state.screenGui then
            state.screenGui:Destroy()
        end
        local existing = playerGui:FindFirstChild("TitleScreen")
        if existing then
            existing:Destroy()
        end

        -- Create ScreenGui (DisplayOrder=1000, above ScreenTransition's 999)
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "TitleScreen"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 1000
        screenGui.IgnoreGuiInset = true
        screenGui.Parent = playerGui

        -- Hide Roblox CoreGui and topbar during title screen
        state.inputClaim = System.InputCapture.claim({}, {
            hideCoreGui = true,
        })

        -- Create and play background music
        local music = Instance.new("Sound")
        music.Name = "TitleMusic"
        music.SoundId = TITLE_MUSIC_ID
        music.Volume = 0.5
        music.Looped = true
        music.Parent = SoundService
        music:Play()
        state.music = music

        -- Create full-screen background image
        local background = Instance.new("ImageLabel")
        background.Name = "Background"
        background.Size = UDim2.new(1, 0, 1, 0)
        background.Position = UDim2.new(0, 0, 0, 0)
        background.Image = "rbxassetid://114898388494877"
        background.ScaleType = Enum.ScaleType.Crop
        background.BackgroundColor3 = Color3.new(0, 0, 0)
        background.BackgroundTransparency = 0
        background.BorderSizePixel = 0
        background.ZIndex = 1
        background.Parent = screenGui

        -- Create logo image (centered above buttons, starts invisible for fade-in)
        local logo = Instance.new("ImageLabel")
        logo.Name = "Logo"
        logo.Size = UDim2.new(1, 0, 0.9, 0)
        logo.Position = UDim2.new(0, 0, -0.12, 0)
        logo.Image = "rbxassetid://91612654080142"
        logo.ScaleType = Enum.ScaleType.Fit
        logo.BackgroundTransparency = 1
        logo.ImageTransparency = 1  -- Start invisible
        logo.ZIndex = 2
        logo.Parent = screenGui

        -- Create studio icon in lower left corner
        local studioIcon = Instance.new("ImageLabel")
        studioIcon.Name = "StudioIcon"
        studioIcon.Size = UDim2.fromOffset(128, 128)
        studioIcon.Position = UDim2.new(0, 16, 1, -144)
        studioIcon.Image = "rbxassetid://115752690911606"
        studioIcon.ScaleType = Enum.ScaleType.Fit
        studioIcon.BackgroundTransparency = 1
        studioIcon.ImageTransparency = 1  -- Start invisible for fade-in
        studioIcon.ZIndex = 2
        studioIcon.Parent = screenGui

        -- Shared background panel for menu buttons
        -- Calculate dimensions based on expected button sizes
        local menuPadding = 8
        local buttonSpacing = 0  -- Gap between buttons (padding inside buttons provides spacing)
        local textHeight = 8 * PIXEL_SCALE  -- 40px (8 = base pixel font size)
        local buttonPadding = 8
        local singleButtonHeight = textHeight + buttonPadding * 2
        local panelHeight = singleButtonHeight * 2 + buttonSpacing + menuPadding * 2
        local panelWidth = 220  -- Wide enough for OPTIONS button plus margin

        local menuPanel = Instance.new("Frame")
        menuPanel.Name = "MenuPanel"
        menuPanel.Size = UDim2.fromOffset(panelWidth, panelHeight)
        -- Center panel at 57% down the screen
        menuPanel.Position = UDim2.new(0.5, -panelWidth / 2, 0.57, -panelHeight / 2)
        menuPanel.BackgroundColor3 = PANEL_COLOR
        menuPanel.BackgroundTransparency = 0.3
        menuPanel.BorderSizePixel = 0
        menuPanel.ZIndex = 1
        menuPanel.Parent = screenGui

        local panelCorner = Instance.new("UICorner")
        panelCorner.CornerRadius = UDim.new(0, 4)
        panelCorner.Parent = menuPanel

        local panelStroke = Instance.new("UIStroke")
        panelStroke.Color = PANEL_BORDER_COLOR
        panelStroke.Thickness = 1
        panelStroke.Parent = menuPanel

        state.menuPanel = menuPanel

        -- Helper to create a menu button with PixelFont
        -- Uses separate TextButton (for clicks) and pixel text Frame (for display)
        -- yOffset is vertical position within the panel
        local function createMenuButton(name, text, yOffset, isActive)
            -- Create pixel text first to get dimensions
            local buttonText = PixelFont.createText(text, {
                scale = PIXEL_SCALE,
                color = Color3.fromRGB(255, 255, 255),
            })

            local textWidth = buttonText.Size.X.Offset
            local textHeight = buttonText.Size.Y.Offset
            local padding = 8
            local buttonWidth = textWidth + padding * 2
            local buttonHeight = textHeight + padding * 2

            -- Create button (click handler only, background is shared panel)
            local button = Instance.new("TextButton")
            button.Name = name
            button.Text = ""
            button.AutoButtonColor = false
            button.BackgroundTransparency = 1  -- Fully transparent (shared panel behind)
            button.BorderSizePixel = 0
            button.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
            -- Position centered horizontally within panel, offset vertically
            button.Position = UDim2.new(0.5, -buttonWidth / 2, 0, yOffset)
            button.ZIndex = 2
            button.Parent = menuPanel

            -- Position text centered within the button
            buttonText.Position = UDim2.fromOffset((buttonWidth - textWidth) / 2, padding)
            buttonText.ZIndex = 3
            buttonText.Parent = button

            -- DEBUG: Start text visible to test
            -- PixelFont.setTransparency(buttonText, 1)

            -- Bracket selection borders (height matches text)
            createBracketBorders(button, textHeight)
            setBracketVisible(button, isActive)

            -- Hover effect - select on hover, colors handled by updateButtonHighlight
            button.MouseEnter:Connect(function()
                -- Select this button on hover
                for i, btn in ipairs(state.buttons) do
                    if btn == button then
                        selectButton(state, i)
                        break
                    end
                end
            end)

            -- MouseLeave doesn't need to do anything - selection stays

            return button, buttonText
        end

        -- Create Start button (positioned at top of panel with padding)
        local startYOffset = menuPadding
        local startButton, startText = createMenuButton("StartButton", "START", startYOffset, true)
        startButton.Activated:Connect(function()
            if not state.isVisible then return end

            -- Disable button to prevent double-clicks
            startButton.Active = false
            PixelFont.setTransparency(startText, 0.5)

            -- Fire signal to server
            self.Out:Fire("startPressed", {
                _targetPlayer = player,
                player = player,
            })
        end)

        -- Create Options button (positioned below Start with spacing)
        local optionsYOffset = menuPadding + singleButtonHeight + buttonSpacing
        local optionsButton, optionsText = createMenuButton("OptionsButton", "OPTIONS", optionsYOffset, false)
        optionsButton.Activated:Connect(function()
            if not state.isVisible then return end
            showOptionsMenu(state)
        end)

        -- Store button and text references
        state.buttons = { startButton, optionsButton }
        state.buttonTexts = { startText, optionsText }

        -- Set initial selection (Start button)
        state.selectedIndex = 1
        -- Initial highlight already set via isActive parameter in createMenuButton

        -- Start blink animation for active button
        startBlinkLoop(state)

        -- Footer text (no background, 75% size of buttons)
        local copyrightStr = "(C) 2025-2026 PURE FICTION RECORDS/ALPHARABBIT GAMES"
        local buildStr = "DEMO BUILD " .. BUILD_NUMBER .. "/Warren 2.5.1"
        local footerScale = 4  -- 75% of PIXEL_SCALE (5)
        local footerTextHeight = 8 * footerScale
        local footerSpacing = 4
        local bottomMargin = 24

        -- Build number (anchored to bottom)
        local buildText = PixelFont.createText(buildStr, {
            scale = footerScale,
            color = Color3.fromRGB(255, 255, 255),
        })
        buildText.Name = "BuildText"
        local buildWidth = buildText.Size.X.Offset
        buildText.Position = UDim2.new(0.5, -buildWidth / 2, 1, -bottomMargin - footerTextHeight)
        buildText.ZIndex = 2
        PixelFont.setTransparency(buildText, 1)  -- Start invisible for fade
        buildText.Parent = screenGui

        -- Copyright line (above build text)
        local copyrightText = PixelFont.createText(copyrightStr, {
            scale = footerScale,
            color = Color3.fromRGB(255, 255, 255),
        })
        copyrightText.Name = "CopyrightText"
        local copyrightWidth = copyrightText.Size.X.Offset
        copyrightText.Position = UDim2.new(0.5, -copyrightWidth / 2, 1, -bottomMargin - footerTextHeight * 2 - footerSpacing)
        copyrightText.ZIndex = 2
        PixelFont.setTransparency(copyrightText, 1)  -- Start invisible for fade
        copyrightText.Parent = screenGui

        -- Store footer text references
        state.footerTexts = { copyrightText, buildText }

        -- Create Options menu and confirmation dialog
        createOptionsMenu(state, screenGui, function()
            -- Clear data button clicked - show confirmation
            showOptionsConfirm(state)
        end)

        createOptionsConfirm(state, screenGui, function()
            -- Confirmed - fire signal to clear data
            -- UI will be closed when server responds via onSavedDataCleared
            self.Out:Fire("clearSavedData", {
                _targetPlayer = player,
                player = player,
            })
        end)

        -- Set up controller/keyboard input
        state.inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if not state.isVisible then return end

            local keyCode = input.KeyCode

            -- Handle options confirm dialog input first (highest priority)
            if state.optionsConfirmOpen then
                -- A/X or Y/Triangle or Enter to confirm
                if keyCode == Enum.KeyCode.Y
                    or keyCode == Enum.KeyCode.ButtonY
                    or keyCode == Enum.KeyCode.ButtonA
                    or keyCode == Enum.KeyCode.ButtonX
                    or keyCode == Enum.KeyCode.Return
                    or keyCode == Enum.KeyCode.Space then
                    -- Confirmed - fire signal to clear data
                    -- UI will be closed when server responds via onSavedDataCleared
                    self.Out:Fire("clearSavedData", {
                        _targetPlayer = player,
                        player = player,
                    })
                -- B/Circle or Escape to cancel
                elseif keyCode == Enum.KeyCode.B
                    or keyCode == Enum.KeyCode.ButtonB
                    or keyCode == Enum.KeyCode.Escape then
                    hideOptionsConfirm(state)
                end
                return
            end

            -- Handle options menu input
            if state.optionsMenuOpen then
                -- B/Circle or Escape to go back
                if keyCode == Enum.KeyCode.B
                    or keyCode == Enum.KeyCode.ButtonB
                    or keyCode == Enum.KeyCode.Escape then
                    hideOptionsMenu(state)
                -- A/X or Enter to select clear data (only button in menu)
                elseif keyCode == Enum.KeyCode.Return
                    or keyCode == Enum.KeyCode.Space
                    or keyCode == Enum.KeyCode.ButtonA
                    or keyCode == Enum.KeyCode.ButtonX then
                    showOptionsConfirm(state)
                end
                return
            end

            -- Main menu input
            -- Up/Down navigation
            if keyCode == Enum.KeyCode.Up or keyCode == Enum.KeyCode.W then
                moveSelection(state, -1)
            elseif keyCode == Enum.KeyCode.Down or keyCode == Enum.KeyCode.S then
                moveSelection(state, 1)
            -- Action button (Enter, Space, or gamepad A/X)
            elseif keyCode == Enum.KeyCode.Return
                or keyCode == Enum.KeyCode.Space
                or keyCode == Enum.KeyCode.ButtonA
                or keyCode == Enum.KeyCode.ButtonX then
                activateSelectedButton(self)
            -- DPad navigation
            elseif keyCode == Enum.KeyCode.DPadUp then
                moveSelection(state, -1)
            elseif keyCode == Enum.KeyCode.DPadDown then
                moveSelection(state, 1)
            end
        end)

        state.screenGui = screenGui

        -- Fade in the content (title and buttons)
        fadeInContent(self)
    end

    local function fadeOut(self, callback)
        local state = getState(self)
        if not state.screenGui then
            if callback then callback() end
            return
        end

        -- Disconnect input to prevent further navigation during fade
        if state.inputConnection then
            state.inputConnection:Disconnect()
            state.inputConnection = nil
        end

        -- Step 1: Fade out content (buttons and footer text)
        fadeOutContent(self, function()
            -- Step 2: Destroy buttons, text, and particle effects
            for _, button in ipairs(state.buttons) do
                button:Destroy()
            end
            for _, textFrame in ipairs(state.buttonTexts) do
                textFrame:Destroy()
            end
            state.buttons = {}
            state.buttonTexts = {}

            for _, footerText in ipairs(state.footerTexts) do
                footerText:Destroy()
            end
            state.footerTexts = {}

            -- Step 3: Fade out background image (keep black background)
            fadeOutBackgroundImage(self, function()
                -- Step 4: Show "Starting...." text for 2 seconds
                showLoadingText(self, function()
                    -- Step 5: Fade out black background to reveal dungeon
                    fadeOutBlackBackground(self, function()
                        -- Step 6: Restore Roblox CoreGui/topbar by releasing input claim
                        if state.inputClaim then
                            state.inputClaim:release()
                            state.inputClaim = nil
                        end

                        -- Step 7: Start gameplay music (after 2 second delay)
                        startGameplayMusic()

                        -- Step 8: Destroy and cleanup
                        if state.screenGui then
                            state.screenGui:Destroy()
                            state.screenGui = nil
                        end
                        state.isVisible = false
                        if callback then callback() end
                    end)
                end)
            end)
        end)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "TitleScreen",
        domain = "client",

        Sys = {
            onInit = function(self)
                createUI(self)
            end,
            onStart = function(self) end,
            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            -- Server signals to hide the title screen
            onHideTitle = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                if data.player and data.player ~= player then return end
                if not state.isVisible then return end

                fadeOut(self)
            end,

            -- Server signals to show the title screen (e.g., returning from game)
            onShowTitle = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                if data.player and data.player ~= player then return end
                if state.isVisible then return end

                -- Recreate the UI
                state.isVisible = true
                createUI(self)
            end,

            -- Server confirms saved data was cleared
            onSavedDataCleared = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                if data.player and data.player ~= player then return end
                if not state.screenGui then return end

                -- Hide the confirmation dialog
                if state.optionsConfirmFrame then
                    state.optionsConfirmOpen = false
                    state.optionsConfirmFrame.Visible = false
                end

                -- Show success/failure message
                local msgStr = data.success and "SAVED DATA CLEARED" or "FAILED TO CLEAR DATA"
                local msgColor = data.success and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)

                local msgText = PixelFont.createText(msgStr, {
                    scale = PIXEL_SCALE,
                    color = msgColor,
                })
                msgText.Name = "ClearMessage"
                local msgWidth = PixelFont.getTextWidth(msgStr, PIXEL_SCALE, 0)
                msgText.Position = UDim2.new(0.5, -msgWidth / 2, 0.5, 0)
                msgText.ZIndex = 70
                msgText.Parent = state.screenGui

                -- After 2 seconds, fade out message and return to main title screen
                task.delay(2, function()
                    if msgText and msgText.Parent then
                        PixelFont.fadeOut(msgText, 0.5, function()
                            if msgText and msgText.Parent then
                                msgText:Destroy()
                            end
                            -- Return to main title screen
                            hideOptionsMenu(state)
                        end)
                    else
                        -- Message already gone, just return to main
                        hideOptionsMenu(state)
                    end
                end)
            end,
        },

        Out = {
            startPressed = {},
            clearSavedData = {},
        },
    }
end)

return TitleScreen
