-- ReplicatedStorage.LibPureFiction.EventBus.EventBus
-- Named bus registry + default bus.

local EventBus = {}

local buses = {}

-- A bus:
-- {
--     name = "DefaultBus",
--     listeners = { ["SomeEvent"] = { cb1, cb2, ... } },
--     requestHandlers = { ["SomeRequest"] = cb }
-- }

local function createBus(name)
	local bus = {
		name = name,
		listeners = {},
		requestHandlers = {},
	}

	function bus:on(eventName, callback)
		assert(type(eventName) == "string", "eventName must be a string")
		assert(type(callback) == "function", "callback must be a function")

		local list = self.listeners[eventName]
		if not list then
			list = {}
			self.listeners[eventName] = list
		end

		table.insert(list, callback)
		return callback
	end

	function bus:off(eventName, callback)
		local list = self.listeners[eventName]
		if not list then
			return
		end

		if not callback then
			self.listeners[eventName] = nil
			return
		end

		for i = #list, 1, -1 do
			if list[i] == callback then
				table.remove(list, i)
			end
		end

		if #list == 0 then
			self.listeners[eventName] = nil
		end
	end

	function bus:emit(eventName, ...)
		local list = self.listeners[eventName]
		if not list then
			return
		end

		local snapshot = {}
		for i = 1, #list do
			snapshot[i] = list[i]
		end

		for _, callback in ipairs(snapshot) do
			local ok, err = pcall(callback, ...)
			if not ok then
				warn(("[EventBus:%s:%s] listener error: %s"):format(self.name, eventName, tostring(err)))
			end
		end
	end

	function bus:onRequest(eventName, callback)
		assert(type(eventName) == "string", "eventName must be a string")
		assert(type(callback) == "function", "callback must be a function")

		self.requestHandlers[eventName] = callback
	end

	function bus:offRequest(eventName)
		self.requestHandlers[eventName] = nil
	end

	function bus:request(eventName, ...)
		local handler = self.requestHandlers[eventName]
		if not handler then
			warn(("[EventBus:%s:%s] no request handler registered"):format(self.name, eventName))
			return nil
		end

		local ok, result = pcall(handler, ...)
		if not ok then
			warn(("[EventBus:%s:%s] request handler error: %s"):format(self.name, eventName, tostring(result)))
			return nil
		end

		return result
	end

	return bus
end

function EventBus.get_bus(name)
	assert(type(name) == "string", "bus name must be a string")

	if not buses[name] then
		buses[name] = createBus(name)
	end

	return buses[name]
end

function EventBus.get_all_buses()
	return buses
end

-- Default bus helpers

local DEFAULT_BUS_NAME = "DefaultBus"

function EventBus.default()
	return EventBus.get_bus(DEFAULT_BUS_NAME)
end

function EventBus.on(eventName, callback)
	return EventBus.default():on(eventName, callback)
end

function EventBus.off(eventName, callback)
	return EventBus.default():off(eventName, callback)
end

function EventBus.emit(eventName, ...)
	return EventBus.default():emit(eventName, ...)
end

function EventBus.onRequest(eventName, callback)
	return EventBus.default():onRequest(eventName, callback)
end

function EventBus.offRequest(eventName)
	return EventBus.default():offRequest(eventName)
end

function EventBus.request(eventName, ...)
	return EventBus.default():request(eventName, ...)
end

-- Optional hook for the networking layer to attach helpers
function EventBus._attachNetwork(impl)
	-- impl is a table with optional fields:
	--   emitToServer(busName, eventName, ...)
	--   requestToServer(busName, eventName, ...)
	--   emitToClient(player, busName, eventName, ...)
	--   emitToAllClients(busName, eventName, ...)
	EventBus.Network = impl
end

return EventBus
