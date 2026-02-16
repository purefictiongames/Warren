return {
    name = "It Gets Worse",
    version = "3.1",
    orchestrator = "DungeonOrchestrator",

    preload = {
        "RoomMasser", "ShellBuilder", "DoorPlanner",
        "TrussBuilder", "LightBuilder", "PadBuilder",
        "SpawnSetter", "Materializer", "DoorCutter", "TerrainPainter",
    },

    mode = {
        name = "Dungeon",
        nodes = {
            "DungeonOrchestrator",
            "RoomMasser", "ShellBuilder", "DoorPlanner",
            "TrussBuilder", "LightBuilder", "PadBuilder",
            "SpawnSetter", "Materializer", "DoorCutter", "TerrainPainter",
        },
        wiring = {
            DungeonOrchestrator = { "RoomMasser" },
            RoomMasser          = { "ShellBuilder" },
            ShellBuilder        = { "DoorPlanner" },
            DoorPlanner         = { "TrussBuilder" },
            TrussBuilder        = { "LightBuilder" },
            LightBuilder        = { "PadBuilder" },
            PadBuilder          = { "SpawnSetter" },
            SpawnSetter         = { "Materializer" },
            Materializer        = { "DoorCutter" },
            DoorCutter          = { "TerrainPainter" },
            TerrainPainter      = { "DungeonOrchestrator" },
        },
    },

    debug = { level = "info" },
    log   = { backend = "Memory" },

    config = {
        lighting = {
            ClockTime = 0, Brightness = 0,
            OutdoorAmbient = { 0, 0, 0 },
            Ambient = { 20, 20, 25 },
            FogEnd = 1000, FogColor = { 0, 0, 0 },
            GlobalShadows = false,
        },
        dungeon = {
            seed = nil,
            baseUnit = 5, wallThickness = 1, doorSize = 12,
            floorThreshold = 6.5,
            mainPathLength = 8, spurCount = 4, loopCount = 1,
            verticalChance = 30, minVerticalRatio = 0.2,
            scaleRange = { min = 4, max = 12, minY = 4, maxY = 8 },
            material = "Brick", color = { 140, 110, 90 },
            hubInterval = 4, hubPadRange = { min = 3, max = 4 },
            padCount = 4,
            origin = { 0, 20, 0 },
        },
    },
}
