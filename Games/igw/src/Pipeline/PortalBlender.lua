--[[
    IGW v2 Pipeline — PortalBlender
    Post-terrain: mixes target biome materials into the PARENT room's surface
    at the door hole connecting to each portal (spur) room.

    Creates a "leaking through" visual preview — e.g. grass/dirt scattered
    into a desert floor around the hole leading down to a meadow portal room.

    Portal room terrain itself is handled by PortalRoomBuilder (separate node).
    Runs after IceTerrainPainter, before PortalRoomBuilder.
--]]

-- Build valid terrain material set at load time by probing the engine.
-- GetMaterialColor only succeeds for materials terrain actually supports.
local TERRAIN_MATERIALS = {}
do
    local terrain = workspace.Terrain
    for _, item in ipairs(Enum.Material:GetEnumItems()) do
        if item.Value ~= 0 then -- skip Air/Plastic defaults
            local ok = pcall(terrain.GetMaterialColor, terrain, item)
            if ok then
                TERRAIN_MATERIALS[item] = true
                TERRAIN_MATERIALS[item.Name] = item
            end
        end
    end
end

local VOXEL = 4
local BLEED = 8 -- studs beyond door edge to spread blend

return {
    name = "PortalBlender",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildPass = function(self, payload)
            local Dom = self._System.Dom
            local Canvas = Dom.Canvas
            local rooms = payload.rooms
            local doors = payload.doors or {}
            local portalAssignments = payload.portalAssignments or {}
            local allBiomes = payload.allBiomes or {}

            -- Index doors by toRoom for fast lookup
            local doorByChild = {}
            for _, door in ipairs(doors) do
                doorByChild[door.toRoom] = door
            end

            local blendCount = 0

            for portalRoomId, targetBiomeName in pairs(portalAssignments) do
                local portalRoom = rooms[portalRoomId]
                local targetBiome = allBiomes[targetBiomeName]
                if not (portalRoom and targetBiome) then continue end

                local parentId = portalRoom.parentId
                local parentRoom = parentId and rooms[parentId]
                local door = doorByChild[portalRoomId]
                if not (parentRoom and door) then
                    warn(string.format("[PortalBlender] Room %d: missing parent or door", portalRoomId))
                    continue
                end

                -- Resolve target materials
                local targetWallName = targetBiome.terrainWall or "Rock"
                local targetFloorName = targetBiome.terrainFloor or "CrackedLava"
                local targetWallMat = TERRAIN_MATERIALS[targetWallName]
                local targetFloorMat = TERRAIN_MATERIALS[targetFloorName]

                if not (targetWallMat or targetFloorMat) then
                    warn(string.format("[PortalBlender] Room %d → %s: no valid terrain materials (%s/%s)",
                        portalRoomId, targetBiomeName, targetWallName, targetFloorName))
                    continue
                end

                -- Set material colors using target biome palette
                local StyleBridge = self._System.StyleBridge
                local Styles = self._System.Styles
                local ClassResolver = self._System.ClassResolver
                local targetPalette = StyleBridge.resolvePalette(
                    targetBiome.paletteClass or "", Styles, ClassResolver
                )
                if targetPalette then
                    local terrain = workspace.Terrain
                    if targetWallMat and targetPalette.wallColor then
                        terrain:SetMaterialColor(targetWallMat, targetPalette.wallColor)
                    end
                    if targetFloorMat and targetPalette.floorColor then
                        terrain:SetMaterialColor(targetFloorMat, targetPalette.floorColor)
                    end
                end

                -- Blend target terrain into parent room's door surface
                local dc = door.center
                local pPos = parentRoom.position
                local pDims = parentRoom.dims

                -- Use buffer if available (orchestrator-managed), else fall back to Canvas
                local buf = payload.buffer

                if door.axis == 2 then
                    -- Vertical door (floor/ceiling hole) — blend parent's floor surface
                    -- Use floor material since this is a horizontal surface
                    local mat = targetFloorMat or targetWallMat

                    -- Blend slab: door area + bleed, one voxel thick, at parent floor
                    local blendW = math.min(door.width + BLEED * 2, pDims[1])
                    local blendD = math.min(door.height + BLEED * 2, pDims[3])
                    local blendCF = CFrame.new(dc[1], pPos[2] - pDims[2] / 2 + VOXEL / 2, dc[3])
                    local blendSize = Vector3.new(blendW, VOXEL, blendD)

                    if buf then
                        buf:mixBlock(blendCF, blendSize, mat, 6, 0.3)
                    else
                        Canvas.mixBlock(blendCF, blendSize, mat, 6, 0.3)
                    end
                else
                    -- Horizontal door (wall opening) — blend parent's wall surface
                    -- Use wall material since this is a vertical surface
                    local mat = targetWallMat or targetFloorMat

                    -- Blend slab: door area + bleed, one voxel deep into the wall plane
                    local blendW = math.min(door.width + BLEED * 2, pDims[door.widthAxis])
                    local blendH = math.min(door.height + BLEED * 2, pDims[2])

                    -- Position: at door center but nudged into parent room
                    local cx, cy, cz = dc[1], dc[2], dc[3]

                    local sx, sy, sz
                    if door.axis == 1 then
                        -- X-axis wall: slab is thin in X, spans width (Z) and height (Y)
                        sx = VOXEL
                        sy = blendH
                        sz = blendW
                    else
                        -- Z-axis wall: slab is thin in Z, spans width (X) and height (Y)
                        sx = blendW
                        sy = blendH
                        sz = VOXEL
                    end

                    local blendCF = CFrame.new(cx, cy, cz)
                    local blendSize = Vector3.new(sx, sy, sz)

                    if buf then
                        buf:mixBlock(blendCF, blendSize, mat, 6, 0.3)
                    else
                        Canvas.mixBlock(blendCF, blendSize, mat, 6, 0.3)
                    end
                end

                blendCount = blendCount + 1
                print(string.format("[PortalBlender] Parent room %d blended near door to portal %d (%s: %s/%s)",
                    parentId, portalRoomId, targetBiomeName,
                    targetWallMat and targetWallName or "[skip]",
                    targetFloorMat and targetFloorName or "[skip]"))
            end

            if blendCount > 0 then
                print(string.format("[PortalBlender] Blended %d portal door surfaces", blendCount))
            end

            self.Out:Fire("buildPass", payload)
        end,
    },
}
