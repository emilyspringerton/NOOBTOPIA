-- src/lighting.lua -- the environment matrix, the NOOBTOPIA half of the engine-upgrade merge.
--
-- SHANKPIT's lighting was one of the engine's real upgrades: weather, time of day, fog and the ambient slider each
-- adjusted the scene independently and every one of them could only subtract, so a stormy night at slider 0
-- collapsed to near-black walls. The fix was a STATE -- "how much light does the world get right now" -- and the
-- decisions behind it live in PARENA (stdlib/shankpit/lighting_rules.prn). SHANKPIT compiles that .prn to C
-- (packages/render/env_matrix.c applies it); this file is the Luau host over the SAME emitted rules
-- (src/generated/lighting_rules.lua), so a World that lives in Roblox gets the same atmosphere as the C build.
--
-- What stays here is the host's own business and nothing else: clamping a caller's sloppy inputs to the ranges the
-- rules declare, and turning permille into the 0..1 numbers a Roblox Lighting service wants. No `game`, no
-- `Instance`, no service write -- tests/lighting_test.lua runs this under plain Lua, and the Roblox host is the one
-- file allowed to touch a service.
--
-- Inputs, all permille 0..1000 unless noted:
--   cover, rain, storm   SkyWeather's own already-smoothed intensities
--   fog_wash             how much the sky itself is swallowed by fog
--   visibility           meteorological visibility in WORLD UNITS; <= 0 means "no fog at all"
--   ambient_level        the player's ambient slider, 0..10
--   interior             1 for a roofed space with no sky exposure
--   flash                a lightning bolt's current intensity
--
-- The point of the matrix, said once: occlusion is capped well short of night (780/1000), light bleed GIVES BACK
-- what haze scatters, exposure lifts the low end, and the ambient floor is a hard competitive-legibility guarantee
-- -- no weather and no slider can put a surface below 300/1000.

local Rules = require("generated.lighting_rules")

local Lighting = {}

-- Straight through to PARENA's own names, so there is one answer per question and none is restated here.
Lighting.occlusion = Rules.envOcclusion
Lighting.occlusionRaw = Rules.envOcclusionRaw
Lighting.lightBleed = Rules.envLightBleed
Lighting.exposure = Rules.envExposure
Lighting.ambientFloor = Rules.envAmbientFloor
Lighting.emissiveScale = Rules.envEmissiveScale
Lighting.flashBoost = Rules.envFlashBoost
Lighting.emitterRangeScale = Rules.envEmitterRangeScale
Lighting.emitterSpreadScale = Rules.envEmitterSpreadScale

Lighting.OPEN, Lighting.ROOFED = 0, 1
Lighting.SLIDER_MIN, Lighting.SLIDER_MAX = 0, 10
Lighting.ROBLOX_BRIGHTNESS_MAX = 3

-- A world that has no ambient slider behaves like the middle of SHANKPIT's, rather than inventing a darker default.
Lighting.DEFAULT_AMBIENT_LEVEL = 5

local function int(v, default)
    local n = tonumber(v)
    if n == nil then return default end
    return math.floor(n)
end

local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function clampRange(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- Roblox's Brightness goes above 1 (a place can be brighter than its default); the ceiling here is the range a
-- Lighting service accepts. It exists so the exposure term survives the conversion: the matrix's own exposure runs
-- 1000..1936 permille -- it LIFTS the low end -- and clamping that to 1.0 would delete the whole compensation.

-- The whole atmosphere, resolved once. `sky` is a plain table (a Roblox host fills it from its own weather state).
-- Returns permille, in the same units the C side uses, so a board or a debug readout can show the real numbers.
function Lighting.scene(sky)
    sky = sky or {}
    local cover = int(sky.cover, 0)
    local rain = int(sky.rain, 0)
    local storm = int(sky.storm, 0)
    local fog = int(sky.fog_wash, 0)
    local interior = int(sky.interior, Lighting.OPEN)
    local level = int(sky.ambient_level, Lighting.DEFAULT_AMBIENT_LEVEL)
    local visibility = int(sky.visibility, 0)
    local flash = int(sky.flash, 0)

    local occlusion = Lighting.occlusion(cover, rain, storm, fog, interior)
    local floor = Lighting.ambientFloor(occlusion, level, interior)
    local range = Lighting.emitterRangeScale(visibility)
    return {
        occlusion = occlusion,
        bleed = Lighting.lightBleed(occlusion, interior),
        exposure = Lighting.exposure(occlusion),
        ambient_floor = floor,
        -- Fed the FLOOR, not the raw occlusion: the floor is the light the scene actually delivers, so an outline
        -- tuned against it reads the same in a storm as at noon. This is the .prn's own stated intent.
        emissive = Lighting.emissiveScale(floor),
        flash = Lighting.flashBoost(flash),
        range = range,
        spread = Lighting.emitterSpreadScale(range),
        ambient_level = level,
        interior = interior,
        visibility = visibility,
    }
end

-- The numbers a Roblox host assigns. Pure, so it is testable without a service: the caller does
-- `Lighting.ambient = Color3.new(r, g, b)` etc. `studs_per_unit` is the world's own scale (SHANKPIT world units to
-- Roblox studs); 1 means "a unit is a stud", which is the honest default when a place has not chosen one.
function Lighting.roblox(scene_in, studs_per_unit)
    local s = scene_in or Lighting.scene(nil)
    local scale = tonumber(studs_per_unit) or 1
    local floor = clamp01((s.ambient_floor or 0) / 1000)
    local bleed = clamp01((s.bleed or 0) / 1000)
    local lit = clamp01(floor + bleed)
    local fog_end = nil
    if (s.visibility or 0) > 0 then fog_end = (s.visibility + 0) * scale end
    return {
        -- Ambient is a colour: a hazy sky fills shaded surfaces with its own scattered light, so the bleed is
        -- added to all three channels rather than being a separate multiplier. A neutral grey, because the matrix
        -- decides HOW MUCH light there is, not what colour the weather is.
        ambient = { floor, lit, floor },
        outdoor_ambient = { floor, lit, floor },
        brightness = clampRange((s.exposure or 1000) / 1000, 0, Lighting.ROBLOX_BRIGHTNESS_MAX),
        emissive = clamp01((s.emissive or 1000) / 1000),
        flash = clamp01((s.flash or 0) / 1000),
        -- nil means "no weather fog in this reading", which is a different fact from "zero fog distance".
        fog_end = fog_end,
        emitter_range = clamp01((s.range or 1000) / 1000),
        emitter_spread = clamp01((s.spread or 1000) / 1000),
    }
end

return Lighting
