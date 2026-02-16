--[[
    IGW v2 — Pipeline Smoke Test

    Standalone ServerScript that manually chains every pipeline node handler
    in sequence, bypassing IPC entirely.

    Bootstrap is disabled — this is the ONLY script running.
    Enable/disable by adding or removing from default.project.json.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Warren = require(ReplicatedStorage:WaitForChild("Warren"))
local Components = require(ReplicatedStorage:WaitForChild("Components"))
local Dom = Warren.Dom
local StyleBridge = Dom.StyleBridge
local Styles = Warren.Styles
local ClassResolver = Warren.ClassResolver

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

local TEST_SEED = 42
local TEST_ORIGIN = { 0, 20, 0 }
local REGION_NUM = 1

local dungeonConfig = {
    seed = TEST_SEED,
    baseUnit = 5, wallThickness = 1, doorSize = 12,
    floorThreshold = 6.5,
    mainPathLength = 6, spurCount = 2, loopCount = 0,
    verticalChance = 30, minVerticalRatio = 0.2,
    scaleRange = { min = 4, max = 10, minY = 4, maxY = 8 },
    material = "Brick", color = { 140, 110, 90 },
    hubInterval = 4, hubPadRange = { min = 3, max = 4 },
    padCount = 2,
    origin = TEST_ORIGIN,
}

--------------------------------------------------------------------------------
-- LIGHTING (so it actually looks like a cave)
--------------------------------------------------------------------------------

Lighting.ClockTime = 0
Lighting.Brightness = 0
Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
Lighting.Ambient = Color3.fromRGB(20, 20, 25)
Lighting.FogEnd = 1000
Lighting.FogColor = Color3.fromRGB(0, 0, 0)
Lighting.GlobalShadows = false

--------------------------------------------------------------------------------
-- PIPELINE ORDER — same chain as manifest wiring
--------------------------------------------------------------------------------

local PIPELINE = {
    "RoomMasser",
    "ShellBuilder",
    "DoorPlanner",
    "TrussBuilder",
    "LightBuilder",
    "PadBuilder",
    "SpawnSetter",
    "Materializer",
    "DoorCutter",
    "TerrainPainter",
}

--------------------------------------------------------------------------------
-- MOCK SELF — pipeline nodes only use self.Out:Fire()
--------------------------------------------------------------------------------

local function makeMockSelf()
    return {
        Out = {
            Fire = function() end,
        },
    }
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
-- RUN
--------------------------------------------------------------------------------

print("\n============================================")
print("  IGW v2 Pipeline Smoke Test")
print("============================================")
print(string.format("  Seed: %d  Origin: (%d, %d, %d)", TEST_SEED,
    TEST_ORIGIN[1], TEST_ORIGIN[2], TEST_ORIGIN[3]))
print("--------------------------------------------")

-- Set up style resolver
local resolver = StyleBridge.createResolver(Styles, ClassResolver)
Dom.setStyleResolver(resolver)

local paletteClass = StyleBridge.getPaletteClass(REGION_NUM)
print("[Setup] Palette class:", paletteClass)

-- Create DOM root
local root = Dom.createElement("Model", {
    Name = "Region_" .. REGION_NUM,
})

-- Initial payload
local payload = {
    dom = root,
    config = dungeonConfig,
    seed = TEST_SEED,
    regionNum = REGION_NUM,
    paletteClass = paletteClass,
}

local startTime = os.clock()
local passCount = 0
local failCount = 0

local function pass(msg) passCount = passCount + 1; print("[PASS] " .. msg) end
local function fail(msg) failCount = failCount + 1; warn("[FAIL] " .. msg) end

-- Run each pipeline stage in order
for _, stageName in ipairs(PIPELINE) do
    print("")
    local nodeClass = Components[stageName]
    if not nodeClass then
        fail(stageName .. " — not found in Components")
        continue
    end

    local handler = nodeClass.In and nodeClass.In.onBuildPass
    if not handler then
        fail(stageName .. " — no In.onBuildPass handler")
        continue
    end

    local mockSelf = makeMockSelf()
    local stageStart = os.clock()
    local ok, err = pcall(handler, mockSelf, payload)
    local elapsed = os.clock() - stageStart

    if not ok then
        fail(string.format("%s — ERROR (%.3fs): %s", stageName, elapsed, tostring(err)))
    else
        pass(string.format("%s — ok (%.3fs)", stageName, elapsed))
    end

    -- Post-stage diagnostics
    if stageName == "RoomMasser" and ok then
        local rc = payload.rooms and count(payload.rooms) or 0
        print(string.format("  → %d rooms placed", rc))
        if payload.rooms then
            for id, room in pairs(payload.rooms) do
                print(string.format("    Room %d: pos=(%.0f,%.0f,%.0f) dims=(%.0f,%.0f,%.0f) parent=%s",
                    id, room.position[1], room.position[2], room.position[3],
                    room.dims[1], room.dims[2], room.dims[3],
                    tostring(room.parentId or "none")))
            end
        end
    end

    if stageName == "DoorPlanner" and ok then
        local dc = payload.doors and #payload.doors or 0
        print(string.format("  → %d doors planned", dc))
        if payload.doors then
            for _, door in ipairs(payload.doors) do
                print(string.format("    Door %d: rooms %d↔%d axis=%d center=(%.1f,%.1f,%.1f) w=%.1f h=%.1f",
                    door.id, door.fromRoom, door.toRoom, door.axis,
                    door.center[1], door.center[2], door.center[3],
                    door.width, door.height))
            end
        end
    end

    if stageName == "TrussBuilder" and ok then
        print(string.format("  → %d trusses", payload.trusses and #payload.trusses or 0))
    end

    if stageName == "LightBuilder" and ok then
        print(string.format("  → %d lights", payload.lights and #payload.lights or 0))
    end

    if stageName == "PadBuilder" and ok then
        print(string.format("  → %d pads", payload.pads and #payload.pads or 0))
    end

    if stageName == "SpawnSetter" and ok and payload.spawn then
        local sp = payload.spawn.position
        print(string.format("  → Spawn at (%.1f, %.1f, %.1f)", sp[1], sp[2], sp[3]))
    end

    if stageName == "Materializer" and ok then
        local container = payload.container
        if container then
            print(string.format("  → Mounted: %s (%d children in workspace)",
                container.Name, #container:GetChildren()))
        else
            warn("  → WARNING: payload.container is nil after mount")
        end
    end

    if stageName == "DoorCutter" and ok then
        -- Verify door cuts by checking room models for CSG results
        if payload.container then
            local cutParts = 0
            for _, child in ipairs(payload.container:GetDescendants()) do
                if child:IsA("UnionOperation") then
                    cutParts = cutParts + 1
                end
            end
            print(string.format("  → %d UnionOperation parts (CSG results) in workspace", cutParts))
            if cutParts == 0 and payload.doors and #payload.doors > 0 then
                warn("  → WARNING: Doors planned but 0 CSG cuts succeeded!")
                warn("  → Checking room model children...")
                for _, child in ipairs(payload.container:GetChildren()) do
                    if child:IsA("Model") then
                        local parts = {}
                        for _, p in ipairs(child:GetChildren()) do
                            table.insert(parts, string.format("%s(%s)", p.Name, p.ClassName))
                        end
                        print(string.format("    %s: %s", child.Name, table.concat(parts, ", ")))
                    end
                end
            end
        end
    end
end

local totalTime = os.clock() - startTime

--------------------------------------------------------------------------------
-- SUMMARY
--------------------------------------------------------------------------------

print("\n============================================")
print(string.format("  Result: %d passed, %d failed (%.3fs)", passCount, failCount, totalTime))
print("============================================")

if failCount == 0 then
    print("  All stages passed. You should spawn in the dungeon.")
else
    warn("  Some stages failed — check errors above.")
end
