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
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

local Node = require(script.Parent.Parent.Node)

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
    local BUILD_NUMBER = 184
    local TITLE_MUSIC_ID = "rbxassetid://115218802234328"
    local GAMEPLAY_MUSIC_ID = "rbxassetid://127750735513287"

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                isVisible = true,
                selectedIndex = 1,  -- 1 = Start, 2 = Options
                buttons = {},       -- { StartButton, OptionsButton }
                inputConnection = nil,
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

    local function updateButtonHighlight(state)
        for i, button in ipairs(state.buttons) do
            local stroke = button:FindFirstChildOfClass("UIStroke")
            if stroke then
                if i == state.selectedIndex then
                    stroke.Enabled = true
                    stroke.Color = ORANGE_BORDER
                else
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
        if button then
            -- Trigger the button's click handler
            if button.Name == "StartButton" then
                -- Disable to prevent double-clicks
                button.Active = false
                button.TextTransparency = 0.5

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
    -- CORE GUI VISIBILITY
    ----------------------------------------------------------------------------

    local function hideCoreGui()
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
        end)
        -- Hide the top bar (Roblox menu button)
        pcall(function()
            StarterGui:SetCore("TopbarEnabled", false)
        end)
    end

    local function showCoreGui()
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
        end)
        -- Show the top bar
        pcall(function()
            StarterGui:SetCore("TopbarEnabled", true)
        end)
    end

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

        -- Fade in buttons and text labels (not the background)
        for _, child in ipairs(state.screenGui:GetChildren()) do
            if child:IsA("TextButton") then
                table.insert(tweens, TweenService:Create(child, tweenInfo, {
                    TextTransparency = 0,
                    BackgroundTransparency = 0,
                }))
            elseif child:IsA("TextLabel") then
                table.insert(tweens, TweenService:Create(child, tweenInfo, {
                    TextTransparency = 0,
                }))
            end
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
            if callback then callback() end
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

        -- Fade out buttons and text labels (not the background yet)
        for _, child in ipairs(state.screenGui:GetChildren()) do
            if child:IsA("TextButton") then
                table.insert(tweens, TweenService:Create(child, tweenInfo, {
                    TextTransparency = 1,
                    BackgroundTransparency = 1,
                }))
            elseif child:IsA("TextLabel") then
                table.insert(tweens, TweenService:Create(child, tweenInfo, {
                    TextTransparency = 1,
                }))
            end
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
            if callback then callback() end
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

        -- Create loading text
        local loadingText = Instance.new("TextLabel")
        loadingText.Name = "LoadingText"
        loadingText.Size = UDim2.new(1, 0, 0.1, 0)
        loadingText.Position = UDim2.new(0, 0, 0.45, 0)
        loadingText.BackgroundTransparency = 1
        loadingText.Font = Enum.Font.GothamBold
        loadingText.Text = "Starting...."
        loadingText.TextColor3 = ORANGE_BORDER  -- Orange color
        loadingText.TextTransparency = 1  -- Start invisible
        loadingText.TextScaled = true
        loadingText.ZIndex = 10
        loadingText.Parent = state.screenGui

        -- Fade in the text
        local fadeInTween = TweenService:Create(
            loadingText,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 0 }
        )

        fadeInTween.Completed:Connect(function()
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
                local fadeOutTween = TweenService:Create(
                    loadingText,
                    TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { TextTransparency = 1 }
                )

                fadeOutTween.Completed:Connect(function()
                    loadingText:Destroy()
                    if callback then callback() end
                end)

                fadeOutTween:Play()
            end)
        end)

        fadeInTween:Play()
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

        -- Hide Roblox toolbar during title screen
        hideCoreGui()

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
        background.Image = "rbxassetid://109454468572134"
        background.ScaleType = Enum.ScaleType.Crop
        background.BackgroundColor3 = Color3.new(0, 0, 0)
        background.BackgroundTransparency = 0
        background.BorderSizePixel = 0
        background.ZIndex = 1
        background.Parent = screenGui

        -- Helper to create a menu button (starts invisible for fade-in)
        local function createMenuButton(name, text, positionY)
            local button = Instance.new("TextButton")
            button.Name = name
            button.Size = UDim2.new(0.3, 0, 0.08, 0)
            button.Position = UDim2.new(0.35, 0, positionY, 0)
            button.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
            button.BackgroundTransparency = 1  -- Start invisible
            button.BorderSizePixel = 0
            button.Font = Enum.Font.GothamBold
            button.Text = text
            button.TextColor3 = Color3.fromRGB(255, 255, 255)
            button.TextTransparency = 1  -- Start invisible
            button.TextScaled = true
            button.ZIndex = 2
            button.Parent = screenGui

            -- Corner rounding
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0.2, 0)
            corner.Parent = button

            -- Selection border (1px orange, initially disabled)
            local stroke = Instance.new("UIStroke")
            stroke.Name = "SelectionStroke"
            stroke.Color = ORANGE_BORDER
            stroke.Thickness = 1
            stroke.Enabled = false
            stroke.Parent = button

            -- Hover effect
            button.MouseEnter:Connect(function()
                -- Select this button on hover
                for i, btn in ipairs(state.buttons) do
                    if btn == button then
                        selectButton(state, i)
                        break
                    end
                end
                TweenService:Create(
                    button,
                    TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { BackgroundColor3 = Color3.fromRGB(60, 60, 80) }
                ):Play()
            end)

            button.MouseLeave:Connect(function()
                TweenService:Create(
                    button,
                    TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { BackgroundColor3 = Color3.fromRGB(40, 40, 50) }
                ):Play()
            end)

            return button
        end

        -- Create Start button
        local startButton = createMenuButton("StartButton", "START", 0.55)
        startButton.MouseButton1Click:Connect(function()
            if not state.isVisible then return end

            -- Disable button to prevent double-clicks
            startButton.Active = false
            startButton.TextTransparency = 0.5

            -- Fire signal to server
            self.Out:Fire("startPressed", {
                _targetPlayer = player,
                player = player,
            })
        end)

        -- Create Options button
        local optionsButton = createMenuButton("OptionsButton", "OPTIONS", 0.66)
        optionsButton.MouseButton1Click:Connect(function()
            if not state.isVisible then return end
            -- TODO: Open options menu
        end)

        -- Store button references
        state.buttons = { startButton, optionsButton }

        -- Set initial selection (Start button)
        state.selectedIndex = 1
        updateButtonHighlight(state)

        -- Footer text - copyright line (starts invisible for fade-in)
        local copyrightText = Instance.new("TextLabel")
        copyrightText.Name = "CopyrightText"
        copyrightText.Size = UDim2.new(1, 0, 0.03, 0)
        copyrightText.Position = UDim2.new(0, 0, 0.92, 0)
        copyrightText.BackgroundTransparency = 1
        copyrightText.Font = Enum.Font.GothamBold
        copyrightText.Text = "(c) 2025 - 2026 Pure Fiction Records/AlphaRabbit Games"
        copyrightText.TextColor3 = Color3.fromRGB(255, 255, 255)
        copyrightText.TextTransparency = 1  -- Start invisible
        copyrightText.TextScaled = true
        copyrightText.ZIndex = 2
        copyrightText.Parent = screenGui

        -- Footer text - build number (starts invisible for fade-in)
        local buildText = Instance.new("TextLabel")
        buildText.Name = "BuildText"
        buildText.Size = UDim2.new(1, 0, 0.03, 0)
        buildText.Position = UDim2.new(0, 0, 0.95, 0)
        buildText.BackgroundTransparency = 1
        buildText.Font = Enum.Font.GothamBold
        buildText.Text = "DEMO BUILD " .. BUILD_NUMBER
        buildText.TextColor3 = Color3.fromRGB(255, 255, 255)
        buildText.TextTransparency = 1  -- Start invisible
        buildText.TextScaled = true
        buildText.ZIndex = 2
        buildText.Parent = screenGui

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
            -- Step 2: Destroy buttons and footer text
            for _, button in ipairs(state.buttons) do
                button:Destroy()
            end
            state.buttons = {}

            local copyrightText = state.screenGui:FindFirstChild("CopyrightText")
            if copyrightText then copyrightText:Destroy() end
            local buildText = state.screenGui:FindFirstChild("BuildText")
            if buildText then buildText:Destroy() end

            -- Step 3: Fade out background image (keep black background)
            fadeOutBackgroundImage(self, function()
                -- Step 4: Show "Starting...." text for 2 seconds
                showLoadingText(self, function()
                    -- Step 5: Fade out black background to reveal dungeon
                    fadeOutBlackBackground(self, function()
                        -- Step 6: Show Roblox toolbar for gameplay
                        showCoreGui()

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
        },

        Out = {
            startPressed = {},
        },
    }
end)

return TitleScreen
