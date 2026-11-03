-- tests/lighting_test.lua -- plain Lua, no Roblox required:  lua tests/lighting_test.lua
--
-- The environment matrix half of the engine-upgrade merge. Two jobs:
--
--   1. PARITY. Read ../PARENA/stdlib/shankpit/lighting_parity.txt and assert this Luau port returns the exact
--      integers generated from the same .prn's C. SHANKPIT's packages/render/env_parity_test.c asserts the SAME
--      file, so the two worlds cannot drift without one of them going red.
--
--   2. PROPERTIES. What a designer means by "the lighting talks to itself": a storm can dim the world but never
--      make it night, haze gives light BACK instead of only taking it away, the low end is floored so a match stays
--      legible, indoor spaces are not darkened by weather they cannot see, and a lightning bolt is a real light
--      source rather than a screen tint.
--
-- Run from the repo root. PARENA_DIR overrides where the vectors are read from.

package.path = "./src/?.lua;" .. package.path

local Lighting = require("lighting")

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
    if dir and #dir > 0 then return dir .. "/stdlib/shankpit/lighting_parity.txt" end
    return "../PARENA/stdlib/shankpit/lighting_parity.txt"
end

local function ints(line)
    local out = {}
    for n in line:gsub("#.*$", ""):gmatch("-?%d+") do out[#out + 1] = tonumber(n) end
    return out
end

-- ---- 1. parity vectors: the C's answers, from the same .prn -----------------------------------------------
-- Format: cover rain storm fog_wash interior ambient flash visibility | occlusion bleed exposure floor emissive
--         flash_boost range spread        (16 integers a row; '#' comments ignored)
local path = parityPath()
local fh = io.open(path, "r")
if not fh then
    print("lighting_test: cannot open " .. path .. " (set PARENA_DIR to the PARENA checkout)")
    os.exit(1)
end

local rows = 0
for line in fh:lines() do
    local v = ints(line)
    if #v == 16 then
        rows = rows + 1
        local cover, rain, storm, fog, interior, level, flash, vis =
            v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]
        local o, bleed, expo, floor, emissive, bolt, range, spread = v[9], v[10], v[11], v[12], v[13], v[14], v[15], v[16]
        local tag = "row " .. rows .. " (" .. cover .. "/" .. rain .. "/" .. storm .. "/" .. fog ..
            " interior " .. interior .. " slider " .. level .. ")"
        eq(Lighting.occlusion(cover, rain, storm, fog, interior), o, tag .. " occlusion")
        eq(Lighting.lightBleed(o, interior), bleed, tag .. " light bleed")
        eq(Lighting.exposure(o), expo, tag .. " exposure")
        eq(Lighting.ambientFloor(o, level, interior), floor, tag .. " ambient floor")
        eq(Lighting.emissiveScale(floor), emissive, tag .. " emissive scale (fed the floor)")
        eq(Lighting.flashBoost(flash), bolt, tag .. " flash boost")
        eq(Lighting.emitterRangeScale(vis), range, tag .. " emitter range")
        eq(Lighting.emitterSpreadScale(range), spread, tag .. " emitter spread")
    end
end
fh:close()
check(rows >= 12, "read at least 12 lighting parity vectors, got " .. rows)

-- ---- 2. a storm dims the world; it does not turn it into night --------------------------------------------
local noon = Lighting.scene({ ambient_level = 5 })
local worst = Lighting.scene({ cover = 1000, rain = 1000, storm = 1000, fog_wash = 1000, ambient_level = 0 })
check(worst.occlusion > noon.occlusion, "the worst weather occludes more than a clear sky")
check(worst.occlusion <= 780, "and is capped short of night (" .. worst.occlusion .. ")")
check(worst.ambient_floor >= 300, "the legibility floor holds at its minimum (" .. worst.ambient_floor .. ")")
check(noon.ambient_floor >= 300 and noon.ambient_floor <= 900, "and never above its ceiling")

-- ---- 3. haze gives light back, and the low end is lifted -------------------------------------------------
check(worst.bleed > 0, "heavy occlusion still scatters some light back into the scene")
check(worst.exposure > noon.exposure, "the dimmer the world, the more the exposure compensates")
check(worst.emissive > noon.emissive, "and outlines are pushed UP in the dark, not down")

-- ---- 4. weather cannot darken a room it cannot see -------------------------------------------------------
local stormOut = Lighting.scene({ cover = 1000, rain = 1000, storm = 1000, fog_wash = 1000, interior = Lighting.OPEN })
local stormIn = Lighting.scene({ cover = 1000, rain = 1000, storm = 1000, fog_wash = 1000, interior = Lighting.ROOFED })
check(stormIn.occlusion < stormOut.occlusion, "a roofed space keeps only part of the weather's occlusion")
check(stormIn.ambient_floor > stormOut.ambient_floor, "and is floored HIGHER, so a room is not a cave")
check(stormIn.occlusion >= 0, "occlusion is never negative")

-- ---- 5. a bolt is a light source, not a screen tint ------------------------------------------------------
eq(Lighting.scene({}).flash, 0, "no bolt, no added light")
eq(Lighting.scene({ flash = 1000 }).flash, 300, "a full bolt adds 300 permille of scattered light")
check(Lighting.scene({ flash = 400 }).flash > 0, "a half bolt still lights the world")

-- ---- 6. emitters trade reach for spread as visibility drops -----------------------------------------------
eq(Lighting.emitterRangeScale(0), 1000, "no fog reading (<= 0) means full reach, not zero reach")
eq(Lighting.emitterRangeScale(3000), 1000, "good visibility is full reach")
check(Lighting.emitterRangeScale(1500) < 1000, "half visibility shortens the beam")
check(Lighting.emitterRangeScale(200) >= 450, "but a beam never goes out entirely")
local near = Lighting.scene({ visibility = 200 })
local far = Lighting.scene({ visibility = 3000 })
check(near.spread > far.spread, "a shorter beam is a WIDER beam (the complement, not a second dial)")
check(near.spread >= 1000 and near.spread <= 1600, "spread stays in its declared range")

-- ---- 7. the host conversions are honest about what they are ----------------------------------------------
local rb = Lighting.roblox(noon, 1)
check(rb.ambient[1] >= 0 and rb.ambient[1] <= 1, "ambient is handed over as 0..1 for Color3")
check(rb.brightness >= 0 and rb.brightness <= 1, "brightness is clamped to 0..1")
eq(rb.fog_end, nil, "no visibility reading means NO fog end, not a fog end of zero")
eq(Lighting.roblox(Lighting.scene({ visibility = 1500 }), 2).fog_end, 3000,
    "a fog end is the world's own scale times studs-per-unit")

-- the default slider is declared, not guessed, and a negative slider cannot darken below the floor
eq(Lighting.DEFAULT_AMBIENT_LEVEL, 5, "the default ambient slider is the middle of SHANKPIT's range")
check(Lighting.scene({ ambient_level = -99 }).ambient_floor >= 300, "a negative slider cannot break the floor")
check(Lighting.scene({ ambient_level = 900 }).ambient_floor <= 900, "and a huge one cannot exceed the ceiling")

if fails > 0 then
    print("lighting_test: " .. fails .. " of " .. checks .. " FAILED")
    os.exit(1)
end
print("lighting_test OK (" .. checks .. " checks, " .. rows .. " parity vectors)")
