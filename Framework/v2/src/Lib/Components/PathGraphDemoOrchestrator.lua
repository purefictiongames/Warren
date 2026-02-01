--[[
    LibPureFiction Framework v2
    PathGraphDemoOrchestrator.lua - Visual Path Graph Demonstration

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Orchestrator that manages PathGraph → RoomBlocker pipeline and visualizes
    the generated path with colorful neon beams, junction spheres, and room blocks.

    Features:
    - Creates and configures PathGraph
    - Chains to RoomBlocker for geometry generation
    - Draws visual segments as neon beams
    - Marks junctions with glowing spheres
    - Shows room/hallway block geometry

--]]

local Node = require(script.Parent.Parent.Node)
local PathGraph = require(script.Parent.PathGraph)
local RoomBlocker = require(script.Parent.RoomBlocker)

--------------------------------------------------------------------------------
-- PATHGRAPH DEMO ORCHESTRATOR (Closure-Based Privacy Pattern)
--------------------------------------------------------------------------------

local PathGraphDemoOrchestrator = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE SCOPE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    -- Direction colors (vibrant neon palette)
    local DIR_COLORS = {
        N = Color3.fromRGB(0, 255, 200),    -- Cyan-green (north/+Z)
        S = Color3.fromRGB(255, 100, 150),  -- Pink (south/-Z)
        E = Color3.fromRGB(255, 200, 0),    -- Gold (east/+X)
        W = Color3.fromRGB(150, 100, 255),  -- Purple (west/-X)
        U = Color3.fromRGB(100, 255, 100),  -- Bright green (up/+Y)
        D = Color3.fromRGB(255, 80, 80),    -- Red (down/-Y)
    }

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                pathGraph = nil,
                roomBlocker = nil,
                visualFolder = nil,
                pathData = nil,
                geometryData = nil,
                origin = Vector3.new(0, 5, 0),
                showPathLines = true,
                showRoomBlocks = true,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --[[
        Get direction from one position to another.
    --]]
    local function getDirection(fromPos, toPos)
        local dx = toPos[1] - fromPos[1]
        local dy = toPos[2] - fromPos[2]
        local dz = toPos[3] - fromPos[3]

        local ax, ay, az = math.abs(dx), math.abs(dy), math.abs(dz)

        if ax >= ay and ax >= az then
            return dx > 0 and "E" or "W"
        elseif az >= ax and az >= ay then
            return dz > 0 and "N" or "S"
        else
            return dy > 0 and "U" or "D"
        end
    end

    --[[
        Convert array position to Vector3 with origin offset.
    --]]
    local function toVector3(self, pos)
        local state = getState(self)
        return state.origin + Vector3.new(pos[1], pos[2], pos[3])
    end

    --[[
        Create a neon beam segment between two positions.
    --]]
    local function createSegmentBeam(self, fromPos, toPos, segmentId)
        local state = getState(self)

        local fromVec = toVector3(self, fromPos)
        local toVec = toVector3(self, toPos)

        local direction = getDirection(fromPos, toPos)
        local color = DIR_COLORS[direction] or Color3.fromRGB(255, 255, 255)

        local midpoint = (fromVec + toVec) / 2
        local delta = toVec - fromVec
        local length = delta.Magnitude

        if length < 0.1 then
            return nil
        end

        -- Offset beams slightly above floor
        midpoint = midpoint + Vector3.new(0, 2, 0)

        local beam = Instance.new("Part")
        beam.Name = "Segment_" .. segmentId
        beam.Size = Vector3.new(0.3, 0.3, length)
        beam.CFrame = CFrame.lookAt(midpoint, toVec + Vector3.new(0, 2, 0))
        beam.Anchored = true
        beam.CanCollide = false
        beam.Material = Enum.Material.Neon
        beam.Color = color
        beam.Parent = state.visualFolder

        local glow = Instance.new("PointLight")
        glow.Color = color
        glow.Brightness = 0.3
        glow.Range = 3
        glow.Parent = beam

        return beam
    end

    --[[
        Create a junction sphere at a position.
    --]]
    local function createJunctionSphere(self, pos, pointId, connectionCount)
        local state = getState(self)
        local pathData = state.pathData

        local worldPos = toVector3(self, pos) + Vector3.new(0, 2, 0)

        local size = 0.6 + (connectionCount - 1) * 0.3
        size = math.min(size, 2)

        local color
        if pointId == pathData.start then
            color = Color3.fromRGB(0, 255, 0)
            size = 1.5
        elseif table.find(pathData.goals, pointId) then
            color = Color3.fromRGB(255, 215, 0)
            size = 1.5
        elseif connectionCount >= 3 then
            color = Color3.fromRGB(255, 255, 255)
        elseif connectionCount == 1 then
            color = Color3.fromRGB(255, 100, 100)
        else
            color = Color3.fromRGB(150, 150, 200)
            size = 0.5
        end

        local sphere = Instance.new("Part")
        sphere.Name = "Point_" .. pointId
        sphere.Shape = Enum.PartType.Ball
        sphere.Size = Vector3.new(size, size, size)
        sphere.Position = worldPos
        sphere.Anchored = true
        sphere.CanCollide = false
        sphere.Material = Enum.Material.Neon
        sphere.Color = color
        sphere.Parent = state.visualFolder

        local glow = Instance.new("PointLight")
        glow.Color = color
        glow.Brightness = 0.8
        glow.Range = size * 2
        glow.Parent = sphere

        if pointId == pathData.start or table.find(pathData.goals, pointId) then
            local billboard = Instance.new("BillboardGui")
            billboard.Size = UDim2.new(0, 80, 0, 25)
            billboard.StudsOffset = Vector3.new(0, size + 1, 0)
            billboard.AlwaysOnTop = true
            billboard.Parent = sphere

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 0.3
            label.BackgroundColor3 = Color3.new(0, 0, 0)
            label.TextColor3 = color
            label.TextScaled = true
            label.Font = Enum.Font.GothamBold
            label.Text = pointId == pathData.start and "START" or "GOAL"
            label.Parent = billboard
        end

        return sphere
    end

    --[[
        Create info display.
    --]]
    local function createInfoDisplay(self)
        local state = getState(self)
        local pathData = state.pathData
        local geometryData = state.geometryData

        local pointCount = 0
        local junctionCount = 0
        local deadEndCount = 0

        for _, point in pairs(pathData.points) do
            pointCount = pointCount + 1
            if #point.connections >= 3 then
                junctionCount = junctionCount + 1
            elseif #point.connections == 1 then
                deadEndCount = deadEndCount + 1
            end
        end

        local infoPart = Instance.new("Part")
        infoPart.Name = "InfoDisplay"
        infoPart.Size = Vector3.new(1, 1, 1)
        infoPart.Position = state.origin + Vector3.new(0, 30, 0)
        infoPart.Anchored = true
        infoPart.CanCollide = false
        infoPart.Transparency = 1
        infoPart.Parent = state.visualFolder

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 320, 0, 180)
        billboard.AlwaysOnTop = true
        billboard.Parent = infoPart

        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundTransparency = 0.2
        frame.BackgroundColor3 = Color3.new(0, 0, 0)
        frame.Parent = billboard

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = frame

        local baseUnit = geometryData and geometryData.baseUnit or "N/A"
        local roomCount = geometryData and #geometryData.rooms or 0
        local hallwayCount = geometryData and #geometryData.hallways or 0

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -10, 1, -10)
        label.Position = UDim2.new(0, 5, 0, 5)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextScaled = true
        label.Font = Enum.Font.Code
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Text = string.format(
            "PATHGRAPH + ROOMBLOCKER DEMO\n" ..
            "════════════════════════════\n" ..
            "Seed: %s\n" ..
            "Base Unit: %s\n" ..
            "Points: %d | Segments: %d\n" ..
            "Junctions: %d | Dead Ends: %d\n" ..
            "Rooms: %d | Hallways: %d",
            pathData.seed or "N/A",
            tostring(baseUnit),
            pointCount,
            #pathData.segments,
            junctionCount,
            deadEndCount,
            roomCount,
            hallwayCount
        )
        label.Parent = frame

        -- Legend
        local legendPart = Instance.new("Part")
        legendPart.Name = "Legend"
        legendPart.Size = Vector3.new(1, 1, 1)
        legendPart.Position = state.origin + Vector3.new(0, 18, 0)
        legendPart.Anchored = true
        legendPart.CanCollide = false
        legendPart.Transparency = 1
        legendPart.Parent = state.visualFolder

        local legendBillboard = Instance.new("BillboardGui")
        legendBillboard.Size = UDim2.new(0, 180, 0, 100)
        legendBillboard.AlwaysOnTop = true
        legendBillboard.Parent = legendPart

        local legendFrame = Instance.new("Frame")
        legendFrame.Size = UDim2.new(1, 0, 1, 0)
        legendFrame.BackgroundTransparency = 0.2
        legendFrame.BackgroundColor3 = Color3.new(0, 0, 0)
        legendFrame.Parent = legendBillboard

        local legendCorner = Instance.new("UICorner")
        legendCorner.CornerRadius = UDim.new(0, 10)
        legendCorner.Parent = legendFrame

        local legendLabel = Instance.new("TextLabel")
        legendLabel.Size = UDim2.new(1, -10, 1, -10)
        legendLabel.Position = UDim2.new(0, 5, 0, 5)
        legendLabel.BackgroundTransparency = 1
        legendLabel.TextColor3 = Color3.new(1, 1, 1)
        legendLabel.TextScaled = true
        legendLabel.Font = Enum.Font.Code
        legendLabel.TextXAlignment = Enum.TextXAlignment.Left
        legendLabel.TextYAlignment = Enum.TextYAlignment.Top
        legendLabel.RichText = true
        legendLabel.Text =
            '<font color="#00ffc8">■ North</font>  ' ..
            '<font color="#ff6496">■ South</font>\n' ..
            '<font color="#ffc800">■ East</font>  ' ..
            '<font color="#9664ff">■ West</font>\n' ..
            '<font color="#64ff64">■ Up</font>  ' ..
            '<font color="#ff5050">■ Down</font>'
        legendLabel.Parent = legendFrame
    end

    --[[
        Draw path visualization (beams and spheres).
    --]]
    local function drawPathVisualization(self)
        local state = getState(self)
        local pathData = state.pathData

        if not pathData or not state.showPathLines then
            return
        end

        -- Debug: count points and segments
        local pointCount = 0
        for _ in pairs(pathData.points) do pointCount = pointCount + 1 end
        print("[PathGraphDemo] Drawing visualization:")
        print("  Points in pathData:", pointCount)
        print("  Segments in pathData:", #pathData.segments)

        -- Draw segments
        local segmentsDrawn = 0
        local segmentsSkipped = 0
        for _, seg in ipairs(pathData.segments) do
            local fromPoint = pathData.points[seg.from]
            local toPoint = pathData.points[seg.to]

            if fromPoint and toPoint then
                createSegmentBeam(self, fromPoint.pos, toPoint.pos, seg.id)
                segmentsDrawn = segmentsDrawn + 1
            else
                segmentsSkipped = segmentsSkipped + 1
                print("  WARNING: Skipped segment", seg.id, "from:", seg.from, "to:", seg.to,
                      "fromPoint:", fromPoint ~= nil, "toPoint:", toPoint ~= nil)
            end
        end
        print("  Segments drawn:", segmentsDrawn, "skipped:", segmentsSkipped)

        -- Draw junction spheres
        for pointId, point in pairs(pathData.points) do
            createJunctionSphere(self, point.pos, pointId, #point.connections)
        end
    end

    --[[
        Move RoomBlocker geometry to correct position with origin offset.
    --]]
    local function adjustRoomBlockerGeometry(self)
        local state = getState(self)
        if not state.roomBlocker then
            print("[PathGraphDemo] adjustRoomBlockerGeometry: no roomBlocker")
            return
        end

        local container = state.roomBlocker:getContainer()
        if not container then
            print("[PathGraphDemo] adjustRoomBlockerGeometry: no container")
            return
        end

        print("[PathGraphDemo] Adjusting geometry in container:", container.Name)
        print("[PathGraphDemo] Container children:", #container:GetChildren())
        print("[PathGraphDemo] Origin offset:", state.origin)

        -- Move all parts by origin offset
        local adjustedCount = 0
        for _, part in ipairs(container:GetChildren()) do
            if part:IsA("BasePart") then
                part.Position = part.Position + state.origin
                adjustedCount = adjustedCount + 1
            end
        end
        print("[PathGraphDemo] Adjusted", adjustedCount, "parts")
    end

    --[[
        Draw everything.
    --]]
    local function drawAll(self)
        local state = getState(self)

        if not state.pathData then return end

        drawPathVisualization(self)
        createInfoDisplay(self)

        print("[PathGraphDemo] Visualization complete!")
        print("  Seed:", state.pathData.seed)
        print("  Segments:", #state.pathData.segments)
        if state.geometryData then
            print("  Base Unit:", state.geometryData.baseUnit)
            print("  Rooms:", #state.geometryData.rooms)
            print("  Hallways:", #state.geometryData.hallways)
        end
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "PathGraphDemoOrchestrator",
        domain = "server",

        Sys = {
            onInit = function(self)
                local state = getState(self)

                state.visualFolder = self:getAttribute("visualFolder")
                state.origin = self:getAttribute("origin") or Vector3.new(0, 5, 0)
                state.showPathLines = self:getAttribute("showPathLines")
                if state.showPathLines == nil then state.showPathLines = true end
                state.showRoomBlocks = self:getAttribute("showRoomBlocks")
                if state.showRoomBlocks == nil then state.showRoomBlocks = true end

                print("[PathGraphDemo] Init - visualFolder:", state.visualFolder and state.visualFolder.Name or "NIL")
                print("[PathGraphDemo] Init - origin:", state.origin)
                print("[PathGraphDemo] Init - showRoomBlocks:", state.showRoomBlocks)

                -- Create PathGraph node
                state.pathGraph = PathGraph:new({
                    id = self.id .. "_PathGraph",
                })
                state.pathGraph.Sys.onInit(state.pathGraph)

                -- Create RoomBlocker node
                state.roomBlocker = RoomBlocker:new({
                    id = self.id .. "_RoomBlocker",
                })
                state.roomBlocker.Sys.onInit(state.roomBlocker)

                -- Configure RoomBlocker container and PathGraph reference
                state.roomBlocker.In.onConfigure(state.roomBlocker, {
                    container = state.visualFolder,
                    pathGraphRef = state.pathGraph,  -- For overlap resolution updates
                    hallScale = 1,
                    heightScale = 2,
                    roomScale = 1.5,
                    junctionScale = 2,
                })

                -- Wire PathGraph → RoomBlocker → Self
                local orchestrator = self

                -- PathGraph output
                local pgOriginalFire = state.pathGraph.Out.Fire
                state.pathGraph.Out.Fire = function(outSelf, signal, data)
                    if signal == "path" then
                        -- Store path data
                        state.pathData = data

                        -- Chain to RoomBlocker if enabled
                        if state.showRoomBlocks then
                            state.roomBlocker.In.onBuildFromPath(state.roomBlocker, data)
                        else
                            -- Just draw visualization without room blocks
                            drawAll(orchestrator)
                            orchestrator.Out:Fire("pathReceived", {
                                pointCount = 0,
                                segmentCount = #data.segments,
                                seed = data.seed,
                            })
                        end
                    elseif signal == "complete" then
                        orchestrator.Out:Fire("generationComplete", data)
                    end
                    pgOriginalFire(outSelf, signal, data)
                end

                -- RoomBlocker output
                local rbOriginalFire = state.roomBlocker.Out.Fire
                state.roomBlocker.Out.Fire = function(outSelf, signal, data)
                    if signal == "geometry" then
                        state.geometryData = data

                        -- Adjust geometry position
                        adjustRoomBlockerGeometry(orchestrator)

                        -- Draw path visualization using original pathData
                        -- (shifted positions break segment orthogonality)
                        drawAll(orchestrator)

                        local pointCount = 0
                        for _ in pairs(state.pathData.points) do
                            pointCount = pointCount + 1
                        end

                        orchestrator.Out:Fire("pathReceived", {
                            pointCount = pointCount,
                            segmentCount = #state.pathData.segments,
                            seed = state.pathData.seed,
                            baseUnit = data.baseUnit,
                            roomCount = #data.rooms,
                            hallwayCount = #data.hallways,
                        })
                    elseif signal == "built" then
                        orchestrator.Out:Fire("geometryBuilt", data)
                    end
                    rbOriginalFire(outSelf, signal, data)
                end
            end,

            onStart = function(self)
                local state = getState(self)
                if state.pathGraph then
                    state.pathGraph.Sys.onStart(state.pathGraph)
                end
                if state.roomBlocker then
                    state.roomBlocker.Sys.onStart(state.roomBlocker)
                end
            end,

            onStop = function(self)
                local state = getState(self)
                if state.pathGraph then
                    state.pathGraph.Sys.onStop(state.pathGraph)
                end
                if state.roomBlocker then
                    state.roomBlocker.Sys.onStop(state.roomBlocker)
                end
                cleanupState(self)
            end,
        },

        In = {
            onConfigure = function(self, data)
                local state = getState(self)
                if state.pathGraph then
                    state.pathGraph.In.onConfigure(state.pathGraph, data)
                end

                -- Pass room-specific config to RoomBlocker
                if state.roomBlocker and data then
                    local roomConfig = {}
                    if data.hallScale then roomConfig.hallScale = data.hallScale end
                    if data.heightScale then roomConfig.heightScale = data.heightScale end
                    if data.roomScale then roomConfig.roomScale = data.roomScale end
                    if data.junctionScale then roomConfig.junctionScale = data.junctionScale end

                    if next(roomConfig) then
                        state.roomBlocker.In.onConfigure(state.roomBlocker, roomConfig)
                    end
                end
            end,

            onGenerate = function(self, data)
                local state = getState(self)
                if state.pathGraph then
                    state.pathGraph.In.onGenerate(state.pathGraph, data)
                end
            end,

            onClear = function(self)
                local state = getState(self)
                if state.roomBlocker then
                    state.roomBlocker.In.onClear(state.roomBlocker)
                end
                -- Clear visualization parts
                if state.visualFolder then
                    for _, child in ipairs(state.visualFolder:GetChildren()) do
                        child:Destroy()
                    end
                end
                state.pathData = nil
                state.geometryData = nil
            end,
        },

        Out = {
            pathReceived = {},
            generationComplete = {},
            geometryBuilt = {},
        },

        getPathData = function(self)
            local state = getState(self)
            return state.pathData
        end,

        getGeometryData = function(self)
            local state = getState(self)
            return state.geometryData
        end,

        getRoomBlocker = function(self)
            local state = getState(self)
            return state.roomBlocker
        end,
    }
end)

return PathGraphDemoOrchestrator
