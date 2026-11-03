-- tests/material_test.lua -- plain Lua, no Roblox required:  lua tests/material_test.lua
--
-- The material half of the engine-upgrade merge. Same two jobs as lighting_test.lua:
--
--   1. PARITY against ../PARENA/stdlib/shankpit/material_parity.txt, which SHANKPIT's
--      packages/render/env_parity_test.c asserts from the C side.
--   2. PROPERTIES: a mirror is more reflective than glass and brick is not reflective at all, a strobe is on and
--      off rather than dim, a dying bulb fades, a health tint engages only below its knee, and every answer stays
--      in its declared range.
--
-- The vector file is query-coded because this vocabulary answers many different questions:
--   q=0  reflection(kind)                    q=1  light level(style, tick)
--   q=2  emissive(style, tick, room_light)   q=3  frame index(fps, frames, tick)
--   q=4  scroll u/v(kind, tick)              q=5  tint low health(hp, max_hp)
--   q=6  tint submerged(depth)               q=7  tint acid(acid)
--   q=8  tint shield(shield, max_shield)     q=9  palette index(index)
--   q=10 voxel axis(pos, origin, extent, res)
-- Each row is:  q a b c d e   answer [answer2]

package.path = "./src/?.lua;" .. package.path

local Material = require("material")

local fails, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end
local function eq(got, want, msg)
    checks = checks + 1
    if got ~= want then
        fails = fails + 1
        print("FAIL: " .. msg .. " (got " .. tostring(got) .. " want " .. tostring(want) .. ")")
    end
end

local function parityPath()
    local dir = os.getenv("PARENA_DIR")
    if dir and #dir > 0 then return dir .. "/stdlib/shankpit/material_parity.txt" end
    return "../PARENA/stdlib/shankpit/material_parity.txt"
end

