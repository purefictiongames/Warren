--[[
    FlemishShop1 Demo

    Run from command bar:
    require(game.ReplicatedStorage.Lib.Demos.FlemishShop1_Demo)()

    Builds: Complete FlemishShop1 package (Shell + Roof + Openings via xref)
    Then applies CSG to cut window/door holes
--]]

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    -- Clear existing
    local existing = workspace:FindFirstChild("FlemishShop1")
    if existing then
        existing:Destroy()
    end

    -- Load framework
    local Lib = require(ReplicatedStorage:WaitForChild("Lib"))
    local Factory = Lib.Factory

    ----------------------------------------------------------------------------
    -- BUILD: Complete package (Shell + Roof + Openings)
    ----------------------------------------------------------------------------
    print("Building FlemishShop1...")
    local building = Factory.geometry(Lib.Layouts.FlemishShop1)
    building.Parent = workspace

    ----------------------------------------------------------------------------
    -- APPLY CSG HOLES
    ----------------------------------------------------------------------------
    print("Cutting window/door openings...")

    -- Find walls and openings
    local walls = {}
    local openings = {}

    for _, part in ipairs(building:GetDescendants()) do
        if part:IsA("BasePart") then
            if part.Name:find("Wall_South") then
                table.insert(walls, part)
            elseif part.Name:find("Window") or part.Name:find("Door") then
                table.insert(openings, part)
            end
        end
    end

    -- Cut each opening from intersecting walls
    for _, opening in ipairs(openings) do
        for i, wall in ipairs(walls) do
            -- Check if opening intersects this wall (simple Y overlap check)
            local wallMinY = wall.Position.Y - wall.Size.Y/2
            local wallMaxY = wall.Position.Y + wall.Size.Y/2
            local openMinY = opening.Position.Y - opening.Size.Y/2
            local openMaxY = opening.Position.Y + opening.Size.Y/2

            if openMinY < wallMaxY and openMaxY > wallMinY then
                local success, result = pcall(function()
                    return wall:SubtractAsync({opening})
                end)

                if success and result then
                    result.Name = wall.Name
                    result.Parent = wall.Parent
                    -- Copy attributes
                    for _, attr in ipairs({"FactoryId", "FactoryClass"}) do
                        local val = wall:GetAttribute(attr)
                        if val then result:SetAttribute(attr, val) end
                    end
                    wall:Destroy()
                    walls[i] = result  -- Update reference for next opening
                else
                    warn("CSG failed for", opening.Name, "on", wall.Name)
                end
            end
        end
        opening:Destroy()  -- Clean up opening after cutting
    end

    ----------------------------------------------------------------------------
    -- Position away from spawn
    building:PivotTo(building:GetPivot() + Vector3.new(50, 0, 50))

    print("FlemishShop1 complete!")
    print("Parts:", #building:GetDescendants())

    return building
end
