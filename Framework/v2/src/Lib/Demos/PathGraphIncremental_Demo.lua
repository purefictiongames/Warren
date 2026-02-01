--[[
    LibPureFiction Framework v2
    PathGraphIncremental_Demo.lua - Incremental Path + Room Demo

    Demonstrates the new incremental architecture where PathGraph and RoomBlocker
    work in lockstep, validating one segment at a time.

    Usage:
    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    Demos.PathGraphIncremental.run()
    ```
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Demo = {}

function Demo.run(config)
    config = config or {}

    ---------------------------------------------------------------------------
    -- CLEANUP
    ---------------------------------------------------------------------------

    local existingDemo = workspace:FindFirstChild("PathGraphIncremental_Demo")
    if existingDemo then
        existingDemo:Destroy()
    end
    task.wait(0.1)

    ---------------------------------------------------------------------------
    -- SETUP
    ---------------------------------------------------------------------------

    local demoFolder = Instance.new("Folder")
    demoFolder.Name = "PathGraphIncremental_Demo"
    demoFolder.Parent = workspace

    -- Get components
    local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
    local PathGraph = Lib.Components.PathGraphIncremental
    local RoomBlocker = Lib.Components.RoomBlockerIncremental

    ---------------------------------------------------------------------------
    -- CREATE NODES
    ---------------------------------------------------------------------------

    local pathGraph = PathGraph:new({ id = "Demo_PathGraph" })
    pathGraph.Sys.onInit(pathGraph)

    local roomBlocker = RoomBlocker:new({ id = "Demo_RoomBlocker" })
    roomBlocker.Sys.onInit(roomBlocker)

    local baseUnit = config.baseUnit or 15

    -- Configure
    pathGraph.In.onConfigure(pathGraph, {
        baseUnit = baseUnit,
        seed = config.seed,
        spurCount = config.spurCount or { min = 2, max = 4 },
        maxSegmentsPerBranch = config.maxSegments or 10,
    })

    roomBlocker.In.onConfigure(roomBlocker, {
        baseUnit = baseUnit,
        container = demoFolder,
        hallScale = config.hallScale or 1,
        heightScale = config.heightScale or 2,
        roomScale = config.roomScale or 1.5,
        junctionScale = config.junctionScale or 2,
    })

    ---------------------------------------------------------------------------
    -- WIRE SIGNALS (the handshake)
    ---------------------------------------------------------------------------

    -- PathGraph -> RoomBlocker: segment
    local pgOriginalFire = pathGraph.Out.Fire
    pathGraph.Out.Fire = function(outSelf, signal, data)
        if signal == "segment" then
            print("[Demo] PathGraph sent segment:", data.segmentId)
            roomBlocker.In.onSegment(roomBlocker, data)
        elseif signal == "branchComplete" then
            print("[Demo] Branch complete:", data.branchIndex, data.branchType)
        elseif signal == "complete" then
            print("==========================================")
            print("[Demo] PATH GENERATION COMPLETE")
            print("  Seed:", data.seed)
            print("  Total Points:", data.totalPoints)
            print("  Total Segments:", data.totalSegments)
            print("==========================================")

            -- Draw path visualization
            Demo.drawPaths(pathGraph, demoFolder, baseUnit)
        end
        pgOriginalFire(outSelf, signal, data)
    end

    -- RoomBlocker -> PathGraph: segmentResult
    local rbOriginalFire = roomBlocker.Out.Fire
    roomBlocker.Out.Fire = function(outSelf, signal, data)
        if signal == "segmentResult" then
            if data.ok then
                print("[Demo] RoomBlocker: OK")
            else
                print("[Demo] RoomBlocker: Overlap", data.overlapAmount)
            end
            pathGraph.In.onSegmentResult(pathGraph, data)
        end
        rbOriginalFire(outSelf, signal, data)
    end

    ---------------------------------------------------------------------------
    -- START GENERATION
    ---------------------------------------------------------------------------

    print("==========================================")
    print("[Demo] Starting incremental path generation")
    print("==========================================")

    local origin = config.position or Vector3.new(0, 5, 0)

    pathGraph.In.onGenerate(pathGraph, {
        start = { origin.X, origin.Y, origin.Z },
        goals = config.goals or { { origin.X + 120, origin.Y, origin.Z + 120 } },
    })

    ---------------------------------------------------------------------------
    -- CLEANUP HANDLER
    ---------------------------------------------------------------------------

    demoFolder.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("[Demo] Cleanup...")
            pathGraph.Sys.onStop(pathGraph)
            roomBlocker.Sys.onStop(roomBlocker)
        end
    end)

    return {
        pathGraph = pathGraph,
        roomBlocker = roomBlocker,
        folder = demoFolder,
    }
end

--[[
    Draw path visualization after generation is complete.
--]]
function Demo.drawPaths(pathGraph, container, baseUnit)
    local pathData = pathGraph:getPath()

    if not pathData or not pathData.segments then
        print("[Demo] No path data to draw")
        return
    end

    print("[Demo] Drawing", #pathData.segments, "path segments")

    -- Direction colors
    local DIR_COLORS = {
        N = Color3.fromRGB(0, 255, 200),
        S = Color3.fromRGB(255, 100, 150),
        E = Color3.fromRGB(255, 200, 0),
        W = Color3.fromRGB(150, 100, 255),
        U = Color3.fromRGB(100, 255, 100),
        D = Color3.fromRGB(255, 80, 80),
    }

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

    -- Draw segments
    for _, seg in ipairs(pathData.segments) do
        local fromPoint = pathData.points[seg.from]
        local toPoint = pathData.points[seg.to]

        if fromPoint and toPoint then
            local fromPos = fromPoint.pos
            local toPos = toPoint.pos

            local fromVec = Vector3.new(fromPos[1], fromPos[2] + 2, fromPos[3])
            local toVec = Vector3.new(toPos[1], toPos[2] + 2, toPos[3])

            local dir = getDirection(fromPos, toPos)
            local color = DIR_COLORS[dir] or Color3.new(1, 1, 1)

            local midpoint = (fromVec + toVec) / 2
            local delta = toVec - fromVec
            local length = delta.Magnitude

            if length > 0.1 then
                local beam = Instance.new("Part")
                beam.Name = "Segment_" .. seg.id
                beam.Size = Vector3.new(0.4, 0.4, length)
                beam.CFrame = CFrame.lookAt(midpoint, toVec)
                beam.Anchored = true
                beam.CanCollide = false
                beam.Material = Enum.Material.Neon
                beam.Color = color
                beam.Parent = container

                local glow = Instance.new("PointLight")
                glow.Color = color
                glow.Brightness = 0.3
                glow.Range = 4
                glow.Parent = beam
            end
        end
    end

    -- Draw junction spheres
    for pointId, point in pairs(pathData.points) do
        local pos = point.pos
        local worldPos = Vector3.new(pos[1], pos[2] + 2, pos[3])
        local connCount = #point.connections

        local size = 0.6 + (connCount - 1) * 0.3
        size = math.min(size, 2)

        local color
        if pointId == pathData.start then
            color = Color3.fromRGB(0, 255, 0)
            size = 1.5
        elseif table.find(pathData.goals, pointId) then
            color = Color3.fromRGB(255, 215, 0)
            size = 1.5
        elseif connCount >= 3 then
            color = Color3.fromRGB(255, 255, 255)
        elseif connCount == 1 then
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
        sphere.Parent = container

        -- Labels for start/goal
        if pointId == pathData.start or table.find(pathData.goals, pointId) then
            local billboard = Instance.new("BillboardGui")
            billboard.Size = UDim2.new(0, 60, 0, 20)
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
    end
end

return Demo
