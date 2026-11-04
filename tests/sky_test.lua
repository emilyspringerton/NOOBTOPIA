-- tests/sky_test.lua -- plain Lua, no Roblox required:  lua tests/sky_test.lua
--
-- The sky slice: day/night, what each weather does, and how far you can see through fog. Two jobs:
--
--   1. PARITY against ../PARENA/stdlib/shankpit/sky_parity.txt, which SHANKPIT's
--      packages/render/sky_parity_test.c asserts from the C side.
--   2. PROPERTIES: noon is full sun and midnight is none, night is a real state and not a small number, fog is
--      harder to see through at night than at noon, only storms have lightning and it decays, and the clock wraps
--      in both directions.
--
-- Run from the repo root. PARENA_DIR overrides where the vectors are read from.

package.path = "./src/?.lua;" .. package.path

local Sky = require("sky")
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
    if dir and #dir > 0 then return dir .. "/stdlib/shankpit/sky_parity.txt" end
    return "../PARENA/stdlib/shankpit/sky_parity.txt"
end

local function ints(line)
    local out = {}
    for n in line:gsub("#.*$", ""):gmatch("-?%d+") do out[#out + 1] = tonumber(n) end
    return out
end

-- ---- 1. parity vectors: the C's answers, from the same .prn -----------------------------------------------
-- Format: minutes weather tick | sun night visibility flash clock_hundredths
local path = parityPath()
local fh = io.open(path, "r")
if not fh then
    print("sky_test: cannot open " .. path .. " (set PARENA_DIR to the PARENA checkout)")
    os.exit(1)
end

local rows = 0
for line in fh:lines() do
    local v = ints(line)
    if #v == 8 then
        rows = rows + 1
        local minutes, weather, tick = v[1], v[2], v[3]
        local tag = "row " .. rows .. " (minutes " .. minutes .. " weather " .. weather .. " tick " .. tick .. ")"
        eq(Sky.sunPermille(minutes), v[4], tag .. " sun")
        eq(Sky.isNightAt(minutes), v[5], tag .. " night")
        eq(Sky.visibilityFor(weather, v[4]), v[6], tag .. " visibility")
        eq(Sky.flashPermille(weather, tick), v[7], tag .. " flash")
        eq(Sky.clockHundredths(minutes), v[8], tag .. " clock hundredths")
    end
end
fh:close()
check(rows >= 20, "read at least 20 sky parity vectors, got " .. rows)

-- ---- 2. the day ---------------------------------------------------------------------------------------
eq(Sky.sunPermille(720), 1000, "noon is full sun")
eq(Sky.sunPermille(0), 0, "midnight is no sun at all")
eq(Sky.sunPermille(300), 0, "05:00 is still night")
eq(Sky.sunPermille(480), 1000, "08:00 is full day")
eq(Sky.sunPermille(1140), 0, "19:00 is night again")
check(Sky.sunPermille(479) < Sky.sunPermille(480), "dawn rises")
check(Sky.sunPermille(600) > Sky.sunPermille(420), "and keeps rising through the morning")
check(Sky.sunPermille(1000) > Sky.sunPermille(1100), "dusk falls")

check(Sky.isNightAt(0) == 1, "midnight is night")
check(Sky.isNightAt(720) == 0, "noon is not")
check(Sky.isNightAt(1200) == 1, "and 20:00 is night again")
check(Sky.isNightAt(330) == 1, "a dim dawn counts as night, by the declared threshold")
check(Sky.isNightAt(450) == 0, "but 07:30 is already 833 permille of sun, so it is not")

-- ---- 3. the weather -----------------------------------------------------------------------------------
eq(Sky.weatherCount(), 5, "five weathers")
eq(Sky.cover(Sky.CLEAR), 0, "a clear sky is not covered")
eq(Sky.cover(Sky.OVERCAST), 700, "overcast is a cloud deck, not a blackout")
eq(Sky.cover(Sky.STORM), 1000, "a storm covers everything")
eq(Sky.rain(Sky.OVERCAST), 0, "overcast does not rain")
eq(Sky.rain(Sky.RAIN), 800, "rain rains")
eq(Sky.storm(Sky.CLEAR), 0, "a clear sky does not storm")
eq(Sky.storm(Sky.STORM), 900, "and a storm does")
eq(Sky.fogWash(Sky.FOG), 1000, "fog is mostly wash")
eq(Sky.fogWash(Sky.CLEAR), 0, "a clear night carries no haze it never had")

-- ---- 4. fog visibility: a reading, not a distance ------------------------------------------------------
eq(Sky.baseVisibility(Sky.CLEAR), 0, "clear weather has NO fog to draw")
eq(Sky.visibilityFor(Sky.CLEAR, 0), 0, "so a clear midnight is still not fog")
eq(Sky.visibilityFor(Sky.FOG, 1000), 300, "fog at noon is 300 world units")
check(Sky.visibilityFor(Sky.FOG, 0) < Sky.visibilityFor(Sky.FOG, 1000), "fog is thicker at night than at noon")
check(Sky.visibilityFor(Sky.FOG, 0) > 0, "but never exactly zero -- you can still see something")
eq(Sky.visibilityFor(Sky.RAIN, 1000), 1500, "rain at noon")
check(Sky.visibilityFor(Sky.STORM, 1000) < Sky.visibilityFor(Sky.RAIN, 1000), "a storm is thicker than rain")

-- ---- 5. lightning is a bolt, and only storms have one ---------------------------------------------------
eq(Sky.flashPermille(Sky.STORM, 0), 1000, "a bolt starts at full")
check(Sky.flashPermille(Sky.STORM, 3) < 1000, "and decays")
eq(Sky.flashPermille(Sky.STORM, 6), 0, "to nothing within a few ticks")
eq(Sky.flashPermille(Sky.STORM, 240), 1000, "then strikes again on its cadence")
eq(Sky.flashPermille(Sky.RAIN, 0), 0, "rain does not light up")
eq(Sky.flashPermille(Sky.CLEAR, 0), 0, "and neither does a clear sky")

-- ---- 6. the clock the host owns -----------------------------------------------------------------------
eq(Sky.clockHundredths(720), 1200, "noon is 12.00 hours")
eq(Sky.clockHundredths(0), 0, "midnight is 0.00")
eq(Sky.wrapMinutes(-60), 1380, "a negative minute wraps backwards to yesterday")
eq(Sky.wrapMinutes(1500), 60, "and past midnight wraps forwards")

local clock = Sky.new(1430, Sky.STORM, 0)
-- clock-hundredths is INTEGER division by design (the rules are I32), so a ClockTime is quantised to two decimals:
-- 23:50 is 2383 hundredths, i.e. 23.83 hours. A host that wants finer resolution asks for minutes instead.
eq(Sky.clockHours(clock), 23.83, "23:50 is 23.83 hours for a ClockTime")
Sky.advance(clock, 20, 20)
eq(clock.minutes, 10, "advancing past midnight wraps the day")
eq(clock.tick, 20, "and the tick advanced, which is what the bolt reads")

local dflt = Sky.new(nil, nil, nil)
eq(dflt.minutes, 720, "a clock with no seed starts at noon")
eq(dflt.weather, Sky.CLEAR, "in clear weather")
eq(Sky.sun(dflt), 1000, "which is full sun")
eq(Sky.night(dflt), false, "and not night")

-- ---- 7. the sky feeds the matrix, and night does not break its floor -----------------------------------
local stormNoon = Sky.inputs(Sky.new(720, Sky.STORM, 0), 5)
eq(stormNoon.cover, 1000, "a storm's inputs carry its cover")
check(stormNoon.visibility > 0, "and a real visibility reading, so the host can draw fog")
local sheet = Lighting.scene(stormNoon)
check(sheet.occlusion > Lighting.scene({}).occlusion, "which the matrix calls darker than a clear noon")

local fogNoon = Sky.inputs(Sky.new(720, Sky.FOG, 0), 5)
eq(fogNoon.fog_wash, 1000, "fog weather reaches the matrix as wash")
check(Lighting.scene(fogNoon).occlusion > Lighting.scene({}).occlusion, "and occludes")

-- the matrix's own promise survives whatever the sky says: weather cannot put a surface under the floor
for _, weather in ipairs({ Sky.CLEAR, Sky.OVERCAST, Sky.RAIN, Sky.STORM, Sky.FOG }) do
    for _, minutes in ipairs({ 0, 300, 720, 1200 }) do
        local sc = Lighting.scene(Sky.inputs(Sky.new(minutes, weather, 0), 0))
        check(sc.ambient_floor >= 300, "weather " .. weather .. " at minute " .. minutes ..
            " still respects the legibility floor (" .. sc.ambient_floor .. ")")
    end
end

if fails > 0 then
    print("sky_test: " .. fails .. " of " .. checks .. " FAILED")
    os.exit(1)
end
print("sky_test OK (" .. checks .. " checks, " .. rows .. " parity vectors)")
