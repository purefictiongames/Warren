--[[
    LibPureFiction Framework v2
    MiniMap.lua - Full Screen 3D Map View

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    MiniMap is a client-side node that displays a full-screen 3D miniature view
    of the dungeon layout using a ViewportFrame. Room volumes are cloned and
    scaled down (1:100) to create a greybox model of the map.

    The map shows:
    - Current room (green)
    - Visited rooms (orange)
    - Adjacent unexplored rooms (grey)
    - Hidden: non-adjacent unexplored rooms

    ============================================================================
    CONTROLS
    ============================================================================

    Gamepad:
    - Back/Select: Toggle map open/close
    - Left Stick: Pan
    - Right Stick: Rotate
    - L1/R1: Zoom out/in

    Touch:
    - Drag: Pan
    - Pinch: Zoom
    - Two-finger rotate: Rotate

    PC (no gamepad):
    - UI button to toggle

    ============================================================================
    SIGNALS
    ============================================================================

    OUT (sends):
        requestMapData({ player })
            - Requests current map data from RegionManager

    IN (receives):
        onMapData({ layout, visitedRooms, currentRoom })
            - Receives map data in response to requestMapData

        onShowMap()
            - Opens the map screen

        onHideMap()
            - Closes the map screen

--]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Node = require(script.Parent.Parent.Node)

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local SCALE = 1 / 100  -- World to minimap scale
local ROOM_TRANSPARENCY = 0.5
local COLORS = {
    current = Color3.fromRGB(80, 180, 80),   -- Green
    visited = Color3.fromRGB(200, 140, 60),  -- Orange
    adjacent = Color3.fromRGB(80, 80, 90),   -- Grey
    padMarker = Color3.fromRGB(180, 0, 255), -- Neon purple
}

--------------------------------------------------------------------------------
-- MINIMAP NODE
--------------------------------------------------------------------------------

local MiniMap = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- FORWARD DECLARATIONS
    ----------------------------------------------------------------------------

    local createUI
    local createToggleButton
    local toggleMap
    local openMap
    local closeMap
    local buildModel
    local updateRoomColors
    local updateCamera
    local updateStats
    local startInputHandling
    local stopInputHandling
    local handleGamepadInput

    ----------------------------------------------------------------------------
    -- PRIVATE STATE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- UI references
                screenGui = nil,
                viewport = nil,
                viewportCamera = nil,
                worldModel = nil,
                toggleButton = nil,
                statsLabel = nil,
                -- Map state
                isOpen = false,
                layout = nil,
                visitedRooms = {},
                currentRoom = nil,
                regionNum = nil,
                stats = nil,
                -- Room part references (for color updates)
                roomParts = {},  -- { [roomId] = Part }
                -- Camera state
                cameraDistance = 5,  -- Distance from target (scaled)
                cameraYaw = 0,       -- Horizontal rotation (degrees)
                cameraPitch = 45,    -- Vertical angle (degrees)
                cameraPanX = 0,      -- Pan offset X (scaled)
                cameraPanZ = 0,      -- Pan offset Z (scaled)
                -- Input state
                toggleConnection = nil,  -- Persistent toggle listener
                renderConnection = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            -- Disconnect toggle listener
            if state.toggleConnection then
                state.toggleConnection:Disconnect()
            end
            if state.renderConnection then
                state.renderConnection:Disconnect()
            end
            -- Unbind context actions
            ContextActionService:UnbindAction("MiniMapSinkLeftStick")
            ContextActionService:UnbindAction("MiniMapRotate")
            ContextActionService:UnbindAction("MiniMapZoomIn")
            ContextActionService:UnbindAction("MiniMapZoomOut")
            ContextActionService:UnbindAction("MiniMapClose")
            -- Destroy UI
            if state.screenGui then
                state.screenGui:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- UI CREATION
    ----------------------------------------------------------------------------

    createUI = function(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        -- Clean up existing
        if state.screenGui then
            state.screenGui:Destroy()
        end
        local existing = playerGui:FindFirstChild("MiniMap")
        if existing then
            existing:Destroy()
        end

        -- Create ScreenGui (full screen, hidden by default)
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "MiniMap"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 999  -- High z-index to be above Roblox toolbar
        screenGui.IgnoreGuiInset = true  -- Ignore Roblox topbar
        screenGui.Enabled = false
        screenGui.Parent = playerGui

        -- ViewportFrame (full screen, transparent overlay)
        local viewport = Instance.new("ViewportFrame")
        viewport.Name = "Viewport"
        viewport.Size = UDim2.new(1, 0, 1, 0)
        viewport.Position = UDim2.new(0, 0, 0, 0)
        viewport.BackgroundTransparency = 1
        viewport.Parent = screenGui

        -- Camera for the viewport
        local camera = Instance.new("Camera")
        camera.Name = "MapCamera"
        camera.FieldOfView = 50
        camera.Parent = viewport
        viewport.CurrentCamera = camera

        -- WorldModel to hold the miniature geometry
        local worldModel = Instance.new("WorldModel")
        worldModel.Name = "MapModel"
        worldModel.Parent = viewport

        -- Stats display (bottom-right corner)
        local statsFrame = Instance.new("Frame")
        statsFrame.Name = "StatsFrame"
        statsFrame.Size = UDim2.new(0, 200, 0, 100)
        statsFrame.Position = UDim2.new(1, -220, 1, -120)
        statsFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        statsFrame.BackgroundTransparency = 0.5
        statsFrame.BorderSizePixel = 0
        statsFrame.Parent = screenGui

        local statsCorner = Instance.new("UICorner")
        statsCorner.CornerRadius = UDim.new(0, 8)
        statsCorner.Parent = statsFrame

        local statsPadding = Instance.new("UIPadding")
        statsPadding.PaddingLeft = UDim.new(0, 10)
        statsPadding.PaddingTop = UDim.new(0, 10)
        statsPadding.Parent = statsFrame

        local statsLabel = Instance.new("TextLabel")
        statsLabel.Name = "StatsLabel"
        statsLabel.Size = UDim2.new(1, -10, 1, -10)
        statsLabel.BackgroundTransparency = 1
        statsLabel.Font = Enum.Font.GothamBold
        statsLabel.TextSize = 14
        statsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        statsLabel.TextXAlignment = Enum.TextXAlignment.Left
        statsLabel.TextYAlignment = Enum.TextYAlignment.Top
        statsLabel.Text = "Loading..."
        statsLabel.Parent = statsFrame

        state.screenGui = screenGui
        state.viewport = viewport
        state.viewportCamera = camera
        state.worldModel = worldModel
        state.statsLabel = statsLabel

        -- Create toggle button if needed (touch/PC without gamepad)
        createToggleButton(self)
    end

    createToggleButton = function(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        -- Only show button if no gamepad connected
        local gamepadConnected = UserInputService.GamepadEnabled

        if gamepadConnected then
            -- Gamepad users use Back/Select button
            if state.toggleButton then
                state.toggleButton:Destroy()
                state.toggleButton = nil
            end
            return
        end

        local playerGui = player:WaitForChild("PlayerGui")

        -- Find or create button ScreenGui
        local buttonGui = playerGui:FindFirstChild("MiniMapToggle")
        if not buttonGui then
            buttonGui = Instance.new("ScreenGui")
            buttonGui.Name = "MiniMapToggle"
            buttonGui.ResetOnSpawn = false
            buttonGui.DisplayOrder = 5
            buttonGui.Parent = playerGui
        end

        -- Create toggle button (bottom-left corner)
        local button = Instance.new("TextButton")
        button.Name = "ToggleButton"
        button.Size = UDim2.new(0, 50, 0, 50)
        button.Position = UDim2.new(0, 20, 1, -70)
        button.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        button.BackgroundTransparency = 0.3
        button.BorderSizePixel = 0
        button.Text = "MAP"
        button.Font = Enum.Font.GothamBold
        button.TextSize = 12
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.Parent = buttonGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = button

        button.MouseButton1Click:Connect(function()
            toggleMap(self)
        end)

        state.toggleButton = button
    end

    ----------------------------------------------------------------------------
    -- MAP TOGGLE
    ----------------------------------------------------------------------------

    toggleMap = function(self)
        local state = getState(self)
        if state.isOpen then
            closeMap(self)
        else
            openMap(self)
        end
    end

    openMap = function(self)
        local state = getState(self)
        if state.isOpen then return end

        state.isOpen = true
        if state.screenGui then
            state.screenGui.Enabled = true
        end

        -- Request fresh map data from RegionManager
        local player = Players.LocalPlayer
        self.Out:Fire("requestMapData", {
            player = player,
        })

        -- Start input handling
        startInputHandling(self)
    end

    closeMap = function(self)
        local state = getState(self)
        if not state.isOpen then return end

        state.isOpen = false
        if state.screenGui then
            state.screenGui.Enabled = false
        end

        -- Stop input handling
        stopInputHandling(self)
    end

    ----------------------------------------------------------------------------
    -- 3D MODEL BUILDING
    ----------------------------------------------------------------------------

    buildModel = function(self)
        local state = getState(self)
        local layout = state.layout

        if not layout or not layout.rooms then return end

        -- Clear existing model
        if state.worldModel then
            state.worldModel:ClearAllChildren()
        end
        state.roomParts = {}

        -- Build adjacency set (rooms adjacent to visited rooms)
        local adjacentRooms = {}
        if layout.doors then
            for _, door in ipairs(layout.doors) do
                local fromVisited = state.visitedRooms[door.fromRoom]
                local toVisited = state.visitedRooms[door.toRoom]
                if fromVisited and not toVisited then
                    adjacentRooms[door.toRoom] = true
                elseif toVisited and not fromVisited then
                    adjacentRooms[door.fromRoom] = true
                end
            end
        end

        -- Calculate bounding box of all rooms
        local minX, maxX = math.huge, -math.huge
        local minY, maxY = math.huge, -math.huge
        local minZ, maxZ = math.huge, -math.huge

        for _, room in pairs(layout.rooms) do
            local x, y, z = room.position[1], room.position[2], room.position[3]
            local hw, hh, hd = room.dims[1] / 2, room.dims[2] / 2, room.dims[3] / 2

            minX = math.min(minX, x - hw)
            maxX = math.max(maxX, x + hw)
            minY = math.min(minY, y - hh)
            maxY = math.max(maxY, y + hh)
            minZ = math.min(minZ, z - hd)
            maxZ = math.max(maxZ, z + hd)
        end

        -- Center is the middle of the bounding box
        local centerX = (minX + maxX) / 2
        local centerY = (minY + maxY) / 2
        local centerZ = (minZ + maxZ) / 2

        -- Create scaled room parts
        for roomId, room in pairs(layout.rooms) do
            local isVisited = state.visitedRooms[roomId]
            local isCurrent = roomId == state.currentRoom
            local isAdjacent = adjacentRooms[roomId]

            -- Skip non-adjacent unexplored rooms
            if not isVisited and not isAdjacent then
                continue
            end

            -- Create part
            local part = Instance.new("Part")
            part.Name = "Room_" .. roomId
            part.Anchored = true
            part.CanCollide = false

            -- Scale position and size
            local scaledX = (room.position[1] - centerX) * SCALE
            local scaledY = (room.position[2] - centerY) * SCALE
            local scaledZ = (room.position[3] - centerZ) * SCALE
            local scaledW = room.dims[1] * SCALE
            local scaledH = room.dims[2] * SCALE
            local scaledD = room.dims[3] * SCALE

            part.Position = Vector3.new(scaledX, scaledY, scaledZ)
            part.Size = Vector3.new(scaledW, scaledH, scaledD)

            -- Color based on state
            if isCurrent then
                part.Color = COLORS.current
            elseif isVisited then
                part.Color = COLORS.visited
            else
                part.Color = COLORS.adjacent
            end

            part.Transparency = ROOM_TRANSPARENCY
            part.Material = Enum.Material.SmoothPlastic
            part.Parent = state.worldModel

            state.roomParts[roomId] = part
        end

        -- Create pad markers (only for visited rooms)
        if layout.pads then
            for _, pad in ipairs(layout.pads) do
                local padRoomId = pad.roomId
                local isRoomVisited = state.visitedRooms[padRoomId]

                if isRoomVisited then
                    -- Scale position
                    local scaledX = (pad.position[1] - centerX) * SCALE
                    local scaledY = (pad.position[2] - centerY) * SCALE
                    local scaledZ = (pad.position[3] - centerZ) * SCALE
                    local markerPos = Vector3.new(scaledX, scaledY, scaledZ)

                    -- Outer glow sphere
                    local glow = Instance.new("Part")
                    glow.Name = "PadGlow_" .. pad.id
                    glow.Shape = Enum.PartType.Ball
                    glow.Anchored = true
                    glow.CanCollide = false
                    glow.Position = markerPos
                    glow.Size = Vector3.new(0.12, 0.12, 0.12)
                    glow.Color = COLORS.padMarker
                    glow.Material = Enum.Material.Neon
                    glow.Transparency = 0.6
                    glow.Parent = state.worldModel

                    -- Inner core
                    local core = Instance.new("Part")
                    core.Name = "PadCore_" .. pad.id
                    core.Shape = Enum.PartType.Ball
                    core.Anchored = true
                    core.CanCollide = false
                    core.Position = markerPos
                    core.Size = Vector3.new(0.05, 0.05, 0.05)
                    core.Color = Color3.fromRGB(255, 255, 255)
                    core.Material = Enum.Material.Neon
                    core.Parent = state.worldModel

                    -- Point light for extra glow
                    local light = Instance.new("PointLight")
                    light.Color = COLORS.padMarker
                    light.Brightness = 2
                    light.Range = 0.3
                    light.Parent = core
                end
            end
        end

        -- Set initial camera distance based on layout bounds
        local maxExtent = 0
        for _, room in pairs(layout.rooms) do
            local dist = math.sqrt(
                (room.position[1] - centerX)^2 +
                (room.position[3] - centerZ)^2
            )
            maxExtent = math.max(maxExtent, dist + math.max(room.dims[1], room.dims[3]) / 2)
        end
        state.cameraDistance = maxExtent * SCALE * 2
    end

    updateRoomColors = function(self)
        local state = getState(self)
        local layout = state.layout

        if not layout or not layout.rooms then return end

        -- Build adjacency set
        local adjacentRooms = {}
        if layout.doors then
            for _, door in ipairs(layout.doors) do
                local fromVisited = state.visitedRooms[door.fromRoom]
                local toVisited = state.visitedRooms[door.toRoom]
                if fromVisited and not toVisited then
                    adjacentRooms[door.toRoom] = true
                elseif toVisited and not fromVisited then
                    adjacentRooms[door.fromRoom] = true
                end
            end
        end

        for roomId, part in pairs(state.roomParts) do
            local isVisited = state.visitedRooms[roomId]
            local isCurrent = roomId == state.currentRoom

            if isCurrent then
                part.Color = COLORS.current
            elseif isVisited then
                part.Color = COLORS.visited
            else
                part.Color = COLORS.adjacent
            end
        end

        -- Check if we need to add newly revealed adjacent rooms
        for roomId, _ in pairs(adjacentRooms) do
            if not state.roomParts[roomId] and layout.rooms[roomId] then
                -- Need to rebuild model to add new room
                buildModel(self)
                return
            end
        end
    end

    updateStats = function(self)
        local state = getState(self)

        if not state.statsLabel then return end
        if not state.stats then
            state.statsLabel.Text = "No map data"
            return
        end

        local s = state.stats
        local statsText = string.format(
            "ROOMS: %d / %d\nPORTALS: %d / %d\n\nCOMPLETION: %d%%",
            s.exploredRooms, s.totalRooms,
            s.discoveredPortals, s.totalPortals,
            s.completion
        )

        state.statsLabel.Text = statsText
    end

    ----------------------------------------------------------------------------
    -- CAMERA
    ----------------------------------------------------------------------------

    updateCamera = function(self)
        local state = getState(self)
        local camera = state.viewportCamera

        if not camera then return end

        -- Convert spherical to cartesian
        local yawRad = math.rad(state.cameraYaw)
        local pitchRad = math.rad(state.cameraPitch)

        local distance = state.cameraDistance

        -- Camera position relative to target
        local offsetX = math.sin(yawRad) * math.cos(pitchRad) * distance
        local offsetY = math.sin(pitchRad) * distance
        local offsetZ = math.cos(yawRad) * math.cos(pitchRad) * distance

        -- Target is at pan offset (model is centered at origin)
        local targetX = state.cameraPanX
        local targetY = 0
        local targetZ = state.cameraPanZ

        local cameraPos = Vector3.new(
            targetX + offsetX,
            targetY + offsetY,
            targetZ + offsetZ
        )
        local targetPos = Vector3.new(targetX, targetY, targetZ)

        camera.CFrame = CFrame.lookAt(cameraPos, targetPos)
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    startInputHandling = function(self)
        local state = getState(self)

        -- Bind gamepad actions (sinks input so player doesn't move)
        -- Sink left stick input (no panning, but prevent player movement)
        ContextActionService:BindAction(
            "MiniMapSinkLeftStick",
            function()
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.Thumbstick1
        )

        ContextActionService:BindAction(
            "MiniMapRotate",
            function(actionName, inputState, inputObject)
                if inputState == Enum.UserInputState.Change then
                    local pos = inputObject.Position
                    local rotSpeed = 3
                    local changed = false
                    -- X axis = yaw (rotate around Y)
                    if math.abs(pos.X) > 0.1 then
                        state.cameraYaw = state.cameraYaw - pos.X * rotSpeed
                        changed = true
                    end
                    -- Y axis = pitch (rotate around X)
                    if math.abs(pos.Y) > 0.1 then
                        state.cameraPitch = math.clamp(
                            state.cameraPitch + pos.Y * rotSpeed,
                            -89, 89  -- Clamp to avoid gimbal lock
                        )
                        changed = true
                    end
                    if changed then
                        updateCamera(self)
                    end
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.Thumbstick2
        )

        ContextActionService:BindAction(
            "MiniMapZoomOut",
            function(actionName, inputState, inputObject)
                if inputState == Enum.UserInputState.Begin then
                    state.cameraDistance = math.min(20, state.cameraDistance * 1.2)
                    updateCamera(self)
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.ButtonL1
        )

        ContextActionService:BindAction(
            "MiniMapZoomIn",
            function(actionName, inputState, inputObject)
                if inputState == Enum.UserInputState.Begin then
                    state.cameraDistance = math.max(0.5, state.cameraDistance * 0.8)
                    updateCamera(self)
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.ButtonR1
        )

        ContextActionService:BindAction(
            "MiniMapClose",
            function(actionName, inputState, inputObject)
                if inputState == Enum.UserInputState.Begin then
                    closeMap(self)
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.ButtonSelect
        )
    end

    stopInputHandling = function(self)
        ContextActionService:UnbindAction("MiniMapSinkLeftStick")
        ContextActionService:UnbindAction("MiniMapRotate")
        ContextActionService:UnbindAction("MiniMapZoomIn")
        ContextActionService:UnbindAction("MiniMapZoomOut")
        ContextActionService:UnbindAction("MiniMapClose")
    end

    handleGamepadInput = function(self, dt)
        -- No longer used - ContextActionService handles input
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "MiniMap",
        domain = "client",

        Sys = {
            onInit = function(self)
                createUI(self)
            end,

            onStart = function(self)
                -- Set up persistent gamepad button listener for toggle (only when map is closed)
                local state = getState(self)
                state.toggleConnection = UserInputService.InputBegan:Connect(function(input, processed)
                    if processed then return end
                    -- Only handle toggle when map is closed (when open, ContextAction handles it)
                    if not state.isOpen and input.KeyCode == Enum.KeyCode.ButtonSelect then
                        toggleMap(self)
                    end
                end)
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            --[[
                Handle map data response from RegionManager.

                @param data table:
                    layout: table - The Layout table
                    visitedRooms: table - Set of visited room IDs
                    currentRoom: number - Current room ID
            --]]
            onMapData = function(self, data)
                if not data then return end

                local state = getState(self)
                local player = Players.LocalPlayer

                -- Only update for local player
                if data.player and data.player ~= player then return end

                -- Store fresh data
                state.layout = data.layout
                state.visitedRooms = data.visitedRooms or {}
                state.currentRoom = data.currentRoom
                state.stats = data.stats

                -- Clear old room parts
                if state.worldModel then
                    state.worldModel:ClearAllChildren()
                end
                state.roomParts = {}

                -- Reset camera for new data
                state.cameraPanX = 0
                state.cameraPanZ = 0
                state.cameraYaw = 0
                state.cameraPitch = 45

                -- Build the model and update stats
                buildModel(self)
                updateCamera(self)
                updateStats(self)
            end,

            --[[
                Open the map screen.
            --]]
            onShowMap = function(self)
                openMap(self)
            end,

            --[[
                Close the map screen.
            --]]
            onHideMap = function(self)
                closeMap(self)
            end,
        },

        Out = {
            requestMapData = {},
        },
    }
end)

return MiniMap
