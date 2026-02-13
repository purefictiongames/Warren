--[[
    LibPureFiction Framework v2
    Hatcher.lua - Gacha/Egg Hatching Component

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Hatcher implements gacha/egg mechanics with weighted rarity selection,
    pity system, and currency cost requirements.

    The component is signal-driven with a fire-and-wait pattern for cost
    validation: it fires costCheck, waits for onCostConfirmed, then proceeds
    with the hatch if approved.

    Uses SpawnerCore internally for spawning the resulting item/entity.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ pool: table })
            - Sets the reward pool with weighted rarities
            - Pool format: { { template, rarity, weight, pity? }, ... }

        onHatch({ player?: Player })
            - Triggers a hatch attempt for the specified player
            - Fires costCheck and waits for onCostConfirmed

        onCostConfirmed({ player: Player, approved: boolean })
            - Response to costCheck signal
            - If approved=true, hatch proceeds; otherwise hatchFailed fires

        onSetPity({ player: Player, count: number })
            - Manually set pity counter for a player
            - Useful for loading saved pity progress

    OUT (emits):
        costCheck({ player: Player, cost: number, costType: string, hatcherId: string })
            - Fired before hatch to request cost validation
            - External system should respond with onCostConfirmed

        hatchStarted({ player: Player, hatchTime: number, hatcherId: string })
            - Fired when hatch begins (after cost confirmed)

        hatched({ player: Player, result: table, rarity: string, assetId: string,
                  pityTriggered: boolean, hatcherId: string })
            - Fired when hatch completes successfully
            - result contains the pool entry that was selected

        hatchFailed({ player: Player, reason: string, hatcherId: string })
            - Fired when hatch cannot proceed (cost denied, no pool, etc.)

    ============================================================================
    ATTRIBUTES
    ============================================================================

    HatchTime: number (default 0)
        Seconds to wait during hatch animation (0 = instant)

    Cost: number (default 0)
        Currency cost per hatch (0 = free)

    CostType: string (default "")
        Currency type identifier for cost validation

    PityThreshold: number (default 0)
        Guaranteed pity item after N hatches without one (0 = disabled)

    CostConfirmTimeout: number (default 10)
        Seconds to wait for onCostConfirmed before timing out

    SpawnParent: Instance (optional)
        Parent for spawned items (if not set, items spawn at Hatcher position)

    ============================================================================
    POOL FORMAT
    ============================================================================

    ```lua
    {
        { template = "CommonPet", rarity = "Common", weight = 60 },
        { template = "RarePet", rarity = "Rare", weight = 30 },
        { template = "LegendaryPet", rarity = "Legendary", weight = 10, pity = true },
    }
    ```

    - template: Name of template to spawn (resolved via SpawnerCore)
    - rarity: Display rarity string
    - weight: Relative probability weight
    - pity: If true, this item can be given by pity system

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    -- Register the component
    local Hatcher = Lib.Components.Hatcher
    System.Asset.register(Hatcher)

    -- Configure via wiring or direct call
    System.IPC.sendTo("EggHatcher_1", "configure", {
        pool = {
            { template = "CommonPet", rarity = "Common", weight = 60 },
            { template = "RarePet", rarity = "Rare", weight = 30 },
            { template = "LegendaryPet", rarity = "Legendary", weight = 10, pity = true },
        },
    })

    -- Trigger hatch
    System.IPC.sendTo("EggHatcher_1", "hatch", { player = player })

    -- Handle costCheck in Currency component, respond with costConfirmed
    ```

--]]

local Node = require(script.Parent.Parent.Node)
local SpawnerCore = require(script.Parent.Parent.Internal.SpawnerCore)

--------------------------------------------------------------------------------
-- HATCHER NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Hatcher = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                pool = nil,
                totalWeight = 0,
                pityCounters = {},
                pendingHatch = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Get a consistent player identifier for pity tracking.
    --]]
    local function getPlayerId(player)
        if not player then
            return "anonymous"
        end
        if typeof(player) == "Instance" and player:IsA("Player") then
            return tostring(player.UserId)
        end
        return tostring(player)
    end

    --[[
        Private: Get pity counter for a player.
    --]]
    local function getPityCount(self, player)
        local state = getState(self)
        local playerId = getPlayerId(player)
        return state.pityCounters[playerId] or 0
    end

    --[[
        Private: Increment pity counter for a player.
    --]]
    local function incrementPity(self, player)
        local state = getState(self)
        local playerId = getPlayerId(player)
        state.pityCounters[playerId] = (state.pityCounters[playerId] or 0) + 1
        return state.pityCounters[playerId]
    end

    --[[
        Private: Reset pity counter for a player.
    --]]
    local function resetPity(self, player)
        local state = getState(self)
        local playerId = getPlayerId(player)
        state.pityCounters[playerId] = 0
    end

    --[[
        Private: Select a random entry from the pool using weighted selection.
    --]]
    local function selectFromPool(self)
        local state = getState(self)
        if not state.pool or state.totalWeight <= 0 then
            return nil
        end

        local roll = math.random() * state.totalWeight
        local cumulative = 0

        for _, entry in ipairs(state.pool) do
            cumulative = cumulative + (entry.weight or 0)
            if roll <= cumulative then
                return entry
            end
        end

        return state.pool[#state.pool]
    end

    --[[
        Private: Get the pity item from the pool.
    --]]
    local function getPityItem(self)
        local state = getState(self)
        if not state.pool then
            return nil
        end

        for _, entry in ipairs(state.pool) do
            if entry.pity then
                return entry
            end
        end

        return nil
    end

    --[[
        Private: Check if pity should trigger for a player.
    --]]
    local function shouldTriggerPity(self, player)
        local threshold = self:getAttribute("PityThreshold") or 0
        if threshold <= 0 then
            return false
        end

        local count = getPityCount(self, player)
        return count >= threshold
    end

    --[[
        Private: Execute the hatch after cost validation.
    --]]
    local function executeHatch(self, player, fromPending)
        local state = getState(self)
        local hatchTime = self:getAttribute("HatchTime") or 0

        self.Out:Fire("hatchStarted", {
            player = player,
            hatchTime = hatchTime,
            hatcherId = self.id,
        })

        task.spawn(function()
            if hatchTime > 0 then
                task.wait(hatchTime)
            end

            local pityTriggered = false
            local result

            if shouldTriggerPity(self, player) then
                result = getPityItem(self)
                if result then
                    pityTriggered = true
                    resetPity(self, player)
                end
            end

            if not result then
                result = selectFromPool(self)
                incrementPity(self, player)
            end

            if not result then
                self.Out:Fire("hatchFailed", {
                    player = player,
                    reason = "selection_failed",
                    hatcherId = self.id,
                })
                return
            end

            local spawnParent = self:getAttribute("SpawnParent")
            local spawnPosition

            if self.model and self.model.PrimaryPart then
                spawnPosition = self.model.PrimaryPart.Position + Vector3.new(0, 3, 0)
            elseif self.model then
                local part = self.model:FindFirstChildWhichIsA("BasePart")
                if part then
                    spawnPosition = part.Position + Vector3.new(0, 3, 0)
                end
            end

            local spawnResult, spawnErr = SpawnerCore.spawn({
                templateName = result.template,
                parent = spawnParent or workspace,
                position = spawnPosition,
                attributes = {
                    Rarity = result.rarity,
                    HatchedBy = player and player.Name or "Unknown",
                },
                metadata = {
                    player = player,
                    poolEntry = result,
                },
            })

            if not spawnResult then
                self.Err:Fire({
                    reason = "spawn_failed",
                    message = spawnErr or "Unknown spawn error",
                    hatcherId = self.id,
                })
                self.Out:Fire("hatchFailed", {
                    player = player,
                    reason = "spawn_failed",
                    hatcherId = self.id,
                })
                return
            end

            self.Out:Fire("hatched", {
                player = player,
                result = result,
                rarity = result.rarity,
                template = result.template,
                assetId = spawnResult.assetId,
                instance = spawnResult.instance,
                pityTriggered = pityTriggered,
                hatcherId = self.id,
            })
        end)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "Hatcher",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                if not self:getAttribute("HatchTime") then
                    self:setAttribute("HatchTime", 0)
                end
                if not self:getAttribute("Cost") then
                    self:setAttribute("Cost", 0)
                end
                if not self:getAttribute("CostType") then
                    self:setAttribute("CostType", "")
                end
                if not self:getAttribute("PityThreshold") then
                    self:setAttribute("PityThreshold", 0)
                end
                if not self:getAttribute("CostConfirmTimeout") then
                    self:setAttribute("CostConfirmTimeout", 10)
                end

                if not SpawnerCore.isInitialized() then
                    SpawnerCore.init({})
                end
            end,

            onStart = function(self)
                -- Nothing to do on start - we wait for signals
            end,

            onStop = function(self)
                local state = getState(self)
                state.pendingHatch = nil
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            onConfigure = function(self, data)
                if not data or not data.pool or type(data.pool) ~= "table" then
                    self.Err:Fire({
                        reason = "invalid_pool",
                        message = "onConfigure requires { pool: table }",
                        hatcherId = self.id,
                    })
                    return
                end

                local state = getState(self)
                state.pool = data.pool

                state.totalWeight = 0
                for _, entry in ipairs(state.pool) do
                    state.totalWeight = state.totalWeight + (entry.weight or 0)
                end

                if state.totalWeight <= 0 then
                    self.Err:Fire({
                        reason = "invalid_pool",
                        message = "Pool has no valid weighted entries",
                        hatcherId = self.id,
                    })
                    state.pool = nil
                end
            end,

            onHatch = function(self, data)
                local state = getState(self)
                local player = data and data.player

                if not state.pool then
                    self.Out:Fire("hatchFailed", {
                        player = player,
                        reason = "no_pool",
                        hatcherId = self.id,
                    })
                    return
                end

                if state.pendingHatch then
                    self.Out:Fire("hatchFailed", {
                        player = player,
                        reason = "hatch_in_progress",
                        hatcherId = self.id,
                    })
                    return
                end

                local cost = self:getAttribute("Cost") or 0
                local costType = self:getAttribute("CostType") or ""

                if cost <= 0 then
                    executeHatch(self, player, false)
                    return
                end

                state.pendingHatch = {
                    player = player,
                    timestamp = os.clock(),
                }

                self.Out:Fire("costCheck", {
                    player = player,
                    cost = cost,
                    costType = costType,
                    hatcherId = self.id,
                })

                local timeout = self:getAttribute("CostConfirmTimeout") or 10
                local confirmed = self:waitForSignal("onCostConfirmed", timeout)

                local pendingPlayer = state.pendingHatch and state.pendingHatch.player
                state.pendingHatch = nil

                if not confirmed then
                    self.Out:Fire("hatchFailed", {
                        player = pendingPlayer,
                        reason = "cost_timeout",
                        hatcherId = self.id,
                    })
                end
            end,

            onCostConfirmed = function(self, data)
                if not data then
                    return
                end

                local state = getState(self)
                local approved = data.approved
                local player = data.player

                if not state.pendingHatch then
                    return
                end

                local pendingPlayer = state.pendingHatch.player
                if player and pendingPlayer and player ~= pendingPlayer then
                    return
                end

                local actualPlayer = player or pendingPlayer

                if approved then
                    executeHatch(self, actualPlayer, false)
                else
                    state.pendingHatch = nil
                    self.Out:Fire("hatchFailed", {
                        player = actualPlayer,
                        reason = "cost_denied",
                        hatcherId = self.id,
                    })
                end
            end,

            onSetPity = function(self, data)
                if not data or not data.player then
                    return
                end

                local state = getState(self)
                local playerId = getPlayerId(data.player)
                if playerId then
                    state.pityCounters[playerId] = data.count or 0
                end
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            costCheck = {},     -- { player, cost, costType, hatcherId }
            hatchStarted = {},  -- { player, hatchTime, hatcherId }
            hatched = {},       -- { player, result, rarity, assetId, pityTriggered, hatcherId }
            hatchFailed = {},   -- { player, reason, hatcherId }
        },

        -- Err (detour) signals documented in header
    }
end)

return Hatcher
