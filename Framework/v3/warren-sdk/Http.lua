--[[
    Warren SDK — HTTP transport layer

    Wraps HttpService with retry/backoff and JSON encoding.
    All requests go through this module.
]]

local HttpService = game:GetService("HttpService")

local Http = {}

local MAX_RETRIES = 3
local BACKOFF_BASE = 0.5 -- seconds

--[[
    Make an HTTP request with retry and exponential backoff.

    @param url string
    @param method string — "GET" or "POST"
    @param headers { [string]: string }
    @param body any? — Will be JSON-encoded if present
    @return { ok: boolean, status: number, body: any }
]]
function Http.request(url, method, headers, body)
    local requestOptions = {
        Url = url,
        Method = method,
        Headers = headers or {},
    }

    requestOptions.Headers["Content-Type"] = "application/json"

    if body ~= nil then
        requestOptions.Body = HttpService:JSONEncode(body)
    end

    local lastErr
    for attempt = 1, MAX_RETRIES do
        local ok, response = pcall(function()
            return HttpService:RequestAsync(requestOptions)
        end)

        if ok then
            local responseBody = nil
            if response.Body and #response.Body > 0 then
                local decodeOk, decoded = pcall(function()
                    return HttpService:JSONDecode(response.Body)
                end)
                responseBody = decodeOk and decoded or response.Body
            end

            -- Don't retry client errors (4xx)
            if response.StatusCode >= 400 and response.StatusCode < 500 then
                return {
                    ok = false,
                    status = response.StatusCode,
                    body = responseBody,
                }
            end

            -- Success
            if response.StatusCode >= 200 and response.StatusCode < 300 then
                return {
                    ok = true,
                    status = response.StatusCode,
                    body = responseBody,
                }
            end

            -- 5xx → retry
            lastErr = "HTTP " .. response.StatusCode
        else
            lastErr = tostring(response)
        end

        -- Exponential backoff before retry
        if attempt < MAX_RETRIES then
            task.wait(BACKOFF_BASE * (2 ^ (attempt - 1)))
        end
    end

    return {
        ok = false,
        status = 0,
        body = { error = "request_failed", detail = lastErr },
    }
end

--[[
    Single RPC call to the Warren API.

    @param warrenUrl string — Base URL of Warren API
    @param sessionToken string
    @param call { module: string?, method: string, args: {any}?, target: string? }
    @return any — Decoded response value
]]
function Http.rpc(warrenUrl, sessionToken, call)
    local result = Http.request(
        warrenUrl .. "/v1/rpc",
        "POST",
        { Authorization = "Bearer " .. sessionToken },
        call
    )

    if not result.ok then
        error("[Warren RPC] " .. tostring(result.status) .. ": "
            .. (type(result.body) == "table" and (result.body.error or "unknown") or tostring(result.body)))
    end

    return result.body.value
end

--[[
    Batch RPC call — multiple operations in a single HTTP request.

    @param warrenUrl string
    @param sessionToken string
    @param calls {{ module: string?, method: string, args: {any}?, target: string? }}
    @return {any} — Array of results
]]
function Http.rpcBatch(warrenUrl, sessionToken, calls)
    local result = Http.request(
        warrenUrl .. "/v1/rpc/batch",
        "POST",
        { Authorization = "Bearer " .. sessionToken },
        { calls = calls }
    )

    if not result.ok then
        error("[Warren RPC Batch] " .. tostring(result.status) .. ": "
            .. (type(result.body) == "table" and (result.body.error or "unknown") or tostring(result.body)))
    end

    return result.body.results
end

return Http
