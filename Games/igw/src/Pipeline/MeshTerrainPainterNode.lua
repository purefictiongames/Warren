--[[
    IGW v2 Pipeline — MeshTerrainPainterNode (Smooth Mesh Terrain)

    Parallel alternative to TerrainPainterNode. Renders the same height field
    as smooth EditableMesh chunks instead of Roblox terrain voxels.

    Algorithm:
        1. Compute height field via TerrainPainterNode.computeHeightField()
        2. For each 512×512 chunk (64 total, up to maxConcurrency parallel):
           a. Create EditableMesh with 65×65 vertices (8-stud spacing)
           b. Assign vertex colors based on biome material + slope
           c. Triangulate 64×64 quads → 8,192 triangles
           d. Bake via AssetService:CreateMeshPartAsync()
           e. Parent baked MeshPart to terrain folder
        3. Parent terrain folder atomically to workspace

    Selection: metadata.lua DungeonOrchestrator.terrainRenderer = "mesh"

    Note: EditableMesh is Client Beta — requires "Allow Mesh/Image APIs" in
    Experience Settings + 13+ ID verification. Fine for dev/testing.

    Signal: onPaintMeshTerrain(payload) -> fires nodeComplete
--]]

local floor = math.floor
local ceil  = math.ceil
local sqrt  = math.sqrt
local max   = math.max
local min   = math.min
local huge  = math.huge

local VOXEL = 4  -- Height field resolution (must match TerrainPainterNode)

--------------------------------------------------------------------------------
-- MATERIAL COLOR LOOKUP (vertex colors by biome material name)
--------------------------------------------------------------------------------

local MATERIAL_COLORS = {
    Rock        = Color3.fromRGB(140, 160, 190),
    Grass       = Color3.fromRGB(76, 153, 0),
    Snow        = Color3.fromRGB(235, 240, 245),
    Sand        = Color3.fromRGB(218, 195, 148),
    Sandstone   = Color3.fromRGB(180, 150, 100),
    Glacier     = Color3.fromRGB(140, 190, 235),
    Ice         = Color3.fromRGB(180, 210, 240),
    CrackedLava = Color3.fromRGB(120, 40, 20),
    Mud         = Color3.fromRGB(90, 70, 50),
    Concrete    = Color3.fromRGB(140, 140, 140),
    Basalt      = Color3.fromRGB(60, 60, 70),
    Salt        = Color3.fromRGB(220, 220, 215),
    Slate       = Color3.fromRGB(100, 100, 110),
    Pavement    = Color3.fromRGB(150, 150, 145),
}
local DEFAULT_COLOR = Color3.fromRGB(127, 127, 127)
local SNOW_COLOR = MATERIAL_COLORS.Snow

--------------------------------------------------------------------------------
-- NODE
--------------------------------------------------------------------------------

local TerrainPainterModule = require(script.Parent.TerrainPainterNode)
local computeHeightField = TerrainPainterModule.computeHeightField

