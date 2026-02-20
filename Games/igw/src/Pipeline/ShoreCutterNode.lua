--[[
    IGW v2 Pipeline — ShoreCutterNode

    Chunk painting chain node. Creates a berm around water areas:

    1. Scan waterYI for air voxels (future water), find 8-neighbor solid
       perimeter (shore columns).
    2. Backfill lipYI (1 above water) for perimeter columns missing it.
    3. Flood-fill backfill inward until every gap at lipYI is filled.
       First 3 rings use gradient occupancy for a gentle shore slope,
       then full occupancy to meet existing terrain.

    Uses 8-neighbor (includes diagonals) to prevent diamond-shaped
    jaggies at 45-degree shorelines.

    Chain: ... → TopologyTerrainPainter → ShoreCutterNode → ...
--]]

local VOXEL = 4

-- 8 directions: cardinals + diagonals
local DIRS = {
    {-1,0}, {1,0}, {0,-1}, {0,1},
    {-1,-1}, {-1,1}, {1,-1}, {1,1},
}

return {
    name = "ShoreCutterNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onChunkDone = function(self, data)
            local waterLevel = data.waterLevel
            local bounds = data.bounds

            if data.action == "paint" and waterLevel and bounds then
                task.wait()

                local terrain = workspace.Terrain
                local lipMaterial = Enum.Material.Sand

                local scanMinY = waterLevel - VOXEL * 2
                local scanMaxY = waterLevel + VOXEL * 4

                -- Read slightly beyond chunk bounds so we can detect
                -- shoreline at chunk edges (adjacent chunk terrain)
                local MARGIN = VOXEL * 4
                local region = Region3.new(
                    Vector3.new(bounds.minX - MARGIN, scanMinY, bounds.minZ - MARGIN),
                    Vector3.new(bounds.maxX + MARGIN, scanMaxY, bounds.maxZ + MARGIN)
                )

                local mats, occs = terrain:ReadVoxels(region, VOXEL)

                local xCount = #mats
                local yCount = #mats[1]
                local zCount = #mats[1][1]

                local waterYI = math.floor((waterLevel - scanMinY) / VOXEL) + 1
                if waterYI < 1 then waterYI = 1 end
                if waterYI > yCount then waterYI = yCount end

                local lipYI = waterYI + 1

                local changed = false

                --------------------------------------------------------
                -- Step 1: Find perimeter — solid non-water columns at
                -- waterYI that are 8-adjacent to air or water at waterYI
                --------------------------------------------------------

                local waterMat = Enum.Material.Water
                local function isWaterSide(xi, zi)
                    return occs[xi][waterYI][zi] == 0
                        or mats[xi][waterYI][zi] == waterMat
                end

                -- Build water-side mask: all columns that are air/water at waterYI.
                -- Also tag columns 8-adjacent to water (perimeter) so the
                -- flood-fill never crosses back toward the water.
                local waterZone = {}  -- "xi,zi" → true for water-side columns
                local perimeter = {}  -- solid columns directly at water edge
                for xi = 1, xCount do
                    for zi = 1, zCount do
                        if isWaterSide(xi, zi) then
                            waterZone[xi .. "," .. zi] = true
                            for _, d in ipairs(DIRS) do
                                local nx, nz = xi + d[1], zi + d[2]
                                if nx >= 1 and nx <= xCount
                                    and nz >= 1 and nz <= zCount
                                    and occs[nx][waterYI][nz] > 0
                                    and mats[nx][waterYI][nz] ~= waterMat
                                then
                                    perimeter[nx .. "," .. nz] = true
                                end
                            end
                        end
                    end
                end

                --------------------------------------------------------
                -- Step 2: Backfill lip at lipYI for perimeter columns
                --------------------------------------------------------

                -- Gradient occupancy for first few rings, then 1.0 for the rest.
                -- Keeps expanding until no more empty lipYI columns remain
                -- above solid waterYI terrain (flood-fills to meet the land).
                local GRADIENT = { [0] = 0.10, 0.40, 0.70 }
                local MAX_RINGS = 200  -- safety cap

                local filled = {}
                if lipYI <= yCount then
                    for key, _ in pairs(perimeter) do
                        local xi, zi = key:match("^(%d+),(%d+)$")
                        xi, zi = tonumber(xi), tonumber(zi)
                        if occs[xi][lipYI][zi] == 0 then
                            mats[xi][lipYI][zi] = lipMaterial
                            occs[xi][lipYI][zi] = GRADIENT[0]
                            filled[key] = true
                            changed = true
                        end
                    end
                end

                --------------------------------------------------------
                -- Step 3: Flood-fill backfill LANDWARD until flush
                -- with existing terrain. Only fills columns that are
                -- NOT in the water zone and NOT adjacent to water.
                --------------------------------------------------------

                local frontier = filled
                local ring = 0
                while true do
                    ring = ring + 1
                    if ring > MAX_RINGS then break end
                    local ringOcc = GRADIENT[ring] or 1.0
                    local nextFrontier = {}
                    local expanded = false
                    for key, _ in pairs(frontier) do
                        local xi, zi = key:match("^(%d+),(%d+)$")
                        xi, zi = tonumber(xi), tonumber(zi)
                        for _, d in ipairs(DIRS) do
                            local nx, nz = xi + d[1], zi + d[2]
                            if nx >= 1 and nx <= xCount
                                and nz >= 1 and nz <= zCount
                            then
                                local nk = nx .. "," .. nz
                                if not filled[nk]
                                    and not perimeter[nk]
                                    and not waterZone[nk]
                                    and occs[nx][waterYI][nz] > 0
                                    and mats[nx][waterYI][nz] ~= waterMat
                                    and occs[nx][lipYI][nz] == 0
                                then
                                    mats[nx][lipYI][nz] = lipMaterial
                                    occs[nx][lipYI][nz] = ringOcc
                                    filled[nk] = true
                                    nextFrontier[nk] = true
                                    changed = true
                                    expanded = true
                                end
                            end
                        end
                    end
                    if not expanded then break end
                    frontier = nextFrontier
                end

                if changed then
                    terrain:WriteVoxels(region, VOXEL, mats, occs)
                end
            end

            data._msgId = nil
            self.Out:Fire("chunkDone", data)
        end,
    },
}
