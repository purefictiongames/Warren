-- ServerScriptService.ServerBootStrap
-- Server entrypoint: runs LibPureFiction bootstrap on the server.

local ServerStorage = game:GetService("ServerStorage")

-- Root of your lib in ServerStorage
local LibRoot = ServerStorage:WaitForChild("LibPureFiction")

-- Bootstrap module lives at:
-- ServerStorage.LibPureFiction.Bootstrap.ReplicatedStorage.Bootstrap
local BootstrapModule = LibRoot
	:WaitForChild("Bootstrap")
	:WaitForChild("ReplicatedStorage")
	:WaitForChild("Bootstrap")

local Bootstrap = require(BootstrapModule)

-- Support both styles, just in case:
if type(Bootstrap) == "function" then
	-- If the module itself is a function, call it directly
	Bootstrap("Server")
elseif type(Bootstrap) == "table" and type(Bootstrap.Init) == "function" then
	-- If it returned a table with Init(), use that
	Bootstrap.Init("Server")
else
	warn("Bootstrap module did not return a function or a table with Init()")
end

