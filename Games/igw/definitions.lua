--[[
    IGW v2 — Node Definitions (ClassResolver Spec)

    The "stylesheet" for pipeline node config. Uses the same
    defaults/base/classes/ids cascade as visual styles.

    Resolution order (lowest → highest priority):
      1. defaults   — applied to ALL nodes
      2. base[type] — per node type (e.g. RoomMasser, TerrainPainter)
      3. classes    — theme presets (future: cave-lava, cave-brick, …)
      4. ids        — per-instance overrides
      5. inline     — per-node overrides in init.cfg.lua preload table
--]]

return {
    -- Level 1: Applied to ALL nodes (JavaFX "user-agent defaults")
    defaults = {
        wallThickness = 1,
        doorSize = 12,
        baseUnit = 5,
    },

    -- Level 2: Per node type (JavaFX "type selectors")
    base = {
        RoomMasser = {
            mainPathLength = 8,
            spurCount = 4,
            verticalChance = 30,
            minVerticalRatio = 0.2,
            scaleRange = { min = 4, max = 12, minY = 4, maxY = 8 },
            origin = { 0, 20, 0 },
        },
        TrussBuilder = {
            floorThreshold = 6.5,
        },
        PadBuilder = {
            padCount = 4,
        },
        TerrainPainter = {
            wallMaterial = "Rock",
            floorMaterial = "CrackedLava",
            noiseScale = 8,
            noiseThreshold = 0.35,
            patchScale = 12,
            patchThreshold = 0.4,
        },
    },

    -- Level 3: Theme presets (JavaFX "class selectors")
    classes = {
        -- Future: ["cave-lava"] = { wallMaterial = "Rock", floorMaterial = "CrackedLava", … },
        -- Future: ["cave-brick"] = { wallMaterial = "Brick", floorMaterial = "Slate", … },
    },

    -- Level 4: Per-instance overrides (JavaFX "id selectors")
    ids = {},
}
