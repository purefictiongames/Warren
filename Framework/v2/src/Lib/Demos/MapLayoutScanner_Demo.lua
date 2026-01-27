--[[
    LibPureFiction Framework v2
    MapLayout Scanner Demo/Utility

    This module provides utilities for scanning existing geometry
    and generating MapLayout configuration code.

    ============================================================================
    QUICK START (Command Bar)
    ============================================================================

    1. Build some geometry in Studio (parts, not meshes)
    2. Put them in a Model or Folder (e.g., workspace.MyLayout)
    3. Run in command bar:

        require(game.ReplicatedStorage.Lib.MapLayout).scan(workspace.MyLayout)

    4. Copy the generated code from Output

    ============================================================================
    TAGGING PARTS (OPTIONAL)
    ============================================================================

    For better output, tag parts with attributes before scanning:

    MapLayoutId (string):
        Becomes the element's 'id' in config
        Example: "northWall", "mainFloor"

    MapLayoutClass (string):
        Becomes the element's 'class' in config
        Example: "exterior brick", "interior wood"

    MapLayoutArea (string):
        Groups parts into a named area (prefab)
        All parts with same area name become one area definition
        Example: "hallway1", "lobby"

    MapLayoutType (string):
        Override auto-detected type
        Options: "wall", "floor", "platform", "cylinder", "sphere", "wedge"

    MapLayoutIgnore (boolean):
        Set to true to skip this part entirely

    ============================================================================
    USAGE EXAMPLES
    ============================================================================

    ```lua
    local Demos = require(game.ReplicatedStorage.Lib.Demos)
    local ScannerDemo = Demos.MapLayoutScanner

    -- Create test geometry
    local testModel = ScannerDemo.createTestGeometry()

    -- Scan it
    ScannerDemo.run(testModel)

    -- Or scan your own model
    ScannerDemo.run(workspace.MyLayout)

    -- Scan with options
    ScannerDemo.run(workspace.MyLayout, {
        includeStyles = true,   -- Include style template
        inferTypes = true,      -- Auto-detect element types
    })
    ```

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lib = require(ReplicatedStorage.Lib)
local MapLayout = Lib.MapLayout

local ScannerDemo = {}

--[[
    Create test geometry for demonstration.
    Returns a Model with sample walls, floors, and platforms.
--]]
function ScannerDemo.createTestGeometry()
    -- Clean up existing
    local existing = workspace:FindFirstChild("ScannerTestGeometry")
    if existing then
        existing:Destroy()
    end

    local model = Instance.new("Model")
    model.Name = "ScannerTestGeometry"

    -- Create a simple room

    -- Floor (flat, wide)
    local floor = Instance.new("Part")
    floor.Name = "Floor"
    floor.Size = Vector3.new(20, 0.5, 15)
    floor.Position = Vector3.new(10, 0.25, 7.5)
    floor.Anchored = true
    floor.Material = Enum.Material.SmoothPlastic
    floor.Color = Color3.fromRGB(200, 195, 185)
    floor:SetAttribute("MapLayoutId", "mainFloor")
    floor:SetAttribute("MapLayoutClass", "concrete")
    floor.Parent = model

    -- North wall (tall, thin)
    local northWall = Instance.new("Part")
    northWall.Name = "NorthWall"
    northWall.Size = Vector3.new(20, 10, 1)
    northWall.Position = Vector3.new(10, 5, 0)
    northWall.Anchored = true
    northWall.Material = Enum.Material.Concrete
    northWall:SetAttribute("MapLayoutId", "northWall")
    northWall:SetAttribute("MapLayoutClass", "exterior")
    northWall.Parent = model

    -- South wall
    local southWall = Instance.new("Part")
    southWall.Name = "SouthWall"
    southWall.Size = Vector3.new(20, 10, 1)
    southWall.Position = Vector3.new(10, 5, 15)
    southWall.Anchored = true
    southWall.Material = Enum.Material.Concrete
    southWall:SetAttribute("MapLayoutId", "southWall")
    southWall:SetAttribute("MapLayoutClass", "exterior")
    southWall.Parent = model

    -- East wall
    local eastWall = Instance.new("Part")
    eastWall.Name = "EastWall"
    eastWall.Size = Vector3.new(1, 10, 15)
    eastWall.Position = Vector3.new(20, 5, 7.5)
    eastWall.Anchored = true
    eastWall.Material = Enum.Material.Concrete
    eastWall:SetAttribute("MapLayoutId", "eastWall")
    eastWall:SetAttribute("MapLayoutClass", "exterior")
    eastWall.Parent = model

    -- West wall
    local westWall = Instance.new("Part")
    westWall.Name = "WestWall"
    westWall.Size = Vector3.new(1, 10, 15)
    westWall.Position = Vector3.new(0, 5, 7.5)
    westWall.Anchored = true
    westWall.Material = Enum.Material.Concrete
    westWall:SetAttribute("MapLayoutId", "westWall")
    westWall:SetAttribute("MapLayoutClass", "exterior")
    westWall.Parent = model

    -- A platform/table in the middle
    local table = Instance.new("Part")
    table.Name = "Table"
    table.Size = Vector3.new(4, 2, 3)
    table.Position = Vector3.new(10, 1.5, 7.5)
    table.Anchored = true
    table.Material = Enum.Material.Wood
    table.Color = Color3.fromRGB(139, 90, 43)
    table:SetAttribute("MapLayoutId", "centerTable")
    table:SetAttribute("MapLayoutClass", "furniture wood")
    table.Parent = model

    -- A pillar (will be detected as platform)
    local pillar = Instance.new("Part")
    pillar.Name = "Pillar"
    pillar.Size = Vector3.new(2, 10, 2)
    pillar.Position = Vector3.new(5, 5, 5)
    pillar.Anchored = true
    pillar.Material = Enum.Material.Concrete
    pillar:SetAttribute("MapLayoutId", "pillar1")
    pillar.Parent = model

    model.Parent = workspace

    print("[ScannerDemo] Created test geometry: workspace.ScannerTestGeometry")
    print("[ScannerDemo] Parts have MapLayoutId and MapLayoutClass attributes set")

    return model
end

--[[
    Run the scanner on a container and print the generated code.

    @param container: Model, Folder, etc. (default: creates test geometry)
    @param options: Optional configuration
--]]
function ScannerDemo.run(container, options)
    if not container then
        print("[ScannerDemo] No container specified, creating test geometry...")
        container = ScannerDemo.createTestGeometry()
    end

    print("[ScannerDemo] Scanning:", container:GetFullName())

    local code = MapLayout.scan(container, options)

    print("[ScannerDemo] Done! Copy the code from Output above.")
    print("[ScannerDemo] Tip: Clean up IDs and classes, then delete the original parts.")

    return code
end

--[[
    Interactive helper: lists all parts and their detected types.

    @param container: Model, Folder, etc.
--]]
function ScannerDemo.analyze(container)
    print("\n=== MapLayout Scanner Analysis ===")
    print("Container:", container:GetFullName())
    print("")

    local parts = container:GetDescendants()
    local partCount = 0

    for _, part in ipairs(parts) do
        if part:IsA("BasePart") then
            partCount = partCount + 1

            local id = part:GetAttribute("MapLayoutId") or part.Name
            local class = part:GetAttribute("MapLayoutClass") or "(none)"
            local area = part:GetAttribute("MapLayoutArea") or "(none)"
            local typeOverride = part:GetAttribute("MapLayoutType")

            -- Infer type
            local inferredType = "platform"
            if part:IsA("WedgePart") then
                inferredType = "wedge"
            elseif part:IsA("Part") then
                if part.Shape == Enum.PartType.Ball then
                    inferredType = "sphere"
                elseif part.Shape == Enum.PartType.Cylinder then
                    inferredType = "cylinder"
                else
                    local size = part.Size
                    local x, y, z = size.X, size.Y, size.Z
                    if y <= 2 and (x / y >= 4 or z / y >= 4) then
                        inferredType = "floor"
                    elseif y / math.min(x, z) >= 3 and math.max(x, z) > math.min(x, z) * 2 then
                        inferredType = "wall"
                    end
                end
            end

            local finalType = typeOverride or inferredType

            print(string.format("  [%s] %s", finalType:upper(), id))
            print(string.format("      Size: %.1f x %.1f x %.1f", part.Size.X, part.Size.Y, part.Size.Z))
            print(string.format("      Class: %s | Area: %s", class, area))
            if typeOverride then
                print(string.format("      (type overridden from '%s')", inferredType))
            end
            print("")
        end
    end

    print(string.format("Total parts: %d", partCount))
    print("=== End Analysis ===\n")
end

return ScannerDemo
