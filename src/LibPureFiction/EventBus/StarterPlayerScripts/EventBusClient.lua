-- StarterPlayerScripts.EventBusClient
-- Client-side wiring for EventBus networking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LibRoot = ReplicatedStorage:WaitForChild("LibPureFiction")
local EventBusFolder = LibRoot:WaitForChild("EventBus")

local Import = require(LibRoot:WaitForChild("Utils"):WaitForChild("Import"))
local EventBus = Import("EventBus.ReplicatedStorage.EventBus")

-- Remote objects (must match names from EventBusServer)
local clientToServer = EventBusFolder:WaitForChild("ClientToServer")
local clientToServerRequest = EventBusFolder:WaitForChild("ClientToServerRequest")
local serverToClient = EventBusFolder:WaitForChild("ServerToClient")

-- Server → Client events are funneled into the local EventBus
serverToClient.OnClientEvent:Connect(function(busName, eventName, ...)
	busName = busName or "DefaultBus"
	local bus = EventBus.get_bus(busName)
	bus:emit(eventName, ...)
end)

local networkImpl = {}

-- Fire-and-forget to server
function networkImpl.emitToServer(busName, eventName, ...)
	busName = busName or "DefaultBus"
	clientToServer:FireServer(busName, eventName, ...)
end

-- Request/response to server
function networkImpl.requestToServer(busName, eventName, ...)
	busName = busName or "DefaultBus"
	return clientToServerRequest:InvokeServer(busName, eventName, ...)
end

-- Attach helpers
EventBus._attachNetwork(networkImpl)

-- Also make sure global wiring exists (in case Bootstrap hasn't run yet on client)
_G.LibPureFiction = _G.LibPureFiction or {}
_G.LibPureFiction.EventBus = _G.LibPureFiction.EventBus or EventBus
_G.LibPureFiction.EventBus.Network = networkImpl
