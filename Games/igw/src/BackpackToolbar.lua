--[[
    IGW Phase 1 — BackpackToolbar (Client Node)
    Minimal toolbar UI for testing door interactions.
    Shows 3 item slots (key, weapon, bomb) at bottom of screen.
    Press 1/2/3 or click to select. Selection fires to server.
    Throwaway scaffolding — Phase 2 builds the real inventory UI.
--]]

return {
    name = "BackpackToolbar",
    domain = "client",

    Sys = {
        onInit = function(self)
            self._gui = nil
            self._slots = {}
            self._selected = 1
        end,

        onStart = function(self)
            self:_createUI()
            self:_bindInput()
            -- Delay initial query to let server create RemoteFunction
            task.delay(2, function()
                self:_refresh()
            end)
        end,

        onStop = function(self)
            if self._gui then
                self._gui:Destroy()
                self._gui = nil
            end
        end,
    },

    _createUI = function(self)
        local Players = game:GetService("Players")
        local player = Players.LocalPlayer
        local playerGui = player:WaitForChild("PlayerGui")

        local sg = Instance.new("ScreenGui")
        sg.Name = "BackpackToolbar"
        sg.ResetOnSpawn = false
        sg.DisplayOrder = 100
        sg.IgnoreGuiInset = true
        sg.Parent = playerGui

        -- Toolbar container at bottom center
        local frame = Instance.new("Frame")
        frame.Name = "Toolbar"
        frame.Size = UDim2.new(0, 260, 0, 56)
        frame.Position = UDim2.new(0.5, -130, 1, -72)
        frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        frame.BackgroundTransparency = 0.3
        frame.BorderSizePixel = 0
        frame.Parent = sg

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = frame

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.VerticalAlignment = Enum.VerticalAlignment.Center
        layout.Padding = UDim.new(0, 6)
        layout.Parent = frame

        local slotNames = { "Key", "Weapon", "Bomb" }
        local slotColors = {
            Color3.fromRGB(80, 120, 220),   -- key: blue
            Color3.fromRGB(220, 60, 60),    -- weapon: red
            Color3.fromRGB(220, 140, 40),   -- bomb: orange
        }

        for i = 1, 3 do
            local slot = Instance.new("TextButton")
            slot.Name = "Slot_" .. i
            slot.Size = UDim2.new(0, 76, 0, 44)
            slot.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            slot.BorderSizePixel = 2
            slot.BorderColor3 = Color3.fromRGB(60, 60, 60)
            slot.Text = slotNames[i]
            slot.TextColor3 = slotColors[i]
            slot.TextSize = 13
            slot.Font = Enum.Font.GothamBold
            slot.AutoButtonColor = false
            slot.Parent = frame

            local slotCorner = Instance.new("UICorner")
            slotCorner.CornerRadius = UDim.new(0, 4)
            slotCorner.Parent = slot

            local countLabel = Instance.new("TextLabel")
            countLabel.Name = "Count"
            countLabel.Size = UDim2.new(0, 20, 0, 14)
            countLabel.Position = UDim2.new(1, -22, 0, 2)
            countLabel.BackgroundTransparency = 1
            countLabel.Text = "0"
            countLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
            countLabel.TextSize = 10
            countLabel.Font = Enum.Font.GothamBold
            countLabel.TextXAlignment = Enum.TextXAlignment.Right
            countLabel.Parent = slot

            local keyLabel = Instance.new("TextLabel")
            keyLabel.Name = "KeyHint"
            keyLabel.Size = UDim2.new(0, 14, 0, 12)
            keyLabel.Position = UDim2.new(0, 3, 0, 2)
            keyLabel.BackgroundTransparency = 1
            keyLabel.Text = tostring(i)
            keyLabel.TextColor3 = Color3.fromRGB(90, 90, 90)
            keyLabel.TextSize = 9
            keyLabel.Font = Enum.Font.GothamBold
            keyLabel.TextXAlignment = Enum.TextXAlignment.Left
            keyLabel.Parent = slot

            slot.MouseButton1Click:Connect(function()
                self:_selectSlot(i)
            end)

            self._slots[i] = { button = slot, countLabel = countLabel }
        end

        self._gui = sg
    end,

    _bindInput = function(self)
        local UserInputService = game:GetService("UserInputService")
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            local keyMap = {
                [Enum.KeyCode.One] = 1,
                [Enum.KeyCode.Two] = 2,
                [Enum.KeyCode.Three] = 3,
            }
            local slot = keyMap[input.KeyCode]
            if slot then
                self:_selectSlot(slot)
            end
        end)
    end,

    _selectSlot = function(self, slotIndex)
        self._selected = slotIndex

        for i, slotData in ipairs(self._slots) do
            if i == slotIndex then
                slotData.button.BorderColor3 = Color3.fromRGB(255, 200, 50)
                slotData.button.BackgroundColor3 = Color3.fromRGB(60, 50, 25)
            else
                slotData.button.BorderColor3 = Color3.fromRGB(60, 60, 60)
                slotData.button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            end
        end

        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local selectEvent = ReplicatedStorage:FindFirstChild("BackpackSelect")
        if selectEvent then
            selectEvent:FireServer(slotIndex)
        end
    end,

    _refresh = function(self)
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local queryFunc = ReplicatedStorage:WaitForChild("BackpackQuery", 5)
        if not queryFunc then return end

        local ok, data = pcall(queryFunc.InvokeServer, queryFunc)
        if ok and data and data.slots then
            for i, slot in ipairs(data.slots) do
                if self._slots[i] then
                    self._slots[i].countLabel.Text = tostring(slot.count)
                end
            end
            if data.selected then
                self:_selectSlot(data.selected)
            end
        end
    end,

    In = {},
}
