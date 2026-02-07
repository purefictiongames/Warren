--[[
    CastleDracula Demo

    Run from command bar:
    require(game.ReplicatedStorage.Warren.Demos.CastleDracula_Demo)()

    Builds: Level 0 (Grotto/Crypt) with rooms, corridors, and door openings
--]]

return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    -- Clear existing
    local existing = workspace:FindFirstChild("CastleDracula")
    if existing then
        existing:Destroy()
    end

    -- Load framework
    local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
    local Factory = Lib.Factory

    -- Build
    print("Building CastleDracula...")
    local castle = Factory.geometry(Lib.Layouts.CastleDracula)
    castle.Parent = workspace

    -- Offset so spawn (0,0,0) is inside R01 (entry cave)
    -- R01 center is at approximately (230, 0, 460)
    local offset = Vector3.new(-230, 0, -460)
    castle:PivotTo(castle:GetPivot() + offset)

    print("CastleDracula complete!")
    print("Parts:", #castle:GetDescendants())

    return castle
end
