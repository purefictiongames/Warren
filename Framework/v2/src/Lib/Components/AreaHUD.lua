--[[
    LibPureFiction Framework v2
    AreaHUD.lua - Client Area/Room Display HUD

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    AreaHUD is a client-side node that displays the current area (region) and
    room number in a simple HUD in the top-right corner of the screen.

    It receives areaInfo signals from RegionManager via IPC wiring.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onAreaInfo({ regionNum, roomNum })
            - Updates the HUD with current area and room numbers

--]]

local Players = game:GetService("Players")

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- AREAHUD NODE
--------------------------------------------------------------------------------

local AreaHUD = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE STATE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                areaLabel = nil,
                roomLabel = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            if state.screenGui then
                state.screenGui:Destroy()
            end
        end
        instanceStates[self.id] = nil
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
        local existing = playerGui:FindFirstChild("AreaHUD")
        if existing then
            existing:Destroy()
        end

        -- Create ScreenGui
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "AreaHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 10
        screenGui.Parent = playerGui

        -- Create container frame (top-right corner)
        local container = Instance.new("Frame")
        container.Name = "Container"
        container.Size = UDim2.new(0, 120, 0, 50)
        container.Position = UDim2.new(1, -130, 0, 10)
        container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        container.BackgroundTransparency = 0.5
        container.BorderSizePixel = 0
        container.Parent = screenGui

        -- Corner rounding
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container

        -- Padding
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 8)
        padding.PaddingRight = UDim.new(0, 8)
        padding.PaddingTop = UDim.new(0, 6)
        padding.PaddingBottom = UDim.new(0, 6)
        padding.Parent = container

        -- Area label (row 1)
        local areaLabel = Instance.new("TextLabel")
        areaLabel.Name = "AreaLabel"
        areaLabel.Size = UDim2.new(1, 0, 0, 18)
        areaLabel.Position = UDim2.new(0, 0, 0, 0)
        areaLabel.BackgroundTransparency = 1
        areaLabel.Font = Enum.Font.GothamBold
        areaLabel.TextSize = 14
        areaLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        areaLabel.TextXAlignment = Enum.TextXAlignment.Left
        areaLabel.Text = "Area: --"
        areaLabel.Parent = container

        -- Room label (row 2)
        local roomLabel = Instance.new("TextLabel")
        roomLabel.Name = "RoomLabel"
        roomLabel.Size = UDim2.new(1, 0, 0, 18)
        roomLabel.Position = UDim2.new(0, 0, 0, 20)
        roomLabel.BackgroundTransparency = 1
        roomLabel.Font = Enum.Font.GothamBold
        roomLabel.TextSize = 14
        roomLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        roomLabel.TextXAlignment = Enum.TextXAlignment.Left
        roomLabel.Text = "Room: --"
        roomLabel.Parent = container

        state.screenGui = screenGui
        state.areaLabel = areaLabel
        state.roomLabel = roomLabel
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "AreaHUD",
        domain = "client",

        Sys = {
            onInit = function(self)
                createUI(self)
            end,

            onStart = function(self)
                -- No polling needed - we receive signals
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            --[[
                Handle area info signal from RegionManager.
                Updates the HUD labels.

                @param data table:
                    regionNum: number - Current area/region number
                    roomNum: number - Current room number within the area
            --]]
            onAreaInfo = function(self, data)
                if not data then return end

                local state = getState(self)
                local player = Players.LocalPlayer

                -- Only update for local player
                if data.player and data.player ~= player then return end

                if state.areaLabel and data.regionNum then
                    state.areaLabel.Text = "Area: " .. tostring(data.regionNum)
                end

                if state.roomLabel and data.roomNum then
                    state.roomLabel.Text = "Room: " .. tostring(data.roomNum)
                end
            end,
        },

        Out = {},
    }
end)

return AreaHUD
