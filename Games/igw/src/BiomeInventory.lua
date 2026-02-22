--[[
    IGW v2 — Biome Inventory (Subtractive Terrain Pipeline)

    Feature budget data per biome, resolved via ClassResolver cascade:
        Level 1: defaults      — universal terrain defaults (all biomes)
        Level 2: classes[X]    — per-biome overrides ("mountain", "desert", "lava")

    Derived from Cascade Range geological analysis. Controls:
        baseElevation → BlockoutNode      (ridge crest / edge heights)
        spine         → SplinePlannerNode  (ridge layout, branching, valley gen)
        features      → InventoryNode      (concrete feature counts)
        rocks         → RockScatterNode    (surface rock blob scatter)
--]]

return {
    -------------------------------------------------------------------------
    -- DEFAULTS — universal feature budget (all biomes inherit)
    -------------------------------------------------------------------------

    defaults = {
        baseElevation = {
            crestHeight = 700,      -- studs: peak ridge crest
            edgeHeight = 80,        -- studs: terrain at map edges
            asymmetry = 0.6,        -- >0.5 = western slope longer
        },

        spine = {
            angle = 15,             -- degrees from X axis
            ridgeCPs = 8,           -- control points on main ridge
            lateralJitter = 200,    -- studs: perpendicular offset per CP
            subRidgeChance = 0.4,   -- probability of sub-ridge at interior CP
            maxBranchDepth = 2,     -- recursive branching limit
            numRidgeSpines = 1,     -- parallel ridge spines (1 = single spine)
            spineSpacing = 1200,    -- studs between parallel spines
            subRidgeExtent = 0.35,  -- fraction of diagonalExtent for sub-ridge reach
            valleysPerSide = { 3, 5 },  -- { min, max } primary valleys per flank
            tributaryChance = 0.5,  -- probability of tributary at valley CP
            maxTributaryDepth = 2,  -- recursive tributary branching limit
        },

        features = {
            stratovolcano  = { count = { 1, 3 },  height = { 400, 800 }, baseRadius = { 500, 1000 } },
            cinder_cone    = { count = { 8, 20 },  height = { 60, 160 },  baseRadius = { 100, 200 } },
            glacial_valley = { count = { 3, 6 },   width = { 300, 800 }, depth = { 160, 400 } },
            fluvial_valley = { count = { 8, 16 },  width = { 60, 200 },  depth = { 40, 160 } },
            cirque         = { count = { 2, 5 },   diameter = { 240, 700 }, depth = { 120, 240 } },
            pass           = { count = { 2, 4 },   width = { 160, 600 },  depth = { 100, 240 } },
        },

        rocks = {
            density = 1200,             -- total rock blobs across map
            sizeRange = { 12, 40 },     -- studs: blob radius
            amplitude = { 0.5, 1.2 },   -- vertical stretch (1.0=sphere, >1=taller)
            clusterTightness = 0.7,     -- 0=uniform scatter, 1=very tight groups
            clusterSize = { 6, 18 },    -- rocks per cluster
            material = "Rock",          -- terrain material for blobs
            minHeight = 30,             -- studs above groundY: skip flat lowlands
            slopeThreshold = 0.7,       -- gradient magnitude: steeper → flagstone
            flagstone = {
                widthRange = { 16, 40 },    -- studs: extent along cliff face
                heightRange = { 12, 32 },   -- studs: vertical extent
                thickness = { 4, 10 },      -- studs: protrusion from face
                material = "Slate",         -- terrain material for slabs
            },
        },

        caves = {
            count = { 8, 15 },             -- caves per map (dungeon entrance points)
            mouthWidth = { 40, 100 },      -- studs: horizontal opening
            mouthHeight = { 30, 70 },      -- studs: vertical opening (rect half + arch half)
            depth = { 60, 160 },           -- studs: mouth-to-chamber distance
            tubeSegments = { 1, 2 },       -- connecting tubes between mouth and chamber
            jitter = { 8, 20 },            -- { vertical, lateral } tube wander in studs
            chamberScale = { 1.8, 2.8 },   -- chamber size vs mouth (always present)
            slopeThreshold = 0.5,          -- min gradient magnitude for mouth placement
            minElevation = 50,             -- studs above groundY
            minSpacing = 160,              -- studs: minimum distance between cave mouths
        },
    },

    -------------------------------------------------------------------------
    -- BIOME CLASSES — per-biome overrides
    -------------------------------------------------------------------------

    classes = {
        -----------------------------------------------------------------
        -- MOUNTAIN (alpine) — Cascade Range reference
        -- High crest, deep glacial valleys, stratovolcanoes, cirques.
        -----------------------------------------------------------------

        mountain = {
            baseElevation = {
                crestHeight = 700,
                edgeHeight = 80,
                asymmetry = 0.6,
            },

            spine = {
                angle = 15,
                ridgeCPs = 8,
                lateralJitter = 200,
                subRidgeChance = 0.55,
                maxBranchDepth = 3,
                numRidgeSpines = 3,
                spineSpacing = 1400,
                subRidgeExtent = 0.55,
                valleysPerSide = { 5, 8 },
                tributaryChance = 0.6,
                maxTributaryDepth = 3,
            },

            features = {
                stratovolcano  = { count = { 2, 5 },  height = { 400, 800 }, baseRadius = { 500, 1000 } },
                cinder_cone    = { count = { 16, 40 }, height = { 60, 160 },  baseRadius = { 100, 200 } },
                glacial_valley = { count = { 6, 12 },  width = { 300, 800 }, depth = { 160, 400 } },
                fluvial_valley = { count = { 16, 32 }, width = { 60, 200 },  depth = { 40, 160 } },
                cirque         = { count = { 4, 10 },  diameter = { 240, 700 }, depth = { 120, 240 } },
                pass           = { count = { 3, 7 },   width = { 160, 600 },  depth = { 100, 240 } },
            },

            rocks = {
                density = 1800,
                sizeRange = { 16, 48 },
                amplitude = { 0.6, 1.4 },
                clusterTightness = 0.7,
                clusterSize = { 8, 20 },
                material = "Rock",
                minHeight = 30,
                slopeThreshold = 0.6,
                flagstone = {
                    widthRange = { 20, 48 },
                    heightRange = { 16, 40 },
                    thickness = { 4, 12 },
                    material = "Slate",
                },
            },

            caves = {
                count = { 25, 25 },
                mouthWidth = { 50, 120 },
                mouthHeight = { 36, 80 },
                depth = { 80, 200 },
                tubeSegments = { 1, 2 },
                jitter = { 10, 24 },
                chamberScale = { 2.0, 3.0 },
                slopeThreshold = 0.5,
                minElevation = 40,
                minSpacing = 200,
            },
        },

        -----------------------------------------------------------------
        -- DESERT — lower crest, no glacial features, more passes
        -----------------------------------------------------------------

        desert = {
            baseElevation = {
                crestHeight = 400,
                edgeHeight = 60,
                asymmetry = 0.5,
            },

            spine = {
                angle = 25,
                ridgeCPs = 6,
                lateralJitter = 300,
                subRidgeChance = 0.2,
                maxBranchDepth = 1,
                numRidgeSpines = 1,
                spineSpacing = 1000,
                subRidgeExtent = 0.3,
                valleysPerSide = { 2, 4 },
                tributaryChance = 0.3,
                maxTributaryDepth = 1,
            },

            features = {
                stratovolcano  = { count = { 0, 1 },  height = { 300, 600 }, baseRadius = { 400, 800 } },
                cinder_cone    = { count = { 4, 12 },  height = { 40, 120 },  baseRadius = { 80, 160 } },
                glacial_valley = { count = { 0, 0 },   width = { 0, 0 },     depth = { 0, 0 } },
                fluvial_valley = { count = { 4, 10 },  width = { 40, 160 },   depth = { 30, 120 } },
                cirque         = { count = { 0, 0 },   diameter = { 0, 0 },   depth = { 0, 0 } },
                pass           = { count = { 3, 6 },   width = { 200, 800 },  depth = { 80, 200 } },
            },

            rocks = {
                density = 600,
                sizeRange = { 8, 32 },
                amplitude = { 0.4, 1.0 },
                clusterTightness = 0.5,
                clusterSize = { 6, 14 },
                material = "Sandstone",
                minHeight = 20,
                slopeThreshold = 0.8,
                flagstone = {
                    widthRange = { 12, 32 },
                    heightRange = { 8, 24 },
                    thickness = { 4, 8 },
                    material = "Sandstone",
                },
            },

            caves = {
                count = { 3, 6 },
                mouthWidth = { 40, 80 },
                mouthHeight = { 24, 50 },
                depth = { 50, 120 },
                tubeSegments = { 1, 1 },
                jitter = { 6, 16 },
                chamberScale = { 1.5, 2.2 },
                slopeThreshold = 0.7,
                minElevation = 40,
                minSpacing = 240,
            },
        },

        -----------------------------------------------------------------
        -- LAVA (volcanic) — tall crest, many cones, cirques as calderas
        -----------------------------------------------------------------

        lava = {
            baseElevation = {
                crestHeight = 800,
                edgeHeight = 100,
                asymmetry = 0.5,
            },

            spine = {
                angle = 10,
                ridgeCPs = 6,
                lateralJitter = 160,
                subRidgeChance = 0.25,
                maxBranchDepth = 1,
                numRidgeSpines = 2,
                spineSpacing = 1000,
                subRidgeExtent = 0.4,
                valleysPerSide = { 2, 3 },
                tributaryChance = 0.3,
                maxTributaryDepth = 1,
            },

            features = {
                stratovolcano  = { count = { 2, 4 },  height = { 500, 1000 }, baseRadius = { 600, 1200 } },
                cinder_cone    = { count = { 12, 30 }, height = { 80, 200 },  baseRadius = { 120, 240 } },
                glacial_valley = { count = { 0, 0 },   width = { 0, 0 },      depth = { 0, 0 } },
                fluvial_valley = { count = { 2, 6 },   width = { 40, 120 },    depth = { 30, 100 } },
                cirque         = { count = { 1, 3 },   diameter = { 300, 800 }, depth = { 160, 300 } },
                pass           = { count = { 1, 2 },   width = { 120, 400 },   depth = { 80, 160 } },
            },

            rocks = {
                density = 1050,
                sizeRange = { 12, 40 },
                amplitude = { 0.5, 1.3 },
                clusterTightness = 0.6,
                clusterSize = { 6, 16 },
                material = "Basalt",
                minHeight = 30,
                slopeThreshold = 0.65,
                flagstone = {
                    widthRange = { 16, 40 },
                    heightRange = { 12, 32 },
                    thickness = { 6, 12 },
                    material = "Basalt",
                },
            },

            caves = {
                count = { 4, 8 },
                mouthWidth = { 30, 70 },
                mouthHeight = { 24, 50 },
                depth = { 70, 160 },
                tubeSegments = { 1, 2 },
                jitter = { 6, 12 },
                chamberScale = { 1.5, 2.2 },
                slopeThreshold = 0.5,
                minElevation = 60,
                minSpacing = 200,
            },
        },

        -----------------------------------------------------------------
        -- STUBS — inherit all defaults
        -----------------------------------------------------------------

        ice     = {},
        meadow  = {},
        sewer   = {},
        crystal = {},
        village = {},
        dungeon = {},
    },
}
