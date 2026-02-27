--[[
    IGW Phase 2 — BackpackToolbar (Client Node)
    Dynamic toolbar UI for inventory. Shows 4 backpack slots at bottom of screen.
    Slots update in real-time as items are picked up, used, or dropped.
    Press 1-4 or click to select. Right-click to drop.
--]]

return {
    name = "BackpackToolbar",
    domain = "client",

    Sys = {
        onInit = function(self)
            self._gui = nil
            self._slots = {}
            self._selected = 1
            self._capacity = 4
        end,

        onStart = function(self)
            self:_createUI()
            self:_bindInput()
            self:_bindUpdates()
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
        frame.Size = UDim2.new(0, 340, 0, 56)
        frame.Position = UDim2.new(0.5, -170, 1, -72)
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

        -- Item type colors for display
        local typeColors = {
            key    = Color3.fromRGB(80, 120, 220),
            weapon = Color3.fromRGB(220, 60, 60),
            bomb   = Color3.fromRGB(220, 140, 40),
        }

        for i = 1, self._capacity do
            local slot = Instance.new("TextButton")
            slot.Name = "Slot_" .. i
            slot.Size = UDim2.new(0, 76, 0, 44)
            slot.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            slot.BorderSizePixel = 2
            slot.BorderColor3 = Color3.fromRGB(60, 60, 60)
            slot.Text = ""
            slot.TextColor3 = Color3.fromRGB(180, 180, 180)
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
            countLabel.Text = ""
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

            -- Left-click to select
            slot.MouseButton1Click:Connect(function()
                self:_selectSlot(i)
            end)

            -- Right-click to drop
            slot.MouseButton2Click:Connect(function()
                self:_dropSlot(i)
            end)

            self._slots[i] = {
                button = slot,
                countLabel = countLabel,
                typeColors = typeColors,
            }
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
                [Enum.KeyCode.Four] = 4,
            }
            local slot = keyMap[input.KeyCode]
            if slot then
                self:_selectSlot(slot)
            end
        end)
    end,

    _bindUpdates = function(self)
        -- Listen for server-pushed inventory updates
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        task.spawn(function()
            local updateEvent = ReplicatedStorage:WaitForChild("BackpackUpdate", 10)
            if updateEvent then
                updateEvent.OnClientEvent:Connect(function(data)
                    self:_applyInventory(data)
                end)
            end
        end)
    end,

    --- Visual-only highlight (no server fire). Used by _applyInventory.
    _highlightSlot = function(self, slotIndex)
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
    end,

    --- User-initiated selection: update visual + tell server.
    _selectSlot = function(self, slotIndex)
        self:_highlightSlot(slotIndex)

        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local selectEvent = ReplicatedStorage:FindFirstChild("BackpackSelect")
        if selectEvent then
            selectEvent:FireServer(slotIndex)
        end
    end,

    _dropSlot = function(self, slotIndex)
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local dropEvent = ReplicatedStorage:FindFirstChild("BackpackDrop")
        if dropEvent then
            dropEvent:FireServer(slotIndex)
        end
    end,

    _applyInventory = function(self, data)
        if not data or not data.slots then return end
        local typeColors = {
            key    = Color3.fromRGB(80, 120, 220),
            weapon = Color3.fromRGB(220, 60, 60),
            bomb   = Color3.fromRGB(220, 140, 40),
        }
        local typeNames = {
            key    = "Key",
            weapon = "Weapon",
            bomb   = "Bomb",
        }

        for i, slot in ipairs(data.slots) do
            local slotData = self._slots[i]
            if not slotData then break end

            if slot and slot ~= false and slot.name then
                local displayName = typeNames[slot.name] or slot.name
                slotData.button.Text = displayName
                slotData.button.TextColor3 = typeColors[slot.name]
                    or Color3.fromRGB(180, 180, 180)
                slotData.countLabel.Text = tostring(slot.count)
            else
                slotData.button.Text = ""
                slotData.button.TextColor3 = Color3.fromRGB(80, 80, 80)
                slotData.countLabel.Text = ""
            end
        end

        if data.selected then
            self:_highlightSlot(data.selected)
        end
    end,

    _refresh = function(self)
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local queryFunc = ReplicatedStorage:WaitForChild("BackpackQuery", 5)
        if not queryFunc then return end

        local ok, data = pcall(queryFunc.InvokeServer, queryFunc)
        if ok and data then
            self:_applyInventory(data)
        end
    end,

    In = {},
}
