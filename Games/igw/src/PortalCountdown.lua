--[[
    IGW v2 — PortalCountdown (client)
    Countdown display UI + screen fade for portal transitions.

    Receives signals from PortalTrigger (countdown) and
    WorldMapOrchestrator (transition start/end).
--]]

return {
    name = "PortalCountdown",
    domain = "client",

    Sys = {
        onInit = function(self)
            self._screenGui = nil
            self._countdownLabel = nil
            self._fadeFrame = nil
        end,
        onStart = function(self) end,
        onStop = function(self)
            if self._screenGui then
                self._screenGui:Destroy()
                self._screenGui = nil
            end
        end,
    },

    _ensureGui = function(self)
        if self._screenGui and self._screenGui.Parent then
            return
        end

        local Players = game:GetService("Players")
        local playerGui = Players.LocalPlayer and Players.LocalPlayer:WaitForChild("PlayerGui")
        if not playerGui then return end

        local gui = Instance.new("ScreenGui")
        gui.Name = "PortalCountdownGui"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 100
        gui.IgnoreGuiInset = true
        gui.Parent = playerGui
        self._screenGui = gui

        -- Countdown label (centered, large text)
        local label = Instance.new("TextLabel")
        label.Name = "CountdownLabel"
        label.Size = UDim2.new(0.6, 0, 0.15, 0)
        label.Position = UDim2.new(0.2, 0, 0.4, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.3
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.TextScaled = true
        label.Text = ""
        label.Visible = false
        label.Parent = gui
        self._countdownLabel = label

        -- Fade overlay (full-screen black frame)
        local fade = Instance.new("Frame")
        fade.Name = "FadeOverlay"
        fade.Size = UDim2.new(1, 0, 1, 0)
        fade.Position = UDim2.new(0, 0, 0, 0)
        fade.BackgroundColor3 = Color3.new(0, 0, 0)
        fade.BackgroundTransparency = 1
        fade.BorderSizePixel = 0
        fade.Visible = false
        fade.ZIndex = 10
        fade.Parent = gui
        self._fadeFrame = fade
    end,

    In = {
        onPortalCountdownStarted = function(self, data)
            self:_ensureGui()
            if not self._countdownLabel then return end

            local biomeName = data.targetBiome or "?"
            local displayName = biomeName:upper()

            self._countdownLabel.Text = "ENTERING " .. displayName .. "...\n" .. (data.seconds or "?")
            self._countdownLabel.Visible = true
        end,

        onPortalCountdownTick = function(self, data)
            if not self._countdownLabel then return end

            local biomeName = data.targetBiome or "?"
            local displayName = biomeName:upper()

            self._countdownLabel.Text = "ENTERING " .. displayName .. "...\n" .. (data.remaining or "?")
        end,

        onPortalCountdownCancelled = function(self)
            if self._countdownLabel then
                self._countdownLabel.Visible = false
                self._countdownLabel.Text = ""
            end
        end,

        onPortalTransitionStart = function(self)
            self:_ensureGui()

            -- Hide countdown
            if self._countdownLabel then
                self._countdownLabel.Visible = false
            end

            -- Fade to black
            if self._fadeFrame then
                self._fadeFrame.BackgroundTransparency = 1
                self._fadeFrame.Visible = true

                local TweenService = game:GetService("TweenService")
                local tween = TweenService:Create(
                    self._fadeFrame,
                    TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                    { BackgroundTransparency = 0 }
                )
                tween:Play()
            end
        end,

        onPortalTransitionEnd = function(self, data)
            self:_ensureGui()

            -- Fade from black
            if self._fadeFrame then
                self._fadeFrame.BackgroundTransparency = 0
                self._fadeFrame.Visible = true

                local TweenService = game:GetService("TweenService")
                local tween = TweenService:Create(
                    self._fadeFrame,
                    TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { BackgroundTransparency = 1 }
                )
                tween:Play()
                tween.Completed:Connect(function()
                    if self._fadeFrame then
                        self._fadeFrame.Visible = false
                    end
                end)
            end
        end,
    },
}
