--[[
    Example Layout - Defensive Zone

    This is an example layout showing the expected format.
    Copy this file as a starting point for new layouts.

    Delete this file in production - it's just a reference.
--]]

return {
    -- Layout name (used for the container Part)
    name = "DefensiveZone",

    -- Geometry specification
    spec = {
        -- Bounding volume (defines the container Part size)
        bounds = {40, 12, 30},

        -- Origin: "corner" (default), "center", or "floor-center"
        origin = "corner",

        -- Scale: converts definition units to studs (optional)
        -- scale = "4:1",  -- 1 unit = 4 studs

        -- Base styles by element type (like CSS element selectors)
        -- "part" applies to all parts (Anchored = true is built-in)
        base = {
            part = { CanCollide = true },
        },

        -- Class-based styling (like CSS classes)
        classes = {
            concrete = { Material = "Concrete", Color = {180, 175, 165} },
            metal = { Material = "DiamondPlate", Color = {100, 100, 105} },
            trigger = { CanCollide = false, CanQuery = true, Transparency = 1 },
        },

        -- Geometry parts (positioned relative to container corner)
        parts = {
            -- Floor
            { id = "floor", class = "concrete", position = {20, 0.25, 15}, size = {40, 0.5, 30} },

            -- Platforms
            { id = "platform1", class = "metal", position = {10, 1.5, 5}, size = {6, 2.5, 6} },
            { id = "platform2", class = "metal", position = {30, 1.5, 5}, size = {6, 2.5, 6} },
            { id = "platform3", class = "metal", position = {20, 1.5, 25}, size = {6, 2.5, 6} },

            -- Detection zone (invisible)
            { id = "detectionZone", class = "trigger", position = {20, 6, 15}, size = {40, 12, 30} },
        },

        -- Mount points for spawning nodes (no geometry created)
        mounts = {
            { id = "turret1", position = {10, 2.75, 5}, facing = {0, 0, 1} },
            { id = "turret2", position = {30, 2.75, 5}, facing = {0, 0, 1} },
            { id = "turret3", position = {20, 2.75, 25}, facing = {0, 0, -1} },
        },
    },
}
