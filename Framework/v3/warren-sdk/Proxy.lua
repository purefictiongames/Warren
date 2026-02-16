--[[
    Warren SDK — Remote Object Proxy

    Wraps a server-side object reference so method calls look local.
    Each method call on a proxy translates to an RPC request.

    Server returns:
        { _ref = "ref_abc123", type = "Element", ... }
    SDK wraps this in a Proxy. Calling methods on the proxy sends:
        POST /v1/rpc { target = "ref_abc123", method = "firstChild", args = {} }

    Example:
        local el = Warren.DOM.getElementById("map001")   -- returns Proxy
        local child = el:firstChild()                     -- RPC call, returns Proxy
        local name = el:getName()                          -- RPC call, returns string
]]

local Http = require(script.Parent.Http)

local Proxy = {}
Proxy.__index = Proxy

--[[
    Create a new proxy wrapping a remote object reference.

    @param warrenUrl string — Base URL of Warren API
    @param sessionToken string — Active session token
    @param ref string — Server-side reference ID
    @return Proxy
]]
function Proxy.new(warrenUrl, sessionToken, ref)
    local self = {
        _warrenUrl = warrenUrl,
        _sessionToken = sessionToken,
        _ref = ref,
        _isProxy = true,
    }

    return setmetatable(self, Proxy)
end

--[[
    Intercept method calls on the proxy.
    el:firstChild() → RPC { target = ref, method = "firstChild" }
]]
function Proxy:__index(key)
    -- Return internal fields directly
    if key == "_warrenUrl" or key == "_sessionToken" or key == "_ref" or key == "_isProxy" then
        return rawget(self, key)
    end

    -- Known Proxy methods
    if key == "getRef" then
        return function(s)
            return rawget(s, "_ref")
        end
    end

    if key == "isProxy" then
        return function()
            return true
        end
    end

    -- Everything else becomes an RPC call
    return function(s, ...)
        local args = { ... }

        -- If any arg is a Proxy, unwrap to its ref
        for i, arg in ipairs(args) do
            if type(arg) == "table" and arg._isProxy then
                args[i] = { _ref = arg._ref }
            end
        end

        local result = Http.rpc(rawget(s, "_warrenUrl"), rawget(s, "_sessionToken"), {
            target = rawget(s, "_ref"),
            method = key,
            args = args,
        })

        -- If the result is a remote reference, wrap it in a new Proxy
        if type(result) == "table" and result._ref then
            return Proxy.new(
                rawget(s, "_warrenUrl"),
                rawget(s, "_sessionToken"),
                result._ref
            )
        end

        return result
    end
end

--[[
    String representation for debugging.
]]
function Proxy:__tostring()
    return "WarrenProxy<" .. rawget(self, "_ref") .. ">"
end

return Proxy
