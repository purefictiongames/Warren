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
    - Player marker (golden pin) - current physical location
    - Selected room (blue) - cursor for room navigation
    - Visited rooms (orange)
    - Adjacent unexplored rooms (grey)
    - Hidden: non-adjacent unexplored rooms

    Portal info is displayed for the selected room, showing destination area
    or "???" for unexplored portals.

    ============================================================================
    CONTROLS
    ============================================================================

    Gamepad:
    - Y/Triangle: Toggle map open/close
    - Right Stick: Rotate
    - L1/R1: Zoom out/in
    - L2/R2: Navigate rooms (previous/next)

    Touch:
    - Pinch: Zoom
    - Two-finger rotate: Rotate

    PC (no gamepad):
    - UI button to toggle

    ============================================================================
    SIGNALS
    ============================================================================

    OUT (sends):
        miniMapReady({ player })
            - Signals RegionManager that minimap geometry is built

        requestVisitedState({ player, regionNum })
            - Requests current visited rooms from RegionManager
            - regionNum ensures correct region lookup (avoids stale activeRegionId)

    IN (receives):
        onBuildMiniMap({ layout, player })
            - Builds minimap geometry during region load (from RegionManager)

        onVisitedState({ visitedRooms, currentRoom, padLinks, stats })
            - Updates room colors/visibility when map is opened

        onTransitionStart({ player })
            - Closes map when region transition begins

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
local System = require(script.Parent.Parent.System)
local PixelFont = require(script.Parent.Parent.PixelFont)

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local SCALE = 1 / 100  -- World to minimap scale
local ROOM_TRANSPARENCY = 0.5
local COLORS = {
    selected = Color3.fromRGB(80, 140, 220), -- Blue (selected room on map)
    visited = Color3.fromRGB(200, 140, 60),  -- Orange
    adjacent = Color3.fromRGB(80, 80, 90),   -- Grey
    padMarker = Color3.fromRGB(180, 0, 255), -- Neon purple
    playerMarker = Color3.fromRGB(255, 200, 60), -- Golden yellow
}

--------------------------------------------------------------------------------
-- MINIMAP NODE
--------------------------------------------------------------------------------