return {
    name = "MeshTerrainPainterNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onPaintMeshTerrain = function(self, payload)
            local selfRef = self
            task.spawn(function()
                local AssetService = game:GetService("AssetService")
                local startTime = os.clock()

                local vpsMaxH = payload.maxH

                ----------------------------------------------------------------
                -- Config from attributes
                ----------------------------------------------------------------

                local mapWidth      = selfRef:getAttribute("mapWidth") or 4000
                local mapDepth      = selfRef:getAttribute("mapDepth") or 4000
                local groundY       = selfRef:getAttribute("groundY") or 0
                local chunkSize     = selfRef:getAttribute("chunkSize") or 512
                local vertexSpacing = selfRef:getAttribute("vertexSpacing") or 8
                local maxConcurrency = selfRef:getAttribute("maxConcurrency") or 8

                -- Height field noise config (pass through to computeHeightField)
                local noiseAmplitude = selfRef:getAttribute("noiseAmplitude")
                    or selfRef:getAttribute("mapNoiseAmplitude") or 50
                local noiseScale1 = selfRef:getAttribute("noiseScale1") or 400
                local noiseScale2 = selfRef:getAttribute("noiseScale2") or 160
                local noiseRatio  = selfRef:getAttribute("noiseRatio") or 0.65

                ----------------------------------------------------------------
                -- Data from payload
                ----------------------------------------------------------------

                local splines     = payload.splines or {}
                local biomeConfig = payload.biomeConfig or {}
                local biome       = payload.biome or {}

                -- Material color for vertex coloring
                local terrainFloor = biome.terrainFloor or "Grass"
                local baseColor = MATERIAL_COLORS[terrainFloor] or DEFAULT_COLOR
                local useSnowOnSlopes = (terrainFloor == "Rock")
                local slopeThreshold = 0.6

                ----------------------------------------------------------------
                -- Compute height field (same function as voxel path)
                ----------------------------------------------------------------

                local hfResult = computeHeightField(splines, biomeConfig, {
                    mapWidth       = mapWidth,
                    mapDepth       = mapDepth,
                    groundY        = groundY,
                    noiseAmplitude = noiseAmplitude,
                    noiseScale1    = noiseScale1,
                    noiseScale2    = noiseScale2,
                    noiseRatio     = noiseRatio,
                    seed           = payload.seed,
                    yield          = task.wait,
                })

                local hField  = hfResult.heightField
                local gridW   = hfResult.gridW
                local gridD   = hfResult.gridD
                local mapMinX = hfResult.mapMinX
                local mapMinZ = hfResult.mapMinZ

                print(string.format(
                    "[MeshTerrainPainterNode] Height field complete: %dx%d (%.2fs)",
                    gridW, gridD, os.clock() - startTime
                ))

                ----------------------------------------------------------------
                -- Store height field for downstream nodes (same as voxel path)
                ----------------------------------------------------------------

                payload.heightField = hField
                payload.heightFieldGridW = gridW
                payload.heightFieldGridD = gridD
                payload.heightFieldMinX = mapMinX
                payload.heightFieldMinZ = mapMinZ
                payload.maxH = vpsMaxH or hfResult.maxH
                if not payload.spawn then
                    payload.spawn = hfResult.spawn
                end

                ----------------------------------------------------------------
                -- Chunk mesh generation
                ----------------------------------------------------------------

                local chunksX = ceil(mapWidth / chunkSize)
                local chunksZ = ceil(mapDepth / chunkSize)
                local vertsPerChunkEdge = floor(chunkSize / vertexSpacing) + 1
                local quadsPerEdge = vertsPerChunkEdge - 1
                local hFieldStep = vertexSpacing / VOXEL  -- Sample every N cells

                print(string.format(
                    "[MeshTerrainPainterNode] Building %dx%d=%d chunks (%dx%d verts, %d tris each)",
                    chunksX, chunksZ, chunksX * chunksZ,
                    vertsPerChunkEdge, vertsPerChunkEdge,
                    quadsPerEdge * quadsPerEdge * 2
                ))

                local terrainFolder = Instance.new("Folder")
                terrainFolder.Name = "MeshTerrain"

                -- Semaphore for concurrency control
                local activeCount = 0
                local completedCount = 0
                local totalChunks = chunksX * chunksZ

                for cx = 0, chunksX - 1 do
                    for cz = 0, chunksZ - 1 do
                        -- Wait for a concurrency slot
                        while activeCount >= maxConcurrency do
                            task.wait()
                        end
                        activeCount = activeCount + 1

                        task.spawn(function()
                            local chunkMinX = mapMinX + cx * chunkSize
                            local chunkMinZ = mapMinZ + cz * chunkSize
                            local chunkCenterX = chunkMinX + chunkSize / 2
                            local chunkCenterZ = chunkMinZ + chunkSize / 2

                            -- Global height field index range for this chunk
                            local gxi0 = cx * chunkSize / VOXEL
                            local gzi0 = cz * chunkSize / VOXEL

                            --------------------------------------------------------
                            -- Pass 1: scan height bounds for Y centering
                            --------------------------------------------------------

                            local chunkMinY = huge
                            local chunkMaxY = -huge
                            for vx = 0, vertsPerChunkEdge - 1 do
                                local gxi = floor(gxi0 + vx * hFieldStep + 0.5) + 1
                                if gxi < 1 then gxi = 1 end
                                if gxi > gridW then gxi = gridW end
                                for vz = 0, vertsPerChunkEdge - 1 do
                                    local gzi = floor(gzi0 + vz * hFieldStep + 0.5) + 1
                                    if gzi < 1 then gzi = 1 end
                                    if gzi > gridD then gzi = gridD end
                                    local h = hField[gxi][gzi]
                                    if h < chunkMinY then chunkMinY = h end
                                    if h > chunkMaxY then chunkMaxY = h end
                                end
                            end
                            local chunkCenterY = (chunkMinY + chunkMaxY) / 2

                            --------------------------------------------------------
                            -- Pass 2: Create EditableMesh with chunk-local coords
                            --------------------------------------------------------

                            local mesh = AssetService:CreateEditableMesh({ FixedSize = false })

                            local vertexIds = table.create(vertsPerChunkEdge)
                            local colorIds  = table.create(vertsPerChunkEdge)

                            for vx = 0, vertsPerChunkEdge - 1 do
                                vertexIds[vx] = table.create(vertsPerChunkEdge)
                                colorIds[vx]  = table.create(vertsPerChunkEdge)

                                local worldX = chunkMinX + vx * vertexSpacing
                                local localX = worldX - chunkCenterX

                                local gxi = floor(gxi0 + vx * hFieldStep + 0.5) + 1
                                if gxi < 1 then gxi = 1 end
                                if gxi > gridW then gxi = gridW end

                                for vz = 0, vertsPerChunkEdge - 1 do
                                    local worldZ = chunkMinZ + vz * vertexSpacing
                                    local localZ = worldZ - chunkCenterZ

                                    local gzi = floor(gzi0 + vz * hFieldStep + 0.5) + 1
                                    if gzi < 1 then gzi = 1 end
                                    if gzi > gridD then gzi = gridD end

                                    local h = hField[gxi][gzi]
                                    local localY = h - chunkCenterY

                                    local vid = mesh:AddVertex(Vector3.new(localX, localY, localZ))
                                    vertexIds[vx][vz] = vid

                                    -- Vertex color: slope-based snow on Rock biomes
                                    local color = baseColor
                                    if useSnowOnSlopes then
                                        local hL = (gxi > 1) and hField[gxi-1][gzi] or h
                                        local hR = (gxi < gridW) and hField[gxi+1][gzi] or h
                                        local hD = (gzi > 1) and hField[gxi][gzi-1] or h
                                        local hU = (gzi < gridD) and hField[gxi][gzi+1] or h
                                        local dHdx = (hR - hL) / (2 * VOXEL)
                                        local dHdz = (hU - hD) / (2 * VOXEL)
                                        local slopeMag = sqrt(dHdx * dHdx + dHdz * dHdz)
                                        if slopeMag < slopeThreshold then
                                            color = SNOW_COLOR
                                        end
                                    end

                                    local cid = mesh:AddColor(color, 1)
                                    colorIds[vx][vz] = cid
                                end
                            end

                            -- Smooth normals via central difference
                            local normalIds = table.create(vertsPerChunkEdge)
                            for vx = 0, vertsPerChunkEdge - 1 do
                                normalIds[vx] = table.create(vertsPerChunkEdge)
                                local gxi = floor(gxi0 + vx * hFieldStep + 0.5) + 1
                                if gxi < 1 then gxi = 1 end
                                if gxi > gridW then gxi = gridW end

                                for vz = 0, vertsPerChunkEdge - 1 do
                                    local gzi = floor(gzi0 + vz * hFieldStep + 0.5) + 1
                                    if gzi < 1 then gzi = 1 end
                                    if gzi > gridD then gzi = gridD end

                                    local hC = hField[gxi][gzi]
                                    local hL = (gxi > 1) and hField[gxi-1][gzi] or hC
                                    local hR = (gxi < gridW) and hField[gxi+1][gzi] or hC
                                    local hD = (gzi > 1) and hField[gxi][gzi-1] or hC
                                    local hU = (gzi < gridD) and hField[gxi][gzi+1] or hC

                                    local nx = (hL - hR) / (2 * VOXEL)
                                    local nz = (hD - hU) / (2 * VOXEL)
                                    local ny = 1
                                    local len = sqrt(nx*nx + ny*ny + nz*nz)
                                    if len > 0.001 then
                                        nx, ny, nz = nx/len, ny/len, nz/len
                                    else
                                        nx, ny, nz = 0, 1, 0
                                    end

                                    normalIds[vx][vz] = mesh:AddNormal(Vector3.new(nx, ny, nz))
                                end
                            end

                            --------------------------------------------------------
                            -- Add triangles (2 per quad, 64×64 quads)
                            --------------------------------------------------------

                            for qx = 0, quadsPerEdge - 1 do
                                for qz = 0, quadsPerEdge - 1 do
                                    local v00 = vertexIds[qx][qz]
                                    local v10 = vertexIds[qx+1][qz]
                                    local v01 = vertexIds[qx][qz+1]
                                    local v11 = vertexIds[qx+1][qz+1]

                                    local n00 = normalIds[qx][qz]
                                    local n10 = normalIds[qx+1][qz]
                                    local n01 = normalIds[qx][qz+1]
                                    local n11 = normalIds[qx+1][qz+1]

                                    local c00 = colorIds[qx][qz]
                                    local c10 = colorIds[qx+1][qz]
                                    local c01 = colorIds[qx][qz+1]
                                    local c11 = colorIds[qx+1][qz+1]

                                    -- CCW from above = front face UP
                                    local fid1 = mesh:AddTriangle(v00, v10, v01)
                                    mesh:SetFaceNormals(fid1, { n00, n10, n01 })
                                    mesh:SetFaceColors(fid1, { c00, c10, c01 })

                                    local fid2 = mesh:AddTriangle(v10, v11, v01)
                                    mesh:SetFaceNormals(fid2, { n10, n11, n01 })
                                    mesh:SetFaceColors(fid2, { c10, c11, c01 })
                                end
                            end

                            --------------------------------------------------------
                            -- Bake to MeshPart + position at chunk center
                            --------------------------------------------------------

                            local ok, meshPart = pcall(function()
                                return AssetService:CreateMeshPartAsync(
                                    Content.fromObject(mesh)
                                )
                            end)

                            mesh:Destroy()

                            if ok and meshPart then
                                meshPart.Name = string.format("Chunk_%d_%d", cx, cz)
                                meshPart.Anchored = true
                                meshPart.CanCollide = true
                                meshPart.CFrame = CFrame.new(
                                    chunkCenterX, chunkCenterY, chunkCenterZ
                                )
                                meshPart.Material = Enum.Material.SmoothPlastic
                                meshPart.Parent = terrainFolder
                            else
                                warn(string.format(
                                    "[MeshTerrainPainterNode] Failed to bake chunk %d,%d: %s",
                                    cx, cz, tostring(meshPart)
                                ))
                            end

                            completedCount = completedCount + 1
                            activeCount = activeCount - 1
                        end)
                    end
                end

                -- Wait for all chunks to complete
                while completedCount < totalChunks do
                    task.wait()
                end

                -- Atomic parent to workspace
                terrainFolder.Parent = workspace

                print(string.format(
                    "[MeshTerrainPainterNode] Complete: %d chunks (%.2fs total)",
                    totalChunks, os.clock() - startTime
                ))

                print(string.format(
                    "[MeshTerrainPainterNode] Spawn set at (0, %.0f, 0)",
                    hfResult.spawn.position[2]
                ))

                selfRef.Out:Fire("nodeComplete", payload)
            end)
        end,
    },
}
