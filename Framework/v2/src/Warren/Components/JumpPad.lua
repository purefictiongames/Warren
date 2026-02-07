--[[
    Warren Framework v2
    JumpPad.lua - Teleport Pad Component

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    JumpPad extends Zone to create a teleportation trigger. It detects when
    players enter/exit and manages a state machine to prevent bounce-back.

    State Machine:
    - spawnIn: Player just arrived. Won't fire jump signal.
    - spawnOut: Ready to fire. Player stepping on triggers jump.

    Flow:
    1. Pad starts in spawnIn mode
    2. Player teleports to pad (lands on it)
    3. Player walks off -> onEntityExit called
    4. After 1.5s delay, switches to spawnOut
    5. Player walks on -> onEntityEnter called -> emits jumpRequested
    6. External node (RegionManager) handles teleport, sets destination to spawnIn

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ ... }) - Inherited from Zone
        onEnable() - Inherited from Zone
        onDisable() - Inherited from Zone
        onSetMode({ mode: "spawnIn" | "spawnOut" })
            - Explicitly set the pad mode (used after teleporting player here)
        onJumpComplete({ player })
            - Called after player has been teleported here

    OUT (emits):
        entityEntered - Inherited from Zone (only fired for non-players)
        entityExited - Inherited from Zone (only fired for non-players)
        jumpRequested({ player, padId, regionId, position })
            - Fired when player triggers a jump (mode was spawnOut)

--]]

local Players = game:GetService("Players")
local Zone = require(script.Parent.Zone)

--------------------------------------------------------------------------------
-- JUMPPAD NODE (Extends Zone)
--------------------------------------------------------------------------------

