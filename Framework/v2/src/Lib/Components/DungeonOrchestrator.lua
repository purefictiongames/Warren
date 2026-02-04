--[[
    LibPureFiction Framework v2
    DungeonOrchestrator.lua - Sequential Dungeon Generation Controller

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    DungeonOrchestrator owns all planning and sequencing for dungeon generation.
    Child nodes (VolumeBuilder, ShellBuilder, DoorCutter) have no knowledge of
    the overall dungeon inventory.

    Build Pipeline (per room):
        1. Orchestrator picks room from inventory
        2. VolumeBuilder places volume, returns position
        3. ShellBuilder builds walls around volume
        4. DoorCutter cuts door to parent room (skip for first room)
        5. Repeat for next room

    Phases:
        1. Main Path - Linear chain of rooms
        2. Spurs - Branch rooms off the main path
        3. Loops - Connect existing rooms to create cycles
        4. Complete - All rooms built

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ seed, baseUnit, wallThickness, mainPathLength, spurCount, loopCount, ... })
        onGenerate({ origin })
        onRoomPlaced({ roomId, position, dims, parentRoomId, attachFace })  -- from VolumeBuilder
        onShellComplete({ roomId, container })                               -- from ShellBuilder
        onDoorComplete({ fromRoomId, toRoomId })                            -- from DoorCutter

    OUT (emits):
        roomBuilt({ roomId, position, dims, pathType })
        doorCut({ fromRoomId, toRoomId })
        phaseStarted({ phase })
        complete({ totalRooms, totalDoors })
        generationFailed({ reason })

--]]

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- DUNGEON ORCHESTRATOR NODE
--------------------------------------------------------------------------------

