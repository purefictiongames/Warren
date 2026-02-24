--[[
    IGW v2 Pipeline — MaterialValidator
    Lazy-init terrain material validator. Probes workspace.Terrain at first
    call (inside handler), not at require-time, so Lune can safely require
    node files that depend on this module.
--]]

local TERRAIN_MATERIALS = nil

local function get()
    if TERRAIN_MATERIALS then return TERRAIN_MATERIALS end

    TERRAIN_MATERIALS = {}
    local terrain = workspace.Terrain
    for _, item in ipairs(Enum.Material:GetEnumItems()) do
        if item.Value ~= 0 then
            local ok = pcall(terrain.GetMaterialColor, terrain, item)
            if ok then
                TERRAIN_MATERIALS[item] = true
                TERRAIN_MATERIALS[item.Name] = item
            end
        end
    end
    return TERRAIN_MATERIALS
end

return { get = get }
