-- ServerStorage.LibPureFiction.Bootstrap.ReplicatedStorage.Manifest

local Manifest = {}

-- Keys become _G.LibPureFiction.<Key>
-- Values are Import() paths from LibPureFiction in *ServerStorage*.
Manifest.Globals = {
	-- ServerStorage.LibPureFiction.Utils.Import.ReplicatedStorage.Import
	Import   = "Utils.Import.ReplicatedStorage.Import",

	-- ServerStorage.LibPureFiction.EventBus.ReplicatedStorage.EventBus
	EventBus = "EventBus.ReplicatedStorage.EventBus",
}

return Manifest
