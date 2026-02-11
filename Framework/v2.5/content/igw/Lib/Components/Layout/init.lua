--[[
    LibPureFiction Framework v2
    Layout/init.lua - Layout Module Index

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    The Layout module provides a data-driven approach to dungeon generation:

    - LayoutSchema: Type definitions and validation
    - LayoutBuilder: Generate layouts from seed (data only, no parts)
    - LayoutInstantiator: Create parts from layout data (legacy)
    - DomBuilder: DOM-based instantiation (v2.5)
    - LayoutSerializer: Encode/decode for storage

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Layout = require(Lib.Components.Layout)

    -- Generate a new layout from seed
    local layout = Layout.Builder.generate({
        seed = 12345,
        origin = { 0, 20, 0 },
        mainPathLength = 8,
        spurCount = 4,
    })

    -- Instantiate parts in world (DOM-based)
    local result = Layout.DomBuilder.instantiate(layout, {
        name = "Region_1",
    })

    -- Serialize for storage
    local encoded = Layout.Serializer.encode(layout)

    -- Later: decode and reinstantiate
    local restored = Layout.Serializer.decode(encoded)
    local result2 = Layout.DomBuilder.instantiate(restored)
    ```

    ============================================================================
    ARCHITECTURE
    ============================================================================

    Generation Phase (once per new region):
        Seed + Config -> LayoutBuilder -> Layout Table

    Instantiation Phase (on load/rebuild):
        Layout Table -> DomBuilder -> DOM tree -> Renderer -> Parts

    Persistence:
        Layout Table <-> LayoutSerializer <-> String (DataStore/sharing)

--]]

local Layout = {}

Layout.Schema = require(script.LayoutSchema)
Layout.Context = require(script.LayoutContext)
Layout.Builder = require(script.LayoutBuilder)
Layout.Instantiator = require(script.LayoutInstantiator)  -- Legacy fallback
Layout.DomBuilder = require(script.DomBuilder)             -- v2.5 DOM-based
Layout.Serializer = require(script.LayoutSerializer)

-- Convenience re-exports (point to DomBuilder by default)
Layout.VERSION = Layout.Schema.VERSION
Layout.generate = Layout.Builder.generate
Layout.instantiate = Layout.DomBuilder.instantiate
Layout.encode = Layout.Serializer.encode
Layout.decode = Layout.Serializer.decode

return Layout
