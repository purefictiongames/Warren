--[[
    It Gets Worse - Component Registry

    IGW-specific components for the infinite dungeon crawler.
--]]

local Components = {}

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
