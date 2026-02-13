--[[
    It Gets Worse — LobbyManager
    Server-side node for multiplayer lobby pad management.

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LobbyManager handles portal pad detection, occupant tracking, countdowns,
    and teleportation for the multiplayer lobby. Each of the 10 portal pads
    supports up to 5 players. When the first player steps on a pad, a 10-second
    countdown starts and ReserveServer is called immediately. At countdown end,
    all pad occupants teleport to the reserved private server.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onPadsReady({ pads })
            - From RegionManager after lobby geometry is built
            - pads: array of { id, part } for each portal pad

        onUnloadLobby()
            - Cleanup all connections and countdowns

    OUT (sends):
        countdownStarted({ padId, timeLeft })
        countdownTick({ padId, timeLeft, playerCount })
        countdownCancelled({ padId, reason })
        padStateChanged({ padId, state, playerCount })
        teleportFailed({ padId, reason })

--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node
local PlaceGraph = require(script.Parent.PlaceGraph)

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local MAX_PLAYERS_PER_PAD = 5
local COUNTDOWN_SECONDS = 10
local TOUCH_GRACE_PERIOD = 0.5  -- Seconds to wait before removing player (debounce walk animations)

--------------------------------------------------------------------------------
-- LOBBYMANAGER NODE
--------------------------------------------------------------------------------

local LobbyManager = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                pads = {},              -- [padId] = { id, part }
                padOccupants = {},      -- [padId] = { player1, player2, ... }
                padTouchCounts = {},    -- [padId] = { [player] = count } (per-body-part touch tracking)
                padGraceTimers = {},    -- [padId] = { [player] = thread } (debounce removal)
                padCountdowns = {},     -- [padId] = { timeLeft, reservedCode, thread }
                padConnections = {},    -- [padId] = { touchedConn, touchEndedConn }
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            -- Cancel all countdowns
            for padId, countdown in pairs(state.padCountdowns) do
                if countdown.thread then
                    task.cancel(countdown.thread)
                end
            end
            -- Cancel all grace timers
            for padId, timers in pairs(state.padGraceTimers) do
                for player, thread in pairs(timers) do
                    task.cancel(thread)
                end
            end
            -- Disconnect all touch connections
            for padId, conns in pairs(state.padConnections) do
                if conns.touchedConn then conns.touchedConn:Disconnect() end
                if conns.touchEndedConn then conns.touchEndedConn:Disconnect() end
            end
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- PAD HELPERS
    ----------------------------------------------------------------------------

    local function getPlayerFromCharacter(character)
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character == character then
                return player
            end
        end
        return nil
    end

    local function isPlayerOnPad(state, padId, player)
        local occupants = state.padOccupants[padId]
        if not occupants then return false end
        for _, p in ipairs(occupants) do
            if p == player then return true end
        end
        return false
    end

    local function removePlayerFromPad(state, padId, player)
        local occupants = state.padOccupants[padId]
        if not occupants then return end
        for i, p in ipairs(occupants) do
            if p == player then
                table.remove(occupants, i)
                return
            end
        end
    end

    ----------------------------------------------------------------------------
    -- CROSS-DOMAIN SIGNAL HELPER
    ----------------------------------------------------------------------------

    -- Fire a signal to each player on a pad (for server→client cross-domain routing)
    local function fireToOccupants(self, state, padId, signalName, data)
        local occupants = state.padOccupants[padId] or {}
        for _, player in ipairs(occupants) do
            local signalData = {}
            for k, v in pairs(data) do
                signalData[k] = v
            end
            signalData._targetPlayer = player
            self.Out:Fire(signalName, signalData)
        end
        -- Also fire without target for any server-side listeners
        if #occupants == 0 then
            self.Out:Fire(signalName, data)
        end
    end

    ----------------------------------------------------------------------------
    -- COUNTDOWN LOGIC
    ----------------------------------------------------------------------------

    local function startCountdown(self, padId)
        local state = getState(self)
        local System = self._System
        local placeId = PlaceGraph.getPlace("gameplay").placeId

        -- Already counting down?
        if state.padCountdowns[padId] then return end

        local countdown = {
            timeLeft = COUNTDOWN_SECONDS,
            reservedCode = nil,
            thread = nil,
        }
        state.padCountdowns[padId] = countdown

        -- Fire countdown started to all occupants
        fireToOccupants(self, state, padId, "countdownStarted", {
            padId = padId,
            timeLeft = COUNTDOWN_SECONDS,
        })

        fireToOccupants(self, state, padId, "padStateChanged", {
            padId = padId,
            state = "active",
            playerCount = #(state.padOccupants[padId] or {}),
        })

        -- Reserve server (skip in Studio where TeleportService is unavailable)
        if RunService:IsStudio() then
            if System and System.Debug then
                System.Debug.warn("LobbyManager", "Studio mode — skipping ReserveServer for pad", padId)
            end
        else
            task.spawn(function()
                local success, code = pcall(function()
                    return TeleportService:ReserveServer(placeId)
                end)

                if not success or not code then
                    -- ReserveServer failed — cancel countdown
                    if System and System.Debug then
                        System.Debug.warn("LobbyManager", "ReserveServer failed for pad", padId, ":", code)
                    end
                    fireToOccupants(self, state, padId, "countdownCancelled", { padId = padId, reason = "reserve_failed" })
                    fireToOccupants(self, state, padId, "padStateChanged", {
                        padId = padId,
                        state = "idle",
                        playerCount = #(state.padOccupants[padId] or {}),
                    })
                    -- Cancel the countdown thread
                    if countdown.thread then
                        task.cancel(countdown.thread)
                    end
                    state.padCountdowns[padId] = nil
                    return
                end

                countdown.reservedCode = code
                if System and System.Debug then
                    System.Debug.info("LobbyManager", "Reserved server for pad", padId)
                end
            end)
        end

        -- Countdown tick loop
        countdown.thread = task.spawn(function()
            while countdown.timeLeft > 0 do
                task.wait(1)
                countdown.timeLeft = countdown.timeLeft - 1

                local occupants = state.padOccupants[padId] or {}

                -- If all players left, cancel
                if #occupants == 0 then
                    -- No occupants, so just fire directly (no targets)
                    self.Out:Fire("countdownCancelled", { padId = padId, reason = "empty" })
                    self.Out:Fire("padStateChanged", {
                        padId = padId,
                        state = "idle",
                        playerCount = 0,
                    })
                    state.padCountdowns[padId] = nil
                    return
                end

                -- Fire tick to all occupants
                fireToOccupants(self, state, padId, "countdownTick", {
                    padId = padId,
                    timeLeft = countdown.timeLeft,
                    playerCount = #occupants,
                })
            end

            -- Countdown reached 0 — teleport
            local occupants = state.padOccupants[padId] or {}
            if #occupants == 0 then
                state.padCountdowns[padId] = nil
                return
            end

            if not countdown.reservedCode then
                -- ReserveServer hasn't completed yet or failed
                fireToOccupants(self, state, padId, "countdownCancelled", { padId = padId, reason = "no_code" })
                fireToOccupants(self, state, padId, "padStateChanged", {
                    padId = padId,
                    state = "idle",
                    playerCount = #occupants,
                })
                state.padCountdowns[padId] = nil
                return
            end

            -- Attempt teleport
            local teleportSuccess, teleportErr = pcall(function()
                TeleportService:TeleportToPrivateServer(placeId, countdown.reservedCode, occupants)
            end)

            if not teleportSuccess then
                if System and System.Debug then
                    System.Debug.warn("LobbyManager", "Teleport failed for pad", padId, ":", teleportErr)
                end
                fireToOccupants(self, state, padId, "teleportFailed", { padId = padId, reason = tostring(teleportErr) })
                fireToOccupants(self, state, padId, "padStateChanged", {
                    padId = padId,
                    state = "idle",
                    playerCount = #occupants,
                })
            else
                if System and System.Debug then
                    System.Debug.info("LobbyManager", "Teleported", #occupants, "players from pad", padId)
                end
            end

            -- Reset pad state
            state.padOccupants[padId] = {}
            state.padCountdowns[padId] = nil
            self.Out:Fire("padStateChanged", {
                padId = padId,
                state = "idle",
                playerCount = 0,
            })
        end)
    end

    ----------------------------------------------------------------------------
    -- PAD WIRING
    ----------------------------------------------------------------------------

    local function wirePad(self, padId, padPart)
        local state = getState(self)
        state.padOccupants[padId] = {}
        state.padTouchCounts[padId] = {}
        state.padGraceTimers[padId] = {}

        -- Track per-body-part touch counts to avoid false exits from walk animations.
        -- A player is only "on" when count > 0, and only "off" when count drops to 0.
        -- Grace period prevents brief animation gaps from removing the player.
        local touchCounts = state.padTouchCounts[padId]
        local graceTimers = state.padGraceTimers[padId]

        local touchedConn = padPart.Touched:Connect(function(hit)
            local character = hit.Parent
            if not character then return end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not humanoid then return end

            local player = getPlayerFromCharacter(character)
            if not player then return end

            -- Increment touch count for this player
            touchCounts[player] = (touchCounts[player] or 0) + 1

            -- Cancel any pending grace removal (player re-touched before grace expired)
            if graceTimers[player] then
                task.cancel(graceTimers[player])
                graceTimers[player] = nil
            end

            -- Already tracked as occupant?
            if isPlayerOnPad(state, padId, player) then return end

            -- Check capacity
            local occupants = state.padOccupants[padId]
            if #occupants >= MAX_PLAYERS_PER_PAD then return end

            -- Add player (first body part contact)
            table.insert(occupants, player)

            local System = self._System
            if System and System.Debug then
                System.Debug.info("LobbyManager", player.Name, "stepped on pad", padId, "(" .. #occupants .. "/" .. MAX_PLAYERS_PER_PAD .. ")")
            end

            -- Fire state change to all occupants on this pad
            local padState = #occupants >= MAX_PLAYERS_PER_PAD and "full" or "active"
            fireToOccupants(self, state, padId, "padStateChanged", {
                padId = padId,
                state = padState,
                playerCount = #occupants,
            })

            -- Start countdown if first player
            if #occupants == 1 then
                startCountdown(self, padId)
            end
        end)

        local touchEndedConn = padPart.TouchEnded:Connect(function(hit)
            local character = hit.Parent
            if not character then return end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not humanoid then return end

            local player = getPlayerFromCharacter(character)
            if not player then return end

            if not isPlayerOnPad(state, padId, player) then return end

            -- Decrement touch count; only start grace when ALL body parts have left
            touchCounts[player] = (touchCounts[player] or 1) - 1
            if touchCounts[player] > 0 then return end

            -- All body parts off the pad — start grace period before removing.
            -- Walk animations cause brief contact loss; grace prevents false exits.
            if graceTimers[player] then return end  -- Already pending
            graceTimers[player] = task.delay(TOUCH_GRACE_PERIOD, function()
                graceTimers[player] = nil

                -- Re-check: player may have re-touched during grace period
                if (touchCounts[player] or 0) > 0 then return end
                if not isPlayerOnPad(state, padId, player) then return end

                -- Grace expired with no re-touch — player has truly left
                touchCounts[player] = nil
                removePlayerFromPad(state, padId, player)
                local occupants = state.padOccupants[padId]

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("LobbyManager", player.Name, "left pad", padId, "(" .. #occupants .. "/" .. MAX_PLAYERS_PER_PAD .. ")")
                end

                fireToOccupants(self, state, padId, "padStateChanged", {
                    padId = padId,
                    state = #occupants > 0 and "active" or "idle",
                    playerCount = #occupants,
                })
            end)
        end)

        state.padConnections[padId] = {
            touchedConn = touchedConn,
            touchEndedConn = touchEndedConn,
        }
    end

    -- Handle player leaving the game during countdown
    local function onPlayerRemoving(self, player)
        local state = getState(self)
        for padId, occupants in pairs(state.padOccupants) do
            -- Clean up touch counts and grace timers
            if state.padTouchCounts[padId] then
                state.padTouchCounts[padId][player] = nil
            end
            if state.padGraceTimers[padId] and state.padGraceTimers[padId][player] then
                task.cancel(state.padGraceTimers[padId][player])
                state.padGraceTimers[padId][player] = nil
            end
            for i, p in ipairs(occupants) do
                if p == player then
                    table.remove(occupants, i)
                    fireToOccupants(self, state, padId, "padStateChanged", {
                        padId = padId,
                        state = #occupants > 0 and "active" or "idle",
                        playerCount = #occupants,
                    })
                    break
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "LobbyManager",
        domain = "server",

        Sys = {
            onInit = function(self) end,

            onStart = function(self)
                -- Clean up occupant tracking when players leave
                Players.PlayerRemoving:Connect(function(player)
                    onPlayerRemoving(self, player)
                end)
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            -- RegionManager signals that lobby pads are ready
            onPadsReady = function(self, data)
                if not data or not data.pads then return end

                local state = getState(self)
                for _, padInfo in ipairs(data.pads) do
                    state.pads[padInfo.id] = padInfo
                    wirePad(self, padInfo.id, padInfo.part)
                end

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("LobbyManager", "Wired", #data.pads, "portal pads")
                end
            end,

            -- RegionManager signals lobby is being unloaded
            onUnloadLobby = function(self)
                cleanupState(self)
            end,
        },

        Out = {
            countdownStarted = {},
            countdownTick = {},
            countdownCancelled = {},
            padStateChanged = {},
            teleportFailed = {},
        },
    }
end)

return LobbyManager
