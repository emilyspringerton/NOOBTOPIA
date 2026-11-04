-- src/sky.lua -- the clock and the weather, the NOOBTOPIA half of the sky slice.
--
-- `lighting.lua` resolves an atmosphere from weather INTENSITIES. Nothing owned those intensities, and nothing
-- owned time of day at all: a place would have had to invent "how overcast is overcast" and SHANKPIT's C would
-- have had its own answer. That shared decision is `PARENA/stdlib/shankpit/sky_rules.prn`, emitted to
-- `src/generated/sky_rules.lua` here and to C in SHANKPIT.
--
-- What stays here is the host's own business: holding a clock and advancing it at the pace a place wants, and
-- presenting the rules' answers in the shape `lighting.lua` takes. No `game`, no `Color3`, no `Lighting` write --
-- tests/sky_test.lua runs every branch under plain Lua.
--
-- Weather codes: 0 CLEAR, 1 OVERCAST, 2 RAIN, 3 STORM, 4 FOG.
-- Minutes are 0..1439 on a 24-hour day and wrap.
--
-- Deliberate split, worth stating because it is the thing that makes night dark without breaking the matrix:
-- the weather intensities go through `lighting.lua`, whose ambient floor is a competitive-legibility guarantee
-- (300 permille, no weather or slider can go below it). NIGHT IS NOT WEATHER, so the sun is reported separately
-- (`Sky.sun`) and a host spends it where it likes -- `wiring.lua` spends it on OutdoorAmbient only, which leaves
-- the floored indoor ambient intact while the outdoors actually gets dark.

local Rules = require("generated.sky_rules")

local Sky = {}

Sky.CLEAR, Sky.OVERCAST, Sky.RAIN, Sky.STORM, Sky.FOG = 0, 1, 2, 3, 4

-- Straight through to PARENA's own names: one answer per question, restated nowhere.
Sky.DAY_MINUTES = Rules.skyDayMinutes()
Sky.weatherCount = Rules.skyWeatherCount
Sky.wrapMinutes = Rules.skyWrapMinutes
Sky.sunPermille = Rules.skySunPermille
Sky.isNightAt = Rules.skyNight
Sky.cover = Rules.skyCover
Sky.rain = Rules.skyRain
Sky.storm = Rules.skyStorm
Sky.fogWash = Rules.skyFogWash
Sky.baseVisibility = Rules.skyBaseVisibility
Sky.visibilityFor = Rules.skyVisibility
Sky.flashPermille = Rules.skyFlashPermille
Sky.clockHundredths = Rules.skyClockHundredths

-- A clock at a place: where it is in the day, what the weather is doing, and how many ticks have gone by (the
-- last one only matters to lightning, which is a bolt and needs a tick).
function Sky.new(minutes, weather, tick)
    return {
        minutes = Sky.wrapMinutes(math.floor(tonumber(minutes) or 720)),
        weather = math.floor(tonumber(weather) or Sky.CLEAR),
        tick = math.floor(tonumber(tick) or 0),
    }
end

-- Advance the clock. The PACING is the host's (`minutes_per_minute` is what "one real minute of play" is worth),
-- because how long a day lasts is a design choice and not a rule; the WRAPPING is the rules'.
function Sky.advance(sky, delta_minutes, delta_ticks)
    sky.minutes = Sky.wrapMinutes(sky.minutes + math.floor(tonumber(delta_minutes) or 0))
    sky.tick = sky.tick + math.floor(tonumber(delta_ticks) or 0)
    return sky.minutes
end

function Sky.sun(sky)
    return Sky.sunPermille(sky.minutes)
end

function Sky.night(sky)
    return Sky.isNightAt(sky.minutes) == 1
end

-- Hours as a fractional number, which is what a Roblox `Lighting.ClockTime` wants. The division by 100 is the
-- only part of this the rules do not do, because the TARGET's representation is the target's business.
function Sky.clockHours(sky)
    return Sky.clockHundredths(sky.minutes) / 100
end

function Sky.visibility(sky)
    return Sky.visibilityFor(sky.weather, Sky.sun(sky))
end

function Sky.flash(sky)
    return Sky.flashPermille(sky.weather, sky.tick)
end

-- The weather inputs `lighting.lua` takes, plus the sun, which it deliberately does not.
function Sky.inputs(sky, ambient_level)
    return {
        cover = Sky.cover(sky.weather),
        rain = Sky.rain(sky.weather),
        storm = Sky.storm(sky.weather),
        fog_wash = Sky.fogWash(sky.weather),
        visibility = Sky.visibility(sky),
        ambient_level = ambient_level,
        flash = Sky.flash(sky),
        sun = Sky.sun(sky),
    }
end

return Sky
