--[[
    It Gets Worse - IGW Content
    DomBuilder.lua - DOM-based Layout Instantiation

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Replaces LayoutInstantiator with DOM-driven building. Same input (Layout
    table), same return value shape — but the intermediate representation is
    a DOM tree that flows through the Renderer and Style system.

    Lives in IGW content (not warren core) because it encodes game-specific
    cave/palette knowledge.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local result = DomBuilder.instantiate(layout, {
        name = "Region_1",
        regionId = "r1",
    })
    -- result.container, result.domTree, result.pads, etc.
    ```
--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Dom = Warren.Dom
local StyleBridge = Dom.StyleBridge
local Canvas = Dom.Canvas
local Styles = Warren.Styles
local ClassResolver = Warren.ClassResolver

local DomBuilder = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function vec3(t)
    return Vector3.new(t[1] or 0, t[2] or 0, t[3] or 0)
end

--------------------------------------------------------------------------------
-- BUILD TREE: Layout table -> DOM tree (unmounted)
--------------------------------------------------------------------------------

--[[
    Build a DOM tree from a Layout table.

    Converts each layout element to DOM nodes with style classes.
    The tree is NOT mounted — call Dom.mount() separately.

    @param layout table - Layout table from LayoutBuilder
    @param options table - { name, paletteClass }
    @return table - { root, roomNodes, zoneNodes, spawnNode, padNodes }
]]
function DomBuilder.buildTree(layout, options)
    options = options or {}
    local regionNum = layout.regionNum or 1
    local paletteClass = options.paletteClass or StyleBridge.getPaletteClass(regionNum)
    local config = layout.config or { wallThickness = 1 }
    local wt = config.wallThickness or 1

    -- Root container
    local root = Dom.createElement("Model", {
        Name = options.name or "Layout",
        RegionNum = regionNum,
    })

    local roomNodes = {}
    local zoneNodes = {}
    local padNodes = {}
    local spawnNode = nil

    -- BUILD ROOMS
    for id, room in pairs(layout.rooms) do
        local pos = room.position
        local dims = room.dims

        -- Room container (Model)
        local roomModel = Dom.createElement("Model", {
            Name = "Room_" .. id,
        })

        -- Floor
        local floor = Dom.createElement("Part", {
            class = "cave-floor " .. paletteClass,
            Name = "Floor",
            Size = { dims[1] + 2*wt, wt, dims[3] + 2*wt },
            Position = { pos[1], pos[2] - dims[2]/2 - wt/2, pos[3] },
        })
        Dom.appendChild(roomModel, floor)

        -- Ceiling
        local ceiling = Dom.createElement("Part", {
            class = "cave-ceiling " .. paletteClass,
            Name = "Ceiling",
            Size = { dims[1] + 2*wt, wt, dims[3] + 2*wt },
            Position = { pos[1], pos[2] + dims[2]/2 + wt/2, pos[3] },
        })
        Dom.appendChild(roomModel, ceiling)

        -- North wall (+Z)
        local wallN = Dom.createElement("Part", {
            class = "cave-wall " .. paletteClass,
            Name = "Wall_N",
            Size = { dims[1] + 2*wt, dims[2], wt },
            Position = { pos[1], pos[2], pos[3] + dims[3]/2 + wt/2 },
        })
        Dom.appendChild(roomModel, wallN)

        -- South wall (-Z)
        local wallS = Dom.createElement("Part", {
            class = "cave-wall " .. paletteClass,
            Name = "Wall_S",
            Size = { dims[1] + 2*wt, dims[2], wt },
            Position = { pos[1], pos[2], pos[3] - dims[3]/2 - wt/2 },
        })
        Dom.appendChild(roomModel, wallS)

        -- East wall (+X)
        local wallE = Dom.createElement("Part", {
            class = "cave-wall " .. paletteClass,
            Name = "Wall_E",
            Size = { wt, dims[2], dims[3] },
            Position = { pos[1] + dims[1]/2 + wt/2, pos[2], pos[3] },
        })
        Dom.appendChild(roomModel, wallE)

        -- West wall (-X)
        local wallW = Dom.createElement("Part", {
            class = "cave-wall " .. paletteClass,
            Name = "Wall_W",
            Size = { wt, dims[2], dims[3] },
            Position = { pos[1] - dims[1]/2 - wt/2, pos[2], pos[3] },
        })
        Dom.appendChild(roomModel, wallW)

        -- Invisible zone part for player detection
        local zone = Dom.createElement("Part", {
            class = "cave-zone",
            Name = "RoomZone_" .. id,
            Size = { dims[1], dims[2], dims[3] },
            Position = { pos[1], pos[2], pos[3] },
            RoomId = id,
            RegionNum = regionNum,
        })
        Dom.appendChild(roomModel, zone)
        zoneNodes[id] = zone

        Dom.appendChild(root, roomModel)
        roomNodes[id] = roomModel
    end

    -- BUILD TRUSSES
    for _, truss in ipairs(layout.trusses) do
        local trussNode = Dom.createElement("TrussPart", {
            class = "cave-truss",
            Name = "Truss_" .. truss.id,
            Size = { truss.size[1], truss.size[2], truss.size[3] },
            Position = { truss.position[1], truss.position[2], truss.position[3] },
        })
        Dom.appendChild(root, trussNode)
    end

    -- BUILD LIGHTS
    for _, light in ipairs(layout.lights) do
        local roomModel = roomNodes[light.roomId]
        local parent = roomModel or root

        local fixtureSize = light.size
        local fixturePos = light.position

        -- Wall direction for spacer offset
        local wallDirs = {
            N = {0, 0, 1},
            S = {0, 0, -1},
            E = {1, 0, 0},
            W = {-1, 0, 0},
        }
        local wallDir = wallDirs[light.wall] or {0, 0, 1}

        -- Spacer position
        local spacerThickness = 1.5
        local spacerSize, spacerOffset
        if math.abs(wallDir[1]) > 0 then
            spacerSize = { spacerThickness, fixtureSize[2], fixtureSize[3] }
            spacerOffset = {
                wallDir[1] * (fixtureSize[1]/2 + spacerThickness/2),
                0,
                0,
            }
        else
            spacerSize = { fixtureSize[1], fixtureSize[2], spacerThickness }
            spacerOffset = {
                0,
                0,
                wallDir[3] * (fixtureSize[3]/2 + spacerThickness/2),
            }
        end

        local spacer = Dom.createElement("Part", {
            class = "cave-light-spacer " .. paletteClass,
            Name = "Light_" .. light.id .. "_Spacer",
            Size = spacerSize,
            Position = {
                fixturePos[1] + spacerOffset[1],
                fixturePos[2] + spacerOffset[2],
                fixturePos[3] + spacerOffset[3],
            },
        })
        Dom.appendChild(parent, spacer)

        -- Light fixture
        local fixture = Dom.createElement("Part", {
            class = "cave-light-fixture " .. paletteClass,
            Name = "Light_" .. light.id,
            Size = fixtureSize,
            Position = fixturePos,
        })

        -- PointLight child
        local pointLight = Dom.createElement("PointLight", {
            class = "cave-point-light " .. paletteClass,
            Name = "PointLight",
        })
        Dom.appendChild(fixture, pointLight)

        Dom.appendChild(parent, fixture)
    end

    -- BUILD PADS
    for _, pad in ipairs(layout.pads) do
        local roomModel = roomNodes[pad.roomId]
        local parent = roomModel or root

        local padSize = {6, 1, 6}
        local padPos = pad.position

        -- Base under pad
        local baseThickness = 1.5
        local base = Dom.createElement("Part", {
            class = "cave-pad-base " .. paletteClass,
            Name = pad.id .. "_Base",
            Size = { padSize[1], baseThickness, padSize[3] },
            Position = {
                padPos[1],
                padPos[2] - (padSize[2] + baseThickness) / 2,
                padPos[3],
            },
        })
        Dom.appendChild(parent, base)

        -- Pad itself
        local padNode = Dom.createElement("Part", {
            class = "cave-pad",
            Name = pad.id,
            Size = padSize,
            Position = padPos,
            TeleportPad = true,
            PadId = pad.id,
            RoomId = pad.roomId,
        })
        Dom.appendChild(parent, padNode)
        padNodes[pad.id] = padNode
    end

    -- BUILD SPAWN
    if layout.spawn then
        spawnNode = Dom.createElement("SpawnLocation", {
            class = "cave-spawn",
            Name = "Spawn_" .. (options.regionId or "default"),
            Size = {6, 1, 6},
            Position = layout.spawn.position,
        })
        Dom.appendChild(root, spawnNode)
    end

    return {
        root = root,
        roomNodes = roomNodes,
        zoneNodes = zoneNodes,
        padNodes = padNodes,
        spawnNode = spawnNode,
        paletteClass = paletteClass,
    }
end

--------------------------------------------------------------------------------
-- TERRAIN PAINTING
--------------------------------------------------------------------------------

--[[
    Paint all terrain passes for a layout.

    @param layout table - Layout table
    @param options table - { paletteClass }
]]
function DomBuilder.paintTerrain(layout, options)
    options = options or {}
    local config = layout.config or { wallThickness = 1 }
    local useTerrainShell = config.useTerrainShell ~= false
    if not useTerrainShell then return end

    local regionNum = layout.regionNum or 1
    local paletteClass = options.paletteClass or StyleBridge.getPaletteClass(regionNum)
    local palette = StyleBridge.resolvePalette(paletteClass, Styles, ClassResolver)

    local wallMaterial = Enum.Material.Rock
    local floorMaterial = Enum.Material.CrackedLava

    -- Set terrain material colors (no global clear — terrain is zone-scoped)
    Canvas.setMaterialColors(palette)

    -- PASS 1: Fill terrain shells
    for _, room in pairs(layout.rooms) do
        Canvas.fillShell(room.position, room.dims, 0, wallMaterial)
    end

    -- PASS 2: Carve interiors
    for _, room in pairs(layout.rooms) do
        Canvas.carveInterior(room.position, room.dims, 0)
    end

    -- PASS 3: Paint lava veins
    for _, room in pairs(layout.rooms) do
        Canvas.paintNoise({
            roomPos = room.position,
            roomDims = room.dims,
            material = floorMaterial,
            noiseScale = 8,
            threshold = 0.35,
        })
    end

    -- PASS 4: Paint floors
    for _, room in pairs(layout.rooms) do
        Canvas.paintFloor(room.position, room.dims, floorMaterial)
    end

    -- PASS 5: Mix granite patches
    for _, room in pairs(layout.rooms) do
        Canvas.mixPatches({
            roomPos = room.position,
            roomDims = room.dims,
            material = wallMaterial,
            noiseScale = 12,
            threshold = 0.4,
        })
    end
end

--------------------------------------------------------------------------------
-- TERRAIN CLEANUP (zone-scoped)
--------------------------------------------------------------------------------

--[[
    Clear all terrain for a layout's rooms.
    Counterpart to paintTerrain — called when a view is destroyed.
    Only clears the terrain zones belonging to this layout's rooms,
    leaving other views' terrain untouched.

    @param layout table - Layout table
]]
function DomBuilder.clearTerrain(layout)
    local config = layout.config or {}
    local useTerrainShell = config.useTerrainShell ~= false
    if not useTerrainShell then return end

    for _, room in pairs(layout.rooms) do
        Canvas.clearShell(room.position, room.dims, 0)
    end
end

--------------------------------------------------------------------------------
-- DOOR CUTTING (CSG on mounted Instances)
--------------------------------------------------------------------------------

--[[
    Cut doors using CSG subtraction on mounted Instances.
    Must be called AFTER Dom.mount() since CSG needs live Instances.

    @param layout table - Layout table
    @param treeData table - Return value from buildTree
]]
function DomBuilder.cutDoors(layout, treeData)
    local config = layout.config or { wallThickness = 1 }
    local wt = config.wallThickness or 1
    local useTerrainShell = config.useTerrainShell ~= false

    for _, door in ipairs(layout.doors) do
        local cutterDepth = wt * 8
        local cutterSize

        if door.axis == 2 then
            cutterSize = Vector3.new(door.width, cutterDepth, door.height)
        else
            if door.widthAxis == 1 then
                cutterSize = Vector3.new(door.width, door.height, cutterDepth)
            else
                cutterSize = Vector3.new(cutterDepth, door.height, door.width)
            end
        end

        local cutterPos = Vector3.new(door.center[1], door.center[2], door.center[3])

        local cutter = Instance.new("Part")
        cutter.Size = cutterSize
        cutter.Position = cutterPos
        cutter.Anchored = true
        cutter.CanCollide = false
        cutter.Transparency = 1

        -- Find walls to cut in both rooms
        local roomsToCheck = { door.fromRoom, door.toRoom }

        for _, roomId in ipairs(roomsToCheck) do
            local roomNode = treeData.roomNodes[roomId]
            if roomNode and roomNode._instance then
                local roomContainer = roomNode._instance
                for _, child in ipairs(roomContainer:GetChildren()) do
                    if child:IsA("BasePart") and (
                        child.Name:match("^Wall") or
                        child.Name == "Floor" or
                        child.Name == "Ceiling"
                    ) then
                        -- AABB intersection check
                        local wallPos = child.Position
                        local wallSize = child.Size
                        local intersects = true

                        for axis = 1, 3 do
                            local prop = axis == 1 and "X" or axis == 2 and "Y" or "Z"
                            local wMin = wallPos[prop] - wallSize[prop] / 2
                            local wMax = wallPos[prop] + wallSize[prop] / 2
                            local cMin = cutter.Position[prop] - cutter.Size[prop] / 2
                            local cMax = cutter.Position[prop] + cutter.Size[prop] / 2

                            if wMax <= cMin or cMax <= wMin then
                                intersects = false
                                break
                            end
                        end

                        if intersects then
                            local success, result = pcall(function()
                                return child:SubtractAsync({cutter})
                            end)

                            if success and result then
                                result.Name = child.Name
                                result.Parent = roomContainer

                                -- Update DomNode's _instance to point to the CSG result
                                -- Find the DomNode that owns this child Instance
                                local children = Dom.getChildren(roomNode)
                                for _, domChild in ipairs(children) do
                                    if domChild._instance == child then
                                        domChild._instance = result
                                        break
                                    end
                                end

                                child:Destroy()
                            end
                        end
                    end
                end
            end
        end

        -- Clear terrain in doorway
        if useTerrainShell then
            Canvas.carveDoorway(CFrame.new(cutterPos), cutterSize)
        end

        cutter:Destroy()
    end
end

--[[
    Carve terrain clearance around mounted lights and pads.
    Must be called AFTER Dom.mount().

    @param layout table - Layout table
    @param treeData table - Return value from buildTree
]]
function DomBuilder.carveFixtures(layout, treeData)
    local config = layout.config or {}
    local useTerrainShell = config.useTerrainShell ~= false
    if not useTerrainShell then return end

    -- Carve around lights
    for _, light in ipairs(layout.lights) do
        local fixturePos = Vector3.new(light.position[1], light.position[2], light.position[3])
        local fixtureSize = Vector3.new(light.size[1], light.size[2], light.size[3])
        Canvas.carveMargin(CFrame.new(fixturePos), fixtureSize, 2)
    end

    -- Carve around pads
    for _, pad in ipairs(layout.pads) do
        local padPos = Vector3.new(pad.position[1], pad.position[2], pad.position[3])
        local padSize = Vector3.new(6, 1, 6)
        Canvas.carveMargin(CFrame.new(padPos), padSize, 2)
    end
end

--------------------------------------------------------------------------------
-- COMBINED INSTANTIATION
--------------------------------------------------------------------------------

--[[
    Full instantiation: build tree -> set up styles -> mount -> terrain -> doors.

    Drop-in replacement for LayoutInstantiator.instantiate().
    Returns compatible shape + domTree.

    @param layout table - Layout table from LayoutBuilder
    @param options table - { name, regionId, container }
    @return table - Same shape as LayoutInstantiator.instantiate() + domTree
]]
function DomBuilder.instantiate(layout, options)
    options = options or {}

    -- Delete existing SpawnLocations
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("SpawnLocation") then
            child:Destroy()
        end
    end

    -- Set up the style resolver
    local resolver = StyleBridge.createResolver(Styles, ClassResolver)
    Dom.setStyleResolver(resolver)

    -- Build DOM tree
    local treeData = DomBuilder.buildTree(layout, {
        name = options.name,
        regionId = options.regionId,
        paletteClass = options.paletteClass,
    })

    -- Determine parent Instance
    local parentInstance
    if options.container then
        parentInstance = options.container
    else
        parentInstance = workspace
    end

    -- Store region metadata
    local regionNum = layout.regionNum or 1
    local paletteClass = treeData.paletteClass

    print(string.format("[DomBuilder] Region %d using palette: %s", regionNum, paletteClass))

    -- Paint terrain BEFORE mount (so shells exist when parts appear)
    DomBuilder.paintTerrain(layout, { paletteClass = paletteClass })

    -- Mount the DOM tree -> creates all Instances
    Dom.mount(treeData.root, parentInstance)

    -- Cut doors (needs live Instances for CSG)
    DomBuilder.cutDoors(layout, treeData)

    -- Carve terrain around fixtures and pads
    DomBuilder.carveFixtures(layout, treeData)

    -- Build compatible return value
    local container = treeData.root._instance
    local roomContainers = {}
    local roomZones = {}
    local pads = {}

    for id, roomNode in pairs(treeData.roomNodes) do
        roomContainers[id] = roomNode._instance
    end

    for id, zoneNode in pairs(treeData.zoneNodes) do
        roomZones[id] = zoneNode._instance
    end

    for padId, padNode in pairs(treeData.padNodes) do
        pads[padId] = {
            part = padNode._instance,
            id = padId,
            roomId = Dom.getAttribute(padNode, "RoomId"),
            position = Dom.getAttribute(padNode, "Position") or layout.pads[1] and layout.pads[1].position,
            domNode = padNode,
        }
    end

    -- Find pad position from layout data
    for _, pad in ipairs(layout.pads) do
        if pads[pad.id] then
            pads[pad.id].position = pad.position
        end
    end

    local spawnPoint = treeData.spawnNode and treeData.spawnNode._instance
    if spawnPoint then
        print(string.format("[DomBuilder] Spawn at (%.1f, %.1f, %.1f)",
            layout.spawn.position[1], layout.spawn.position[2], layout.spawn.position[3]))
    end

    return {
        container = container,
        roomContainers = roomContainers,
        roomZones = roomZones,
        spawnPoint = spawnPoint,
        spawnPosition = layout.spawn and layout.spawn.position,
        pads = pads,
        roomCount = #layout.rooms,
        domTree = treeData,
    }
end

return DomBuilder