local function ints(line)
    local out = {}
    for n in line:gsub("#.*$", ""):gmatch("-?%d+") do out[#out + 1] = tonumber(n) end
    return out
end

-- The same dispatch the C dumper uses, so a row means the same question on both sides.
local function answer(q, a, b, c, d)
    if q == 0 then return { Material.reflectionPermille(a) } end
    if q == 1 then return { Material.lightLevel(a, b) } end
    if q == 2 then return { Material.emissive(a, b, c) } end
    if q == 3 then return { Material.frameIndex(a, b, c) } end
    if q == 4 then return { Material.scrollU(a, b), Material.scrollV(a, b) } end
    if q == 5 then return { Material.tintLowHealth(a, b) } end
    if q == 6 then return { Material.tintSubmerged(a) } end
    if q == 7 then return { Material.tintAcid(a) } end
    if q == 8 then return { Material.tintShield(a, b) } end
    if q == 9 then return { Material.paletteIndex(a) } end
    if q == 10 then return { Material.voxelAxis(a, b, c, d) } end
    return nil
end

local path = parityPath()
local fh = io.open(path, "r")
if not fh then
    print("material_test: cannot open " .. path .. " (set PARENA_DIR to the PARENA checkout)")
    os.exit(1)
end

local rows = 0
for line in fh:lines() do
    local v = ints(line)
    if #v >= 7 then
        rows = rows + 1
        -- v[1]=q, v[2..6]=a..e, so the first ANSWER is v[7] (the C reader indexes the same fields 0-based)
        local q, a, b, c, d = v[1], v[2], v[3], v[4], v[5]
        local got = answer(q, a, b, c, d)
        check(got ~= nil, "row " .. rows .. " names a known question (" .. tostring(q) .. ")")
        if got then
            for i = 1, #got do
                eq(got[i], v[6 + i], "row " .. rows .. " q=" .. q .. " answer " .. i)
            end
        end
    end
end
fh:close()
check(rows >= 20, "read at least 20 material parity vectors, got " .. rows)

-- ---- the reflection ladder, in the words a designer uses -------------------------------------------------
-- The REFLECTION axis, which is NOT the animation-kind axis: both start at 0 and mean different things, and this
-- file once conflated them (calling the mirror "plain"). They are named apart now.
eq(Material.reflectance(Material.MIRROR), 0.9, "a mirror is 90% reflection, which is what makes it a mirror")
eq(Material.reflectance(Material.METAL), 0.38, "metal is a bright highlight over a real base coat")
eq(Material.reflectance(Material.GLASS), 0.32, "glass stays subtle over a pane that is already transparent")
eq(Material.reflectance(Material.OTHER), 0, "anything else reflects nothing, and costs nothing")
check(Material.reflectance(Material.MIRROR) > Material.reflectance(Material.METAL), "a mirror out-reflects metal")
check(Material.reflectance(Material.METAL) > Material.reflectance(Material.GLASS), "and metal out-reflects glass")
-- Both axes happen to START at 0 -- that is precisely why they are named apart, so the check is that each name
-- answers its own question and neither drifts into the other: `MIRROR` is a reflection surface, `KIND_PLAIN` is an
-- animation kind (it does not scroll), and calling one where the other belongs would be a visible bug.
eq(Material.MIRROR, 0, "the reflection axis starts at mirror")
eq(Material.KIND_PLAIN, 0, "the animation axis starts at plain -- same integer, different question")
eq(Material.appearance(Material.KIND_PLAIN, 500).scroll_u, 0, "a plain material does not scroll")
eq(Material.reflectance(Material.MIRROR), 0.9, "and a mirror's reflection is not a scroll speed")

-- ---- light styles are behaviours, not brightness levels --------------------------------------------------
eq(Material.lightLevel(Material.STROBE, 0), 1000, "a strobe is fully on at tick 0")
eq(Material.lightLevel(Material.STROBE, 6), 0, "and fully OFF six ticks later -- not merely dim")
local seen = {}
for t = 0, 24 do seen[Material.lightLevel(Material.STROBE, t)] = true end
check(seen[1000] and seen[0], "over a few ticks it really visits both extremes")
check(Material.lightLevel(Material.DYING, 0) > Material.lightLevel(Material.DYING, 900),
    "a dying bulb fades rather than flickering randomly")
check(Material.lightLevel(Material.STEADY, 12345) == 1000, "a steady fixture stays steady at any tick")

-- ---- a fixture keeps a floor in a dark room, and does not blind you in a lit one --------------------------
local dark = Material.fixture(Material.STROBE, 6, 100)  -- a dark room: the fixture keeps its floor
local lit = Material.fixture(Material.STROBE, 6, 900)
check(dark.level >= 350, "in a dark room even an OFF fixture keeps a readable floor (" .. dark.level .. ")")
check(lit.level <= dark.level, "a lit room does not push a fixture brighter than a dark one needs")
check(dark.brightness == dark.level / 1000, "the Roblox-facing brightness is the same number, converted once")

-- ---- tints engage at their own knee, and stay in range ---------------------------------------------------
eq(Material.tintLowHealth(100, 100), 0, "full health has no tint")
check(Material.tintLowHealth(10, 100) > Material.tintLowHealth(25, 100), "the tint deepens as health falls")
eq(Material.tintLowHealth(50, 0), 0, "a zero max health cannot divide by zero -- it returns no tint")
for hp = 0, 100, 5 do
    local t = Material.tintLowHealth(hp, 100)
    check(t >= 0 and t <= 1000, "low-health tint stays 0..1000 at hp " .. hp)
end
eq(Material.tintSubmerged(0), 0, "dry land has no water tint")
eq(Material.tintSubmerged(4000), 1000, "deep water is fully tinted")
check(Material.tintAcid(1000) <= 900, "acid tints cap at 900, so the HUD is never fully washed out")

-- ---- animation: one sheet, one offset, and the palette never wraps negative ------------------------------
eq(Material.frameIndex(10, 4, 0), 0, "a frame loop starts on its first frame")
check(Material.frameIndex(10, 4, 6) ~= Material.frameIndex(10, 4, 12), "and advances with the tick")
eq(Material.frameIndex(0, 4, 100), 0, "a zero fps is frame 0, not a division by zero")
eq(Material.paletteIndex(-1), 255, "a negative palette index wraps to 255, not -1")
eq(Material.paletteIndex(256), 0, "and 256 wraps to 0")
eq(Material.scrollU(Material.KIND_PLAIN, 500), 0, "a plain material does not scroll")
check(Material.scrollU(Material.KIND_SCROLL, 30) > 0, "ooze creeps")
check(Material.scrollV(Material.KIND_SCROLL, 30) > 0, "and creeps sideways, which is what makes it read as thick")

-- ---- the voxel lightmap has a floor outside every volume -------------------------------------------------
eq(Material.VOXEL_AMBIENT_FLOOR, 120, "outside every probe volume there is still some light (120)")
eq(Material.voxelAxis(0, 0, 1000, 16), 0, "the start of a volume is cell 0")
eq(Material.voxelAxis(1000, 0, 1000, 16), 15, "the end is the last cell, not past it")
eq(Material.voxelAxis(99999, 0, 1000, 16), 15, "past the end is clamped, not wrapped")
eq(Material.voxelAxis(500, 0, 0, 16), 0, "a zero-extent volume has no cells")

if fails > 0 then
    print("material_test: " .. fails .. " of " .. checks .. " FAILED")
    os.exit(1)
end
print("material_test OK (" .. checks .. " checks, " .. rows .. " parity vectors)")
