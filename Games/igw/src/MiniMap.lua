--[[
    IGW v2 — MiniMap
    Client-side full-screen 3D map view using ViewportFrame.
    DOM-driven: observes workspace for RoomZone_ parts and builds minimap
    geometry from ReplicatedStorage (server builds CSG'd walls per-room,
    client clones). Cutaway view: floors always, walls only where doors
    are with CSG holes.

    Fog-of-war states:
        visited  (orange)  — player entered room
        adjacent (grey)    — neighbor of visited room
        unknown            — room not yet visited/adjacent (invisible)

    Controls:
        M / ButtonY (Triangle): Toggle map
        WASD / Left Stick: Pan map
        Arrow Keys / Right Stick: Rotate camera
        Q/E / L1/R1: Zoom out/in

    Signals:
        onBuildMiniMap({ rooms, doors, adjacency, spawnPos, containerName, mapCenter })
        onMapReady() → enables map opening (called after spawn)
--]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local SCALE = 1 / 100

-- Fog-of-war colors
local VISITED_TRANSPARENCY = 0.3
local ADJACENT_TRANSPARENCY = 0.55
local VISITED_COLOR = Color3.fromRGB(220, 160, 80)
local ADJACENT_COLOR = Color3.fromRGB(130, 130, 140)

-- Player marker
local MARKER_COLOR = Color3.fromRGB(80, 255, 120)
local MARKER_SIZE = 0.25

-- Shared input rate factor (per-second base, halved from original)
local INPUT_RATE = 1.5

return {
    name = "MiniMap",
    domain = "client",

    Sys = {
        onInit = function(self)
            self._screenGui = nil
            self._viewport = nil
            self._camera = nil
            self._worldModel = nil
            self._isOpen = false
            self._canOpen = false
            self._hasModel = false
            self._cameraDistance = 5
            self._initCamDist = 5
            self._cameraYaw = 0
            self._cameraPitch = 45
            self._inputClaim = nil
            self._toggleConn = nil
            self._zoomDir = 0  -- -1 = zoom out (L1 held), +1 = zoom in (R1 held)

            -- Pan offset (map-space, added to pivot)
            self._panX = 0
            self._panZ = 0

            -- Keyboard held-key state (for per-frame pan/rotate)
            self._heldKeys = {}
            self._inputConns = {}

            -- Fog-of-war state
            self._rooms = {}
            self._visitedRooms = {}
            self._currentRoom = nil
            self._adjacency = {}
            self._roomClones = {}   -- { [roomId] = { {clone, isFloor}, ... } }
            self._builtRooms = {}   -- { [roomId] = true } — tracks which rooms have geometry
            self._zoneConns = {}
            self._positionConn = nil

            -- Geo observer (ReplicatedStorage.MiniMapGeo)
            self._geoConns = {}

            -- Player marker
            self._playerMarker = nil
            self._mapCenter = { 0, 0, 0 }
            self._markerConn = nil

            self:_createUI()
        end,

        onStart = function(self)
            print("[MiniMap] onStart — binding ButtonY + M key")
            local selfRef = self
            self._toggleConn = UserInputService.InputBegan:Connect(function(input, processed)
                if processed then return end
                if not selfRef._isOpen
                    and (input.KeyCode == Enum.KeyCode.ButtonY
                      or input.KeyCode == Enum.KeyCode.M) then
                    selfRef:_toggleMap()
                end
            end)
        end,

        onStop = function(self)
            self:_disconnectZones()
            self:_disconnectGeo()
            if self._markerConn then
                self._markerConn:Disconnect()
                self._markerConn = nil
            end
            if self._toggleConn then
                self._toggleConn:Disconnect()
            end
            if self._inputClaim then
                self._inputClaim:release()
                self._inputClaim = nil
            end
            ContextActionService:UnbindAction("MiniMapRotate")
            ContextActionService:UnbindAction("MiniMapPan")
            ContextActionService:UnbindAction("MiniMapZoomIn")
            ContextActionService:UnbindAction("MiniMapZoomOut")
            ContextActionService:UnbindAction("MiniMapClose")
            if self._screenGui then
                self._screenGui:Destroy()
            end
        end,
    },

    ------------------------------------------------------------------------
    -- UI
    ------------------------------------------------------------------------

    _createUI = function(self)
        local player = Players.LocalPlayer
        if not player then return end
        local playerGui = player:WaitForChild("PlayerGui")

        local existing = playerGui:FindFirstChild("MiniMap")
        if existing then existing:Destroy() end

        local sg = Instance.new("ScreenGui")
        sg.Name = "MiniMap"
        sg.ResetOnSpawn = false
        sg.DisplayOrder = 999
        sg.IgnoreGuiInset = true
        sg.Enabled = false
        sg.Parent = playerGui

        -- Fullscreen black backdrop
        local bg = Instance.new("Frame")
        bg.Name = "Backdrop"
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        bg.BackgroundTransparency = 0.5
        bg.BorderSizePixel = 0
        bg.Parent = sg

        local vp = Instance.new("ViewportFrame")
        vp.Name = "Viewport"
        vp.Size = UDim2.new(1, 0, 1, 0)
        vp.BackgroundTransparency = 1
        vp.Parent = sg

        local cam = Instance.new("Camera")
        cam.Name = "MapCamera"
        cam.FieldOfView = 50
        cam.Parent = vp
        vp.CurrentCamera = cam

        local wm = Instance.new("WorldModel")
        wm.Name = "MapModel"
        wm.Parent = vp

        -- Room count label (top-left)
        local label = Instance.new("TextLabel")
        label.Name = "RoomCount"
        label.Size = UDim2.new(0, 200, 0, 30)
        label.Position = UDim2.new(0, 20, 0, 20)
        label.BackgroundTransparency = 0.5
        label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 16
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = ""
        label.Parent = sg

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = label

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 8)
        pad.Parent = label

        -- Loading overlay (shown while server CSG is in progress)
        local loading = Instance.new("TextLabel")
        loading.Name = "LoadingOverlay"
        loading.Size = UDim2.new(1, 0, 1, 0)
        loading.BackgroundTransparency = 0.7
        loading.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        loading.TextColor3 = Color3.fromRGB(255, 255, 255)
        loading.Font = Enum.Font.GothamBold
        loading.TextSize = 24
        loading.Text = "Building Map..."
        loading.Visible = false
        loading.ZIndex = 10
        loading.Parent = sg

        self._screenGui = sg
        self._viewport = vp
        self._camera = cam
        self._worldModel = wm
        self._roomCountLabel = label
        self._loadingOverlay = loading
    end,

    ------------------------------------------------------------------------
    -- MAP TOGGLE
    ------------------------------------------------------------------------

    _toggleMap = function(self)
        if self._isOpen then
            self:_closeMap()
        else
            self:_openMap()
        end
    end,

    _openMap = function(self)
        if self._isOpen then return end
        if not self._canOpen then
            print("[MiniMap] _openMap blocked: _canOpen=false (mapReady signal not received)")
            return
        end
        if not self._hasModel then
            print("[MiniMap] _openMap blocked: _hasModel=false (buildMiniMap signal not received)")
            return
        end

        self._isOpen = true
        self._panX = 0
        self._panZ = 0
        if self._screenGui then
            self._screenGui.Enabled = true
        end

        self:_updateDisplay()
        self:_updateMarker()
        self:_updateCamera()
        self:_updateLoadingState()
        self:_startInput()
        self:_startMarkerTracking()
    end,

    _closeMap = function(self)
        if not self._isOpen then return end

        self._isOpen = false
        self._zoomDir = 0
        if self._loadingOverlay then
            self._loadingOverlay.Visible = false
        end
        if self._screenGui then
            self._screenGui.Enabled = false
        end

        self:_stopMarkerTracking()
        self:_stopInput()
    end,

    ------------------------------------------------------------------------
    -- INPUT HANDLING
    ------------------------------------------------------------------------

    _startInput = function(self)
        local InputCapture = _G.Warren.System.InputCapture
        if InputCapture then
            self._inputClaim = InputCapture.claim({}, {
                sinkMovement = true,
            })
        end

        local selfRef = self

        -- Keyboard held-key tracking for per-frame pan/rotate
        self._heldKeys = {}
        self._inputConns = {}
        table.insert(self._inputConns, UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            selfRef._heldKeys[input.KeyCode] = true
        end))
        table.insert(self._inputConns, UserInputService.InputEnded:Connect(function(input)
            selfRef._heldKeys[input.KeyCode] = nil
        end))

        -- Mouse scroll wheel zoom
        table.insert(self._inputConns, UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseWheel then
                local scroll = input.Position.Z  -- +1 scroll up, -1 scroll down
                local factor = 1 - scroll * 0.15
                selfRef._cameraDistance = math.clamp(
                    selfRef._cameraDistance * factor,
                    selfRef._initCamDist * 0.05,
                    selfRef._initCamDist * 4
                )
                selfRef:_updateCamera()
            end
        end))

        -- Gamepad: right stick rotate
        ContextActionService:BindAction(
            "MiniMapRotate",
            function(_, inputState, inputObject)
                if inputState == Enum.UserInputState.Change then
                    local pos = inputObject.Position
                    if math.abs(pos.X) > 0.1 then
                        selfRef._cameraYaw = selfRef._cameraYaw - pos.X * INPUT_RATE
                    end
                    if math.abs(pos.Y) > 0.1 then
                        selfRef._cameraPitch = math.clamp(
                            selfRef._cameraPitch + pos.Y * INPUT_RATE,
                            -89, 89
                        )
                    end
                    selfRef:_updateCamera()
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.Thumbstick2
        )

        -- Gamepad: left stick pan
        ContextActionService:BindAction(
            "MiniMapPan",
            function(_, inputState, inputObject)
                if inputState == Enum.UserInputState.Change then
                    local pos = inputObject.Position
                    local speed = selfRef._cameraDistance * (INPUT_RATE / 2) * 0.02
                    local yawRad = math.rad(selfRef._cameraYaw)
                    if math.abs(pos.X) > 0.1 then
                        selfRef._panX = selfRef._panX + math.cos(yawRad) * pos.X * speed
                        selfRef._panZ = selfRef._panZ - math.sin(yawRad) * pos.X * speed
                    end
                    if math.abs(pos.Y) > 0.1 then
                        selfRef._panX = selfRef._panX + math.sin(yawRad) * pos.Y * speed
                        selfRef._panZ = selfRef._panZ + math.cos(yawRad) * pos.Y * speed
                    end
                    selfRef:_updateCamera()
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.Thumbstick1
        )

        -- Zoom: L1/Q = out, R1/E = in
        ContextActionService:BindAction(
            "MiniMapZoomOut",
            function(_, inputState)
                if inputState == Enum.UserInputState.Begin then
                    selfRef._zoomDir = -1
                elseif inputState == Enum.UserInputState.End then
                    if selfRef._zoomDir == -1 then selfRef._zoomDir = 0 end
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.ButtonL1,
            Enum.KeyCode.Q
        )

        ContextActionService:BindAction(
            "MiniMapZoomIn",
            function(_, inputState)
                if inputState == Enum.UserInputState.Begin then
                    selfRef._zoomDir = 1
                elseif inputState == Enum.UserInputState.End then
                    if selfRef._zoomDir == 1 then selfRef._zoomDir = 0 end
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.ButtonR1,
            Enum.KeyCode.E
        )

        -- Close: ButtonY / M
        ContextActionService:BindAction(
            "MiniMapClose",
            function(_, inputState)
                if inputState == Enum.UserInputState.Begin then
                    selfRef:_closeMap()
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.ButtonY,
            Enum.KeyCode.M
        )
    end,

    _stopInput = function(self)
        if self._inputClaim then
            self._inputClaim:release()
            self._inputClaim = nil
        end
        for _, conn in ipairs(self._inputConns or {}) do
            conn:Disconnect()
        end
        self._inputConns = {}
        self._heldKeys = {}
        ContextActionService:UnbindAction("MiniMapRotate")
        ContextActionService:UnbindAction("MiniMapPan")
        ContextActionService:UnbindAction("MiniMapZoomIn")
        ContextActionService:UnbindAction("MiniMapZoomOut")
        ContextActionService:UnbindAction("MiniMapClose")
    end,

    ------------------------------------------------------------------------
    -- CAMERA
    ------------------------------------------------------------------------

    _getPlayerMapPos = function(self)
        local player = Players.LocalPlayer
        local char = player and player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return Vector3.new(0, 0, 0) end

        local mc = self._mapCenter
        return Vector3.new(
            (hrp.Position.X - mc[1]) * SCALE,
            (hrp.Position.Y - mc[2]) * SCALE,
            (hrp.Position.Z - mc[3]) * SCALE
        )
    end,

    _updateCamera = function(self)
        local cam = self._camera
        if not cam then return end

        local yawRad = math.rad(self._cameraYaw)
        local pitchRad = math.rad(self._cameraPitch)
        local dist = self._cameraDistance

        local offsetX = math.sin(yawRad) * math.cos(pitchRad) * dist
        local offsetY = math.sin(pitchRad) * dist
        local offsetZ = math.cos(yawRad) * math.cos(pitchRad) * dist

        local pivot = self:_getPlayerMapPos() + Vector3.new(self._panX, 0, self._panZ)
        local camPos = pivot + Vector3.new(offsetX, offsetY, offsetZ)

        cam.CFrame = CFrame.lookAt(camPos, pivot)
    end,

    ------------------------------------------------------------------------
    -- PLAYER MARKER — live position on the map
    ------------------------------------------------------------------------

    _createMarker = function(self)
        if self._playerMarker then return end

        local marker = Instance.new("Part")
        marker.Name = "PlayerMarker"
        marker.Shape = Enum.PartType.Ball
        marker.Size = Vector3.new(MARKER_SIZE, MARKER_SIZE, MARKER_SIZE)
        marker.Color = MARKER_COLOR
        marker.Material = Enum.Material.Neon
        marker.Anchored = true
        marker.CanCollide = false
        marker.Transparency = 0
        marker.Parent = self._worldModel

        self._playerMarker = marker
    end,

    _updateMarker = function(self)
        if not self._playerMarker then return end

        local player = Players.LocalPlayer
        local char = player and player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local mc = self._mapCenter
        local relX = (hrp.Position.X - mc[1]) * SCALE
        local relY = (hrp.Position.Y - mc[2]) * SCALE
        local relZ = (hrp.Position.Z - mc[3]) * SCALE

        self._playerMarker.Position = Vector3.new(relX, relY, relZ)
    end,

    _startMarkerTracking = function(self)
        if self._markerConn then return end
        local selfRef = self
        self._markerConn = RunService.RenderStepped:Connect(function(dt)
            local keys = selfRef._heldKeys or {}

            -- Fluid zoom: apply per-frame while L1/R1/Q/E held
            if selfRef._zoomDir ~= 0 then
                local zoomRate = INPUT_RATE * dt
                local factor = 1 + zoomRate * (-selfRef._zoomDir)
                selfRef._cameraDistance = math.clamp(
                    selfRef._cameraDistance * factor,
                    selfRef._initCamDist * 0.05,
                    selfRef._initCamDist * 4
                )
            end

            -- Keyboard pan: WASD (yaw-relative)
            local panSpeed = selfRef._cameraDistance * 0.02
            local yawRad = math.rad(selfRef._cameraYaw)
            if keys[Enum.KeyCode.W] then
                selfRef._panX = selfRef._panX + math.sin(yawRad) * panSpeed
                selfRef._panZ = selfRef._panZ + math.cos(yawRad) * panSpeed
            end
            if keys[Enum.KeyCode.S] then
                selfRef._panX = selfRef._panX - math.sin(yawRad) * panSpeed
                selfRef._panZ = selfRef._panZ - math.cos(yawRad) * panSpeed
            end
            if keys[Enum.KeyCode.A] then
                selfRef._panX = selfRef._panX - math.cos(yawRad) * panSpeed
                selfRef._panZ = selfRef._panZ + math.sin(yawRad) * panSpeed
            end
            if keys[Enum.KeyCode.D] then
                selfRef._panX = selfRef._panX + math.cos(yawRad) * panSpeed
                selfRef._panZ = selfRef._panZ - math.sin(yawRad) * panSpeed
            end

            -- Keyboard rotate: arrow keys
            local rotSpeed = 90 * dt  -- degrees per second
            if keys[Enum.KeyCode.Left] then
                selfRef._cameraYaw = selfRef._cameraYaw + rotSpeed
            end
            if keys[Enum.KeyCode.Right] then
                selfRef._cameraYaw = selfRef._cameraYaw - rotSpeed
            end
            if keys[Enum.KeyCode.Up] then
                selfRef._cameraPitch = math.clamp(selfRef._cameraPitch + rotSpeed, -89, 89)
            end
            if keys[Enum.KeyCode.Down] then
                selfRef._cameraPitch = math.clamp(selfRef._cameraPitch - rotSpeed, -89, 89)
            end

            selfRef:_updateMarker()
            selfRef:_updateCamera()
        end)
    end,

    _stopMarkerTracking = function(self)
        if self._markerConn then
            self._markerConn:Disconnect()
            self._markerConn = nil
        end
    end,

    ------------------------------------------------------------------------
    -- ZONE DETECTION — track which rooms the player has visited
    -- Deferred: waits for workspace replication via DescendantAdded
    ------------------------------------------------------------------------

    _disconnectZones = function(self)
        for _, conn in ipairs(self._zoneConns) do
            conn:Disconnect()
        end
        self._zoneConns = {}
    end,

    _connectZones = function(self, containerName)
        self:_disconnectZones()

        local selfRef = self

        task.spawn(function()
            local container = workspace:WaitForChild(containerName or "Dungeon", 30)
            if not container then return end

            local function connectZone(desc)
                if not desc:IsA("BasePart") then return end
                if not desc.Name:match("^RoomZone_") then return end
                local roomId = tonumber(desc.Name:match("^RoomZone_(%d+)$"))
                if not roomId then return end

                desc.CanTouch = true

                table.insert(selfRef._zoneConns, desc.Touched:Connect(function(hit)
                    local player = Players.LocalPlayer
                    if not player or not player.Character then return end
                    if not hit:IsDescendantOf(player.Character) then return end

                    if not selfRef._visitedRooms[roomId] then
                        selfRef._visitedRooms[roomId] = true
                        selfRef:_updateDisplay()
                        selfRef:_updateLabel()
                    end
                    if selfRef._currentRoom ~= roomId then
                        selfRef._currentRoom = roomId
                    end
                end))
            end

            for _, desc in ipairs(container:GetDescendants()) do
                connectZone(desc)
            end

            table.insert(selfRef._zoneConns, container.DescendantAdded:Connect(function(desc)
                connectZone(desc)
            end))
        end)
    end,

    ------------------------------------------------------------------------
    -- INITIAL ROOM DETECTION — pure data, no workspace dependency
    ------------------------------------------------------------------------

    _detectInitialRoom = function(self, spawnPos)
        if not spawnPos or type(spawnPos) ~= "table" then return end
        local sx, sy, sz = spawnPos[1], spawnPos[2], spawnPos[3]
        if not (sx and sy and sz) then return end

        for roomId, room in pairs(self._rooms) do
            local p = room.position
            local d = room.dims
            if sx >= p[1] - d[1]/2 and sx <= p[1] + d[1]/2
                and sy >= p[2] - d[2]/2 and sy <= p[2] + d[2]/2
                and sz >= p[3] - d[3]/2 and sz <= p[3] + d[3]/2 then
                self._currentRoom = roomId
                self._visitedRooms[roomId] = true
                return
            end
        end

        -- Fallback: mark first room
        local firstId = next(self._rooms)
        if firstId then
            self._currentRoom = firstId
            self._visitedRooms[firstId] = true
        end
    end,

    ------------------------------------------------------------------------
    -- FOG-OF-WAR DISPLAY
    ------------------------------------------------------------------------

    _updateDisplay = function(self)
        -- Determine visibility: visited (orange), adjacent (grey), unknown (invisible)
        local showState = {}

        for roomId in pairs(self._visitedRooms) do
            showState[roomId] = "visited"
        end

        for roomId in pairs(self._visitedRooms) do
            for _, neighborId in ipairs(self._adjacency[roomId] or {}) do
                if not showState[neighborId] then
                    showState[neighborId] = "adjacent"
                end
            end
        end

        -- Apply to clones (proximity CSG means distant rooms have no geometry)
        for roomId, clones in pairs(self._roomClones) do
            local state = showState[roomId]
            for _, entry in ipairs(clones) do
                if state == "visited" then
                    entry.clone.Transparency = VISITED_TRANSPARENCY
                    entry.clone.Color = VISITED_COLOR
                elseif state == "adjacent" then
                    entry.clone.Transparency = ADJACENT_TRANSPARENCY
                    entry.clone.Color = ADJACENT_COLOR
                else
                    entry.clone.Transparency = 1
                end
            end
        end
    end,

    _updateLabel = function(self)
        if not self._roomCountLabel then return end
        local visitedCount = 0
        for _ in pairs(self._visitedRooms) do visitedCount = visitedCount + 1 end
        local totalCount = 0
        for _ in pairs(self._rooms) do totalCount = totalCount + 1 end
        self._roomCountLabel.Text = string.format("  ROOMS: %d / %d", visitedCount, totalCount)
    end,

    _updateLoadingState = function(self)
        if not self._loadingOverlay then return end
        local totalRooms = 0
        for _ in pairs(self._rooms) do totalRooms = totalRooms + 1 end
        local builtRooms = 0
        for _ in pairs(self._builtRooms) do builtRooms = builtRooms + 1 end

        if totalRooms > 0 and builtRooms < totalRooms then
            self._loadingOverlay.Text = string.format("Building Map... %d / %d", builtRooms, totalRooms)
            self._loadingOverlay.Visible = true
        else
            self._loadingOverlay.Visible = false
        end
    end,

    ------------------------------------------------------------------------
    -- ROOM GEOMETRY — clone from ReplicatedStorage.MiniMapGeo
    --
    -- Server builds CSG'd walls + floors, scales to 1/100, puts in
    -- ReplicatedStorage. Client just clones into ViewportFrame.
    ------------------------------------------------------------------------

    _cloneRoomGeo = function(self, roomModel)
        local roomId = roomModel:GetAttribute("RoomId")
        if not roomId or self._builtRooms[roomId] then return end

        local clones = {}
        for _, child in ipairs(roomModel:GetChildren()) do
            if child:IsA("BasePart") or child:IsA("UnionOperation") then
                local clone = child:Clone()
                clone.Anchored = true
                clone.CanCollide = false
                clone.Transparency = 1  -- starts hidden, _updateDisplay sets visibility
                clone.Parent = self._worldModel
                table.insert(clones, {
                    clone = clone,
                    isFloor = child:GetAttribute("IsFloor") == true,
                })
            end
        end

        -- Only mark as built if we produced clones (children may not have replicated yet)
        if #clones > 0 then
            self._builtRooms[roomId] = true
            self._roomClones[roomId] = clones
        end
    end,

    _connectGeo = function(self)
        self:_disconnectGeo()
        local RS = game:GetService("ReplicatedStorage")
        local selfRef = self

        local geoFolder = RS:FindFirstChild("MiniMapGeo")
        if geoFolder then
            -- Clone rooms already built by server
            for _, child in ipairs(geoFolder:GetChildren()) do
                selfRef:_cloneRoomGeo(child)
            end
            selfRef:_updateDisplay()
            selfRef:_updateLoadingState()
        end

        -- Watch for new rooms as server CSG completes them incrementally
        task.spawn(function()
            local folder = RS:WaitForChild("MiniMapGeo", 30)
            if not folder then return end
            table.insert(selfRef._geoConns, folder.ChildAdded:Connect(function(child)
                -- Wait for children to replicate (server adds children before
                -- parenting the model, but replication may split across frames)
                task.spawn(function()
                    if #child:GetChildren() == 0 then
                        child.ChildAdded:Wait()
                    end
                    selfRef:_cloneRoomGeo(child)
                    selfRef:_updateDisplay()
                    selfRef:_updateLoadingState()
                end)
            end))
        end)
    end,

    _disconnectGeo = function(self)
        for _, conn in ipairs(self._geoConns) do
            conn:Disconnect()
        end
        self._geoConns = {}
    end,

    ------------------------------------------------------------------------
    -- MODEL BUILDING — store data, camera setup, NO geometry
    ------------------------------------------------------------------------

    _buildModel = function(self, data)
        -- Clear existing
        if self._worldModel then
            self._worldModel:ClearAllChildren()
        end
        self._hasModel = false
        self._rooms = {}
        self._roomClones = {}
        self._builtRooms = {}
        self._visitedRooms = {}
        self._currentRoom = nil
        self._playerMarker = nil
        self:_disconnectZones()
        self:_disconnectGeo()

        local spawnPos = data.spawnPos
        local containerName = data.containerName

        -- Normalize all table keys to numbers (RemoteEvent may stringify them)
        local rooms = {}
        for k, v in pairs(data.rooms or {}) do
            rooms[tonumber(k) or k] = v
        end
        local adjacency = {}
        for k, v in pairs(data.adjacency or {}) do
            local nk = tonumber(k) or k
            local normalized = {}
            for _, neighborId in ipairs(v) do
                table.insert(normalized, tonumber(neighborId) or neighborId)
            end
            adjacency[nk] = normalized
        end

        self._rooms = rooms
        self._adjacency = adjacency

        -- Use server-provided mapCenter (matches geometry positions exactly)
        if data.mapCenter then
            self._mapCenter = data.mapCenter
        else
            -- Fallback: compute from room data
            local minX, maxX = math.huge, -math.huge
            local minY, maxY = math.huge, -math.huge
            local minZ, maxZ = math.huge, -math.huge
            for _, room in pairs(rooms) do
                local p = room.position
                local d = room.dims
                minX = math.min(minX, p[1] - d[1]/2)
                maxX = math.max(maxX, p[1] + d[1]/2)
                minY = math.min(minY, p[2] - d[2]/2)
                maxY = math.max(maxY, p[2] + d[2]/2)
                minZ = math.min(minZ, p[3] - d[3]/2)
                maxZ = math.max(maxZ, p[3] + d[3]/2)
            end
            self._mapCenter = {
                (minX + maxX) / 2,
                (minY + maxY) / 2,
                (minZ + maxZ) / 2,
            }
        end

        -- Count rooms for camera distance
        local roomCount = 0
        local minX, maxX = math.huge, -math.huge
        local minZ, maxZ = math.huge, -math.huge
        for _, room in pairs(rooms) do
            roomCount = roomCount + 1
            local p = room.position
            local d = room.dims
            minX = math.min(minX, p[1] - d[1]/2)
            maxX = math.max(maxX, p[1] + d[1]/2)
            minZ = math.min(minZ, p[3] - d[3]/2)
            maxZ = math.max(maxZ, p[3] + d[3]/2)
        end

        if roomCount == 0 then
            warn("[MiniMap] No rooms in data")
            return
        end

        -- Camera distance from extents
        local extentX = (maxX - minX) / 2
        local extentZ = (maxZ - minZ) / 2
        local maxExtent = math.max(extentX, extentZ)
        self._cameraDistance = maxExtent * SCALE * 2 / 6
        self._initCamDist = self._cameraDistance

        self._hasModel = true

        -- Player marker
        self:_createMarker()

        -- Detect initial room from data (no workspace dependency)
        self:_detectInitialRoom(spawnPos)

        -- Zone detection via position check (fog-of-war)
        self:_connectZones()

        -- Clone geometry from ReplicatedStorage (server builds CSG'd walls)
        self:_connectGeo()

        self:_updateDisplay()
        self:_updateLabel()

        print(string.format(
            "[MiniMap] %d rooms stored, initial room: %s, watching ReplicatedStorage",
            roomCount, tostring(self._currentRoom)
        ))
    end,

    ------------------------------------------------------------------------
    -- SIGNALS
    ------------------------------------------------------------------------

    In = {
        onBuildMiniMap = function(self, data)
            print("[MiniMap] onBuildMiniMap received", data and "with data" or "NO DATA")
            if not data then return end

            local player = Players.LocalPlayer
            if data._targetPlayer and data._targetPlayer ~= player then return end

            self:_buildModel(data)
            self:_updateCamera()

            self.Out:Fire("miniMapReady", {
                player = player,
            })
            print("[MiniMap] onBuildMiniMap complete, _hasModel =", self._hasModel)
        end,

        onMapReady = function(self, data)
            print("[MiniMap] onMapReady received")
            local player = Players.LocalPlayer
            if data and data._targetPlayer and data._targetPlayer ~= player then return end
            self._canOpen = true
            print("[MiniMap] _canOpen set to true")
        end,
    },

    Out = {
        miniMapReady = {},
    },
}
