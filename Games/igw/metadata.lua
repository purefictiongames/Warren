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
        "SpawnSetter", "Materializer", "TerrainPainter",
        "IceTerrainPainter", "DoorCutter",
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
            TerrainPainter      = { "IceTerrainPainter" },
            IceTerrainPainter   = { "DoorCutter" },
            DoorCutter          = { "DungeonOrchestrator" },
        },
        biomes = {
            lava = {
                paletteClass = "palette-classic-lava",
                terrainWall = "Rock",
                terrainFloor = "CrackedLava",
                partWall = "Cobblestone",
                partFloor = "CrackedLava",
                lightType = "PointLight",
                lightStyle = "cave-point-light",
                lighting = {
                    ClockTime = 0, Brightness = 0,
                    OutdoorAmbient = { 0, 0, 0 },
                    Ambient = { 20, 20, 25 },
                    FogEnd = 1000, FogColor = { 0, 0, 0 },
                    GlobalShadows = false,
                },
            },
            ice = {
                paletteClass = "palette-glacier-ice",
                terrainStyle = "outdoor",
                terrainWall = "Glacier",
                terrainWallMix = "Rock",
                terrainFloor = "Snow",
                partWall = "Ice",
                partFloor = "Glacier",
                doorWallClass = "ice-wall-solid",
                skipLights = true,
                lighting = {
                    ClockTime = 14, Brightness = 1.5,
                    OutdoorAmbient = { 140, 160, 190 },
                    Ambient = { 80, 90, 110 },
                    FogEnd = 800, FogColor = { 180, 200, 220 },
                    GlobalShadows = true,
                },
            },
            meadow = {
                paletteClass = "palette-highland-meadow",
                terrainStyle = "outdoor",
                terrainWall = "Slate",
                terrainFloor = "Grass",
                partWall = "Cobblestone",
                partFloor = "Grass",
                doorWallClass = "outdoor-wall-solid",
                skipLights = true,
                lighting = {
                    ClockTime = 14, Brightness = 2,
                    OutdoorAmbient = { 160, 170, 140 },
                    Ambient = { 90, 100, 80 },
                    FogEnd = 1200, FogColor = { 170, 190, 160 },
                    GlobalShadows = true,
                },
            },
            dungeon = {
                paletteClass = "palette-dungeon-keep",
                terrainWall = "Granite",
                terrainFloor = "Cobblestone",
                partWall = "Brick",
                partFloor = "Cobblestone",
                lightType = "PointLight",
                lightStyle = "cave-point-light",
                lighting = {
                    ClockTime = 0, Brightness = 0,
                    OutdoorAmbient = { 0, 0, 0 },
                    Ambient = { 15, 12, 10 },
                    FogEnd = 800, FogColor = { 10, 8, 5 },
                    GlobalShadows = false,
                },
            },
            desert = {
                paletteClass = "palette-desert-ruins",
                terrainStyle = "outdoor",
                terrainWall = "Sandstone",
                terrainFloor = "Sand",
                partWall = "Limestone",
                partFloor = "Sandstone",
                doorWallClass = "outdoor-wall-solid",
                skipLights = true,
                lighting = {
                    ClockTime = 12, Brightness = 3,
                    OutdoorAmbient = { 200, 180, 140 },
                    Ambient = { 120, 110, 85 },
                    FogEnd = 1500, FogColor = { 220, 200, 160 },
                    GlobalShadows = true,
                },
            },
            sewer = {
                paletteClass = "palette-sewer-works",
                terrainWall = "Concrete",
                terrainFloor = "Mud",
                partWall = "CorrodedMetal",
                partFloor = "Metal",
                lightType = "PointLight",
                lightStyle = "cave-point-light",
                lighting = {
                    ClockTime = 0, Brightness = 0,
                    OutdoorAmbient = { 0, 0, 0 },
                    Ambient = { 10, 15, 8 },
                    FogEnd = 600, FogColor = { 15, 20, 10 },
                    GlobalShadows = false,
                },
            },
            crystal = {
                paletteClass = "palette-crystal-cave",
                terrainWall = "Basalt",
                terrainFloor = "Salt",
                partWall = "Glass",
                partFloor = "Neon",
                lightType = "PointLight",
                lightStyle = "cave-point-light",
                lighting = {
                    ClockTime = 0, Brightness = 0,
                    OutdoorAmbient = { 0, 0, 0 },
                    Ambient = { 25, 15, 35 },
                    FogEnd = 700, FogColor = { 10, 5, 20 },
                    GlobalShadows = false,
                },
            },
            village = {
                paletteClass = "palette-village-green",
                terrainStyle = "outdoor",
                terrainWall = "Pavement",
                terrainFloor = "Grass",
                partWall = "Brick",
                partFloor = "WoodPlanks",
                doorWallClass = "outdoor-wall-solid",
                skipLights = true,
                lighting = {
                    ClockTime = 15, Brightness = 2,
                    OutdoorAmbient = { 150, 155, 130 },
                    Ambient = { 85, 90, 75 },
                    FogEnd = 1400, FogColor = { 180, 190, 170 },
                    GlobalShadows = true,
                },
            },
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
