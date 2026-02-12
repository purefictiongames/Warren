--[[
    It Gets Worse — LobbyCountdown
    Client-side node for lobby pad countdown display.

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LobbyCountdown shows a centered countdown timer and player count when the
    local player is on a portal pad in the multiplayer lobby.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onCountdownStarted({ padId, timeLeft })
        onCountdownTick({ padId, timeLeft, playerCount })
        onCountdownCancelled({ padId, reason })
        onPadStateChanged({ padId, state, playerCount })

    OUT: (none)

--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node
local PixelFont = Warren.PixelFont

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local PIXEL_SCALE = 5       -- Large countdown text
local PIXEL_SCALE_SMALL = 3 -- Player count text
local MAX_PLAYERS = 5

--------------------------------------------------------------------------------
-- LOBBYCOUNTDOWN NODE
--------------------------------------------------------------------------------

local LobbyCountdown = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                countdownText = nil,
                playerCountText = nil,
                activePadId = nil,
                isVisible = false,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state and state.screenGui then
            state.screenGui:Destroy()
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- UI MANAGEMENT
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
        local existing = playerGui:FindFirstChild("LobbyCountdown")
        if existing then
            existing:Destroy()
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "LobbyCountdown"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 1001  -- Above title screen
        screenGui.IgnoreGuiInset = true
        screenGui.Enabled = false
        screenGui.Parent = playerGui

        state.screenGui = screenGui
    end

    local function showCountdown(self, timeLeft, playerCount)
        local state = getState(self)
        if not state.screenGui then return end

        -- Clear old text frames
        if state.countdownText then
            state.countdownText:Destroy()
            state.countdownText = nil
        end
        if state.playerCountText then
            state.playerCountText:Destroy()
            state.playerCountText = nil
        end

        -- Create countdown text
        local countdownStr = "DEPARTING IN " .. tostring(timeLeft) .. "..."
        local countdownText = PixelFont.createText(countdownStr, {
            scale = PIXEL_SCALE,
            color = Color3.fromRGB(255, 255, 255),
        })
        countdownText.Name = "CountdownText"
        local countdownWidth = PixelFont.getTextWidth(countdownStr, PIXEL_SCALE, 0)
        local countdownHeight = countdownText.Size.Y.Offset
        countdownText.Position = UDim2.new(0.5, -countdownWidth / 2, 0.35, 0)
        countdownText.ZIndex = 2
        countdownText.Parent = state.screenGui
        state.countdownText = countdownText

        -- Create player count text
        local countStr = tostring(playerCount or 1) .. "/" .. tostring(MAX_PLAYERS) .. " PLAYERS"
        local playerCountText = PixelFont.createText(countStr, {
            scale = PIXEL_SCALE_SMALL,
            color = Color3.fromRGB(200, 200, 200),
        })
        playerCountText.Name = "PlayerCountText"
        local countWidth = PixelFont.getTextWidth(countStr, PIXEL_SCALE_SMALL, 0)
        playerCountText.Position = UDim2.new(0.5, -countWidth / 2, 0.35, countdownHeight + 16)
        playerCountText.ZIndex = 2
        playerCountText.Parent = state.screenGui
        state.playerCountText = playerCountText

        state.screenGui.Enabled = true
        state.isVisible = true
    end

    local function hideCountdown(self)
        local state = getState(self)
        if not state.screenGui then return end

        state.screenGui.Enabled = false
        state.isVisible = false
        state.activePadId = nil

        if state.countdownText then
            state.countdownText:Destroy()
            state.countdownText = nil
        end
        if state.playerCountText then
            state.playerCountText:Destroy()
            state.playerCountText = nil
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "LobbyCountdown",
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
            onCountdownStarted = function(self, data)
                if not data then return end
                local state = getState(self)
                state.activePadId = data.padId
                showCountdown(self, data.timeLeft, 1)
            end,

            onCountdownTick = function(self, data)
                if not data then return end
                local state = getState(self)
                if state.activePadId ~= data.padId then return end
                showCountdown(self, data.timeLeft, data.playerCount)
            end,

            onCountdownCancelled = function(self, data)
                if not data then return end
                local state = getState(self)
                if state.activePadId ~= data.padId then return end
                hideCountdown(self)
            end,

            onPadStateChanged = function(self, data)
                -- No-op: countdown visibility is driven by countdownCancelled/teleportFailed,
                -- not pad state. Touch detection causes brief idle flickers during walk
                -- animations that would flash the HUD.
            end,

            onTeleportFailed = function(self, data)
                if not data then return end
                local state = getState(self)
                if state.activePadId == data.padId then
                    hideCountdown(self)
                end
            end,
        },

        Out = {},
    }
end)

return LobbyCountdown
