--[[
    Warren Framework v3.0
    lune-compat.lua — Roblox→Lune compatibility shim

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Makes Roblox-style `require(script.Child)` work on Lune by providing:

        1. _G.task      — Lune's task library as a global (matches Roblox built-in)
        2. _G.script    — Proxy tree mimicking Roblox's script.Child/Parent navigation
        3. require()    — Override that intercepts proxy objects, resolves to filesystem paths

    Must be required BEFORE warren/src/init.lua.

    All originalRequire("./X") calls resolve relative to THIS file (warren/src/),
    which is exactly where the shared modules live. No absolute paths needed.

--]]

-- Capture original require — resolves relative to THIS file (warren/src/)
local originalRequire = require

--------------------------------------------------------------------------------
-- 1. TASK GLOBAL
--------------------------------------------------------------------------------

-- Roblox exposes `task` as a built-in global; Lune requires explicit import.
_G.task = originalRequire("@lune/task")

--------------------------------------------------------------------------------
-- 2. SCRIPT PROXY
--------------------------------------------------------------------------------

-- Maps proxy objects → path strings (weak keys for GC safety)
local pathMap = setmetatable({}, { __mode = "k" })

-- Caches proxy objects by path string (prevents duplicate proxies, ensures identity)
local proxyCache = {}

local function makeProxy(path)
    if proxyCache[path] then
        return proxyCache[path]
    end

    local proxy = setmetatable({}, {
        __index = function(_, key)
            if key == "Parent" then
                -- "Transport/Codec" → "Transport",  "Boot" → ".",  "." → ".."
                local parent = path:match("^(.+)/[^/]+$")
                if not parent then
                    parent = (path ~= ".") and "." or ".."
                end
                return makeProxy(parent)
            end

            -- Child: "." + "Runtime" → "Runtime"
            --        "Transport" + "Envelope" → "Transport/Envelope"
            local childPath = (path == ".") and key or (path .. "/" .. key)
            return makeProxy(childPath)
        end,

        __tostring = function()
            return "ScriptProxy<" .. path .. ">"
        end,
    })

    pathMap[proxy] = path
    proxyCache[path] = proxy
    return proxy
end

--------------------------------------------------------------------------------
-- 3. REQUIRE OVERRIDE
--------------------------------------------------------------------------------

-- Intercepts proxy objects passed to require(), resolves them to relative
-- filesystem paths, and saves/restores _G.script around each module load
-- (mirroring Roblox's per-ModuleScript `script` binding).

require = function(target)
    -- Non-proxy targets (strings like "@lune/net", "../../foo") pass through
    local proxyPath = pathMap[target]
    if not proxyPath then
        return originalRequire(target)
    end

    -- Resolve proxy path → relative require path from warren/src/
    local requirePath = "./" .. proxyPath

    -- Set script context for the module being loaded, restore after
    local prevScript = _G.script
    _G.script = makeProxy(proxyPath)

    local ok, result = pcall(originalRequire, requirePath)

    _G.script = prevScript

    if not ok then
        error("[lune-compat] require('" .. requirePath .. "'): " .. tostring(result), 2)
    end

    return result
end

--------------------------------------------------------------------------------
-- 4. INITIAL CONTEXT
--------------------------------------------------------------------------------

-- Set root script proxy so warren/src/init.lua sees
-- script.Runtime, script.Transport, etc.
_G.script = makeProxy(".")

return true
