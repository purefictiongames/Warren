local Components = {}

Components.DungeonOrchestrator = require(script.DungeonOrchestrator)
Components.RoomMasser     = require(script.Pipeline.RoomMasser)
Components.ShellBuilder   = require(script.Pipeline.ShellBuilder)
Components.DoorPlanner    = require(script.Pipeline.DoorPlanner)
Components.TrussBuilder   = require(script.Pipeline.TrussBuilder)
Components.LightBuilder   = require(script.Pipeline.LightBuilder)
Components.PadBuilder     = require(script.Pipeline.PadBuilder)
Components.SpawnSetter    = require(script.Pipeline.SpawnSetter)
Components.Materializer   = require(script.Pipeline.Materializer)
Components.DoorCutter     = require(script.Pipeline.DoorCutter)
Components.TerrainPainter = require(script.Pipeline.TerrainPainter)
Components.IceTerrainPainter = require(script.Pipeline.IceTerrainPainter)

return Components
