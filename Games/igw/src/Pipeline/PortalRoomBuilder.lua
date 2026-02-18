--[[
    IGW v2 Pipeline — PortalRoomBuilder
    Builds terrain for portal (spur) rooms using the TARGET biome's materials.

    Regular terrain painters (TerrainPainter, IceTerrainPainter) skip portal
    rooms. This node runs after PortalBlender and handles them from scratch:
    fill shell → carve interior → paint floor, all in the target biome's
    terrain materials and palette colors.

    Portal rooms are always cave-style (enclosed chambers) regardless of
    whether the target biome is outdoor. This makes gameplay sense — the
    portal is an enclosed transition space.

    Also tints the room zone volume purple and adds a purple PointLight
    to flood the room — clear visual grammar for portal rooms.

    Runs after PortalBlender, before DoorCutter.
--]]

-- Build valid terrain material set at load time by probing the engine.
local TERRAIN_MATERIALS = {}
do
    local terrain = workspace.Terrain
    for _, item in ipairs(Enum.Material:GetEnumItems()) do
        if item.Value ~= 0 then
            local ok = pcall(terrain.GetMaterialColor, terrain, item)
            if ok then
                TERRAIN_MATERIALS[item] = true
                TERRAIN_MATERIALS[item.Name] = item
            end
        end
    end
end

local PORTAL_COLOR = Color3.fromRGB(128, 0, 255)
local PORTAL_TRANSPARENCY = 0.3
local PORTAL_LIGHT_COLOR = Color3.fromRGB(160, 80, 255)
local PORTAL_LIGHT_MIN = 1
local PORTAL_LIGHT_MAX = 1.5
local PORTAL_LIGHT_RANGE = 30

return {
    name = "PortalRoomBuilder",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildPass = function(self, payload)
            local t0 = os.clock()
            local Dom = self._System.Dom
            local Canvas = Dom.Canvas
            local StyleBridge = self._System.StyleBridge
            local Styles = self._System.Styles
            local ClassResolver = self._System.ClassResolver

            local rooms = payload.rooms
            local doors = payload.doors or {}
            local portalAssignments = payload.portalAssignments or {}
            local allBiomes = payload.allBiomes or {}

            -- Index doors by child room
            local doorByChild = {}
            for _, door in ipairs(doors) do
                doorByChild[door.toRoom] = door
            end

            local builtCount = 0

            for roomId, targetBiomeName in pairs(portalAssignments) do
                local room = rooms[roomId]
                local targetBiome = allBiomes[targetBiomeName]
                if not (room and targetBiome) then continue end

                -- Resolve target terrain materials
                local wallName = targetBiome.terrainWall or "Rock"
                local floorName = targetBiome.terrainFloor or "CrackedLava"
                local wallMat = TERRAIN_MATERIALS[wallName] or TERRAIN_MATERIALS["Rock"]
                local floorMat = TERRAIN_MATERIALS[floorName] or TERRAIN_MATERIALS["Ground"]

                -- Set material colors from target biome palette
                local targetPalette = StyleBridge.resolvePalette(
                    targetBiome.paletteClass or "", Styles, ClassResolver
                )
                if targetPalette then
                    local terrain = workspace.Terrain
                    if wallMat and targetPalette.wallColor then
                        terrain:SetMaterialColor(wallMat, targetPalette.wallColor)
                    end
                    if floorMat and targetPalette.floorColor then
                        terrain:SetMaterialColor(floorMat, targetPalette.floorColor)
                    end
                end

                -- Build terrain: fill shell → carve interior → paint floor
                local pos = room.position
                local dims = room.dims

                -- Use buffer if available (orchestrator-managed), else fall back to Canvas
                local buf = payload.buffer

                if wallMat then
                    if buf then
                        buf:fillShell(pos, dims, 0, wallMat)
                    else
                        Canvas.fillShell(pos, dims, 0, wallMat)
                    end
                end
                if buf then
                    buf:carveInterior(pos, dims, 0)
                else
                    Canvas.carveInterior(pos, dims, 0)
                end
                if floorMat then
                    if buf then
                        buf:paintFloor(pos, dims, floorMat)
                    else
                        Canvas.paintFloor(pos, dims, floorMat)
                    end
                end

                -- Style the room zone volume — purple tint + flood light
                local container = payload.container
                if container then
                    local zonePart = container:FindFirstChild("RoomZone_" .. roomId, true)
                    if zonePart then
                        zonePart.Color = PORTAL_COLOR
                        zonePart.Transparency = PORTAL_TRANSPARENCY

                        local light = Instance.new("PointLight")
                        light.Color = PORTAL_LIGHT_COLOR
                        light.Brightness = PORTAL_LIGHT_MIN
                        light.Range = PORTAL_LIGHT_RANGE
                        light.Shadows = false
                        light.Parent = zonePart

                        local TweenService = game:GetService("TweenService")
                        local tween = TweenService:Create(light,
                            TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                            { Brightness = PORTAL_LIGHT_MAX }
                        )
                        tween:Play()
                    end
                end

                -- Place biome label SurfaceGui in the door opening
                local door = doorByChild[roomId]
                local parentRoom = room.parentId and rooms[room.parentId]
                if door and parentRoom and container then
                    local dc = door.center
                    local doorPos = Vector3.new(dc[1], dc[2], dc[3])
                    local parentCenter = Vector3.new(
                        parentRoom.position[1], parentRoom.position[2], parentRoom.position[3]
                    )

                    -- Orient sign to face the parent room
                    local lookDir = parentCenter - doorPos
                    local up = Vector3.new(0, 1, 0)
                    if math.abs(lookDir.Unit.Y) > 0.9 then
                        up = Vector3.new(0, 0, 1)
                    end
                    local signCF = CFrame.lookAt(doorPos, doorPos + lookDir, up)

                    local signPart = Instance.new("Part")
                    signPart.Name = "PortalSign_" .. roomId
                    signPart.Size = Vector3.new(door.width, door.height, 0.1)
                    signPart.CFrame = signCF
                    signPart.Anchored = true
                    signPart.CanCollide = false
                    signPart.Transparency = 1

                    local gui = Instance.new("SurfaceGui")
                    gui.Face = Enum.NormalId.Front
                    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
                    gui.PixelsPerStud = 20
                    gui.Parent = signPart

                    local label = Instance.new("TextLabel")
                    label.Size = UDim2.new(1, 0, 1, 0)
                    label.BackgroundTransparency = 1
                    label.Text = targetBiomeName:upper()
                    label.TextColor3 = PORTAL_LIGHT_COLOR
                    label.TextStrokeTransparency = 0.5
                    label.TextStrokeColor3 = Color3.new(0, 0, 0)
                    label.TextScaled = true
                    label.Font = Enum.Font.GothamBold
                    label.Parent = gui

                    signPart.Parent = container
                end

                builtCount = builtCount + 1
                print(string.format("[PortalRoomBuilder] Room %d → %s (wall: %s, floor: %s)",
                    roomId, targetBiomeName, wallName, floorName))
            end

            if builtCount > 0 then
                print(string.format("[PortalRoomBuilder] Built terrain for %d portal rooms — %.2fs", builtCount, os.clock() - t0))
            end

            self.Out:Fire("buildPass", payload)
        end,
    },
}
