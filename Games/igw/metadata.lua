--[[
    IGW v2 — Game Metadata

    Flat table keyed by node class name. Combines what was previously split
    across init.cfg (preload/mode/wiring/config), definitions.lua (cascade),
    and inline overrides into a single authoritative file.

    Resolution: metadata.defaults → metadata[NodeName] → ClassResolver (future themes)
--]]

return {
    -- Pipeline node load order (orchestrator is implicit from init.cfg)
    nodes = {
        "RoomMasser", "ShellBuilder", "DoorPlanner",
        "TrussBuilder", "LightBuilder", "PadBuilder",
        "SpawnSetter", "Materializer", "TerrainPainter", "DoorCutter",
    },

    ---------------------------------------------------------------------------
    -- Orchestrator
    ---------------------------------------------------------------------------

    DungeonOrchestrator = {
        wiring = {
            DungeonOrchestrator = { "RoomMasser" },
            RoomMasser          = { "ShellBuilder" },
            ShellBuilder        = { "DoorPlanner" },
            DoorPlanner         = { "TrussBuilder" },
            TrussBuilder        = { "LightBuilder" },
            LightBuilder        = { "PadBuilder" },
            PadBuilder          = { "SpawnSetter" },
            SpawnSetter         = { "Materializer" },
            Materializer        = { "TerrainPainter" },
            TerrainPainter      = { "DoorCutter" },
            DoorCutter          = { "DungeonOrchestrator" },
        },
        lighting = {
            ClockTime = 0, Brightness = 0,
            OutdoorAmbient = { 0, 0, 0 },
            Ambient = { 20, 20, 25 },
            FogEnd = 1000, FogColor = { 0, 0, 0 },
            GlobalShadows = false,
        },
    },

    ---------------------------------------------------------------------------
    -- Per-node config (JavaFX "type selectors" — Level 2)
    ---------------------------------------------------------------------------

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

    ---------------------------------------------------------------------------
    -- Shared defaults (JavaFX "user-agent defaults" — Level 1)
    ---------------------------------------------------------------------------

    defaults = {
        wallThickness = 1,
        doorSize = 12,
        baseUnit = 5,
    },

    ---------------------------------------------------------------------------
    -- ClassResolver cascade (future themes — Levels 3 & 4)
    ---------------------------------------------------------------------------

    definitions = {
        classes = {},
        ids = {},
    },
}
