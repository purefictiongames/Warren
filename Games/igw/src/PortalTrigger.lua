--[[
    IGW v2 — PortalTrigger (server)
    Zone-based portal room detection with countdown.

    Listens for portalRoomsReady from WorldMapOrchestrator. For each portal
    room, finds the RoomZone_{id} Part (created by ShellBuilder) and wires
    Touched/TouchEnded with a grace period.

    First occupant starts countdown. All occupants leave → cancelled.
    Countdown hits 0 → fires portalActivated.
--]]

return {
    name = "PortalTrigger",
    domain = "server",

    Sys = {
        onInit = function(self)
            self._connections = {}
            self._occupants = {}    -- [roomId] = { [player] = true }
            self._countdowns = {}   -- [roomId] = coroutine thread
            self._graceTimers = {}  -- [roomId][player] = timestamp
        end,
        onStart = function(self) end,
        onStop = function(self)
            self:_cleanup()
        end,
    },

    _cleanup = function(self)
        for _, conn in ipairs(self._connections) do
            conn:Disconnect()
        end
        self._connections = {}
        self._occupants = {}
        self._graceTimers = {}

        -- Cancel active countdowns
        for roomId, thread in pairs(self._countdowns) do
            task.cancel(thread)
        end
        self._countdowns = {}
    end,

    _getPlayerFromPart = function(self, hit)
        local Players = game:GetService("Players")
        local char = hit.Parent
        if not char then return nil end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid then return nil end
        return Players:GetPlayerFromCharacter(char)
    end,

    _startCountdown = function(self, roomId, targetBiome, seconds)
        -- Cancel existing countdown for this room
        if self._countdowns[roomId] then
            task.cancel(self._countdowns[roomId])
            self._countdowns[roomId] = nil
        end

        local selfRef = self
        self._countdowns[roomId] = task.spawn(function()
            selfRef.Out:Fire("portalCountdownStarted", {
                roomId = roomId,
                targetBiome = targetBiome,
                seconds = seconds,
            })

            for remaining = seconds, 1, -1 do
                selfRef.Out:Fire("portalCountdownTick", {
                    roomId = roomId,
                    targetBiome = targetBiome,
                    remaining = remaining,
                })
                task.wait(1.0)

                -- Check if still occupied
                local occ = selfRef._occupants[roomId]
                if not occ or not next(occ) then
                    selfRef.Out:Fire("portalCountdownCancelled", {
                        roomId = roomId,
                    })
                    selfRef._countdowns[roomId] = nil
                    return
                end
            end

            -- Countdown complete
            selfRef._countdowns[roomId] = nil
            selfRef.Out:Fire("portalActivated", {
                roomId = roomId,
                targetBiome = targetBiome,
            })
        end)
    end,

    _cancelCountdown = function(self, roomId)
        if self._countdowns[roomId] then
            task.cancel(self._countdowns[roomId])
            self._countdowns[roomId] = nil

            self.Out:Fire("portalCountdownCancelled", {
                roomId = roomId,
            })
        end
    end,

    In = {
        onPortalRoomsReady = function(self, data)
            -- Clean up old connections from previous region
            self:_cleanup()

            local portalRooms = data.portalRooms or {}
            local container = data.container
            local countdownSeconds = data.countdownSeconds or 5

            if not container then
                warn("[PortalTrigger] No container in portalRoomsReady")
                return
            end

            local GRACE_PERIOD = 0.5
            local selfRef = self

            for _, portal in ipairs(portalRooms) do
                local roomId = portal.roomId
                local targetBiome = portal.targetBiome
                local zoneName = "RoomZone_" .. roomId

                -- Find zone part in container (recursive search)
                local zonePart = container:FindFirstChild(zoneName, true)
                if not zonePart then
                    warn(string.format("[PortalTrigger] Zone %s not found", zoneName))
                    continue
                end

                self._occupants[roomId] = {}
                self._graceTimers[roomId] = {}

                -- Touched handler
                local touchConn = zonePart.Touched:Connect(function(hit)
                    local player = selfRef:_getPlayerFromPart(hit)
                    if not player then return end

                    -- Clear grace timer (player re-entered before grace expired)
                    if selfRef._graceTimers[roomId] then
                        selfRef._graceTimers[roomId][player] = nil
                    end

                    local occ = selfRef._occupants[roomId]
                    if not occ then return end

                    if not occ[player] then
                        occ[player] = true

                        -- First occupant starts countdown
                        local count = 0
                        for _ in pairs(occ) do count = count + 1 end
                        if count == 1 and not selfRef._countdowns[roomId] then
                            print(string.format("[PortalTrigger] Player entered portal room %d → %s",
                                roomId, targetBiome))
                            selfRef:_startCountdown(roomId, targetBiome, countdownSeconds)
                        end
                    end
                end)
                table.insert(self._connections, touchConn)

                -- TouchEnded handler with grace period
                local endConn = zonePart.TouchEnded:Connect(function(hit)
                    local player = selfRef:_getPlayerFromPart(hit)
                    if not player then return end

                    -- Start grace timer instead of immediate removal
                    if not selfRef._graceTimers[roomId] then return end

                    selfRef._graceTimers[roomId][player] = tick()

                    task.delay(GRACE_PERIOD, function()
                        local timer = selfRef._graceTimers[roomId]
                            and selfRef._graceTimers[roomId][player]
                        if not timer then return end

                        -- Grace period expired, player actually left
                        if tick() - timer >= GRACE_PERIOD - 0.05 then
                            selfRef._graceTimers[roomId][player] = nil

                            local occ = selfRef._occupants[roomId]
                            if occ then
                                occ[player] = nil

                                -- All left → cancel countdown
                                if not next(occ) then
                                    print(string.format("[PortalTrigger] Portal room %d empty — cancelling",
                                        roomId))
                                    selfRef:_cancelCountdown(roomId)
                                end
                            end
                        end
                    end)
                end)
                table.insert(self._connections, endConn)

                print(string.format("[PortalTrigger] Wired zone %s → %s", zoneName, targetBiome))
            end

            print(string.format("[PortalTrigger] Monitoring %d portal rooms", #portalRooms))
        end,
    },
}
