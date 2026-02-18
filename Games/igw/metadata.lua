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
        "DungeonOrchestrator",
        "TopologyManager", "ChunkManager", "TopologyTerrainPainter",
        "MountainRoomMasser",
        "ShellBuilder", "DoorPlanner",
        "TrussBuilder", "MountainLightBuilder",
        -- Replaced by topology: "MountainBuilder", "MountainTerrainPainter",
        -- Full pipeline (disabled for mountain blockout testing)
        -- "RoomMasser", "ShellBuilder", "DoorPlanner",
        -- "TrussBuilder", "LightBuilder",
        -- "SpawnSetter", "Materializer", "TerrainPainter",
        -- "IceTerrainPainter", "PortalBlender", "PortalRoomBuilder", "DoorCutter",
        -- "PortalTrigger", "PortalCountdown",
    },

    ---------------------------------------------------------------------------
    -- Orchestrator — WorldMapOrchestrator owns biomes + world map
    ---------------------------------------------------------------------------

    WorldMapOrchestrator = {
        startBiome = "mountain",
        portalCountdownSeconds = 5,

        worldMap = {
            mountain = { elevation = 4, connects = {} },  -- blockout testing
            desert  = { elevation = 1,  connects = { "meadow", "sewer" } },
            meadow  = { elevation = 2,  connects = { "desert", "ice", "village" } },
            ice     = { elevation = 3,  connects = { "meadow", "crystal" } },
            village = { elevation = 2,  connects = { "meadow" } },
            sewer   = { elevation = -1, connects = { "desert", "crystal" } },
            crystal = { elevation = -2, connects = { "sewer", "ice", "lava" } },
            lava    = { elevation = -3, connects = { "crystal" } },
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
            -- dungeon removed: Cobblestone isn't a valid terrain material,
            -- causes terrain fallback issues + spawn-outside-map bug

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
            mountain = {
                paletteClass = "palette-highland-meadow",
                terrainStyle = "outdoor",
                terrainWall = "Sandstone",
                terrainFloor = "Grass",
                partWall = "Slate",
                partFloor = "Grass",
                lightType = "PointLight",
                lightStyle = "cave-torch-light",
                lighting = {
                    ClockTime = 14, Brightness = 1,
                    OutdoorAmbient = { 78, 83, 88 },
                    Ambient = { 49, 52, 56 },
                    FogEnd = 2000, FogColor = { 180, 190, 210 },
                    GlobalShadows = true,
                },
            },
        },

        wiring = {
            -- Hub-and-spoke: orchestrator calls each node sequentially
            WorldMapOrchestrator    = { "DungeonOrchestrator" },
            DungeonOrchestrator     = {
                "TopologyManager", "ChunkManager",
                "MountainRoomMasser",
                "ShellBuilder", "DoorPlanner",
                "TrussBuilder", "MountainLightBuilder",
                "WorldMapOrchestrator",
            },
            TopologyManager         = { "DungeonOrchestrator" },
            ChunkManager            = { "TopologyTerrainPainter", "DungeonOrchestrator" },
            TopologyTerrainPainter  = { "ChunkManager" },
            MountainRoomMasser      = { "DungeonOrchestrator" },
            ShellBuilder            = { "DungeonOrchestrator" },
            DoorPlanner             = { "DungeonOrchestrator" },
            TrussBuilder            = { "DungeonOrchestrator" },
            MountainLightBuilder    = { "DungeonOrchestrator" },
            -- Replaced by topology:
            -- MountainBuilder        = { "DungeonOrchestrator" },
            -- MountainTerrainPainter = { "DungeonOrchestrator" },

            -- Full pipeline (disabled for mountain blockout testing)
            -- WorldMapOrchestrator = { "DungeonOrchestrator", "PortalTrigger", "PortalCountdown" },
            -- DungeonOrchestrator  = { "RoomMasser", "WorldMapOrchestrator" },
            -- RoomMasser           = { "ShellBuilder" },
            -- ShellBuilder         = { "DoorPlanner" },
            -- DoorPlanner          = { "TrussBuilder" },
            -- TrussBuilder         = { "LightBuilder" },
            -- LightBuilder         = { "SpawnSetter" },
            -- SpawnSetter          = { "Materializer" },
            -- Materializer         = { "TerrainPainter" },
            -- TerrainPainter       = { "IceTerrainPainter" },
            -- IceTerrainPainter    = { "PortalBlender" },
            -- PortalBlender        = { "PortalRoomBuilder" },
            -- PortalRoomBuilder    = { "DoorCutter" },
            -- DoorCutter           = { "DungeonOrchestrator" },
            -- PortalTrigger        = { "WorldMapOrchestrator", "PortalCountdown" },
        },
    },

    -- DungeonOrchestrator is now a pipeline node (receives everything via signal)
    DungeonOrchestrator = {},

    ---------------------------------------------------------------------------
    -- Per-node config (JavaFX "type selectors" — Level 2)
    ---------------------------------------------------------------------------

    MountainBuilder = {
        baseWidth = 400,
        baseDepth = 300,
        peakWidth = 30,
        peakDepth = 30,
        layerHeight = 50,
        layerCount = 6,
        -- Slope tangent: -1 (funnel) to +1 (dome), 0 = linear
        -- slopeProfile: "hill" | "mound" | "linear" | "steep" | "jagged"
        -- or tangent (both axes), or tangentX + tangentZ (asymmetric)
        -- omit all for random profile per seed
        -- slopeProfile = "linear",
        forkChance = 25,
        maxPeaks = 3,
        jitterRange = 0.15,
        forkWidthFraction = 0.6,
        origin = { 0, 0, 0 },
    },

    TopologyManager = {
        -- Map extents (terrain grid limit: ±16384 studs per axis)
        mapWidth = 4000,        -- studs (X axis)
        mapDepth = 4000,        -- studs (Z axis)
        groundHeight = 4,       -- studs — ground plane thickness
        groundY = 0,            -- base Y of ground plane

        -- Feature seeding
        featureSpacing = 667,   -- grid cell size for feature placement
        forkChance = 5,         -- % chance a region forks into 2 sub-peaks
        forkWidthFraction = 0.55,  -- each fork child gets this fraction
        jitterRange = 0.3,      -- position jitter as fraction of margin
        minRegionSize = 20,     -- regions smaller than this stop growing
        attritionChance = 3,    -- % chance a region dies (plateau)

        -- Spine (ridge axis — taller features cluster here)
        spineAngle = 15,        -- degrees from X axis
        spineWidth = 0.2,       -- gaussian width (0-1 normalized)

        -- Feature type weights (before spine bias)
        rollingWeight = 0.35,   -- gentle domes, 20-stud layers
        hillWeight = 0.60,      -- moderate hills, 12-stud layers
        mountainWeight = 0.33,  -- steep mountains, 6-stud layers
        peakWeight = 0.10,      -- steep spires, 4-stud layers

        -- Perimeter features (visual interest at horizon)
        perimeterRadius = 800,  -- studs from origin
        perimeterCount = 12,    -- features scattered on ring

        origin = { 0, 0, 0 },
    },

    ChunkManager = {
        chunkSize = 512,        -- studs per chunk edge
        loadRadius = 1024,      -- fill terrain within this radius
        unloadRadius = 1280,    -- clear terrain beyond this (hysteresis)
        checkInterval = 0.25,   -- seconds between heartbeat checks
    },

    MountainRoomMasser = {
        falseEntries = 6,
        caveSystems = 3,
        falseEntryMaxRooms = 3,
        caveMinRooms = 6,
        caveMaxRooms = 15,
        inwardBias = 60,
        scaleRange = { min = 4, max = 10, minY = 4, maxY = 7 },
    },

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
