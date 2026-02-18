--[[
    IGW v2 Pipeline — IceTerrainPainter
    Outdoor terrain for ice/glacier biome.

    Unlike the cave TerrainPainter (fill shell → hollow → decorate), this
    painter only fills the floor plane with Snow terrain. Walls and ceiling
    are left open so daylight enters.

    Door-wall promotion: ShellBuilder marks all outdoor walls as ice-wall-clear
    (Transparency 1). This node detects which walls have doors and promotes
    them to ice-wall-solid (Transparency 0.4) via Dom.addClass/removeClass,
    so they render as translucent glacier ice. Non-door walls stay invisible.

    DoorCutter still runs after this to CSG-cut the visible door walls.
--]]

return {
    name = "IceTerrainPainter",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildPass = function(self, payload)
            local biome = payload.biome or {}

            -- Only process outdoor biomes; pass through otherwise
            if biome.terrainStyle ~= "outdoor" then
                self.Out:Fire("buildPass", payload)
                return
            end

            local Dom = self._System.Dom
            local Canvas = Dom.Canvas
            local StyleBridge = self._System.StyleBridge
            local Styles = self._System.Styles
            local ClassResolver = self._System.ClassResolver

            local rooms = payload.rooms
            local doors = payload.doors or {}
            local pads = payload.pads or {}
            local portalAssignments = payload.portalAssignments or {}
            local regionNum = payload.regionNum or 1
            local paletteClass = payload.paletteClass or StyleBridge.getPaletteClass(regionNum)

            local palette = StyleBridge.resolvePalette(paletteClass, Styles, ClassResolver)

            local wallMaterial = Enum.Material[biome.terrainWall or "Glacier"]
            local floorMaterial = Enum.Material[biome.terrainFloor or "Snow"]
            local wallMixMaterial = biome.terrainWallMix and Enum.Material[biome.terrainWallMix] or nil

            -- Set terrain material colors for biome palette
            Canvas.setMaterialColors(palette, wallMaterial, floorMaterial)

            -- Tint mix material with same wall color
            if wallMixMaterial and palette.wallColor then
                local terrain = workspace.Terrain
                terrain:SetMaterialColor(wallMixMaterial, palette.wallColor)
            end

            local VOXEL = Canvas.getVoxelSize()

            ----------------------------------------------------------------
            -- Build door-face map per room (same logic as LightBuilder)
            ----------------------------------------------------------------
            local roomDoorFaces = {}
            for _, door in ipairs(doors) do
                local roomA = rooms[door.fromRoom]
                local roomB = rooms[door.toRoom]
                if not (roomA and roomB) then continue end

                if door.axis == 1 then
                    if roomA.position[1] < roomB.position[1] then
                        roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                        roomDoorFaces[door.fromRoom]["E"] = true
                        roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                        roomDoorFaces[door.toRoom]["W"] = true
                    else
                        roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                        roomDoorFaces[door.fromRoom]["W"] = true
                        roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                        roomDoorFaces[door.toRoom]["E"] = true
                    end
                elseif door.axis == 3 then
                    if roomA.position[3] < roomB.position[3] then
                        roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                        roomDoorFaces[door.fromRoom]["N"] = true
                        roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                        roomDoorFaces[door.toRoom]["S"] = true
                    else
                        roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                        roomDoorFaces[door.fromRoom]["S"] = true
                        roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                        roomDoorFaces[door.toRoom]["N"] = true
                    end
                end
            end

            ----------------------------------------------------------------
            -- Terrain: door-wall slabs → carve interiors → paint floors
            -- (order matters: carve before floor so voxel overlap doesn't
            -- erase the floor, then floor re-fills the bottom layer)
            ----------------------------------------------------------------

            -- Use buffer if available (orchestrator-managed), else fall back to Canvas
            local buf = payload.buffer

            -- Fill terrain slabs on door walls so DoorCutter can carve through them
            -- (skip portal rooms — PortalRoomBuilder handles those)
            for roomId, doorFaces in pairs(roomDoorFaces) do
                local room = rooms[roomId]
                if not room then continue end
                if portalAssignments[roomId] then continue end
                local pos = room.position
                local dims = room.dims

                for face in pairs(doorFaces) do
                    local cf, sz
                    if face == "N" then
                        cf = CFrame.new(pos[1], pos[2], pos[3] + dims[3]/2 + VOXEL/2)
                        sz = Vector3.new(dims[1] + 2*VOXEL, dims[2] + 2*VOXEL, VOXEL * 2)
                    elseif face == "S" then
                        cf = CFrame.new(pos[1], pos[2], pos[3] - dims[3]/2 - VOXEL/2)
                        sz = Vector3.new(dims[1] + 2*VOXEL, dims[2] + 2*VOXEL, VOXEL * 2)
                    elseif face == "E" then
                        cf = CFrame.new(pos[1] + dims[1]/2 + VOXEL/2, pos[2], pos[3])
                        sz = Vector3.new(VOXEL * 2, dims[2] + 2*VOXEL, dims[3] + 2*VOXEL)
                    elseif face == "W" then
                        cf = CFrame.new(pos[1] - dims[1]/2 - VOXEL/2, pos[2], pos[3])
                        sz = Vector3.new(VOXEL * 2, dims[2] + 2*VOXEL, dims[3] + 2*VOXEL)
                    end
                    if cf then
                        if buf then
                            buf:fillBlock(cf, sz, wallMaterial)
                            if wallMixMaterial then
                                buf:mixBlock(cf, sz, wallMixMaterial, 6, 0.3)
                            end
                        else
                            Canvas.fillBlock(cf, sz, wallMaterial)
                            if wallMixMaterial then
                                Canvas.mixBlock(cf, sz, wallMixMaterial, 6, 0.3)
                            end
                        end
                    end
                end
            end

            -- Carve interiors so door-wall slabs don't bleed into rooms (skip portal rooms)
            for id, room in pairs(rooms) do
                if not portalAssignments[id] then
                    if buf then
                        buf:carveInterior(room.position, room.dims, 0)
                    else
                        Canvas.carveInterior(room.position, room.dims, 0)
                    end
                end
            end

            -- Paint floors AFTER carve (skip portal rooms)
            for id, room in pairs(rooms) do
                if not portalAssignments[id] then
                    if buf then
                        buf:paintFloor(room.position, room.dims, floorMaterial)
                    else
                        Canvas.paintFloor(room.position, room.dims, floorMaterial)
                    end
                end
            end

            -- Carve clearance around pads
            for _, pad in ipairs(pads) do
                local padPos = Vector3.new(pad.position[1], pad.position[2], pad.position[3])
                local padSize = Vector3.new(6, 1, 6)
                if buf then
                    buf:carveMargin(CFrame.new(padPos), padSize, 2)
                else
                    Canvas.carveMargin(CFrame.new(padPos), padSize, 2)
                end
            end

            ----------------------------------------------------------------
            -- DOM: promote door walls ice-wall-clear → ice-wall-solid
            ----------------------------------------------------------------

            local roomModels = {}
            for _, child in ipairs(Dom.getChildren(payload.dom)) do
                local rid = Dom.getAttribute(child, "RoomId")
                if rid then
                    roomModels[rid] = child
                end
            end

            local promotedCount = 0
            for roomId, doorFaces in pairs(roomDoorFaces) do
                local roomNode = roomModels[roomId]
                if not roomNode then continue end

                for _, child in ipairs(Dom.getChildren(roomNode)) do
                    local name = Dom.getAttribute(child, "Name") or ""
                    local face = name:match("^Wall_(%u)$")
                    if face and doorFaces[face] then
                        Dom.removeClass(child, "ice-wall-clear")
                        Dom.addClass(child, biome.doorWallClass or "ice-wall-solid")
                        promotedCount = promotedCount + 1
                    end
                end
            end

            local roomCount = 0
            for _ in pairs(rooms) do roomCount = roomCount + 1 end

            print(string.format(
                "[IceTerrainPainter] Floor + %d door-wall slabs for %d rooms, promoted %d wall Parts",
                #doors, roomCount, promotedCount
            ))

            payload.roomCount = roomCount
            payload.doorCount = #doors

            self.Out:Fire("buildPass", payload)
        end,
    },
}
