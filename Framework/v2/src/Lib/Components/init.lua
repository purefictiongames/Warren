--[[
    LibPureFiction Framework v2
    Components/init.lua - Component Library Index

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This module exports all reusable game components. Components are pre-built
    Node extensions that implement common game mechanics.

    Components are designed to be:
    - Standalone: Work independently with minimal dependencies
    - Composable: Can be combined to create complex behaviors
    - Signal-driven: All control via In/Out pins per v2 architecture

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Lib = require(game.ReplicatedStorage.Lib)
    local PathFollower = Lib.Components.PathFollower

    -- Register with IPC
    System.Asset.register(PathFollower)
    ```

--]]

local Components = {}

-- Navigation
Components.PathFollower = require(script.PathFollower)
Components.PathedConveyor = require(script.PathedConveyor)

-- Spawning
Components.Hatcher = require(script.Hatcher)
Components.Dropper = require(script.Dropper)

-- Detection
Components.Zone = require(script.Zone)
Components.Checkpoint = require(script.Checkpoint)
Components.JumpPad = require(script.JumpPad)

-- Screen Transitions
Components.ScreenTransition = require(script.ScreenTransition)
Components.TitleScreen = require(script.TitleScreen)
Components.ExitScreen = require(script.ExitScreen)

-- HUD
Components.AreaHUD = require(script.AreaHUD)
Components.MiniMap = require(script.MiniMap)

-- Pool Management
Components.NodePool = require(script.NodePool)

-- Composition
Components.Orchestrator = require(script.Orchestrator)
Components.SwivelDemoOrchestrator = require(script.SwivelDemoOrchestrator)
Components.LauncherDemoOrchestrator = require(script.LauncherDemoOrchestrator)
Components.SwivelLauncherOrchestrator = require(script.SwivelLauncherOrchestrator)
Components.TargetSpawnerOrchestrator = require(script.TargetSpawnerOrchestrator)

-- Turret System
Components.Swivel = require(script.Swivel)
Components.Targeter = require(script.Targeter)
Components.Launcher = require(script.Launcher)

-- Projectiles & Beams
Components.Tracer = require(script.Tracer)
Components.PlasmaBeam = require(script.PlasmaBeam)

-- Power
Components.Battery = require(script.Battery)

-- Attribute System
Components.EntityStats = require(script.EntityStats)
Components.DamageCalculator = require(script.DamageCalculator)
Components.StatusEffect = require(script.StatusEffect)

-- Targets
Components.FlyingTarget = require(script.FlyingTarget)

-- Procedural Generation
Components.PathGraph = require(script.PathGraph)
Components.RoomBlocker = require(script.RoomBlocker)
Components.Room = require(script.Room)
Components.DoorwayCutter = require(script.DoorwayCutter)
Components.VolumeGraph = require(script.VolumeGraph)
Components.ClusterStrategies = require(script.ClusterStrategies)

-- Sequential Dungeon Generation (legacy - use Layout module for new code)
Components.VolumeBuilder = require(script.VolumeBuilder)
Components.ShellBuilder = require(script.ShellBuilder)
Components.DoorCutter = require(script.DoorCutter)
Components.TrussBuilder = require(script.TrussBuilder)
Components.LightBuilder = require(script.LightBuilder)
Components.TeleportPadBuilder = require(script.TeleportPadBuilder)
Components.DungeonOrchestrator = require(script.DungeonOrchestrator)
Components.RegionManager = require(script.RegionManager)

-- Layout System (data-driven dungeon generation)
Components.Layout = require(script.Layout)

return Components
