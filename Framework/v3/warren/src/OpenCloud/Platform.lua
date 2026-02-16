--[[
    Warren Framework v3.0
    OpenCloud/Platform.lua - Cross-Runtime Abstraction Layer

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Provides a unified API for HTTP requests, JSON serialization, URL encoding,
    and MD5 hashing across Roblox and Lune runtimes.

    On Roblox: Uses HttpService for HTTP/JSON/URL, pure-Lua MD5 for hashing.
    On Lune:   Uses net/serde modules.

    Same detection pattern as Transport/Codec.lua: `_L = script == nil`.

    ============================================================================
    API
    ============================================================================

    Platform.jsonEncode(value) -> string
    Platform.jsonDecode(str)   -> any
    Platform.urlEncode(str)    -> string
    Platform.request(options)  -> { statusCode, headers, body }
    Platform.md5Base64(str)    -> string  (base64-encoded MD5 hash)

--]]

local _L = script == nil

local Platform = {}

--------------------------------------------------------------------------------
-- LUNE RUNTIME
--------------------------------------------------------------------------------

if _L then
    local net = require("@lune/net")
    local serde = require("@lune/serde")

    function Platform.jsonEncode(value)
        return serde.encode("json", value)
    end

    function Platform.jsonDecode(str)
        return serde.decode("json", str)
    end

    function Platform.urlEncode(str)
        return net.urlEncode(str)
    end

    function Platform.request(options)
        local response = net.request(options)
        return {
            statusCode = response.statusCode,
            headers = response.headers,
            body = response.body,
        }
    end

    function Platform.md5Base64(body)
        local hexHash = serde.hash("md5", body)

        -- Convert hex string to raw bytes
        local raw = {}
        for i = 1, #hexHash, 2 do
            raw[#raw + 1] = string.char(tonumber(hexHash:sub(i, i + 1), 16))
        end
        local bytes = table.concat(raw)

        -- Base64 encode
        local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local result = {}
        for i = 1, #bytes, 3 do
            local b1, b2, b3 = string.byte(bytes, i, i + 2)
            b2 = b2 or 0
            b3 = b3 or 0
            local n = b1 * 65536 + b2 * 256 + b3
            local remaining = #bytes - i + 1
            result[#result + 1] = b64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
            result[#result + 1] = b64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
            result[#result + 1] = remaining >= 2 and b64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
            result[#result + 1] = remaining >= 3 and b64:sub(n % 64 + 1, n % 64 + 1) or "="
        end
        return table.concat(result)
    end

--------------------------------------------------------------------------------
-- ROBLOX RUNTIME
--------------------------------------------------------------------------------

else
    local HttpService = game:GetService("HttpService")

    function Platform.jsonEncode(value)
        return HttpService:JSONEncode(value)
    end

    function Platform.jsonDecode(str)
        return HttpService:JSONDecode(str)
    end

    function Platform.urlEncode(str)
        return HttpService:UrlEncode(str)
    end

    function Platform.request(options)
        local response = HttpService:RequestAsync({
            Url = options.url,
            Method = options.method or "GET",
            Headers = options.headers,
            Body = options.body,
        })
        -- Normalize PascalCase → camelCase
        return {
            statusCode = response.StatusCode,
            headers = response.Headers,
            body = response.Body,
        }
    end

    --------------------------------------------------------------------------
    -- Pure-Lua MD5 (Roblox has no native MD5, uses bit32)
    --------------------------------------------------------------------------

    local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
    local lshift, rshift, rrotate = bit32.lshift, bit32.rshift, bit32.rrotate

    -- Per-round shift amounts
    local S = {
        7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
        5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
        4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
        6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,
    }

    -- Pre-computed T table: floor(2^32 * abs(sin(i))) for i = 1..64
    local T = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    }

    -- Left-rotate a 32-bit integer
    local function lrotate(x, n)
        return bor(lshift(band(x, 0xFFFFFFFF), n), rshift(band(x, 0xFFFFFFFF), 32 - n))
    end

    -- Add multiple 32-bit values with overflow wrapping
    local function add32(...)
        local sum = 0
        for i = 1, select("#", ...) do
            sum = sum + select(i, ...)
        end
        return band(sum, 0xFFFFFFFF)
    end

    local function md5(msg)
        local len = #msg
        local bits = len * 8

        -- Pad message: append 1-bit, zeros, then 64-bit length
        msg = msg .. "\128"
        while (#msg % 64) ~= 56 do
            msg = msg .. "\0"
        end
        -- Append original length as 64-bit little-endian
        for i = 0, 7 do
            msg = msg .. string.char(band(rshift(bits, i * 8), 0xFF))
        end

        -- Initialize hash values
        local a0, b0, c0, d0 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476

        -- Process each 64-byte chunk
        for chunk = 0, #msg - 1, 64 do
            local M = {}
            for i = 0, 15 do
                local offset = chunk + i * 4 + 1
                local b1, b2, b3, b4 = string.byte(msg, offset, offset + 3)
                M[i] = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
            end

            local A, B, C, D = a0, b0, c0, d0

            for i = 0, 63 do
                local F, g
                if i < 16 then
                    F = bor(band(B, C), band(bnot(B), D))
                    g = i
                elseif i < 32 then
                    F = bor(band(D, B), band(bnot(D), C))
                    g = (5 * i + 1) % 16
                elseif i < 48 then
                    F = bxor(B, bxor(C, D))
                    g = (3 * i + 5) % 16
                else
                    F = bxor(C, bor(B, bnot(D)))
                    g = (7 * i) % 16
                end

                F = add32(F, A, T[i + 1], M[g])
                A = D
                D = C
                C = B
                B = add32(B, lrotate(F, S[i + 1]))
            end

            a0 = add32(a0, A)
            b0 = add32(b0, B)
            c0 = add32(c0, C)
            d0 = add32(d0, D)
        end

        -- Output as hex string (little-endian)
        local function toLEHex(val)
            return string.format("%02x%02x%02x%02x",
                band(val, 0xFF),
                band(rshift(val, 8), 0xFF),
                band(rshift(val, 16), 0xFF),
                band(rshift(val, 24), 0xFF))
        end

        return toLEHex(a0) .. toLEHex(b0) .. toLEHex(c0) .. toLEHex(d0)
    end

    function Platform.md5Base64(body)
        local hexHash = md5(body)

        -- Convert hex to raw bytes
        local raw = {}
        for i = 1, #hexHash, 2 do
            raw[#raw + 1] = string.char(tonumber(hexHash:sub(i, i + 1), 16))
        end
        local bytes = table.concat(raw)

        -- Base64 encode
        local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local result = {}
        for i = 1, #bytes, 3 do
            local b1, b2, b3 = string.byte(bytes, i, i + 2)
            b2 = b2 or 0
            b3 = b3 or 0
            local n = b1 * 65536 + b2 * 256 + b3
            local remaining = #bytes - i + 1
            result[#result + 1] = b64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
            result[#result + 1] = b64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
            result[#result + 1] = remaining >= 2 and b64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
            result[#result + 1] = remaining >= 3 and b64:sub(n % 64 + 1, n % 64 + 1) or "="
        end
        return table.concat(result)
    end
end

return Platform
