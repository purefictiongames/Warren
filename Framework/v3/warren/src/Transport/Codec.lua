--[[
    Warren Framework v3.0
    Transport/Codec.lua - Type-Tagged JSON Codec

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Lossless JSON serialization for Roblox types. Values that JSON can't
    natively represent are wrapped in a type tag: { _t = "TypeName", _v = data }.

    On encode, Roblox userdata (Vector3, CFrame, Color3, Enum, etc.) are
    converted to tagged tables. On decode, tagged tables are reconstituted
    into native types on whichever runtime is active.

    On Lune, decoded Roblox types stay as tagged tables — Lune code
    operates on the raw numeric data without needing Roblox constructors.

    ============================================================================
    TAGGED FORMAT
    ============================================================================

    Vector3.new(10, 20, 30)        → { _t = "Vector3", _v = {10, 20, 30} }
    CFrame.new(1,2,3)              → { _t = "CFrame", _v = {1,2,3, ...12 components} }
    Color3.fromRGB(255, 0, 0)      → { _t = "Color3", _v = {255, 0, 0} }
    Enum.Material.Rock              → { _t = "Enum", _v = "Material.Rock" }

--]]

local Runtime = require(script.Parent.Parent.Runtime)

local Codec = {}

--------------------------------------------------------------------------------
-- JSON BACKEND
--------------------------------------------------------------------------------

local jsonEncode, jsonDecode

if Runtime.isRoblox then
    local HttpService = game:GetService("HttpService")
    jsonEncode = function(data) return HttpService:JSONEncode(data) end
    jsonDecode = function(str) return HttpService:JSONDecode(str) end
else
    local net = require("@lune/net")
    jsonEncode = function(data) return net.jsonEncode(data) end
    jsonDecode = function(data) return net.jsonDecode(data) end
end

--------------------------------------------------------------------------------
-- TYPE ENCODERS (Roblox userdata → tagged table)
--------------------------------------------------------------------------------

local encoders = {}

if Runtime.isRoblox then
    encoders["Vector3"] = function(v)
        return { _t = "Vector3", _v = { v.X, v.Y, v.Z } }
    end

    encoders["Vector2"] = function(v)
        return { _t = "Vector2", _v = { v.X, v.Y } }
    end

    encoders["CFrame"] = function(cf)
        return { _t = "CFrame", _v = { cf:GetComponents() } }
    end

    encoders["Color3"] = function(c)
        return {
            _t = "Color3",
            _v = {
                math.round(c.R * 255),
                math.round(c.G * 255),
                math.round(c.B * 255),
            },
        }
    end

    encoders["BrickColor"] = function(bc)
        return { _t = "BrickColor", _v = bc.Name }
    end

    encoders["EnumItem"] = function(e)
        -- e.EnumType gives the enum category, e.Name gives the value
        return { _t = "Enum", _v = tostring(e.EnumType) .. "." .. e.Name }
    end

    encoders["UDim2"] = function(u)
        return {
            _t = "UDim2",
            _v = { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset },
        }
    end

    encoders["UDim"] = function(u)
        return { _t = "UDim", _v = { u.Scale, u.Offset } }
    end

    encoders["NumberRange"] = function(nr)
        return { _t = "NumberRange", _v = { nr.Min, nr.Max } }
    end
end

--------------------------------------------------------------------------------
-- TYPE DECODERS (tagged table → native type)
--------------------------------------------------------------------------------

local decoders = {}

if Runtime.isRoblox then
    decoders["Vector3"] = function(v)
        return Vector3.new(v[1], v[2], v[3])
    end

    decoders["Vector2"] = function(v)
        return Vector2.new(v[1], v[2])
    end

    decoders["CFrame"] = function(v)
        return CFrame.new(unpack(v))
    end

    decoders["Color3"] = function(v)
        return Color3.fromRGB(v[1], v[2], v[3])
    end

    decoders["BrickColor"] = function(v)
        return BrickColor.new(v)
    end

    decoders["Enum"] = function(v)
        -- v = "Material.Rock" → Enum.Material.Rock
        local dot = string.find(v, ".", 1, true)
        local enumType = string.sub(v, 1, dot - 1)
        local enumValue = string.sub(v, dot + 1)
        return Enum[enumType][enumValue]
    end

    decoders["UDim2"] = function(v)
        return UDim2.new(v[1], v[2], v[3], v[4])
    end

    decoders["UDim"] = function(v)
        return UDim.new(v[1], v[2])
    end

    decoders["NumberRange"] = function(v)
        return NumberRange.new(v[1], v[2])
    end
else
    -- On Lune, tagged tables stay as tagged tables.
    -- Lune code reads ._t and ._v directly for any Roblox type it needs.
    -- No decoders registered — tagged values pass through unchanged.
end

--------------------------------------------------------------------------------
-- DEEP ENCODE
--------------------------------------------------------------------------------

local function deepEncode(value)
    local vtype = type(value)

    if vtype == "table" then
        -- Already a tagged value? Leave it alone.
        if value._t then
            return value
        end

        local result = {}
        for k, v in pairs(value) do
            result[k] = deepEncode(v)
        end
        return result
    end

    -- On Roblox, check userdata types
    if Runtime.isRoblox and vtype == "userdata" then
        local rtype = typeof(value)
        local encoder = encoders[rtype]
        if encoder then
            return encoder(value)
        end
        -- Unknown userdata — convert to string as fallback
        return { _t = "_unknown", _v = tostring(value) }
    end

    -- Primitives (string, number, boolean, nil) pass through
    return value
end

--------------------------------------------------------------------------------
-- DEEP DECODE
--------------------------------------------------------------------------------

local function deepDecode(value)
    if type(value) ~= "table" then
        return value
    end

    -- Is this a tagged type?
    if value._t and value._v ~= nil then
        local decoder = decoders[value._t]
        if decoder then
            return decoder(value._v)
        end
        -- No decoder (Lune, or unknown type) — return tagged table as-is
        return value
    end

    -- Recurse into plain tables
    local result = {}
    for k, v in pairs(value) do
        result[k] = deepDecode(v)
    end
    return result
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
    Encode a Lua value to a JSON string.
    Roblox types are converted to tagged tables before JSON serialization.

    @param data any - Value to encode
    @return string - JSON string
]]
function Codec.encode(data)
    local tagged = deepEncode(data)
    return jsonEncode(tagged)
end

--[[
    Decode a JSON string back to a Lua value.
    Tagged tables are reconstituted to native Roblox types (on Roblox).
    On Lune, tagged tables remain as { _t, _v } for direct access.

    @param str string - JSON string
    @return any - Decoded value
]]
function Codec.decode(str)
    local raw = jsonDecode(str)
    return deepDecode(raw)
end

--[[
    Encode a Lua value to a tagged table (no JSON serialization).
    Useful when you need the intermediate representation.

    @param data any - Value to encode
    @return table - Tagged table
]]
function Codec.tag(data)
    return deepEncode(data)
end

--[[
    Decode a tagged table back to native types (no JSON parsing).

    @param data table - Tagged table
    @return any - Decoded value
]]
function Codec.untag(data)
    return deepDecode(data)
end

return Codec
