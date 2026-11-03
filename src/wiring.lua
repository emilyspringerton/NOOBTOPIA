-- src/wiring.lua -- WHAT to apply, and to what. Not how to reach Roblox.
--
-- `src/lighting.lua` and `src/material.lua` answer "how dark is a storm" and "how reflective is a mirror". They were
-- pure and nothing applied them. This module is the missing decision layer between them and the engine: it turns a
-- scene into a plan of property assignments, and a part name into a surface id. It is deliberately duck-typed --
-- it writes `target.Ambient`, `part.Reflectance`, `light.Brightness` and never mentions `game`, `Color3` or
-- `Instance` -- so tests/wiring_test.lua can run every branch under plain Lua, and `src/noobtopia.lua` (the one
-- file allowed to touch a service) is left with nothing but a Color3 wrapper.
--
-- It invents no threshold. The place publishes its weather through attributes (`SHANKPIT_cover`, ...); a missing
-- reading falls back to the .prn's own declared default, and "no fog reading" is reported as `kept_fog` rather
-- than turned into a made-up fog distance -- a clear sky and a missing sensor are different facts.

local Lighting = require("lighting")
local Material = require("material")

local Wiring = {}

-- The keys a place may publish, with the defaults PARENA's own declarations imply (all-zero weather, the middle of
-- the ambient slider, open sky). `interior` is the roofed-space flag.
local SKY_DEFAULTS = {
    cover = 0,
    rain = 0,
    storm = 0,
    fog_wash = 0,
    visibility = 0,          -- 0/absent means "no weather fog reading", which the matrix treats as no fog
    ambient_level = Lighting.DEFAULT_AMBIENT_LEVEL,
    flash = 0,
    interior = Lighting.OPEN,
}
Wiring.SKY_DEFAULTS = SKY_DEFAULTS

-- Read a place's published weather. `get(key)` is supplied by the host (an attribute lookup); a throwing or
-- non-numeric getter yields the default instead of aborting the whole frame.
function Wiring.skyFrom(get)
    local sky = {}
    for key, default in pairs(SKY_DEFAULTS) do
        local value = nil
        if type(get) == "function" then
            local ok, got = pcall(get, key)
            if ok then value = got end
        end
        local n = tonumber(value)
        sky[key] = (n ~= nil) and math.floor(n) or default
    end
    return sky
end

-- The assignments a Roblox host should make, as data. `FogEnd` may be nil, and that is a READING, not a gap: the
-- matrix says there is no fog to draw, so the plan says so instead of choosing a distance.
function Wiring.lightPlan(scene, studs_per_unit)
    local rb = Lighting.roblox(scene or Lighting.scene(nil), studs_per_unit)
    return {
        Ambient = rb.ambient,
        OutdoorAmbient = rb.outdoor_ambient,
        Brightness = rb.brightness,
        FogEnd = rb.fog_end,
        scene = scene,
    }
end

-- Apply a plan to a target. `colour` converts a 0..1 triple to whatever the engine wants (the host passes
-- `Color3.new`); the default identity conversion is what the tests use. Returns which keys were written, because a
-- silent no-op is the failure mode that makes a wiring bug invisible.
function Wiring.applyPlan(plan, target, colour)
    if type(plan) ~= "table" then return nil, "no-plan" end
    if target == nil then return nil, "no-target" end
    local wrap = colour or function(rgb) return rgb end
    local keys = {}
    local function put(key, value)
        target[key] = value
        keys[#keys + 1] = key
    end
    if plan.Ambient ~= nil then put("Ambient", wrap(plan.Ambient)) end
    if plan.OutdoorAmbient ~= nil then put("OutdoorAmbient", wrap(plan.OutdoorAmbient)) end
    if plan.Brightness ~= nil then put("Brightness", plan.Brightness) end
    if plan.FogEnd ~= nil then put("FogEnd", plan.FogEnd) end
    return { keys = keys, kept_fog = (plan.FogEnd == nil) }
end

-- Name convention -> REFLECTION surface. A Roblox place has no material-kind attribute, so the surface is read from
-- the part's own name unless the part states one; a name that matches nothing reflects nothing.
local SURFACE_WORDS = {
    { "mirror", Material.MIRROR },
    { "metal", Material.METAL },
    { "glass", Material.GLASS },
}

function Wiring.surfaceForName(name)
    local lower = string.lower(tostring(name or ""))
    for _, pair in ipairs(SURFACE_WORDS) do
        if string.find(lower, pair[1], 1, true) ~= nil then return pair[2] end
    end
    return Material.OTHER
end

-- An explicit `SHANKPIT_Surface` attribute (0..3) beats the name convention: a place knows its own parts better
-- than a substring does. An out-of-range number is clamped to the vocabulary rather than passed through.
function Wiring.surfaceForPart(part)
    if part == nil then return Material.OTHER end
    local explicit = nil
    if type(part.GetAttribute) == "function" then
        local ok, got = pcall(part.GetAttribute, part, "SHANKPIT_Surface")
        if ok then explicit = got end
    end
    local n = tonumber(explicit)
    if n ~= nil then
        if n < Material.MIRROR then return Material.MIRROR end
        if n > Material.OTHER then return Material.OTHER end
        return math.floor(n)
    end
    return Wiring.surfaceForName(part.Name)
end

-- Write the surface's reflection onto a part. Returns the value written, so a caller (or a test) can see it.
function Wiring.applySurface(part, surface)
    if part == nil then return nil, "no-part" end
    local value = Material.reflectance(surface)
    part.Reflectance = value
    return value
end

-- Drive one light-emitting fixture. `room_light_milli` is how lit the room already is: a dying bulb in a bright
-- room stays readable, which is the .prn's own rule, so the host must supply it rather than assume darkness.
function Wiring.applyFixture(light, style, tick, room_light_milli)
    if light == nil then return nil, "no-light" end
    local f = Material.fixture(style, tick, room_light_milli)
    light.Brightness = f.brightness
    return f
end

return Wiring