local MiniMap = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- FORWARD DECLARATIONS
    ----------------------------------------------------------------------------

    local createUI
    local toggleMap
    local openMap
    local closeMap
    local buildModel
    local createPlayerMarker
    local updatePlayerMarker
    local updateRoomColors
    local selectRoom
    local navigateRoom
    local updateCamera
    local updateStats
    local updatePortalInfo
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
                toggleButtonText = nil,  -- PixelFont text frame for toggle button
                statsLabels = {},  -- Array of PixelFont text frames for stats lines
                -- Map state
                isOpen = false,
                layout = nil,
                visitedRooms = {},
                currentRoom = nil,
                regionNum = nil,
                pendingVisitedRequest = false, -- True if we've sent requestVisitedState
                gameplayActive = false, -- True when player can move (after transitionEnd)
                stats = nil,
                -- Room part references (for color updates)
                roomParts = {},  -- { [roomId] = Part }
                -- Pad part references (for visibility control)
                padParts = {},  -- { [padId] = { glow, core, light, roomId } }
                -- Player marker (shows current physical location)
                playerMarker = nil,
                -- Selected room for navigation (highlighted blue)
                selectedRoom = nil,
                -- Sorted room IDs for L2/R2 navigation
                sortedRoomIds = {},
                -- Pad links for portal destination info
                padLinks = {},
                -- Layout center position (for positioning markers)
                layoutCenter = { x = 0, y = 0, z = 0 },
                -- Camera state
                cameraDistance = 5,  -- Distance from target (scaled)
                cameraYaw = 0,       -- Horizontal rotation (degrees)
                cameraPitch = 45,    -- Vertical angle (degrees)
                cameraPanX = 0,      -- Pan offset X (scaled)
                cameraPanZ = 0,      -- Pan offset Z (scaled)
                -- Input state
                toggleConnection = nil,  -- Persistent toggle listener
                renderConnection = nil,
                inputClaim = nil,  -- InputCapture claim for movement sinking
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
            -- Release input claim if active
            if state.inputClaim then
                state.inputClaim:release()
                state.inputClaim = nil
            end
            -- Destroy room parts
            destroyRoomParts(state)
            -- Unbind context actions
            ContextActionService:UnbindAction("MiniMapRotate")
            ContextActionService:UnbindAction("MiniMapZoomIn")
            ContextActionService:UnbindAction("MiniMapZoomOut")
            ContextActionService:UnbindAction("MiniMapPrevRoom")
            ContextActionService:UnbindAction("MiniMapNextRoom")
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
        local STATS_SCALE = 2
        local STATS_PADDING = 10
        local LINE_HEIGHT = 8 * STATS_SCALE + 4  -- 8px char + 4px spacing
        local NUM_LINES = 6

        -- Calculate width based on longest possible text
        local maxStatsWidth = math.max(
            PixelFont.getTextWidth("ROOMS: 999 / 999", STATS_SCALE, 0),
            PixelFont.getTextWidth("PORTALS: 99 / 99", STATS_SCALE, 0),
            PixelFont.getTextWidth("COMPLETION: 100%", STATS_SCALE, 0),
            PixelFont.getTextWidth("PORTAL TO AREA 99", STATS_SCALE, 0)
        )
        local statsWidth = maxStatsWidth + STATS_PADDING * 2
        local statsHeight = NUM_LINES * LINE_HEIGHT + STATS_PADDING * 2

        local statsFrame = Instance.new("Frame")
        statsFrame.Name = "StatsFrame"
        statsFrame.Size = UDim2.new(0, statsWidth, 0, statsHeight)
        statsFrame.Position = UDim2.new(1, -statsWidth - 20, 1, -statsHeight - 20)
        statsFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        statsFrame.BackgroundTransparency = 0.5
        statsFrame.BorderSizePixel = 0
        statsFrame.Parent = screenGui

        local statsCorner = Instance.new("UICorner")
        statsCorner.CornerRadius = UDim.new(0, 8)
        statsCorner.Parent = statsFrame

        -- Create pixel text labels for stats (6 lines: rooms, portals, blank, completion, blank, portal info)
        state.statsLabels = {}

        for i = 1, NUM_LINES do
            local lineText = PixelFont.createText(i == 1 and "LOADING..." or "", {
                scale = STATS_SCALE,
                color = Color3.fromRGB(255, 255, 255),
            })
            lineText.Name = "StatsLine" .. i
            lineText.Position = UDim2.new(0, STATS_PADDING, 0, STATS_PADDING + (i - 1) * LINE_HEIGHT)
            lineText.Parent = statsFrame
            state.statsLabels[i] = lineText
        end

        state.screenGui = screenGui
        state.viewport = viewport
        state.viewportCamera = camera
        state.worldModel = worldModel

        -- No on-screen toggle button — map opens via gamepad touchpad (ButtonSelect)
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

        -- Don't open if no layout built yet
        if not state.layout then return end

        -- Don't open until gameplay is active (after transition completes)
        if not state.gameplayActive then return end

        state.isOpen = true
        if state.screenGui then
            state.screenGui.Enabled = true
        end

        -- Request current visited state from RegionManager (for color updates)
        local player = Players.LocalPlayer
        state.pendingVisitedRequest = true
        self.Out:Fire("requestVisitedState", {
            player = player,
            regionNum = state.regionNum,  -- Include regionNum to avoid stale activeRegionId lookup
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

    --[[
        Explicitly destroys all room parts and markers to prevent memory leaks.
    --]]
    local function destroyRoomParts(state)
        -- Explicitly destroy each room part to prevent memory leaks
        for _, part in pairs(state.roomParts or {}) do
            if part and part.Parent then
                part:Destroy()
            end
        end
        state.roomParts = {}

        -- Destroy pad parts
        for _, padParts in pairs(state.padParts or {}) do
            if padParts.glow and padParts.glow.Parent then
                padParts.glow:Destroy()
            end
            if padParts.core and padParts.core.Parent then
                padParts.core:Destroy()
            end
        end
        state.padParts = {}

        -- Destroy player marker
        if state.playerMarker then
            state.playerMarker:Destroy()
            state.playerMarker = nil
        end

        -- Clear world model (catches anything we missed)
        if state.worldModel then
            state.worldModel:ClearAllChildren()
        end
    end

    buildModel = function(self)
        local state = getState(self)
        local layout = state.layout

        if not layout or not layout.rooms then return end

        -- Clear existing model
        destroyRoomParts(state)

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

        -- Store center for player marker positioning
        state.layoutCenter = { x = centerX, y = centerY, z = centerZ }

        -- Build sorted room IDs for L2/R2 navigation
        state.sortedRoomIds = {}
        for roomId, _ in pairs(layout.rooms) do
            table.insert(state.sortedRoomIds, roomId)
        end
        table.sort(state.sortedRoomIds)

        -- Create scaled room parts (build ALL rooms, visibility controlled by updateRoomColors)
        for roomId, room in pairs(layout.rooms) do
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

            -- Default color (grey) - updateRoomColors will set proper colors/visibility
            part.Color = COLORS.adjacent
            part.Transparency = 1  -- Hidden until updateRoomColors is called
            part.Material = Enum.Material.SmoothPlastic
            part.Parent = state.worldModel

            state.roomParts[roomId] = part
        end

        -- Create pad markers for ALL pads (visibility controlled by updateRoomColors)
        state.padParts = {}
        if layout.pads then
            for _, pad in ipairs(layout.pads) do
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
                glow.Transparency = 1  -- Hidden until updateRoomColors
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
                core.Transparency = 1  -- Hidden until updateRoomColors
                core.Parent = state.worldModel

                -- Point light for extra glow
                local light = Instance.new("PointLight")
                light.Color = COLORS.padMarker
                light.Brightness = 2
                light.Range = 0.3
                light.Enabled = false  -- Disabled until updateRoomColors
                light.Parent = core

                -- Store reference for visibility control
                state.padParts[pad.id] = {
                    glow = glow,
                    core = core,
                    light = light,
                    roomId = pad.roomId,
                }
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

        -- Note: Player marker is created/updated in onVisitedState via updatePlayerMarker
    end

    --[[
        Creates the player location marker - a golden downward-pointing pin
        that hovers above the player's current room position.
    --]]
    createPlayerMarker = function(self)
        local state = getState(self)
        local layout = state.layout

        if not layout or not layout.rooms then return end

        -- Remove existing marker
        if state.playerMarker then
            state.playerMarker:Destroy()
            state.playerMarker = nil
        end

        local currentRoom = layout.rooms[state.currentRoom]
        if not currentRoom then return end

        local center = state.layoutCenter

        -- Scale position
        local scaledX = (currentRoom.position[1] - center.x) * SCALE
        local scaledY = (currentRoom.position[2] - center.y) * SCALE
        local scaledZ = (currentRoom.position[3] - center.z) * SCALE
        local roomHeight = currentRoom.dims[2] * SCALE

        -- Position marker above the room
        local markerPos = Vector3.new(scaledX, scaledY + roomHeight / 2 + 0.15, scaledZ)

        -- Create marker container (Model to hold multiple parts)
        local marker = Instance.new("Model")
        marker.Name = "PlayerMarker"

        -- Pin head (sphere on top)
        local head = Instance.new("Part")
        head.Name = "Head"
        head.Shape = Enum.PartType.Ball
        head.Anchored = true
        head.CanCollide = false
        head.Size = Vector3.new(0.08, 0.08, 0.08)
        head.Color = COLORS.playerMarker
        head.Material = Enum.Material.Neon
        head.Position = markerPos + Vector3.new(0, 0.06, 0)
        head.Parent = marker

        -- Pin shaft (wedge pointing down)
        local shaft = Instance.new("WedgePart")
        shaft.Name = "Shaft"
        shaft.Anchored = true
        shaft.CanCollide = false
        shaft.Size = Vector3.new(0.04, 0.12, 0.06)
        shaft.Color = COLORS.playerMarker
        shaft.Material = Enum.Material.Neon
        -- Rotate wedge so it points downward (tip at bottom)
        shaft.CFrame = CFrame.new(markerPos) * CFrame.Angles(math.rad(180), 0, 0)
        shaft.Parent = marker

        -- Glow effect
        local light = Instance.new("PointLight")
        light.Color = COLORS.playerMarker
        light.Brightness = 3
        light.Range = 0.4
        light.Parent = head

        marker.Parent = state.worldModel
        state.playerMarker = marker
    end

    --[[
        Updates the player marker position when currentRoom changes.
    --]]
    updatePlayerMarker = function(self)
        local state = getState(self)
        local layout = state.layout

        if not layout or not layout.rooms then return end
        if not state.playerMarker then
            createPlayerMarker(self)
            return
        end

        local currentRoom = layout.rooms[state.currentRoom]
        if not currentRoom then return end

        local center = state.layoutCenter

        -- Scale position
        local scaledX = (currentRoom.position[1] - center.x) * SCALE
        local scaledY = (currentRoom.position[2] - center.y) * SCALE
        local scaledZ = (currentRoom.position[3] - center.z) * SCALE
        local roomHeight = currentRoom.dims[2] * SCALE

        local markerPos = Vector3.new(scaledX, scaledY + roomHeight / 2 + 0.15, scaledZ)

        -- Update positions of marker parts
        local head = state.playerMarker:FindFirstChild("Head")
        local shaft = state.playerMarker:FindFirstChild("Shaft")

        if head then
            head.Position = markerPos + Vector3.new(0, 0.06, 0)
        end
        if shaft then
            shaft.CFrame = CFrame.new(markerPos) * CFrame.Angles(math.rad(180), 0, 0)
        end
    end

    updateRoomColors = function(self)
        local state = getState(self)
        local layout = state.layout

        if not layout or not layout.rooms then return end

        -- Build adjacency set (rooms adjacent to visited rooms)
        -- Handle key type mismatch (RemoteEvents can convert number keys to strings)
        local adjacentRooms = {}
        if layout.doors then
            for _, door in ipairs(layout.doors) do
                local fromVisited = state.visitedRooms[door.fromRoom] or state.visitedRooms[tostring(door.fromRoom)]
                local toVisited = state.visitedRooms[door.toRoom] or state.visitedRooms[tostring(door.toRoom)]
                if fromVisited and not toVisited then
                    adjacentRooms[door.toRoom] = true
                elseif toVisited and not fromVisited then
                    adjacentRooms[door.fromRoom] = true
                end
            end
        end

        -- Update room visibility and colors
        for roomId, part in pairs(state.roomParts) do
            -- Handle key type mismatch (RemoteEvents can convert number keys to strings)
            local isVisited = state.visitedRooms[roomId] or state.visitedRooms[tostring(roomId)]
            local isAdjacent = adjacentRooms[roomId]
            local isSelected = roomId == state.selectedRoom

            -- Show only visited + adjacent rooms
            if isVisited or isAdjacent then
                part.Transparency = ROOM_TRANSPARENCY

                if isSelected then
                    part.Color = COLORS.selected
                elseif isVisited then
                    part.Color = COLORS.visited
                else
                    part.Color = COLORS.adjacent
                end
            else
                -- Hide unexplored non-adjacent rooms
                part.Transparency = 1
            end
        end

        -- Update pad marker visibility (show only in visited rooms)
        for padId, padParts in pairs(state.padParts or {}) do
            local isRoomVisited = state.visitedRooms[padParts.roomId] or state.visitedRooms[tostring(padParts.roomId)]

            if isRoomVisited then
                padParts.glow.Transparency = 0.6
                padParts.core.Transparency = 0
                padParts.light.Enabled = true
            else
                padParts.glow.Transparency = 1
                padParts.core.Transparency = 1
                padParts.light.Enabled = false
            end
        end
    end

    updateStats = function(self)
        local state = getState(self)

        if not state.statsLabels or #state.statsLabels == 0 then return end
        if not state.stats then
            PixelFont.updateText(state.statsLabels[1], "NO MAP DATA")
            for i = 2, #state.statsLabels do
                PixelFont.updateText(state.statsLabels[i], "")
            end
            return
        end

        local s = state.stats
        local lines = {
            string.format("ROOMS: %d / %d", s.exploredRooms, s.totalRooms),
            string.format("PORTALS: %d / %d", s.discoveredPortals, s.totalPortals),
            "",
            string.format("COMPLETION: %d%%", s.completion),
            "",  -- Reserved for portal info
            "",  -- Reserved for portal info
        }

        for i, line in ipairs(lines) do
            if state.statsLabels[i] then
                PixelFont.updateText(state.statsLabels[i], line)
            end
        end
    end

    --[[
        Selects a room on the minimap (highlights it blue and shows info).
    --]]
    selectRoom = function(self, roomId)
        local state = getState(self)

        if not state.layout or not state.layout.rooms then return end
        if not state.layout.rooms[roomId] then return end

        state.selectedRoom = roomId
        updateRoomColors(self)
        updatePortalInfo(self)
    end

    --[[
        Navigates to next/previous visited room in numerical order.
        Skips unexplored rooms. Wraps around at list ends.
        @param direction: 1 for next, -1 for previous
    --]]
    navigateRoom = function(self, direction)
        local state = getState(self)

        if not state.sortedRoomIds or #state.sortedRoomIds == 0 then return end

        -- Find current index
        local currentIndex = 1
        for i, roomId in ipairs(state.sortedRoomIds) do
            if roomId == state.selectedRoom then
                currentIndex = i
                break
            end
        end

        -- Search for next visited room in direction, with wrapping
        local totalRooms = #state.sortedRoomIds
        local searchIndex = currentIndex

        for _ = 1, totalRooms do
            -- Move in direction with wrapping
            searchIndex = searchIndex + direction
            if searchIndex < 1 then
                searchIndex = totalRooms
            elseif searchIndex > totalRooms then
                searchIndex = 1
            end

            local candidateRoomId = state.sortedRoomIds[searchIndex]

            -- Only select if visited
            if state.visitedRooms[candidateRoomId] then
                selectRoom(self, candidateRoomId)
                return
            end
        end

        -- No other visited rooms found, stay on current
    end

    --[[
        Updates the portal info display for the selected room.
        Shows destination area for any portals in the room.
    --]]
    updatePortalInfo = function(self)
        local state = getState(self)

        if not state.statsLabels or #state.statsLabels == 0 then return end
        if not state.layout then return end

        -- Start with base stats (update first 4 lines)
        local s = state.stats
        if s then
            PixelFont.updateText(state.statsLabels[1], string.format("ROOMS: %d / %d", s.exploredRooms, s.totalRooms))
            PixelFont.updateText(state.statsLabels[2], string.format("PORTALS: %d / %d", s.discoveredPortals, s.totalPortals))
            PixelFont.updateText(state.statsLabels[3], "")
            PixelFont.updateText(state.statsLabels[4], string.format("COMPLETION: %d%%", s.completion))
        end

        -- Check if selected room has a portal (use lines 5-6)
        local portalLine = ""
        if state.layout.pads and state.selectedRoom then
            for _, pad in ipairs(state.layout.pads) do
                if pad.roomId == state.selectedRoom then
                    -- Found a portal in this room
                    local padLink = state.padLinks[pad.id]
                    local destText

                    if padLink and padLink.regionId then
                        -- Extract region number from regionId (e.g., "region_3" -> 3)
                        local regionNum = tonumber(string.match(padLink.regionId, "region_(%d+)"))
                        if regionNum then
                            destText = "AREA " .. regionNum
                        else
                            destText = padLink.regionId
                        end
                    else
                        -- Unlinked portal
                        destText = "???"
                    end

                    portalLine = "PORTAL: " .. destText
                    break  -- Only show first portal (rooms typically have 1)
                end
            end
        end

        PixelFont.updateText(state.statsLabels[5], "")
        PixelFont.updateText(state.statsLabels[6], portalLine)
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

        -- Target is player's current room (pivot point for rotation)
        local targetX = state.cameraPanX
        local targetY = 0
        local targetZ = state.cameraPanZ

        -- Calculate current room's scaled position as pivot point
        if state.currentRoom and state.layout and state.layout.rooms then
            local currentRoom = state.layout.rooms[state.currentRoom]
            if currentRoom then
                local center = state.layoutCenter
                targetX = (currentRoom.position[1] - center.x) * SCALE + state.cameraPanX
                targetY = (currentRoom.position[2] - center.y) * SCALE
                targetZ = (currentRoom.position[3] - center.z) * SCALE + state.cameraPanZ
            end
        end

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

        -- Use InputCapture to sink movement (player can't walk while map is open)
        state.inputClaim = System.InputCapture.claim({}, {
            sinkMovement = true,
            -- Note: NOT sinking camera - we use Thumbstick2 for map rotation
        })

        -- Bind gamepad actions for map controls
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

        -- L2: Navigate to previous room
        ContextActionService:BindAction(
            "MiniMapPrevRoom",
            function(actionName, inputState, inputObject)
                if inputState == Enum.UserInputState.Begin then
                    navigateRoom(self, -1)
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.ButtonL2
        )

        -- R2: Navigate to next room
        ContextActionService:BindAction(
            "MiniMapNextRoom",
            function(actionName, inputState, inputObject)
                if inputState == Enum.UserInputState.Begin then
                    navigateRoom(self, 1)
                end
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.KeyCode.ButtonR2
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
        local state = getState(self)

        -- Release input claim (restores movement)
        if state.inputClaim then
            state.inputClaim:release()
            state.inputClaim = nil
        end

        -- Unbind map-specific controls
        ContextActionService:UnbindAction("MiniMapRotate")
        ContextActionService:UnbindAction("MiniMapZoomIn")
        ContextActionService:UnbindAction("MiniMapZoomOut")
        ContextActionService:UnbindAction("MiniMapPrevRoom")
        ContextActionService:UnbindAction("MiniMapNextRoom")
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
                Handle minimap build request from RegionManager (during map load).
                Builds geometry for the new region, then signals ready.

                @param data table:
                    layout: table - The Layout table with rooms, doors, pads
                    player: Player - The player this is for
            --]]
            onBuildMiniMap = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                -- Only process for local player
                if data and data._targetPlayer and data._targetPlayer ~= player then return end

                -- Always signal ready, even if layout is missing (prevents hang)
                if not data or not data.layout then
                    self.Out:Fire("miniMapReady", {
                        player = player,
                    })
                    return
                end

                -- Store layout
                state.layout = data.layout
                state.regionNum = data.layout.regionNum

                -- Destroy old geometry and build new
                destroyRoomParts(state)

                -- Reset camera for new layout
                state.cameraPanX = 0
                state.cameraPanZ = 0
                state.cameraYaw = 0
                state.cameraPitch = 45

                -- Build the 3D model (geometry only, no colors yet)
                buildModel(self)
                updateCamera(self)

                -- Signal back to RegionManager that we're ready
                self.Out:Fire("miniMapReady", {
                    player = player,
                })
            end,

            --[[
                Handle visited state response from RegionManager (when map is opened).
                Updates room colors and player marker based on current exploration state.

                @param data table:
                    visitedRooms: table - Set of visited room IDs
                    currentRoom: number - Current room ID
                    padLinks: table - { [padId] = { regionId, padId } } for portal destinations
                    stats: table - Exploration statistics
            --]]
            onVisitedState = function(self, data)
                if not data then return end

                local state = getState(self)
                local player = Players.LocalPlayer

                -- Only process for local player
                if data._targetPlayer and data._targetPlayer ~= player then return end

                -- Discard if we didn't request this
                if not state.pendingVisitedRequest then return end
                state.pendingVisitedRequest = false

                -- Update state with fresh visited data
                state.visitedRooms = data.visitedRooms or {}
                state.currentRoom = data.currentRoom
                state.stats = data.stats
                state.padLinks = data.padLinks or {}

                -- Set selected room to current room
                state.selectedRoom = data.currentRoom

                -- Update colors and markers (geometry already exists)
                updateRoomColors(self)
                updatePlayerMarker(self)
                updateStats(self)
                updatePortalInfo(self)
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

            --[[
                Handle region transition start - close map and block opening.
            --]]
            onTransitionStart = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                if data._targetPlayer and data._targetPlayer ~= player then return end

                -- Block map opening during transition
                state.gameplayActive = false

                -- Close map if open (geometry will be rebuilt via onBuildMiniMap)
                if state.isOpen then
                    closeMap(self)
                end
            end,

            --[[
                Handle region transition end - allow map to be opened.
            --]]
            onTransitionEnd = function(self, data)
                local state = getState(self)
                local player = Players.LocalPlayer

                if data._targetPlayer and data._targetPlayer ~= player then return end

                -- Allow map opening now that gameplay is active
                state.gameplayActive = true
            end,
        },

        Out = {
            miniMapReady = {},
            requestVisitedState = {},
        },
    }
end)

return MiniMap