local DungeonOrchestrator = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                config = {
                    seed = os.time(),
                    baseUnit = 5,
                    wallThickness = 1,
                    doorSize = 10,        -- Doors are 10x10 studs square
                    verticalChance = 30,  -- 30% chance to try vertical room connections
                    minVerticalRatio = 0.2, -- At least 20% of rooms must have vertical connections
                    floorThreshold = 5,   -- Height diff (studs) before wall door needs truss
                    mainPathLength = 5,
                    spurCount = 2,
                    loopCount = 0,
                    scaleRange = { min = 4, max = 10, minY = 4, maxY = 8 },  -- Bigger rooms
                },
                verticalCount = 0,  -- Track actual vertical connections made
                container = nil,
                -- Inventory: rooms to build
                inventory = {},  -- { { id, dims, pathType, parentId } }
                inventoryIndex = 0,
                -- Tracking
                builtRooms = {},  -- { [roomId] = { position, dims, pathType, parentId } }
                mainPath = {},    -- Array of room IDs in main path order
                spurs = {},       -- Array of spur room IDs
                loops = {},       -- Array of { fromId, toId } pairs
                -- Phase management
                currentPhase = "idle",  -- idle, main, spurs, loops, complete
                pendingRoom = nil,      -- Currently building room
                -- Child nodes
                volumeBuilder = nil,
                shellBuilder = nil,
                doorCutter = nil,
                trussBuilder = nil,
                terrainBuilder = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- INVENTORY BUILDING
    ----------------------------------------------------------------------------

    local function randomScale(config)
        local range = config.scaleRange
        return {
            math.random(range.min, range.max) * config.baseUnit,
            math.random(range.minY or range.min, range.maxY or range.max) * config.baseUnit,
            math.random(range.min, range.max) * config.baseUnit,
        }
    end

    local function buildInventory(self)
        local state = getState(self)
        local config = state.config
        local inventory = {}

        -- Seed random
        math.randomseed(config.seed)

        local roomId = 1

        -- Main path rooms
        local prevRoomId = nil
        for i = 1, config.mainPathLength do
            local entry = {
                id = roomId,
                dims = randomScale(config),
                pathType = "main",
                parentId = prevRoomId,
            }
            table.insert(inventory, entry)
            prevRoomId = roomId
            roomId = roomId + 1
        end

        -- Spur rooms (branch off random main path rooms)
        for i = 1, config.spurCount do
            -- Pick a random room from main path to branch from
            local branchFromIdx = math.random(1, config.mainPathLength)
            local branchFromId = branchFromIdx  -- Main path rooms are 1..mainPathLength

            local entry = {
                id = roomId,
                dims = randomScale(config),
                pathType = "spur",
                parentId = branchFromId,
            }
            table.insert(inventory, entry)
            roomId = roomId + 1
        end

        -- Note: Loops are handled separately after all rooms are built
        -- They don't add new rooms, just connect existing ones

        state.inventory = inventory
        state.inventoryIndex = 0

        return inventory
    end

    ----------------------------------------------------------------------------
    -- PHASE MANAGEMENT
    ----------------------------------------------------------------------------

    -- Forward declarations for functions called before definition
    local processLoops
    local finishGeneration

    local function startPhase(self, phase)
        local state = getState(self)
        state.currentPhase = phase

        self.Out:Fire("phaseStarted", { phase = phase })
    end

    local function buildNextRoom(self)
        local state = getState(self)

        state.inventoryIndex = state.inventoryIndex + 1
        local entry = state.inventory[state.inventoryIndex]

        if not entry then
            -- No more rooms to build
            if state.currentPhase == "main" or state.currentPhase == "spurs" then
                -- Check if we should do loops
                if state.config.loopCount > 0 and #state.loops == 0 then
                    startPhase(self, "loops")
                    processLoops(self)
                else
                    finishGeneration(self)
                end
            end
            return
        end

        state.pendingRoom = entry

        -- Determine which phase we're in based on room type
        if entry.pathType == "main" and state.currentPhase ~= "main" then
            startPhase(self, "main")
        elseif entry.pathType == "spur" and state.currentPhase ~= "spurs" then
            startPhase(self, "spurs")
        end

        -- Calculate if we need to force vertical placement
        local forceVertical = false
        if entry.parentId ~= nil then  -- Can't force vertical on first room
            local totalRooms = #state.inventory
            local roomsRemaining = totalRooms - state.inventoryIndex + 1  -- +1 because we haven't placed current yet
            local minRequired = math.ceil(totalRooms * state.config.minVerticalRatio)
            local verticalsNeeded = minRequired - state.verticalCount

            -- If we need more verticals than rooms remaining, force it
            if verticalsNeeded > 0 and verticalsNeeded >= roomsRemaining then
                forceVertical = true
            end
        end

        -- Send to VolumeBuilder
        if entry.parentId == nil then
            -- First room - place at origin
            state.volumeBuilder.In.onPlaceOrigin(state.volumeBuilder, {
                roomId = entry.id,
                dims = entry.dims,
                position = state.origin or { 0, 0, 0 },
            })
        else
            -- Attach to parent
            state.volumeBuilder.In.onPlaceRoom(state.volumeBuilder, {
                roomId = entry.id,
                dims = entry.dims,
                parentRoomId = entry.parentId,
                forceVertical = forceVertical,
            })
        end
    end

    ----------------------------------------------------------------------------
    -- LOOP PROCESSING
    ----------------------------------------------------------------------------

    processLoops = function(self)
        local state = getState(self)
        local config = state.config

        -- Find potential loop connections
        -- Look for rooms that are adjacent but not already connected
        local rooms = state.volumeBuilder:getAllRooms()

        -- Build adjacency set from parent-child relationships
        local connected = {}
        for _, room in ipairs(rooms) do
            if room.parentRoomId then
                local key1 = room.id .. "_" .. room.parentRoomId
                local key2 = room.parentRoomId .. "_" .. room.id
                connected[key1] = true
                connected[key2] = true
            end
        end

        -- Find potentially adjacent pairs that aren't connected
        local candidates = {}
        for i = 1, #rooms do
            for j = i + 1, #rooms do
                local roomA = rooms[i]
                local roomB = rooms[j]
                local key = roomA.id .. "_" .. roomB.id

                if not connected[key] then
                    -- Check if they could be adjacent (rough distance check)
                    local dx = math.abs(roomA.position[1] - roomB.position[1])
                    local dy = math.abs(roomA.position[2] - roomB.position[2])
                    local dz = math.abs(roomA.position[3] - roomB.position[3])

                    local maxDistX = (roomA.dims[1] + roomB.dims[1]) / 2 + config.wallThickness * 3
                    local maxDistY = (roomA.dims[2] + roomB.dims[2]) / 2 + config.wallThickness * 3
                    local maxDistZ = (roomA.dims[3] + roomB.dims[3]) / 2 + config.wallThickness * 3

                    if dx <= maxDistX and dy <= maxDistY and dz <= maxDistZ then
                        table.insert(candidates, { roomA = roomA, roomB = roomB })
                    end
                end
            end
        end

        -- Try to create up to loopCount loops
        local loopsCreated = 0
        for _, candidate in ipairs(candidates) do
            if loopsCreated >= config.loopCount then break end

            -- Try to cut a door between these rooms
            state.doorCutter.In.onCutDoor(state.doorCutter, {
                roomA = candidate.roomA,
                roomB = candidate.roomB,
            })

            -- Mark as loop (actual success tracked by doorComplete signal)
            table.insert(state.loops, {
                fromId = candidate.roomA.id,
                toId = candidate.roomB.id,
            })
            loopsCreated = loopsCreated + 1
        end

        -- Loops are async, but we don't wait - finish generation
        task.defer(function()
            finishGeneration(self)
        end)
    end

    finishGeneration = function(self)
        local state = getState(self)

        startPhase(self, "complete")

        local totalRooms = 0
        for _ in pairs(state.builtRooms) do
            totalRooms = totalRooms + 1
        end

        -- Create spawn point in first room
        local firstRoom = state.builtRooms[1]
        if firstRoom and state.container then
            local spawn = Instance.new("SpawnLocation")
            spawn.Name = "DungeonSpawn"
            spawn.Size = Vector3.new(4, 1, 4)
            spawn.Position = Vector3.new(
                firstRoom.position[1],
                firstRoom.position[2] - firstRoom.dims[2]/2 + 1,  -- On floor + 1 stud
                firstRoom.position[3]
            )
            spawn.Anchored = true
            spawn.CanCollide = false
            spawn.Transparency = 0.5
            spawn.Material = Enum.Material.Neon
            spawn.Color = Color3.fromRGB(100, 255, 100)
            spawn.Parent = state.container
            state.spawnPoint = spawn
        end

        self.Out:Fire("complete", {
            totalRooms = totalRooms,
            totalDoors = state.doorCutter:getDoorwayCount(),
        })
    end

    ----------------------------------------------------------------------------
    -- SIGNAL HANDLERS FROM CHILD NODES
    ----------------------------------------------------------------------------

    local function onVolumeBuilderPlaced(self, data)
        local state = getState(self)

        -- Store room data
        state.builtRooms[data.roomId] = {
            position = data.position,
            dims = data.dims,
            pathType = state.pendingRoom and state.pendingRoom.pathType,
            parentId = data.parentRoomId,
            attachFace = data.attachFace,
        }

        -- Track vertical connections
        if data.attachFace == "U" or data.attachFace == "D" then
            state.verticalCount = state.verticalCount + 1
        end

        -- Track in path arrays
        if state.pendingRoom then
            if state.pendingRoom.pathType == "main" then
                table.insert(state.mainPath, data.roomId)
            elseif state.pendingRoom.pathType == "spur" then
                table.insert(state.spurs, data.roomId)
            end
        end

        -- Send to ShellBuilder
        state.shellBuilder.In.onBuildShell(state.shellBuilder, {
            roomId = data.roomId,
            position = data.position,
            dims = data.dims,
        })
    end

    local function onVolumeBuilderFailed(self, data)
        local state = getState(self)

        warn(string.format("[DungeonOrchestrator] Room %s placement failed: %s",
            tostring(data.roomId), data.reason))

        -- Skip this room and continue
        buildNextRoom(self)
    end

    local function onShellBuilderComplete(self, data)
        local state = getState(self)

        local roomData = state.builtRooms[data.roomId]
        if not roomData then return end

        -- Send to TerrainBuilder to paint terrain shell on walls
        state.terrainBuilder.In.onBuildTerrain(state.terrainBuilder, {
            roomId = data.roomId,
            walls = data.walls,
            position = roomData.position,
            dims = roomData.dims,
        })
    end

    local function onTerrainBuilderComplete(self, data)
        local state = getState(self)

        local roomData = state.builtRooms[data.roomId]
        if not roomData then return end

        -- Emit roomBuilt signal
        self.Out:Fire("roomBuilt", {
            roomId = data.roomId,
            position = roomData.position,
            dims = roomData.dims,
            pathType = roomData.pathType,
        })

        -- Cut door to parent (skip for first room)
        if roomData.parentId then
            local parentRoom = state.builtRooms[roomData.parentId]
            if parentRoom then
                state.doorCutter.In.onCutDoor(state.doorCutter, {
                    roomA = {
                        id = roomData.parentId,
                        position = parentRoom.position,
                        dims = parentRoom.dims,
                    },
                    roomB = {
                        id = data.roomId,
                        position = roomData.position,
                        dims = roomData.dims,
                    },
                })
            else
                -- Parent not built yet - shouldn't happen with proper ordering
                warn("[DungeonOrchestrator] Parent room not found: " .. tostring(roomData.parentId))
                buildNextRoom(self)
            end
        else
            -- First room - no door needed, continue to next
            buildNextRoom(self)
        end
    end

    local function onDoorCutterComplete(self, data)
        local state = getState(self)

        self.Out:Fire("doorCut", {
            fromRoomId = data.fromRoomId,
            toRoomId = data.toRoomId,
        })

        -- Send to TrussBuilder to check if truss is needed
        local roomA = state.builtRooms[data.fromRoomId]
        local roomB = state.builtRooms[data.toRoomId]

        if roomA and roomB then
            state.trussBuilder.In.onCheckDoorway(state.trussBuilder, {
                doorway = {
                    center = data.position,
                    width = data.width,
                    height = data.height,
                    axis = data.axis,
                    widthAxis = data.widthAxis,
                },
                roomA = {
                    id = data.fromRoomId,
                    position = roomA.position,
                    dims = roomA.dims,
                },
                roomB = {
                    id = data.toRoomId,
                    position = roomB.position,
                    dims = roomB.dims,
                },
            })
        else
            -- Missing room data, skip truss check and continue
            if state.currentPhase ~= "loops" then
                buildNextRoom(self)
            end
        end
    end

    local function onDoorCutterFailed(self, data)
        local state = getState(self)

        warn(string.format("[DungeonOrchestrator] Door %s<->%s failed: %s",
            tostring(data.fromRoomId), tostring(data.toRoomId), data.reason))

        -- Continue anyway
        if state.currentPhase ~= "loops" then
            buildNextRoom(self)
        end
    end

    local function onTrussBuilderPlaced(self, data)
        local state = getState(self)

        -- Continue to next room (unless we're in loops phase)
        if state.currentPhase ~= "loops" then
            buildNextRoom(self)
        end
    end

    local function onTrussBuilderNotNeeded(self, data)
        local state = getState(self)

        -- Continue to next room (unless we're in loops phase)
        if state.currentPhase ~= "loops" then
            buildNextRoom(self)
        end
    end

    ----------------------------------------------------------------------------
    -- CHILD NODE SETUP
    ----------------------------------------------------------------------------

    local function setupChildNodes(self)
        local state = getState(self)
        local config = state.config

        -- Create VolumeBuilder
        local VolumeBuilder = require(script.Parent.VolumeBuilder)
        state.volumeBuilder = VolumeBuilder:new({
            id = self.id .. "_VolumeBuilder",
        })
        state.volumeBuilder.Sys.onInit(state.volumeBuilder)
        state.volumeBuilder.In.onConfigure(state.volumeBuilder, {
            wallThickness = config.wallThickness,
            doorSize = config.doorSize,
            verticalChance = config.verticalChance,
        })

        -- Wire VolumeBuilder signals
        local vbOriginalFire = state.volumeBuilder.Out.Fire
        state.volumeBuilder.Out.Fire = function(outSelf, signal, data)
            if signal == "placed" then
                onVolumeBuilderPlaced(self, data)
            elseif signal == "failed" then
                onVolumeBuilderFailed(self, data)
            end
            vbOriginalFire(outSelf, signal, data)
        end

        -- Create ShellBuilder
        local ShellBuilder = require(script.Parent.ShellBuilder)
        state.shellBuilder = ShellBuilder:new({
            id = self.id .. "_ShellBuilder",
        })
        state.shellBuilder.Sys.onInit(state.shellBuilder)
        state.shellBuilder.In.onConfigure(state.shellBuilder, {
            wallThickness = config.wallThickness,
            material = config.material or Enum.Material.Brick,
            color = config.color or Color3.fromRGB(120, 90, 70),
            container = state.container,
        })

        -- Wire ShellBuilder signals
        local sbOriginalFire = state.shellBuilder.Out.Fire
        state.shellBuilder.Out.Fire = function(outSelf, signal, data)
            if signal == "shellComplete" then
                onShellBuilderComplete(self, data)
            end
            sbOriginalFire(outSelf, signal, data)
        end

        -- Create DoorCutter
        local DoorCutter = require(script.Parent.DoorCutter)
        state.doorCutter = DoorCutter:new({
            id = self.id .. "_DoorCutter",
        })
        state.doorCutter.Sys.onInit(state.doorCutter)
        state.doorCutter.In.onConfigure(state.doorCutter, {
            wallThickness = config.wallThickness,
            doorSize = config.doorSize,
            container = state.container,
        })

        -- Wire DoorCutter signals
        local dcOriginalFire = state.doorCutter.Out.Fire
        state.doorCutter.Out.Fire = function(outSelf, signal, data)
            if signal == "doorComplete" then
                onDoorCutterComplete(self, data)
            elseif signal == "doorFailed" then
                onDoorCutterFailed(self, data)
            end
            dcOriginalFire(outSelf, signal, data)
        end

        -- Create TrussBuilder
        local TrussBuilder = require(script.Parent.TrussBuilder)
        state.trussBuilder = TrussBuilder:new({
            id = self.id .. "_TrussBuilder",
        })
        state.trussBuilder.Sys.onInit(state.trussBuilder)
        state.trussBuilder.In.onConfigure(state.trussBuilder, {
            wallThickness = config.wallThickness,
            floorThreshold = config.floorThreshold,
            container = state.container,
        })

        -- Wire TrussBuilder signals
        local tbOriginalFire = state.trussBuilder.Out.Fire
        state.trussBuilder.Out.Fire = function(outSelf, signal, data)
            if signal == "trussPlaced" then
                onTrussBuilderPlaced(self, data)
            elseif signal == "trussNotNeeded" then
                onTrussBuilderNotNeeded(self, data)
            end
            tbOriginalFire(outSelf, signal, data)
        end

        -- Create TerrainBuilder
        local TerrainBuilder = require(script.Parent.TerrainBuilder)
        state.terrainBuilder = TerrainBuilder:new({
            id = self.id .. "_TerrainBuilder",
        })
        state.terrainBuilder.Sys.onInit(state.terrainBuilder)
        state.terrainBuilder.In.onConfigure(state.terrainBuilder, {
            material = Enum.Material.Rock,
            container = state.container,
        })

        -- Wire TerrainBuilder signals
        local terrOriginalFire = state.terrainBuilder.Out.Fire
        state.terrainBuilder.Out.Fire = function(outSelf, signal, data)
            if signal == "terrainComplete" then
                onTerrainBuilderComplete(self, data)
            end
            terrOriginalFire(outSelf, signal, data)
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "DungeonOrchestrator",
        domain = "server",

        Sys = {
            onInit = function(self)
                local _ = getState(self)
            end,

            onStart = function(self) end,

            onStop = function(self)
                local state = getState(self)

                -- Stop child nodes
                if state.volumeBuilder then
                    state.volumeBuilder.Sys.onStop(state.volumeBuilder)
                end
                if state.shellBuilder then
                    state.shellBuilder.Sys.onStop(state.shellBuilder)
                end
                if state.doorCutter then
                    state.doorCutter.Sys.onStop(state.doorCutter)
                end
                if state.trussBuilder then
                    state.trussBuilder.Sys.onStop(state.trussBuilder)
                end
                if state.terrainBuilder then
                    state.terrainBuilder.Sys.onStop(state.terrainBuilder)
                end

                cleanupState(self)
            end,
        },

        In = {
            onConfigure = function(self, data)
                if not data then return end

                local state = getState(self)
                local config = state.config

                if data.seed then config.seed = data.seed end
                if data.baseUnit then config.baseUnit = data.baseUnit end
                if data.wallThickness then config.wallThickness = data.wallThickness end
                if data.doorSize then config.doorSize = data.doorSize end
                if data.verticalChance then config.verticalChance = data.verticalChance end
                if data.minVerticalRatio then config.minVerticalRatio = data.minVerticalRatio end
                if data.floorThreshold then config.floorThreshold = data.floorThreshold end
                if data.mainPathLength then config.mainPathLength = data.mainPathLength end
                if data.spurCount then config.spurCount = data.spurCount end
                if data.loopCount then config.loopCount = data.loopCount end
                if data.scaleRange then config.scaleRange = data.scaleRange end
                if data.material then config.material = data.material end
                if data.color then config.color = data.color end

                if data.container then
                    state.container = data.container
                end
            end,

            onGenerate = function(self, data)
                local state = getState(self)
                data = data or {}

                state.origin = data.origin or { 0, 0, 0 }

                -- Create container if not provided
                if not state.container then
                    state.container = Instance.new("Model")
                    state.container.Name = "Dungeon_" .. self.id
                    state.container.Parent = workspace
                end

                -- Setup child nodes
                setupChildNodes(self)

                -- Build inventory
                buildInventory(self)

                print(string.format("[DungeonOrchestrator] Starting generation: %d rooms planned",
                    #state.inventory))

                -- Start building
                buildNextRoom(self)
            end,

            -- Manual signal handlers for external control
            onRoomPlaced = function(self, data)
                onVolumeBuilderPlaced(self, data)
            end,

            onShellComplete = function(self, data)
                onShellBuilderComplete(self, data)
            end,

            onDoorComplete = function(self, data)
                onDoorCutterComplete(self, data)
            end,
        },

        Out = {
            roomBuilt = {},
            doorCut = {},
            phaseStarted = {},
            complete = {},
            generationFailed = {},
        },

        ------------------------------------------------------------------------
        -- PUBLIC QUERY METHODS
        ------------------------------------------------------------------------

        getRoom = function(self, roomId)
            return getState(self).builtRooms[roomId]
        end,

        getAllRooms = function(self)
            return getState(self).builtRooms
        end,

        getMainPath = function(self)
            return getState(self).mainPath
        end,

        getSpurs = function(self)
            return getState(self).spurs
        end,

        getLoops = function(self)
            return getState(self).loops
        end,

        getCurrentPhase = function(self)
            return getState(self).currentPhase
        end,

        getInventory = function(self)
            return getState(self).inventory
        end,

        getContainer = function(self)
            return getState(self).container
        end,

        getVolumeBuilder = function(self)
            return getState(self).volumeBuilder
        end,

        getShellBuilder = function(self)
            return getState(self).shellBuilder
        end,

        getDoorCutter = function(self)
            return getState(self).doorCutter
        end,

        getTrussBuilder = function(self)
            return getState(self).trussBuilder
        end,

        getTerrainBuilder = function(self)
            return getState(self).terrainBuilder
        end,

        getSpawnPoint = function(self)
            return getState(self).spawnPoint
        end,
    }
end)

return DungeonOrchestrator