local JumpPad = Zone.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Per-player state tracking
                playerModes = {},      -- { [Player] = "spawnIn" | "spawnOut" }
                playerTimers = {},     -- { [Player] = thread }
                -- Pad geometry
                padPart = nil,         -- The physical pad part
                ownsModel = false,     -- Whether we created the model ourselves
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            -- Cancel all pending timers
            for _, timer in pairs(state.playerTimers) do
                task.cancel(timer)
            end
            -- Destroy pad if we created it
            if state.ownsModel and state.padPart then
                state.padPart:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    --[[
        Get a player's mode on this pad.
        New players default to "spawnOut" (can trigger jump).
    --]]
    local function getPlayerMode(self, player)
        local state = getState(self)
        return state.playerModes[player] or "spawnOut"
    end

    --[[
        Set a player's mode on this pad.
    --]]
    local function setPlayerMode(self, player, mode)
        local state = getState(self)
        state.playerModes[player] = mode

        -- Cancel any pending timer for this player when mode changes
        if state.playerTimers[player] then
            task.cancel(state.playerTimers[player])
            state.playerTimers[player] = nil
        end
    end

    ----------------------------------------------------------------------------
    -- GEOMETRY CREATION
    ----------------------------------------------------------------------------

    local function createDefaultPad(self)
        local state = getState(self)

        local pad = Instance.new("Part")
        pad.Name = self.id or "JumpPad"
        pad.Size = Vector3.new(6, 1, 6)
        pad.Anchored = true
        pad.CanCollide = true
        pad.Material = Enum.Material.Neon
        pad.Color = Color3.fromRGB(180, 50, 255)  -- Purple
        pad.TopSurface = Enum.SurfaceType.Smooth
        pad.BottomSurface = Enum.SurfaceType.Smooth

        -- Position from attributes or default
        local posX = self:getAttribute("PositionX") or 0
        local posY = self:getAttribute("PositionY") or 5
        local posZ = self:getAttribute("PositionZ") or 0
        pad.Position = Vector3.new(posX, posY, posZ)

        -- Parent to workspace or specified container
        local container = self:getAttribute("Container")
        if container and typeof(container) == "Instance" then
            pad.Parent = container
        else
            pad.Parent = workspace
        end

        state.padPart = pad
        state.ownsModel = true

        -- Set as our model for Zone to use
        self.model = pad

        return pad
    end

    ----------------------------------------------------------------------------
    -- MODE MANAGEMENT (Per-Player)
    ----------------------------------------------------------------------------

    --[[
        Check if a specific player is physically on the pad using bounds check.
        This is more reliable than collision events which can fire spuriously.
    --]]
    local function isPlayerOnPad(self, player)
        local state = getState(self)
        local padPart = state.padPart
        if not padPart then return false end

        local character = player.Character
        if not character then return false end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end

        local padPos = padPart.Position
        local padSize = padPart.Size
        local hrpPos = hrp.Position

        -- Check horizontal distance from pad center
        local dx = math.abs(hrpPos.X - padPos.X)
        local dz = math.abs(hrpPos.Z - padPos.Z)
        -- Check vertical: player should be above pad surface
        local dy = hrpPos.Y - padPos.Y

        -- Within horizontal bounds (with margin) and standing on/near pad
        return dx <= padSize.X / 2 + 3 and dz <= padSize.Z / 2 + 3 and dy >= -1 and dy <= 8
    end

    local function scheduleSpawnOutSwitchForPlayer(self, player)
        local state = getState(self)

        -- Cancel existing timer for this player if any
        if state.playerTimers[player] then
            task.cancel(state.playerTimers[player])
        end

        -- Schedule switch to spawnOut after 1.5s for this specific player
        state.playerTimers[player] = task.delay(1.5, function()
            state.playerTimers[player] = nil

            -- Only switch if player is still in spawnIn mode
            if getPlayerMode(self, player) == "spawnIn" then
                -- Verify this specific player is actually off the pad
                if not isPlayerOnPad(self, player) then
                    state.playerModes[player] = "spawnOut"
                else
                    -- Player still on pad - reschedule check
                    scheduleSpawnOutSwitchForPlayer(self, player)
                end
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "JumpPad",
        domain = "server",

        Sys = {
            onInit = function(self)
                -- Initialize our state
                local state = getState(self)

                -- Create default pad geometry if no model provided
                if not self.model then
                    createDefaultPad(self)
                else
                    state.padPart = self.model:IsA("BasePart") and self.model or self.model:FindFirstChildWhichIsA("BasePart")
                end

                -- Call parent init (Zone will use self.model for detection)
                parent.Sys.onInit(self)
            end,

            onStart = function(self)
                parent.Sys.onStart(self)
            end,

            onStop = function(self)
                parent.Sys.onStop(self)
                cleanupState(self)
            end,
        },

        ------------------------------------------------------------------------
        -- ZONE HOOKS (Override Zone's default behavior)
        ------------------------------------------------------------------------

        --[[
            Called when an entity enters the zone.
            For players: implements per-player state machine logic.
            For non-players: fires entityEntered signal (default Zone behavior).
        --]]
        onEntityEnter = function(self, data)
            local state = getState(self)

            -- Check if this is a player
            local player = Players:GetPlayerFromCharacter(data.entity)
            if not player then
                -- Not a player - use default Zone behavior
                self.Out:Fire("entityEntered", data)
                return
            end

            -- Cancel any pending exit timer for this player (they came back)
            if state.playerTimers[player] then
                task.cancel(state.playerTimers[player])
                state.playerTimers[player] = nil
            end

            -- Only fire jump if this player is in spawnOut mode
            local playerMode = getPlayerMode(self, player)
            if playerMode == "spawnOut" then
                -- Switch to spawnIn immediately to prevent double-triggers
                setPlayerMode(self, player, "spawnIn")

                -- Get pad position from our stored part
                local position = state.padPart and state.padPart.Position or nil

                -- Emit jump request via IPC
                self.Out:Fire("jumpRequested", {
                    player = player,
                    padId = self:getAttribute("PadId") or self.id,
                    regionId = self:getAttribute("RegionId"),
                    position = position,
                })
            end
        end,

        --[[
            Called when an entity exits the zone.
            For players: schedules per-player mode switch after delay.
            For non-players: fires entityExited signal (default Zone behavior).
        --]]
        onEntityExit = function(self, data)
            -- Check if this is a player
            local player = Players:GetPlayerFromCharacter(data.entity)
            if not player then
                -- Not a player - use default Zone behavior
                self.Out:Fire("entityExited", data)
                return
            end

            -- Only schedule switch if this player is in spawnIn mode
            local playerMode = getPlayerMode(self, player)
            if playerMode == "spawnIn" then
                scheduleSpawnOutSwitchForPlayer(self, player)
            end
        end,

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            -- Inherit Zone's input handlers
            onConfigure = parent.In.onConfigure,
            onEnable = parent.In.onEnable,
            onDisable = parent.In.onDisable,

            -- Set pad mode for a specific player (called after teleporting player here)
            onSetMode = function(self, data)
                if data and data.player and data.mode then
                    setPlayerMode(self, data.player, data.mode)
                end
            end,

            -- Called after player teleported here
            onJumpComplete = function(self, data)
                if data and data.player then
                    -- Ensure this player is in spawnIn mode
                    setPlayerMode(self, data.player, "spawnIn")
                end
            end,
        },

        Out = {
            -- Inherited from Zone
            entityEntered = {},
            entityExited = {},
            -- JumpPad-specific
            jumpRequested = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC METHODS
        ------------------------------------------------------------------------

        --[[
            Get a player's mode on this pad.
            @param player Player - The player to check
            @return string - "spawnIn" or "spawnOut"
        --]]
        getModeForPlayer = function(self, player)
            return getPlayerMode(self, player)
        end,

        --[[
            Set a player's mode on this pad.
            @param player Player - The player to set mode for
            @param mode string - "spawnIn" or "spawnOut"
        --]]
        setModeForPlayer = function(self, player, mode)
            setPlayerMode(self, player, mode)
        end,

        getPart = function(self)
            return getState(self).padPart
        end,

        getPosition = function(self)
            local part = getState(self).padPart
            return part and part.Position or nil
        end,

        setPosition = function(self, position)
            local part = getState(self).padPart
            if part then
                if typeof(position) == "Vector3" then
                    part.Position = position
                elseif type(position) == "table" then
                    part.Position = Vector3.new(position[1], position[2], position[3])
                end
            end
        end,

        setColor = function(self, color)
            local part = getState(self).padPart
            if part then
                if typeof(color) == "Color3" then
                    part.Color = color
                elseif type(color) == "table" then
                    part.Color = Color3.fromRGB(color[1], color[2], color[3])
                end
            end
        end,

        setParent = function(self, newParent)
            local part = getState(self).padPart
            if part then
                part.Parent = newParent
            end
        end,
    }
end)

return JumpPad
