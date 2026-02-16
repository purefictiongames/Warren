--[[
    Warren SDK — Thin RPC client for Roblox

    All framework logic runs server-side on Warren infrastructure.
    The SDK translates local API calls into REST requests transparently.

    Usage:
        local Warren = require(ServerStorage.WarrenSDK)

        local session = Warren.init({
            apiKeySecret = "warren_api_key",
            registryUrl = "https://registry.alpharabbitgames.com",
        })

        -- These look local but are RPC calls:
        local layout = Warren.Layout.generate({ seed = 42, config = { ... } })
        local el = Warren.DOM.getElementById("map001")
        local child = el:firstChild()
]]

local Http = require(script.Http)
local Auth = require(script.Auth)
local Proxy = require(script.Proxy)

local Warren = {}
Warren._session = nil
Warren._config = nil

--[[
    Initialize the SDK. Authenticates with the Registry and sets up
    module proxies for transparent RPC.

    @param config { apiKeySecret: string, registryUrl: string }
    @return { tier: string, scopes: {string}, expiresAt: string }
]]
function Warren.init(config)
    assert(config.apiKeySecret, "apiKeySecret is required")
    assert(config.registryUrl, "registryUrl is required")

    Warren._config = config

    -- Read API key from Roblox Secrets
    local HttpService = game:GetService("HttpService")
    local secret = HttpService:GetSecret(config.apiKeySecret)

    -- Build auth payload
    local gameId = game.GameId
    local universeId = game.CreatorId ~= 0 and game.CreatorId or nil
    -- In a live game, game.GameId is the universeId
    -- game.PlaceId is the specific place, game.JobId is the server instance
    local placeId = game.PlaceId
    local jobId = game.JobId

    -- Authenticate with Registry
    local session = Auth.validate(config.registryUrl, {
        apiKey = secret,
        universeId = gameId,
        placeId = placeId,
        jobId = jobId,
    })

    Warren._session = session

    -- Start refresh loop (refresh at TTL/2)
    Auth.startRefreshLoop(config.registryUrl, session, session.ttl)

    return {
        tier = session.tier,
        scopes = session.scopes,
        expiresAt = session.expiresAt,
    }
end

--[[
    Get the current session. Errors if not initialized.
]]
function Warren.getSession()
    assert(Warren._session, "Warren.init() must be called first")
    return Warren._session
end

--[[
    Module-level RPC. Call a method on a server-side Warren module.

    @param module string — Module name (e.g. "Layout", "Style", "DOM")
    @param method string — Method name (e.g. "generate", "resolve", "getElementById")
    @param ... any — Arguments
    @return any — Return value (may be a Proxy for object references)
]]
function Warren.call(moduleName, method, ...)
    assert(Warren._session, "Warren.init() must be called first")
    assert(Warren._config, "Warren.init() must be called first")

    local args = { ... }
    local result = Http.rpc(Warren._config.registryUrl, Warren._session.sessionToken, {
        module = moduleName,
        method = method,
        args = args,
    })

    -- If the result is a remote reference, wrap it in a Proxy
    if type(result) == "table" and result._ref then
        return Proxy.new(Warren._config.registryUrl, Warren._session.sessionToken, result._ref)
    end

    return result
end

--[[
    Batch RPC. Send multiple calls in a single HTTP request.
    Useful for reducing round trips during initialization.

    @param calls {{ module: string, method: string, args: {any}, target: string? }}
    @return {any} — Array of results, one per call
]]
function Warren.batch(calls)
    assert(Warren._session, "Warren.init() must be called first")
    assert(Warren._config, "Warren.init() must be called first")

    local results = Http.rpcBatch(Warren._config.registryUrl, Warren._session.sessionToken, calls)

    -- Wrap any remote references in proxies
    for i, result in ipairs(results) do
        if type(result) == "table" and result._ref then
            results[i] = Proxy.new(Warren._config.registryUrl, Warren._session.sessionToken, result._ref)
        end
    end

    return results
end

--[[
    Shutdown. Revokes the session with the Registry.
    Call this on game:BindToClose().
]]
function Warren.shutdown()
    if Warren._session and Warren._config then
        Auth.revoke(Warren._config.registryUrl, Warren._session.sessionToken)
        Warren._session = nil
    end
end

-- Module proxies: Warren.Layout.generate(...) → Warren.call("Layout", "generate", ...)
-- These are lazy — created on first access via __index
setmetatable(Warren, {
    __index = function(self, key)
        -- Don't proxy known SDK methods
        if key == "init" or key == "call" or key == "batch" or key == "shutdown"
            or key == "getSession" or key == "_session" or key == "_config" then
            return nil
        end

        -- Create a module proxy
        local moduleProxy = setmetatable({}, {
            __index = function(_, method)
                return function(...)
                    return Warren.call(key, method, ...)
                end
            end,
        })

        -- Cache it
        rawset(self, key, moduleProxy)
        return moduleProxy
    end,
})

return Warren
