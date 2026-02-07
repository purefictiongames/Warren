--[[
    AtomicRanch Demo

    Run this from the command bar to test the Atomic Ranch house:

    require(game.ReplicatedStorage.Warren.Demos.AtomicRanch_Demo)()
--]]

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    -- Clear any existing test
    local existing = workspace:FindFirstChild("AtomicRanch")
    if existing then
        existing:Destroy()
    end

    -- Load the framework
    local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
    local Factory = Lib.Factory

    -- Build the house
    print("Building Atomic Ranch...")
    local house = Factory.geometry(Lib.Layouts.AtomicRanch)
    house.Name = "AtomicRanch"
    house.Parent = workspace

    -- Position for easy viewing
    house:PivotTo(CFrame.new(0, 0, 0))

    print("Atomic Ranch built!")
    print("Parts created:", #house:GetDescendants())

    -- List major elements
    print("\nStructure:")
    local categories = {
        Foundation = {},
        Floor = {},
        Wall = {},
        Ceiling = {},
        Roof = {},
        Glass = {},
        Other = {}
    }

    for _, part in ipairs(house:GetChildren()) do
        local name = part.Name
        local category = "Other"
        if name:find("Foundation") or name:find("Ground") then
            category = "Foundation"
        elseif name:find("Floor") then
            category = "Floor"
        elseif name:find("Wall") or name:find("Counter") then
            category = "Wall"
        elseif name:find("Ceiling") then
            category = "Ceiling"
        elseif name:find("Roof") or name:find("Fascia") then
            category = "Roof"
        elseif name:find("Glass") then
            category = "Glass"
        end
        table.insert(categories[category], name)
    end

    for cat, parts in pairs(categories) do
        if #parts > 0 then
            print(string.format("  %s: %d parts", cat, #parts))
        end
    end

    return house
end
