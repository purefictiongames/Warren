--[[
    IGW v2 Pipeline — InventoryNode (Subtractive Terrain)

    Computes the feature budget for a biome region. Reads BiomeInventory.lua
    via ClassResolver cascade, rolls concrete counts from {min, max} ranges
    using seeded RNG.

    Output (payload):
        .biomeConfig — resolved full config (baseElevation, spine, features)
        .inventory   — concrete counts: { stratovolcano = 2, cinder_cone = 14, ... }
--]]

return {
    name = "InventoryNode",
    domain = "server",

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onBuildInventory = function(self, payload)
            local ClassResolver = self._System.ClassResolver
            local BiomeInventory = require(script.Parent.Parent.BiomeInventory)

            local biomeName = payload.biomeName or "mountain"
            local seed = (payload.seed or os.time()) + 4217

            -- Resolve biome config via ClassResolver cascade
            local biomeConfig = ClassResolver.resolve(
                { class = biomeName },
                BiomeInventory,
                { reservedKeys = { class = true, name = true } }
            )
            biomeConfig.name = biomeName

            -- Seeded RNG for deterministic rolls
            local rng = Random.new(seed)

            -- Roll concrete counts from {min, max} ranges
            local features = biomeConfig.features or {}
            local inventory = {}
            local parts = {}

            for className, def in pairs(features) do
                local countRange = def.count or { 0, 0 }
                local count = rng:NextInteger(countRange[1], math.max(countRange[1], countRange[2]))
                inventory[className] = count
                if count > 0 then
                    table.insert(parts, className .. "=" .. count)
                end
            end

            table.sort(parts)

            payload.biomeConfig = biomeConfig
            payload.inventory = inventory

            print(string.format(
                "[InventoryNode] Biome: %s | Features: %s (seed %d)",
                biomeName, table.concat(parts, " "), seed
            ))

            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
