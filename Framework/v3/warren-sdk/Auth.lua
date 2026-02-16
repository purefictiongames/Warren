--[[
    Warren SDK — Auth module

    Handles session lifecycle: validate, refresh loop, revoke.
]]

local Http = require(script.Parent.Http)

local Auth = {}

local _refreshThread = nil

--[[
    Authenticate with the Registry.

    @param registryUrl string
    @param params { apiKey: Secret, universeId: number, placeId: number, jobId: string }
    @return { sessionToken: string, tier: string, scopes: {string}, ttl: number, expiresAt: string }
]]
function Auth.validate(registryUrl, params)
    -- Roblox Secret objects are opaque — they CANNOT be passed through
    -- JSONEncode (body). They can only be used as header values, where
    -- RequestAsync resolves them at the HTTP layer.

    local result = Http.request(
        registryUrl .. "/v1/auth/validate",
        "POST",
        { ["X-API-Key"] = params.apiKey },
        {
            universeId = params.universeId,
            placeId = params.placeId,
            jobId = params.jobId,
        }
    )

    if not result.ok then
        local errMsg = "unknown"
        if type(result.body) == "table" then
            errMsg = result.body.error or "unknown"
        end
        error("[Warren Auth] Validation failed (" .. result.status .. "): " .. errMsg)
    end

    return result.body
end

--[[
    Start a background refresh loop.
    Refreshes the session at half the TTL interval.

    @param registryUrl string
    @param session { sessionToken: string, ttl: number }
    @param ttl number — TTL in seconds
]]
function Auth.startRefreshLoop(registryUrl, session, ttl)
    if _refreshThread then
        task.cancel(_refreshThread)
    end

    local interval = math.max(ttl / 2, 10) -- refresh at half TTL, minimum 10s

    _refreshThread = task.spawn(function()
        while true do
            task.wait(interval)

            local result = Http.request(
                registryUrl .. "/v1/auth/refresh",
                "POST",
                { Authorization = "Bearer " .. session.sessionToken },
                nil
            )

            if result.ok and result.body then
                session.ttl = result.body.ttl or ttl
                session.expiresAt = result.body.expiresAt
                interval = math.max(session.ttl / 2, 10)
            else
                warn("[Warren Auth] Refresh failed, will retry in " .. interval .. "s")
            end
        end
    end)
end

--[[
    Revoke the session. Called on shutdown.

    @param registryUrl string
    @param sessionToken string
]]
function Auth.revoke(registryUrl, sessionToken)
    if _refreshThread then
        task.cancel(_refreshThread)
        _refreshThread = nil
    end

    -- Best-effort revoke (game is shutting down)
    pcall(function()
        Http.request(
            registryUrl .. "/v1/auth/revoke",
            "POST",
            { Authorization = "Bearer " .. sessionToken },
            nil
        )
    end)
end

return Auth
