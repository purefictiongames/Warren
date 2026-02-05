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
    local BUILD_NUMBER = 186
    local TITLE_MUSIC_ID = "rbxassetid://115218802234328"
    local GAMEPLAY_MUSIC_ID = "rbxassetid://127750735513287"
    local PIXEL_SCALE = 3  -- 24px equivalent (8 * 3)
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
            if state.screenGui then
                state.screenGui:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- BUTTON SELECTION
    ----------------------------------------------------------------------------

    local BUTTON_ACTIVE_COLOR = Color3.fromRGB(0, 255, 255)  -- Cyan
    local BUTTON_INACTIVE_COLOR = Color3.fromRGB(40, 40, 50)

    local function updateButtonHighlight(state)
        for i, button in ipairs(state.buttons) do
            local stroke = button:FindFirstChildOfClass("UIStroke")
            if i == state.selectedIndex then
                -- Active: cyan, 75% transparent
                button.BackgroundColor3 = BUTTON_ACTIVE_COLOR
                button.BackgroundTransparency = 0.75
                if stroke then
                    stroke.Enabled = true
                    stroke.Color = ORANGE_BORDER
                end
            else
                -- Inactive: dark, 50% transparent
                button.BackgroundColor3 = BUTTON_INACTIVE_COLOR
                button.BackgroundTransparency = 0.5
                if stroke then
                    stroke.Enabled = false
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
                -- TODO: Open options menu
                -- For now, just a visual feedback
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

        -- Fade in buttons (TextButton backgrounds only)
        -- Active button fades to 0.75, inactive to 0.5
        for i, button in ipairs(state.buttons) do
            if button:IsA("TextButton") then
                local targetTransparency = (i == state.selectedIndex) and 0.75 or 0.5
                table.insert(tweens, TweenService:Create(button, tweenInfo, {
                    BackgroundTransparency = targetTransparency,
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

        -- Fade out buttons (TextButton backgrounds only)
        for _, button in ipairs(state.buttons) do
            if button:IsA("TextButton") then
                table.insert(tweens, TweenService:Create(button, tweenInfo, {
                    BackgroundTransparency = 1,
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

        -- Helper to create a menu button with PixelFont
        -- Uses separate TextButton (for clicks) and pixel text Frame (for display)
        local function createMenuButton(name, text, positionY, isActive)
            -- Create pixel text first to get dimensions
            local buttonText = PixelFont.createText(text, {
                scale = PIXEL_SCALE,
                color = Color3.fromRGB(255, 255, 255),
            })

            local textWidth = buttonText.Size.X.Offset
            local textHeight = buttonText.Size.Y.Offset
            local padding = 16
            local buttonWidth = textWidth + padding * 2
            local buttonHeight = textHeight + padding * 2

            -- Create button (background + click handler)
            local button = Instance.new("TextButton")
            button.Name = name
            button.Text = ""
            button.AutoButtonColor = false
            -- Set initial state based on isActive
            if isActive then
                button.BackgroundColor3 = Color3.fromRGB(0, 255, 255)  -- Cyan
                button.BackgroundTransparency = 0.75
            else
                button.BackgroundColor3 = Color3.fromRGB(40, 40, 50)  -- Dark gray
                button.BackgroundTransparency = 0.5
            end
            button.BorderSizePixel = 0
            button.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
            button.Position = UDim2.new(0.5, -buttonWidth / 2, positionY, 0)
            button.ZIndex = 2
            button.Parent = screenGui

            -- Position text centered over the button (as sibling, not child)
            buttonText.Position = UDim2.new(0.5, -textWidth / 2, positionY, padding)
            buttonText.ZIndex = 3
            buttonText.Parent = screenGui

            -- DEBUG: Start text visible to test
            -- PixelFont.setTransparency(buttonText, 1)

            -- Corner rounding
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = button

            -- Selection border (1px orange)
            local stroke = Instance.new("UIStroke")
            stroke.Name = "SelectionStroke"
            stroke.Color = ORANGE_BORDER
            stroke.Thickness = 2
            stroke.Enabled = isActive  -- Enabled if active
            stroke.Parent = button

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

        -- Create Start button
        local startButton, startText = createMenuButton("StartButton", "START", 0.52, true)  -- Active by default
        startButton.MouseButton1Click:Connect(function()
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

        -- Create Options button
        local optionsButton, optionsText = createMenuButton("OptionsButton", "OPTIONS", 0.63, false)  -- Inactive
        optionsButton.MouseButton1Click:Connect(function()
            if not state.isVisible then return end
            -- TODO: Open options menu
        end)

        -- Store button and text references
        state.buttons = { startButton, optionsButton }
        state.buttonTexts = { startText, optionsText }

        -- Set initial selection (Start button)
        state.selectedIndex = 1
        -- Initial highlight already set via isActive parameter in createMenuButton

        -- Footer text - copyright line (starts invisible for fade-in)
        local copyrightStr = "(C) 2025-2026 PURE FICTION RECORDS"
        local copyrightText = PixelFont.createText(copyrightStr, {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(255, 255, 255),
        })
        copyrightText.Name = "CopyrightText"
        local copyrightWidth = PixelFont.getTextWidth(copyrightStr, PIXEL_SCALE_SMALL, 0)
        copyrightText.Position = UDim2.new(0.5, -copyrightWidth / 2, 0.92, 0)
        copyrightText.ZIndex = 2
        PixelFont.setTransparency(copyrightText, 1)  -- Start invisible for fade
        copyrightText.Parent = screenGui

        -- Footer text - build number (starts invisible for fade-in)
        local buildStr = "DEMO BUILD " .. BUILD_NUMBER
        local buildText = PixelFont.createText(buildStr, {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(255, 255, 255),
        })
        buildText.Name = "BuildText"
        local buildWidth = PixelFont.getTextWidth(buildStr, PIXEL_SCALE_SMALL, 0)
        buildText.Position = UDim2.new(0.5, -buildWidth / 2, 0.95, 0)
        buildText.ZIndex = 2
        PixelFont.setTransparency(buildText, 1)  -- Start invisible for fade
        buildText.Parent = screenGui

        -- Store footer text references
        state.footerTexts = { copyrightText, buildText }

        -- Set up controller/keyboard input
        state.inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if not state.isVisible then return end

            local keyCode = input.KeyCode

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
            -- Step 2: Destroy buttons and their text (now separate)
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
        },

        Out = {
            startPressed = {},
        },
    }
end)

return TitleScreen
