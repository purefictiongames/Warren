--[[
    LibPureFiction Framework v2
    ExitScreen.lua - Exit/Pause Menu Component

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    ExitScreen is a client-side node that displays an exit/pause menu overlay.
    It allows players to return to the title screen.

    ============================================================================
    CONTROLS
    ============================================================================

    Gamepad:
    - Select/Touchpad: Toggle exit screen open/close
    - A/X: Confirm selection
    - B/Circle: Cancel/close confirmation

    Keyboard:
    - Escape: Toggle exit screen
    - Enter/Space: Confirm
    - Escape: Cancel confirmation

    ============================================================================
    SIGNALS
    ============================================================================

    OUT (sends):
        exitToTitle({ player })
            - Fired when player confirms exit to title screen

    IN (receives):
        onShowExit()
            - Opens the exit screen

        onHideExit()
            - Closes the exit screen

--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local Node = require(script.Parent.Parent.Node)
local System = require(script.Parent.Parent.System)
local PixelFont = require(script.Parent.Parent.PixelFont)

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local FADE_DURATION = 3.0  -- Used for overlay fade and music fade
local ORANGE_BORDER = Color3.fromRGB(255, 140, 0)

--------------------------------------------------------------------------------
-- EXITSCREEN NODE
--------------------------------------------------------------------------------

local ExitScreen = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- FORWARD DECLARATIONS
    ----------------------------------------------------------------------------

    local createUI
    local openExitScreen
    local closeExitScreen
    local toggleExitScreen
    local showConfirmation
    local hideConfirmation
    local confirmExit
    local fadeInOverlay
    local fadeOutOverlay

    ----------------------------------------------------------------------------
    -- PRIVATE STATE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                isOpen = false,
                isConfirmationOpen = false,
                selectedIndex = 1,
                buttons = {},
                inputConnection = nil,
                inputClaim = nil,  -- InputCapture claim for pausing gameplay
                overlay = nil,
                menuFrame = nil,
                confirmFrame = nil,
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
            -- Release input claim if active
            if state.inputClaim then
                state.inputClaim:release()
                state.inputClaim = nil
            end
            if state.screenGui then
                state.screenGui:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- FADE ANIMATIONS
    ----------------------------------------------------------------------------

    fadeInOverlay = function(self, callback)
        local state = getState(self)
        if not state.overlay then
            if callback then callback() end
            return
        end

        state.overlay.BackgroundTransparency = 1
        state.screenGui.Enabled = true

        local tween = TweenService:Create(
            state.overlay,
            TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 0.5 }
        )

        tween.Completed:Connect(function()
            if callback then callback() end
        end)

        tween:Play()
    end

    fadeOutOverlay = function(self, callback)
        local state = getState(self)
        if not state.overlay then
            if callback then callback() end
            return
        end

        local tween = TweenService:Create(
            state.overlay,
            TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 1 }
        )

        tween.Completed:Connect(function()
            state.screenGui.Enabled = false
            if callback then callback() end
        end)

        tween:Play()
    end

    ----------------------------------------------------------------------------
    -- UI CREATION
    ----------------------------------------------------------------------------

    local PIXEL_SCALE = 3  -- 24px equivalent (8 * 3)
    local PIXEL_SCALE_SMALL = 2  -- 16px equivalent

    createUI = function(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        -- Clean up existing
        if state.screenGui then
            state.screenGui:Destroy()
        end
        local existing = playerGui:FindFirstChild("ExitScreen")
        if existing then
            existing:Destroy()
        end

        -- Create ScreenGui (hidden by default)
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "ExitScreen"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 1001  -- Above title screen
        screenGui.IgnoreGuiInset = true
        screenGui.Enabled = false
        screenGui.Parent = playerGui

        -- Semi-transparent dark overlay
        local overlay = Instance.new("Frame")
        overlay.Name = "Overlay"
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.Position = UDim2.new(0, 0, 0, 0)
        overlay.BackgroundColor3 = Color3.new(0, 0, 0)
        overlay.BackgroundTransparency = 1
        overlay.BorderSizePixel = 0
        overlay.ZIndex = 1
        overlay.Parent = screenGui

        -- Menu frame (centered)
        local menuFrame = Instance.new("Frame")
        menuFrame.Name = "MenuFrame"
        menuFrame.Size = UDim2.new(0, 400, 0, 200)
        menuFrame.Position = UDim2.new(0.5, -200, 0.5, -100)
        menuFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        menuFrame.BorderSizePixel = 0
        menuFrame.ZIndex = 2
        menuFrame.Parent = screenGui

        local menuCorner = Instance.new("UICorner")
        menuCorner.CornerRadius = UDim.new(0, 12)
        menuCorner.Parent = menuFrame

        -- Menu title - pixel text
        local titleText = PixelFont.createText("PAUSED", {
            scale = PIXEL_SCALE,
            color = Color3.fromRGB(255, 255, 255),
        })
        titleText.Name = "Title"
        -- Center horizontally
        local titleWidth = PixelFont.getTextWidth("PAUSED", PIXEL_SCALE, 0)
        titleText.Position = UDim2.new(0.5, -titleWidth / 2, 0, 20)
        titleText.ZIndex = 3
        titleText.Parent = menuFrame

        -- Return to Title Screen button - pixel button
        local returnButton, returnButtonText = PixelFont.createButton("RETURN TO TITLE", {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(255, 255, 255),
            backgroundColor = Color3.fromRGB(50, 50, 60),
            padding = 12,
        })
        returnButton.Name = "ReturnButton"
        returnButton.Position = UDim2.new(0.5, -returnButton.Size.X.Offset / 2, 0.5, -returnButton.Size.Y.Offset / 2)
        returnButton.ZIndex = 3
        returnButton.Parent = menuFrame

        local returnCorner = Instance.new("UICorner")
        returnCorner.CornerRadius = UDim.new(0, 8)
        returnCorner.Parent = returnButton

        -- Selection border (1px orange)
        local stroke = Instance.new("UIStroke")
        stroke.Name = "SelectionStroke"
        stroke.Color = ORANGE_BORDER
        stroke.Thickness = 2
        stroke.Enabled = true  -- Start selected
        stroke.Parent = returnButton

        -- Hover effect
        returnButton.MouseEnter:Connect(function()
            TweenService:Create(
                returnButton,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { BackgroundColor3 = Color3.fromRGB(70, 70, 90) }
            ):Play()
        end)

        returnButton.MouseLeave:Connect(function()
            TweenService:Create(
                returnButton,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { BackgroundColor3 = Color3.fromRGB(50, 50, 60) }
            ):Play()
        end)

        returnButton.MouseButton1Click:Connect(function()
            showConfirmation(self)
        end)

        -- Help text at bottom - pixel text
        local helpText = PixelFont.createText("B / CIRCLE TO CLOSE", {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(150, 150, 150),
        })
        helpText.Name = "HelpText"
        local helpWidth = PixelFont.getTextWidth("B / CIRCLE TO CLOSE", PIXEL_SCALE_SMALL, 0)
        helpText.Position = UDim2.new(0.5, -helpWidth / 2, 1, -36)
        helpText.ZIndex = 3
        helpText.Parent = menuFrame

        -- Confirmation frame (hidden by default)
        local confirmFrame = Instance.new("Frame")
        confirmFrame.Name = "ConfirmFrame"
        confirmFrame.Size = UDim2.new(0, 500, 0, 200)
        confirmFrame.Position = UDim2.new(0.5, -250, 0.5, -100)
        confirmFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        confirmFrame.BorderSizePixel = 0
        confirmFrame.ZIndex = 10
        confirmFrame.Visible = false
        confirmFrame.Parent = screenGui

        local confirmCorner = Instance.new("UICorner")
        confirmCorner.CornerRadius = UDim.new(0, 12)
        confirmCorner.Parent = confirmFrame

        -- Confirmation text - pixel text (split into two lines for readability)
        local confirmLine1 = PixelFont.createText("ARE YOU SURE YOU WANT", {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(255, 255, 255),
        })
        confirmLine1.Name = "ConfirmText1"
        local confirm1Width = PixelFont.getTextWidth("ARE YOU SURE YOU WANT", PIXEL_SCALE_SMALL, 0)
        confirmLine1.Position = UDim2.new(0.5, -confirm1Width / 2, 0, 25)
        confirmLine1.ZIndex = 11
        confirmLine1.Parent = confirmFrame

        local confirmLine2 = PixelFont.createText("TO EXIT THE GAME?", {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(255, 255, 255),
        })
        confirmLine2.Name = "ConfirmText2"
        local confirm2Width = PixelFont.getTextWidth("TO EXIT THE GAME?", PIXEL_SCALE_SMALL, 0)
        confirmLine2.Position = UDim2.new(0.5, -confirm2Width / 2, 0, 50)
        confirmLine2.ZIndex = 11
        confirmLine2.Parent = confirmFrame

        -- Yes button - pixel button
        local yesButton, yesButtonText = PixelFont.createButton("YES", {
            scale = PIXEL_SCALE,
            color = Color3.fromRGB(255, 255, 255),
            backgroundColor = Color3.fromRGB(180, 60, 60),
            padding = 16,
        })
        yesButton.Name = "YesButton"
        yesButton.Position = UDim2.new(0.5, -yesButton.Size.X.Offset / 2, 0.5, 0)
        yesButton.ZIndex = 11
        yesButton.Parent = confirmFrame

        local yesCorner = Instance.new("UICorner")
        yesCorner.CornerRadius = UDim.new(0, 8)
        yesCorner.Parent = yesButton

        local yesStroke = Instance.new("UIStroke")
        yesStroke.Name = "SelectionStroke"
        yesStroke.Color = ORANGE_BORDER
        yesStroke.Thickness = 2
        yesStroke.Enabled = true
        yesStroke.Parent = yesButton

        yesButton.MouseButton1Click:Connect(function()
            confirmExit(self)
        end)

        -- Cancel help text - pixel text
        local cancelText = PixelFont.createText("PRESS B / CIRCLE TO CANCEL", {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(150, 150, 150),
        })
        cancelText.Name = "CancelText"
        local cancelWidth = PixelFont.getTextWidth("PRESS B / CIRCLE TO CANCEL", PIXEL_SCALE_SMALL, 0)
        cancelText.Position = UDim2.new(0.5, -cancelWidth / 2, 1, -36)
        cancelText.ZIndex = 11
        cancelText.Parent = confirmFrame

        state.screenGui = screenGui
        state.overlay = overlay
        state.menuFrame = menuFrame
        state.confirmFrame = confirmFrame
        state.buttons = { returnButton }
    end

    ----------------------------------------------------------------------------
    -- EXIT SCREEN TOGGLE
    ----------------------------------------------------------------------------

    openExitScreen = function(self)
        local state = getState(self)
        if state.isOpen then return end

        state.isOpen = true
        state.isConfirmationOpen = false

        -- Pause gameplay via InputCapture (sinks movement/camera, disables PlayerModule)
        state.inputClaim = System.InputCapture.claim({}, {
            sinkMovement = true,
            sinkCamera = true,
            disablePlayerModule = true,
        })

        -- Hide confirmation if showing
        if state.confirmFrame then
            state.confirmFrame.Visible = false
        end
        if state.menuFrame then
            state.menuFrame.Visible = true
        end

        fadeInOverlay(self)
    end

    closeExitScreen = function(self)
        local state = getState(self)
        if not state.isOpen then return end

        fadeOutOverlay(self, function()
            state.isOpen = false
            state.isConfirmationOpen = false

            -- Resume gameplay by releasing input claim
            if state.inputClaim then
                state.inputClaim:release()
                state.inputClaim = nil
            end
        end)
    end

    toggleExitScreen = function(self)
        local state = getState(self)
        if state.isOpen then
            if state.isConfirmationOpen then
                hideConfirmation(self)
            else
                closeExitScreen(self)
            end
        else
            openExitScreen(self)
        end
    end

    ----------------------------------------------------------------------------
    -- CONFIRMATION
    ----------------------------------------------------------------------------

    showConfirmation = function(self)
        local state = getState(self)
        if not state.isOpen then return end

        state.isConfirmationOpen = true

        if state.menuFrame then
            state.menuFrame.Visible = false
        end
        if state.confirmFrame then
            state.confirmFrame.Visible = true
        end
    end

    hideConfirmation = function(self)
        local state = getState(self)
        if not state.isConfirmationOpen then return end

        state.isConfirmationOpen = false

        if state.confirmFrame then
            state.confirmFrame.Visible = false
        end
        if state.menuFrame then
            state.menuFrame.Visible = true
        end
    end

    confirmExit = function(self)
        local state = getState(self)
        local player = Players.LocalPlayer

        -- Hide the exit screen immediately (before fade to black)
        if state.screenGui then
            state.screenGui.Enabled = false
        end
        state.isOpen = false
        state.isConfirmationOpen = false

        -- Release input claim (restore controls temporarily - they'll be disabled by ScreenTransition)
        if state.inputClaim then
            state.inputClaim:release()
            state.inputClaim = nil
        end

        -- Start fading out gameplay music (fade over 3 seconds)
        -- The actual music cleanup happens after the transition completes
        local gameplayMusic = SoundService:FindFirstChild("GameplayMusic")
        if gameplayMusic then
            local fadeOutTween = TweenService:Create(
                gameplayMusic,
                TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Volume = 0 }
            )
            fadeOutTween.Completed:Connect(function()
                gameplayMusic:Stop()
                gameplayMusic:Destroy()
            end)
            fadeOutTween:Play()
        end

        -- Fire exit signal to server (server will trigger fade to black)
        self.Out:Fire("exitToTitle", {
            _targetPlayer = player,
            player = player,
        })
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "ExitScreen",
        domain = "client",

        Sys = {
            onInit = function(self)
                createUI(self)
            end,

            onStart = function(self)
                local state = getState(self)

                -- Set up input listener
                state.inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
                    if processed then return end

                    local keyCode = input.KeyCode

                    -- Toggle with Select/Touchpad button or Escape (open or close)
                    -- PS4 touchpad click maps to ButtonSelect
                    if keyCode == Enum.KeyCode.ButtonSelect or keyCode == Enum.KeyCode.Escape then
                        toggleExitScreen(self)
                        return
                    end

                    -- Only handle other inputs when open
                    if not state.isOpen then return end

                    if state.isConfirmationOpen then
                        -- Confirmation dialog controls
                        -- A/X/Enter/Space = confirm exit
                        if keyCode == Enum.KeyCode.ButtonA
                            or keyCode == Enum.KeyCode.ButtonX
                            or keyCode == Enum.KeyCode.Return
                            or keyCode == Enum.KeyCode.Space then
                            confirmExit(self)
                        -- B/Circle = back to menu
                        elseif keyCode == Enum.KeyCode.ButtonB then
                            hideConfirmation(self)
                        end
                    else
                        -- Menu controls
                        -- A/X/Enter/Space = show confirmation
                        if keyCode == Enum.KeyCode.ButtonA
                            or keyCode == Enum.KeyCode.ButtonX
                            or keyCode == Enum.KeyCode.Return
                            or keyCode == Enum.KeyCode.Space then
                            showConfirmation(self)
                        -- B/Circle = close exit screen
                        elseif keyCode == Enum.KeyCode.ButtonB then
                            closeExitScreen(self)
                        end
                    end
                end)
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onShowExit = function(self)
                openExitScreen(self)
            end,

            onHideExit = function(self)
                closeExitScreen(self)
            end,

            -- Called when returning to title screen is complete
            onReturnToTitle = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                if data.player and data.player ~= player then return end

                -- Close exit screen
                state.isOpen = false
                state.isConfirmationOpen = false
                if state.screenGui then
                    state.screenGui.Enabled = false
                end
            end,
        },

        Out = {
            exitToTitle = {},
        },
    }
end)

return ExitScreen
