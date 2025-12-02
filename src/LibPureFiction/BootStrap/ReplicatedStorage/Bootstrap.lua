-- ServerStorage.LibPureFiction.Bootstrap.ReplicatedStorage.Bootstrap
-- Core bootstrap logic rooted in ServerStorage.LibPureFiction.

local ServerStorage = game:GetService("ServerStorage")

local LibRoot = ServerStorage:WaitForChild("LibPureFiction")
local BootstrapFolder = LibRoot:WaitForChild("Bootstrap"):WaitForChild("ReplicatedStorage")

local Manifest = require(BootstrapFolder:WaitForChild("Manifest"))

-- NOTE: path matches your tree:
-- Utils
--   Import
--     ReplicatedStorage
--       Import (ModuleScript)
local ImportModule = LibRoot
	:WaitForChild("Utils")
	:WaitForChild("Import")
	:WaitForChild("ReplicatedStorage")
	:WaitForChild("Import")

local Import = require(ImportModule)

local Bootstrap = {}

local function ensureGlobalNamespace()
	_G.LibPureFiction = _G.LibPureFiction or {}
	_G.LibPureFiction.System = _G.LibPureFiction.System or {} -- keep for any old code
end

local function wireGlobals()
	ensureGlobalNamespace()

	local globals = Manifest.Globals or {}

	for key, importPath in pairs(globals) do
		local module = Import(importPath)

		-- New style
		_G.LibPureFiction[key] = module

		-- Backwards compat
		_G.LibPureFiction.System[key] = _G.LibPureFiction.System[key] or module
	end
end

function Bootstrap.Init(context)
	wireGlobals()

	local EventBus = _G.LibPureFiction.EventBus
	if EventBus and type(EventBus.default) == "function" then
		local defaultBus = EventBus.default()
		defaultBus:emit("BootstrapComplete", context or "Unknown", os.time())
	end
end

return Bootstrap
