--[[
    LibPureFiction Framework v2
    TerrainBuilder.lua - Terrain Shell Construction

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    TerrainBuilder creates a terrain "shell" on the outer faces of wall parts.
    Wall parts are made invisible (transparency=1) but retain collision.
    Terrain voxels are painted 1 voxel thick (4 studs) on each wall's outer face.

    Strategy:
    - Floor outer face = DOWN (-Y)
    - Ceiling outer face = UP (+Y)
    - North wall outer face = NORTH (+Z)
    - South wall outer face = SOUTH (-Z)
    - East wall outer face = EAST (+X)
    - West wall outer face = WEST (-X)

    Used by DungeonOrchestrator in the sequential build pipeline:
    VolumeBuilder -> ShellBuilder -> TerrainBuilder -> DoorCutter -> ...

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ material, container })
        onBuildTerrain({ roomId, walls, position, dims })
        onClear({})

    OUT (emits):
        terrainComplete({ roomId })

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local VOXEL_SIZE = 4  -- Roblox terrain minimum voxel size

-- Wall definitions: name -> outer face direction (axis offset)
local WALL_OUTER_FACE = {
    Floor   = Vector3.new(0, -1, 0),  -- Down
    Ceiling = Vector3.new(0,  1, 0),  -- Up
    North   = Vector3.new(0, 0,  1),  -- +Z
    South   = Vector3.new(0, 0, -1),  -- -Z
    East    = Vector3.new( 1, 0, 0),  -- +X
    West    = Vector3.new(-1, 0, 0),  -- -X
}

--------------------------------------------------------------------------------
-- TERRAIN BUILDER NODE
--------------------------------------------------------------------------------

local TerrainBuilder = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    material = Enum.Material.Rock,  -- Default terrain material
                },
                container = nil,
                builtRooms = {},  -- { [roomId] = true }
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- TERRAIN SHELL CONSTRUCTION
    ----------------------------------------------------------------------------

    --[[
        Paint a 1-voxel terrain layer on the outer face of a wall part.

        @param wall: The wall Part
        @param outerDir: Vector3 direction of the outer face
        @param material: Terrain material to use
    --]]
    local function paintOuterFace(wall, outerDir, material)
        local terrain = workspace.Terrain
        local wallPos = wall.Position
        local wallSize = wall.Size

        -- Determine terrain block size and position based on outer direction
        local terrainSize
        local terrainPos

        if math.abs(outerDir.Y) > 0 then
            -- Floor/Ceiling: terrain spans X and Z, thin in Y
            terrainSize = Vector3.new(wallSize.X, VOXEL_SIZE, wallSize.Z)
            -- Position: offset from wall center by half wall thickness + half voxel
            local offsetY = outerDir.Y * (wallSize.Y / 2 + VOXEL_SIZE / 2)
            terrainPos = wallPos + Vector3.new(0, offsetY, 0)
        elseif math.abs(outerDir.X) > 0 then
            -- East/West: terrain spans Y and Z, thin in X
            terrainSize = Vector3.new(VOXEL_SIZE, wallSize.Y, wallSize.Z)
            local offsetX = outerDir.X * (wallSize.X / 2 + VOXEL_SIZE / 2)
            terrainPos = wallPos + Vector3.new(offsetX, 0, 0)
        else
            -- North/South: terrain spans X and Y, thin in Z
            terrainSize = Vector3.new(wallSize.X, wallSize.Y, VOXEL_SIZE)
            local offsetZ = outerDir.Z * (wallSize.Z / 2 + VOXEL_SIZE / 2)
            terrainPos = wallPos + Vector3.new(0, 0, offsetZ)
        end

        -- Fill the terrain block
        terrain:FillBlock(CFrame.new(terrainPos), terrainSize, material)
    end

    --[[
        Build terrain shell for a room's walls.
        Makes wall parts invisible and paints terrain on outer faces.
    --]]
    local function buildTerrain(self, roomId, walls, position, dims)
        local state = getState(self)
        local material = state.config.material

        -- Clear terrain on first room
        if roomId == 1 then
            print("[TerrainBuilder] Clearing existing terrain...")
            workspace.Terrain:Clear()
        end

        if not walls then
            warn("[TerrainBuilder] walls is nil for room", roomId)
            state.builtRooms[roomId] = true
            return
        end

        -- Process each wall
        for wallName, wall in pairs(walls) do
            local outerDir = WALL_OUTER_FACE[wallName]
            if outerDir then
                -- Make wall invisible (keeps collision)
                wall.Transparency = 1

                -- Paint terrain on outer face
                paintOuterFace(wall, outerDir, material)
            end
        end

        state.builtRooms[roomId] = true
    end

    --[[
        Clear all terrain (nuclear option).
        Note: This clears ALL terrain in workspace, not just what we built.
        For selective clearing, we'd need to track regions.
    --]]
    local function clearAllTerrain()
        workspace.Terrain:Clear()
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "TerrainBuilder",
        domain = "server",

        Sys = {
            onInit = function(self)
                local _ = getState(self)
            end,

            onStart = function(self) end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)
                local config = state.config

                if data.material then config.material = data.material end

                if data.container then
                    state.container = data.container
                end
            end,

            onBuildTerrain = function(self, data)
                if not data then return end

                local roomId = data.roomId
                local walls = data.walls
                local position = data.position
                local dims = data.dims

                if not roomId then
                    warn("[TerrainBuilder] Missing roomId")
                    return
                end

                if not position or not dims then
                    warn("[TerrainBuilder] Missing position or dims")
                    return
                end

                buildTerrain(self, roomId, walls, position, dims)

                self.Out:Fire("terrainComplete", {
                    roomId = roomId,
                })
            end,

            onClear = function(self)
                local state = getState(self)
                clearAllTerrain()
                state.builtRooms = {}
            end,
        },

        Out = {
            terrainComplete = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        hasBuiltRoom = function(self, roomId)
            return getState(self).builtRooms[roomId] == true
        end,

        getBuiltRoomCount = function(self)
            local count = 0
            for _ in pairs(getState(self).builtRooms) do
                count = count + 1
            end
            return count
        end,
    }
end)

return TerrainBuilder
