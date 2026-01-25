--[[
    LibPureFiction Framework v2
    Checkpoint.lua - Direction-Aware Threshold Detector

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Checkpoint detects when entities cross a threshold and reports which
    direction/face they crossed from. Unlike Zone (which tracks presence),
    Checkpoint fires once per crossing event.

    Always uses a box shape with 6 defined faces:
    - Front (+Z), Back (-Z)
    - Left (-X), Right (+X)
    - Top (+Y), Bottom (-Y)

    Key features:
    - Direction-aware: knows which face entity entered from
    - Single-fire: fires once per crossing, not continuous
    - Active face: define which face is the "entry" for path flow
    - Filter support: selective detection

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ activeFace?, filter?, cooldown? })
            - activeFace: "Front"|"Back"|"Left"|"Right"|"Top"|"Bottom" (default "Front")
            - filter: standard filter schema
            - cooldown: seconds before same entity can trigger again (default 0.5)

        onEnable()
            - Start detecting crossings

        onDisable()
            - Stop detecting crossings

    OUT (emits):
        crossed({ entity, entityId, face, isActiveFace, direction, position })
            - Fired when an entity crosses the checkpoint threshold
            - face: which face they crossed ("Front", "Back", etc.)
            - isActiveFace: true if they crossed the configured active face
            - direction: Vector3 of entity's movement direction
            - position: Vector3 where crossing occurred

        entityInside({ entity, entityId })
            - Fired when entity is detected inside (optional tracking)

        entityLeft({ entity, entityId })
            - Fired when entity leaves the checkpoint zone

    ============================================================================
    ATTRIBUTES
    ============================================================================

    ActiveFace: string (default "Front")
        The face that represents the "correct" entry direction for path flow

    Cooldown: number (default 0.5)
        Seconds before same entity can trigger crossing again

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local checkpoint = Checkpoint:new({
        id = "Checkpoint_1",
        model = workspace.CheckpointPart,  -- Must be a Part (box)
    })
    checkpoint.Sys.onInit(checkpoint)

    checkpoint.In.onConfigure(checkpoint, {
        activeFace = "Front",  -- Entities should enter from front
        cooldown = 0.5,
    })

    -- Wire to track controller
    checkpoint.Out.crossed -> trackController.In.onHandoff

    checkpoint.In.onEnable(checkpoint)
    ```

--]]

local RunService = game:GetService("RunService")
local Node = require(script.Parent.Parent.Node)
local EntityUtils = require(script.Parent.Parent.Internal.EntityUtils)

-- Face definitions (normal vectors in local space) - FILE SCOPE CONSTANTS
local FACES = {
    Front = Vector3.new(0, 0, 1),   -- +Z
    Back = Vector3.new(0, 0, -1),   -- -Z
    Right = Vector3.new(1, 0, 0),   -- +X
    Left = Vector3.new(-1, 0, 0),   -- -X
    Top = Vector3.new(0, 1, 0),     -- +Y
    Bottom = Vector3.new(0, -1, 0), -- -Y
}

local FACE_NAMES = { "Front", "Back", "Right", "Left", "Top", "Bottom" }

--------------------------------------------------------------------------------
-- CHECKPOINT NODE (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local Checkpoint = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    -- Nothing here exists on the node instance.
    ----------------------------------------------------------------------------

    -- Per-instance state registry (keyed by instance.id)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                enabled = false,
                updateConnection = nil,
                entitiesInside = {},       -- { [entity] = { enterTime, lastPosition, triggered } }
                cooldowns = {},            -- { [entity] = timestamp } for cooldown tracking
                activeFace = "Front",
                cooldown = 0.5,
                filter = nil,
                part = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Private: Determine which face an entity entered from based on their position
        relative to the checkpoint center.
    --]]
    local function determineEntryFace(self, entity, entityPos)
        local state = getState(self)
        local partCFrame = state.part.CFrame
        local partSize = state.part.Size

        -- Convert entity position to local space
        local localPos = partCFrame:PointToObjectSpace(entityPos)

        -- Normalize by part size to get relative position (-1 to 1 range)
        local normalizedPos = Vector3.new(
            localPos.X / (partSize.X / 2),
            localPos.Y / (partSize.Y / 2),
            localPos.Z / (partSize.Z / 2)
        )

        -- Find which face they're closest to (highest absolute value in that axis)
        local absX = math.abs(normalizedPos.X)
        local absY = math.abs(normalizedPos.Y)
        local absZ = math.abs(normalizedPos.Z)

        local face = "Front"
        local direction = Vector3.new(0, 0, 0)

        if absX >= absY and absX >= absZ then
            -- X axis dominant
            if normalizedPos.X > 0 then
                face = "Right"
                direction = partCFrame.RightVector
            else
                face = "Left"
                direction = -partCFrame.RightVector
            end
        elseif absY >= absX and absY >= absZ then
            -- Y axis dominant
            if normalizedPos.Y > 0 then
                face = "Top"
                direction = partCFrame.UpVector
            else
                face = "Bottom"
                direction = -partCFrame.UpVector
            end
        else
            -- Z axis dominant
            if normalizedPos.Z > 0 then
                face = "Front"
                direction = partCFrame.LookVector
            else
                face = "Back"
                direction = -partCFrame.LookVector
            end
        end

        return face, direction
    end

    --[[
        Private: Handle an entity entering the checkpoint.
        Determines which face they entered from and fires crossed signal.
    --]]
    local function handleEntityEntry(self, entity, entityPos)
        local state = getState(self)

        -- Check cooldown
        local now = os.clock()
        if state.cooldowns[entity] and (now - state.cooldowns[entity]) < state.cooldown then
            return  -- Still in cooldown
        end

        -- Determine which face the entity entered from
        local face, direction = determineEntryFace(self, entity, entityPos)

        -- Update cooldown
        state.cooldowns[entity] = now

        -- Mark as triggered
        state.entitiesInside[entity].triggered = true

        -- Fire crossed signal
        self.Out:Fire("crossed", {
            entity = entity,
            entityId = EntityUtils.getId(entity),
            face = face,
            isActiveFace = (face == state.activeFace),
            direction = direction,
            position = entityPos,
        })
    end

    --[[
        Private: Update detection loop - check for entities inside the checkpoint.
    --]]
    local function updateDetection(self)
        local state = getState(self)
        if not state.enabled or not state.part then return end

        local currentEntities = {}
        local partCFrame = state.part.CFrame
        local partSize = state.part.Size

        -- Find entities inside the checkpoint box
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = { state.part }

        local parts = workspace:GetPartBoundsInBox(partCFrame, partSize, overlapParams)

        for _, part in ipairs(parts) do
            local entity = EntityUtils.getEntityFromPart(part)

            if entity and not currentEntities[entity] then
                currentEntities[entity] = true

                -- Check filter
                if not EntityUtils.passesFilter(entity, state.filter) then
                    continue
                end

                local entityPos = EntityUtils.getPosition(entity)

                if not state.entitiesInside[entity] then
                    -- New entity entering
                    state.entitiesInside[entity] = {
                        enterTime = os.clock(),
                        lastPosition = entityPos,
                        triggered = false,
                    }

                    -- Determine entry face and fire crossed
                    handleEntityEntry(self, entity, entityPos)

                    self.Out:Fire("entityInside", {
                        entity = entity,
                        entityId = EntityUtils.getId(entity),
                    })
                else
                    -- Update position for direction tracking
                    state.entitiesInside[entity].lastPosition = entityPos
                end
            end
        end

        -- Check for entities that left
        for entity, data in pairs(state.entitiesInside) do
            if not currentEntities[entity] then
                state.entitiesInside[entity] = nil

                self.Out:Fire("entityLeft", {
                    entity = entity,
                    entityId = EntityUtils.getId(entity),
                })
            end
        end
    end

    --[[
        Private: Start the detection loop.
    --]]
    local function startDetectionLoop(self)
        local state = getState(self)
        state.updateConnection = RunService.Heartbeat:Connect(function(dt)
            updateDetection(self)
        end)
    end

    --[[
        Private: Enable detection.
    --]]
    local function enable(self)
        local state = getState(self)
        if state.enabled then return end

        if not state.part then
            self.Err:Fire({
                reason = "no_part",
                message = "Checkpoint requires a BasePart for detection",
            })
            return
        end

        state.enabled = true
        startDetectionLoop(self)
    end

    --[[
        Private: Disable detection.
    --]]
    local function disable(self)
        local state = getState(self)
        if not state.enabled then return end

        state.enabled = false

        if state.updateConnection then
            state.updateConnection:Disconnect()
            state.updateConnection = nil
        end

        -- Fire entityLeft for any remaining entities
        for entity in pairs(state.entitiesInside) do
            self.Out:Fire("entityLeft", {
                entity = entity,
                entityId = EntityUtils.getId(entity),
            })
        end

        state.entitiesInside = {}
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    -- Only this table exists on the node.
    ----------------------------------------------------------------------------

    return {
        name = "Checkpoint",
        domain = "server",

        ------------------------------------------------------------------------
        -- SYSTEM HANDLERS
        ------------------------------------------------------------------------

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Get the detection part from model
                if self.model then
                    if self.model:IsA("BasePart") then
                        state.part = self.model
                    elseif self.model:IsA("Model") then
                        state.part = self.model.PrimaryPart or self.model:FindFirstChildWhichIsA("BasePart")
                    end
                end

                -- Default attributes
                if not self:getAttribute("ActiveFace") then
                    self:setAttribute("ActiveFace", "Front")
                end
                if not self:getAttribute("Cooldown") then
                    self:setAttribute("Cooldown", 0.5)
                end
            end,

            onStart = function(self)
                -- Nothing to do - wait for onEnable
            end,

            onStop = function(self)
                disable(self)
                cleanupState(self)  -- CRITICAL: prevents memory leak
            end,
        },

        ------------------------------------------------------------------------
        -- INPUT HANDLERS
        ------------------------------------------------------------------------

        In = {
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)

                if data.activeFace and FACES[data.activeFace] then
                    state.activeFace = data.activeFace
                    self:setAttribute("ActiveFace", data.activeFace)
                end

                if data.cooldown then
                    state.cooldown = data.cooldown
                    self:setAttribute("Cooldown", data.cooldown)
                end

                if data.filter then
                    state.filter = data.filter
                end

                -- Allow setting the part directly
                if data.part and data.part:IsA("BasePart") then
                    state.part = data.part
                end
            end,

            onEnable = function(self)
                enable(self)
            end,

            onDisable = function(self)
                disable(self)
            end,
        },

        ------------------------------------------------------------------------
        -- OUTPUT SIGNALS
        ------------------------------------------------------------------------

        Out = {
            crossed = {},       -- { entity, entityId, face, isActiveFace, direction, position }
            entityInside = {},  -- { entity, entityId }
            entityLeft = {},    -- { entity, entityId }
        },
    }
end)

return Checkpoint
