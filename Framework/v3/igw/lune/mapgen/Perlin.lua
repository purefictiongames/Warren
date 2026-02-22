--[[
    Pure Luau Perlin Noise (2D)
    Fallback for environments without math.noise (Lune, etc.)

    Perlin.noise2d(x, y) → number in [-0.5, 0.5]
    Matches Roblox math.noise(x, y) range convention.

    Based on Ken Perlin's improved noise (2002).
    Seeded via Perlin.seed(n) — shuffles permutation table.
--]]

local Perlin = {}

-- Permutation table (doubled for wrap-around)
local p = {}
local perm = {
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,
    140,36,103,30,69,142,8,99,37,240,21,10,23,190,6,148,
    247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,
    57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,
    74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,
    60,211,133,230,220,105,92,41,55,46,245,40,244,102,143,54,
    65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,
    200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,
    52,217,226,250,124,123,5,202,38,147,118,126,255,82,85,212,
    207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,
    119,248,152,2,44,154,163,70,221,153,101,155,167,43,172,9,
    129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,
    218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,241,
    81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,157,
    184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,
    222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180,
}

-- Initialize default permutation
for i = 0, 255 do
    p[i] = perm[i + 1]
    p[i + 256] = perm[i + 1]
end

function Perlin.seed(n)
    -- Fisher-Yates shuffle seeded from n
    local shuffled = {}
    for i = 1, 256 do shuffled[i] = perm[i] end

    -- Simple LCG seeded RNG for shuffle
    local s = n % 2147483647
    if s <= 0 then s = s + 2147483646 end
    local function nextRand()
        s = (s * 48271) % 2147483647
        return s
    end

    for i = 256, 2, -1 do
        local j = (nextRand() % i) + 1
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    for i = 0, 255 do
        p[i] = shuffled[i + 1]
        p[i + 256] = shuffled[i + 1]
    end
end

-- Fade curve: 6t^5 - 15t^4 + 10t^3
local function fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- 2D gradient (4 directions)
local function grad2d(hash, x, y)
    local h = hash % 4
    if h == 0 then return  x + y end
    if h == 1 then return -x + y end
    if h == 2 then return  x - y end
    return -x - y
end

function Perlin.noise2d(x, y)
    -- Integer cell coordinates
    local xi = math.floor(x) % 256
    local yi = math.floor(y) % 256

    -- Fractional position within cell
    local xf = x - math.floor(x)
    local yf = y - math.floor(y)

    -- Fade curves
    local u = fade(xf)
    local v = fade(yf)

    -- Hash corners
    local aa = p[p[xi] + yi]
    local ab = p[p[xi] + yi + 1]
    local ba = p[p[xi + 1] + yi]
    local bb = p[p[xi + 1] + yi + 1]

    -- Bilinear interpolation of gradients
    local result = lerp(
        lerp(grad2d(aa, xf, yf),     grad2d(ba, xf - 1, yf),     u),
        lerp(grad2d(ab, xf, yf - 1), grad2d(bb, xf - 1, yf - 1), u),
        v
    )

    -- Scale to [-0.5, 0.5] range (raw range is approx [-1, 1])
    return result * 0.5
end

return Perlin
