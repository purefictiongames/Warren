--[[
    Chunker — Spatial Chunk Splitter

    Pure function: Chunker.split(mapData, opts) → { chunks, global }

    Assigns rooms to 512-stud spatial chunks by center position.
    Classifies doors as interior (both rooms in same chunk) vs border
    (rooms span two chunks). Border doors stored in BOTH chunks.

    8x8 grid of 512x512 stud chunks. Chunk coords: (cx, cz) where (0,0) is
    top-left. Key format: "cx,cz".
--]]

local floor = math.floor

local Chunker = {}

--- Assign a world-space X or Z position to a chunk index (0-based).
local function toChunkCoord(pos, mapMin, chunkSize)
    return floor((pos - mapMin) / chunkSize)
end

--- Split monolithic map data into spatial chunks.
--- @param mapData table — Full map data from MapGen.generate()
--- @param opts? table — { chunkSize?, mapWidth?, mapDepth? }
--- @return table — { chunks = { ["cx,cz"] = chunkData }, global = globalData }
function Chunker.split(mapData, opts)
    opts = opts or {}

    local chunkSize = opts.chunkSize or 512
    local mapWidth  = opts.mapWidth or 4000
    local mapDepth  = opts.mapDepth or 4000

    local mapMinX = -(mapWidth / 2)
    local mapMinZ = -(mapDepth / 2)

    local sizeX = math.ceil(mapWidth / chunkSize)
    local sizeZ = math.ceil(mapDepth / chunkSize)

    ----------------------------------------------------------------
    -- Initialize chunk buckets
    ----------------------------------------------------------------

    local chunks = {}

    local function ensureChunk(cx, cz)
        local key = cx .. "," .. cz
        if not chunks[key] then
            chunks[key] = {
                cx = cx,
                cz = cz,
                worldMinX = mapMinX + cx * chunkSize,
                worldMinZ = mapMinZ + cz * chunkSize,
                rooms = {},
                doors = {},
                borderDoors = {},
            }
        end
        return chunks[key]
    end

    ----------------------------------------------------------------
    -- Assign rooms to chunks by center position
    ----------------------------------------------------------------

    local roomChunkMap = {}  -- roomId → "cx,cz"

    for roomId, room in pairs(mapData.rooms or {}) do
        local pos = room.position
        local cx = toChunkCoord(pos[1], mapMinX, chunkSize)
        local cz = toChunkCoord(pos[3], mapMinZ, chunkSize)

        -- Clamp to grid bounds
        cx = math.max(0, math.min(sizeX - 1, cx))
        cz = math.max(0, math.min(sizeZ - 1, cz))

        local chunk = ensureChunk(cx, cz)
        -- Stringify key for JSON serialization (Lune serde requires string keys)
        local roomKey = tostring(roomId)
        chunk.rooms[roomKey] = room

        local key = cx .. "," .. cz
        roomChunkMap[roomId] = key
    end

    ----------------------------------------------------------------
    -- Classify doors as interior vs border
    ----------------------------------------------------------------

    for _, door in ipairs(mapData.doors or {}) do
        local chunkA = roomChunkMap[door.fromRoom]
        local chunkB = roomChunkMap[door.toRoom]

        if chunkA and chunkB then
            if chunkA == chunkB then
                -- Interior door: both rooms in same chunk
                local chunk = chunks[chunkA]
                table.insert(chunk.doors, door)
            else
                -- Border door: rooms span two chunks — store in BOTH
                local chunkDataA = chunks[chunkA]
                local chunkDataB = chunks[chunkB]
                if chunkDataA then
                    table.insert(chunkDataA.borderDoors, door)
                end
                if chunkDataB then
                    table.insert(chunkDataB.borderDoors, door)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Build global data (sent once on world create)
    -- Room keys MUST be stringified for JSON serialization (Lune serde
    -- encodes numeric-keyed tables as arrays, which breaks sparse maps).
    ----------------------------------------------------------------

    local globalRooms = {}
    for roomId, room in pairs(mapData.rooms or {}) do
        globalRooms[tostring(roomId)] = room
    end

    local global = {
        seed        = mapData.seed,
        biomeConfig = mapData.biomeConfig,
        inventory   = mapData.inventory,
        splines     = mapData.splines,
        maxH        = mapData.maxH,
        spawn       = mapData.spawn,
        roomOrder   = mapData.roomOrder,
        rooms       = globalRooms,
        doors       = mapData.doors,
        chunkGrid   = {
            sizeX     = sizeX,
            sizeZ     = sizeZ,
            chunkSize = chunkSize,
            mapMinX   = mapMinX,
            mapMinZ   = mapMinZ,
        },
    }

    ----------------------------------------------------------------
    -- Stats
    ----------------------------------------------------------------

    local chunkCount = 0
    local totalRooms = 0
    local totalInterior = 0
    local totalBorder = 0

    for _, chunk in pairs(chunks) do
        chunkCount = chunkCount + 1
        for _ in pairs(chunk.rooms) do
            totalRooms = totalRooms + 1
        end
        totalInterior = totalInterior + #chunk.doors
        totalBorder = totalBorder + #chunk.borderDoors
    end

    print(string.format(
        "[Chunker] Split into %d chunks (%dx%d grid, %d-stud) | %d rooms, %d interior doors, %d border door refs",
        chunkCount, sizeX, sizeZ, chunkSize,
        totalRooms, totalInterior, totalBorder
    ))

    return {
        chunks = chunks,
        global = global,
    }
end

return Chunker
