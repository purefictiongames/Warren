--[[
    It Gets Worse — Lune Authority Server
    lune/server.lua

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the Lune-side entry point for IGW. It serves as a stateless
    compute backend for:

        - Layout generation (LayoutBuilder + style resolution)

    Roblox game servers call layout generation via:
        - WarrenSDK → Registry → Lune RPC (port 8091)

    ============================================================================
    RUNNING
    ============================================================================

    ```bash
    lune run lune/server.lua
    ```

    Environment variables:
        WARREN_AUTH_TOKEN     - Shared secret for RPC auth
        WARREN_RPC_PORT       - RPC port (default 8091)

--]]

local process = require("@lune/process")
local stdio = require("@lune/stdio")

-- Roblox exposes `task` as a built-in global; Lune requires explicit import
_G.task = require("@lune/task")

-- Load Warren framework (dual-runtime modules detect Lune via `script == nil`)
local Warren = require("../../warren/src")

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local config = {
    authToken = process.env.WARREN_AUTH_TOKEN or "igw-dev-token",
    rpcPort = tonumber(process.env.WARREN_RPC_PORT) or 8091,
}

--------------------------------------------------------------------------------
-- BOOT
--------------------------------------------------------------------------------

stdio.write("=== IT GETS WORSE — Lune Authority Server ===\n")
stdio.write("Warren v" .. Warren._VERSION .. "\n\n")

-- No Boot.start() — IGW only needs RPC compute, not Transport/Sync/OpenCloud
stdio.write("[IGW] Server ready.\n")

--------------------------------------------------------------------------------
-- LAYOUT GENERATION (authority — keeps generation code off client)
--------------------------------------------------------------------------------

local net = require("@lune/net")
local serde = require("@lune/serde")

local LayoutBuilder = require("../src/Components/Layout/LayoutBuilder")
local Styles = Warren.Styles
local ClassResolver = Warren.ClassResolver

--------------------------------------------------------------------------------
-- STYLE RESOLUTION (pre-resolve on server, send alongside layout)
--------------------------------------------------------------------------------

-- Palette names (same list as StyleBridge.getPaletteClass)
local PALETTE_NAMES = {
    "palette-classic-lava",
    "palette-blue-inferno",
    "palette-toxic-depths",
    "palette-void-abyss",
    "palette-golden-forge",
    "palette-frozen-fire",
    "palette-blood-sanctum",
    "palette-solar-furnace",
    "palette-nether-realm",
    "palette-spectral-cavern",
}

-- Maps element role class -> which palette color property to use for Color
local COLOR_ROLE_MAP = {
    ["cave-wall"]           = "wallColor",
    ["cave-ceiling"]        = "wallColor",
    ["cave-floor"]          = "floorColor",
    ["cave-light-fixture"]  = "fixtureColor",
    ["cave-light-spacer"]   = "wallColor",
    ["cave-pad-base"]       = "floorColor",
    ["cave-point-light"]    = "lightColor",
}

-- Class combos that DomBuilder.buildTree() produces (with palette)
local PALETTE_CLASSES = {
    "cave-wall", "cave-ceiling", "cave-floor",
    "cave-light-spacer", "cave-light-fixture",
    "cave-point-light", "cave-pad-base",
}

-- Non-palette classes
local PLAIN_CLASSES = {
    "cave-zone", "cave-truss", "cave-pad", "cave-spawn",
}

local function resolveStylesForRegion(regionNum)
    local paletteClass = PALETTE_NAMES[((regionNum - 1) % #PALETTE_NAMES) + 1]
    local reservedKeys = { id = true, class = true, type = true }
    local resolvedClasses = {}

    -- Resolve palette-bearing class combos
    for _, baseClass in ipairs(PALETTE_CLASSES) do
        local classStr = baseClass .. " " .. paletteClass
        local resolved = ClassResolver.resolve(
            { class = classStr }, Styles, { reservedKeys = reservedKeys }
        )

        -- Apply color role mapping (same logic as StyleBridge.createResolver)
        local roleKey = COLOR_ROLE_MAP[baseClass]
        if roleKey and resolved[roleKey] and not resolved.Color then
            resolved.Color = resolved[roleKey]
        end

        -- Clean up palette meta-properties (not real Instance properties)
        resolved.wallColor = nil
        resolved.floorColor = nil
        resolved.lightColor = nil
        resolved.fixtureColor = nil

        resolvedClasses[classStr] = resolved
    end

    -- Resolve plain classes (no palette)
    for _, className in ipairs(PLAIN_CLASSES) do
        resolvedClasses[className] = ClassResolver.resolve(
            { class = className }, Styles, { reservedKeys = reservedKeys }
        )
    end

    -- Resolve palette colors for terrain painting (kept as RGB tables)
    local paletteResolved = ClassResolver.resolve(
        { class = paletteClass }, Styles, { reservedKeys = reservedKeys }
    )

    return {
        resolvedClasses = resolvedClasses,
        palette = {
            wallColor = paletteResolved.wallColor,
            floorColor = paletteResolved.floorColor,
            lightColor = paletteResolved.lightColor,
            fixtureColor = paletteResolved.fixtureColor,
        },
        paletteClass = paletteClass,
    }
end

local function handleLayoutGenerate(payload)
    if not payload.config then
        return { status = "rejected", reason = "missing_config" }
    end

    local layout = LayoutBuilder.generate(payload.config)
    local styles = resolveStylesForRegion(payload.config.regionNum or 1)

    stdio.write("[IGW] Generated layout: seed=" .. (payload.config.seed or "?")
        .. ", region=" .. (payload.config.regionNum or "?")
        .. ", rooms=" .. (layout.rooms and #layout.rooms or 0)
        .. ", styles=" .. (styles.paletteClass or "?") .. "\n")

    return { status = "ok", layout = layout, styles = styles }
end

--------------------------------------------------------------------------------
-- SYNCHRONOUS RPC SERVER (Registry → Lune compute calls)
--------------------------------------------------------------------------------
-- The Registry proxies stateless compute (layout, styles) through this endpoint.

local rpcHandlers = {
    ["layout.action.generate"] = handleLayoutGenerate,
}

net.serve(config.rpcPort, {
    address = "0.0.0.0",
    handleRequest = function(request)
        if request.method ~= "POST" or request.path ~= "/rpc" then
            return { status = 404, body = '{"error":"not_found"}' }
        end

        -- Auth check
        local auth = request.headers["authorization"] or ""
        if auth ~= "Bearer " .. config.authToken then
            return { status = 401, body = '{"error":"unauthorized"}' }
        end

        local body = serde.decode("json", request.body)
        local handler = rpcHandlers[body.action]
        if not handler then
            return { status = 404, body = serde.encode("json", { error = "action_not_found", action = body.action }) }
        end

        local ok, result = pcall(handler, body.payload)
        if ok then
            return { status = 200, body = serde.encode("json", result) }
        else
            return { status = 500, body = serde.encode("json", { error = tostring(result) }) }
        end
    end,
})

stdio.write("[IGW] RPC server listening on port " .. config.rpcPort .. "\n")
stdio.write("[IGW] Press Ctrl+C to stop.\n\n")

-- Lune's net.serve runs in the background — script stays alive
-- until the process is killed
