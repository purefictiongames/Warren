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

-- Face definitions (normal vectors in local space)
local FACES = {
    Front = Vector3.new(0, 0, 1),   -- +Z
    Back = Vector3.new(0, 0, -1),   -- -Z
    Right = Vector3.new(1, 0, 0),   -- +X
    Left = Vector3.new(-1, 0, 0),   -- -X
    Top = Vector3.new(0, 1, 0),     -- +Y
    Bottom = Vector3.new(0, -1, 0), -- -Y
}

local FACE_NAMES = { "Front", "Back", "Right", "Left", "Top", "Bottom" }

local Checkpoint = Node.extend({
    name = "Checkpoint",
    domain = "server",

    ----------------------------------------------------------------------------
    -- LIFECYCLE
    ----------------------------------------------------------------------------

    Sys = {
        onInit = function(self)
            -- Detection state
            self._enabled = false
            self._updateConnection = nil

            -- Entity tracking
            self._entitiesInside = {}       -- { [entity] = { enterTime, lastPosition, triggered } }
            self._cooldowns = {}            -- { [entity] = timestamp } for cooldown tracking

            -- Configuration
            self._activeFace = "Front"
            self._cooldown = 0.5
            self._filter = nil

            -- Get the detection part from model
            self._part = nil
            if self._model then
                if self._model:IsA("BasePart") then
                    self._part = self._model
                elseif self._model:IsA("Model") then
                    self._part = self._model.PrimaryPart or self._model:FindFirstChildWhichIsA("BasePart")
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
            self:_disable()
        end,
    },

    ----------------------------------------------------------------------------
    -- INPUT HANDLERS
    ----------------------------------------------------------------------------

    In = {
        onConfigure = function(self, data)
            if not data then return end

            if data.activeFace and FACES[data.activeFace] then
                self._activeFace = data.activeFace
                self:setAttribute("ActiveFace", data.activeFace)
            end

            if data.cooldown then
                self._cooldown = data.cooldown
                self:setAttribute("Cooldown", data.cooldown)
            end

            if data.filter then
                self._filter = data.filter
            end

            -- Allow setting the part directly
            if data.part and data.part:IsA("BasePart") then
                self._part = data.part
            end
        end,

        onEnable = function(self)
            self:_enable()
        end,

        onDisable = function(self)
            self:_disable()
        end,
    },

    ----------------------------------------------------------------------------
    -- OUTPUT SCHEMA
    ----------------------------------------------------------------------------

    Out = {
        crossed = {},       -- { entity, entityId, face, isActiveFace, direction, position }
        entityInside = {},  -- { entity, entityId }
        entityLeft = {},    -- { entity, entityId }
    },

    ----------------------------------------------------------------------------
    -- PRIVATE METHODS
    ----------------------------------------------------------------------------

    _enable = function(self)
        if self._enabled then return end

        if not self._part then
            self.Err:Fire({
                reason = "no_part",
                message = "Checkpoint requires a BasePart for detection",
            })
            return
        end

        self._enabled = true
        self:_startDetectionLoop()
    end,

    _disable = function(self)
        if not self._enabled then return end

        self._enabled = false

        if self._updateConnection then
            self._updateConnection:Disconnect()
            self._updateConnection = nil
        end

        -- Fire entityLeft for any remaining entities
        for entity in pairs(self._entitiesInside) do
            self.Out:Fire("entityLeft", {
                entity = entity,
                entityId = EntityUtils.getId(entity),
            })
        end

        self._entitiesInside = {}
    end,

    _startDetectionLoop = function(self)
        self._updateConnection = RunService.Heartbeat:Connect(function(dt)
            self:_updateDetection()
        end)
    end,

    _updateDetection = function(self)
        if not self._enabled or not self._part then return end

        local currentEntities = {}
        local partCFrame = self._part.CFrame
        local partSize = self._part.Size

        -- Find entities inside the checkpoint box
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = { self._part }

        local parts = workspace:GetPartBoundsInBox(partCFrame, partSize, overlapParams)

        for _, part in ipairs(parts) do
            local entity = EntityUtils.getEntityFromPart(part)

            if entity and not currentEntities[entity] then
                currentEntities[entity] = true

                -- Check filter
                if not EntityUtils.passesFilter(entity, self._filter) then
                    continue
                end

                local entityPos = EntityUtils.getPosition(entity)

                if not self._entitiesInside[entity] then
                    -- New entity entering
                    self._entitiesInside[entity] = {
                        enterTime = os.clock(),
                        lastPosition = entityPos,
                        triggered = false,
                    }

                    -- Determine entry face and fire crossed
                    self:_handleEntityEntry(entity, entityPos)

                    self.Out:Fire("entityInside", {
                        entity = entity,
                        entityId = EntityUtils.getId(entity),
                    })
                else
                    -- Update position for direction tracking
                    self._entitiesInside[entity].lastPosition = entityPos
                end
            end
        end

        -- Check for entities that left
        for entity, data in pairs(self._entitiesInside) do
            if not currentEntities[entity] then
                self._entitiesInside[entity] = nil

                self.Out:Fire("entityLeft", {
                    entity = entity,
                    entityId = EntityUtils.getId(entity),
                })
            end
        end
    end,

    --[[
        Handle an entity entering the checkpoint.
        Determines which face they entered from and fires crossed signal.
    --]]
    _handleEntityEntry = function(self, entity, entityPos)
        -- Check cooldown
        local now = os.clock()
        if self._cooldowns[entity] and (now - self._cooldowns[entity]) < self._cooldown then
            return  -- Still in cooldown
        end

        -- Determine which face the entity entered from
        local face, direction = self:_determineEntryFace(entity, entityPos)

        -- Update cooldown
        self._cooldowns[entity] = now

        -- Mark as triggered
        self._entitiesInside[entity].triggered = true

        -- Fire crossed signal
        self.Out:Fire("crossed", {
            entity = entity,
            entityId = EntityUtils.getId(entity),
            face = face,
            isActiveFace = (face == self._activeFace),
            direction = direction,
            position = entityPos,
        })
    end,

    --[[
        Determine which face an entity entered from based on their position
        relative to the checkpoint center.
    --]]
    _determineEntryFace = function(self, entity, entityPos)
        local partCFrame = self._part.CFrame
        local partSize = self._part.Size

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
    end,
})

return Checkpoint
