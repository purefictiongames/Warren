-- ReplicatedFirst.ClientBootstrap (source in ServerStorage.LibPureFiction.Bootstrap.ReplicatedFirst)

local ServerStorage = game:GetService("ServerStorage")
local LibRoot = ServerStorage:WaitForChild("LibPureFiction")
local BootstrapModule = LibRoot:WaitForChild("Bootstrap"):WaitForChild("ReplicatedStorage"):WaitForChild("Bootstrap")

local Bootstrap = require(BootstrapModule)
Bootstrap.Init("Client")
