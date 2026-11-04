-- tests/wiring_test.lua -- plain Lua, no Roblox required:  lua tests/wiring_test.lua
--
-- The last mile, tested where it can be: `src/wiring.lua` decides WHAT to write to a Lighting service, a part's
-- Reflectance and a PointLight's Brightness, and writes it into duck-typed targets. So every branch below runs for
-- real here, and `src/noobtopia.lua` (which cannot be run on this box) is left with only the Color3 wrapper.
--
-- What this pins, in the order it matters:
--   * a place that publishes nothing gets the .prn's own defaults, not zeros that mean something else;
--   * a throwing or non-numeric attribute does not abort a frame;
--   * "no fog reading" leaves the existing fog alone and says so (`kept_fog`), instead of writing a made-up distance;
--   * the ambient handed to the engine still respects the legibility floor, so wiring cannot undo it;
--   * a part's explicit surface attribute beats its name, and an out-of-range one is clamped to the vocabulary;
--   * a fixture's brightness is what the rules said, in the 0..1 Roblox wants.

package.path = "./src/?.lua;" .. package.path

local Wiring = require("wiring")
local Lighting = require("lighting")
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

-- ---- 1. a place that publishes nothing ---------------------------------------------------------------
local bare = Wiring.skyFrom(nil)
eq(bare.cover, 0, "no published weather is clear")
eq(bare.visibility, 0, "and no visibility reading")
eq(bare.ambient_level, Lighting.DEFAULT_AMBIENT_LEVEL, "the slider falls back to the .prn's own default")
eq(bare.interior, Lighting.OPEN, "a place is open sky unless it says otherwise")

local published = { cover = 1000, storm = 250, ambient_level = 8, visibility = 1500 }
local sky = Wiring.skyFrom(function(key) return published[key] end)
eq(sky.cover, 1000, "a published reading is used")
eq(sky.storm, 250, "each key is read on its own")
eq(sky.rain, 0, "an unpublished key keeps its default rather than borrowing a neighbour's value")
eq(sky.ambient_level, 8, "the slider comes through")

local threw = Wiring.skyFrom(function() error("no attributes on this instance") end)
eq(threw.cover, 0, "a throwing getter falls back to defaults instead of killing the frame")
eq(threw.ambient_level, Lighting.DEFAULT_AMBIENT_LEVEL, "all of them, not just the first")
eq(Wiring.skyFrom(function() return "7" end).cover, 7, "a numeric string is coerced")
eq(Wiring.skyFrom(function() return 3.9 end).cover, 3, "and floored, because the rules are integer-in")
eq(Wiring.skyFrom(function() return true end).cover, 0, "a non-number is not treated as 1")

-- ---- 2. the plan: what the engine should be told -----------------------------------------------------
local clear = Lighting.scene({})
local clearPlan = Wiring.lightPlan(clear, 1)
eq(clearPlan.FogEnd, nil, "no visibility reading means NO fog end, which is a fact about the reading")
check(clearPlan.Ambient[1] >= 0 and clearPlan.Ambient[1] <= 1, "a colour triple is 0..1, ready for Color3")
eq(clearPlan.Brightness, clear.exposure / 1000, "brightness is the exposure, converted once")

local stormy = Lighting.scene({ cover = 1000, rain = 1000, storm = 1000, fog_wash = 1000,
                                ambient_level = 0, visibility = 3000 })
local stormPlan = Wiring.lightPlan(stormy, 1)
eq(stormPlan.FogEnd, 3000, "a visibility reading becomes a fog distance at the place's own scale")
eq(Wiring.lightPlan(stormy, 4).FogEnd, 12000, "studs-per-unit scales it, and the host owns that choice")
check(stormPlan.Ambient[1] >= 0.3, "the worst weather still hands the engine at least the 300 permille floor")
check(stormPlan.Brightness > clearPlan.Brightness, "and more exposure compensation than a clear sky")
check(stormPlan.Brightness > 1, "which means it must be handed a Brightness above 1.0, not clamped back to it")

-- ---- 3. applying a plan writes only what it has ------------------------------------------------------
local target = { FogEnd = 12345 }
local report = Wiring.applyPlan(clearPlan, target, function(rgb) return { triple = rgb } end)
eq(report.kept_fog, true, "a plan without a fog end reports that it kept the existing fog")
eq(target.FogEnd, 12345, "and does not overwrite it")
check(target.Ambient ~= nil and target.Ambient.triple ~= nil, "the host's colour wrapper was used")
eq(target.Brightness, clearPlan.Brightness, "brightness is written through")
local keys = {}
for _, k in ipairs(report.keys) do keys[k] = true end
check(keys.Ambient and keys.Brightness, "the report names what it actually wrote")
check(not keys.FogEnd, "and does not claim a key it skipped")

local fogTarget = {}
local fogReport = Wiring.applyPlan(stormPlan, fogTarget, nil)
eq(fogTarget.FogEnd, 3000, "a plan WITH a fog end writes it")
eq(fogReport.kept_fog, false, "and says it did")
eq(fogTarget.Ambient[1], stormPlan.Ambient[1], "with the identity conversion the tests pass")

eq(select(2, Wiring.applyPlan(nil, {})), "no-plan", "no plan is its own reason")
eq(select(2, Wiring.applyPlan({}, nil)), "no-target", "no target is its own reason")

-- ---- 3b. night is spent on the OUTDOORS, and a place's own reading beats the model -------------------
local noonPlan = Wiring.lightPlan(clear, 1, 1000)
eq(noonPlan.night_scale, 1000, "full sun leaves the outdoors at full ambient")
eq(noonPlan.OutdoorAmbient[1], noonPlan.Ambient[1], "so outdoors and indoors agree at noon")
local nightPlan = Wiring.lightPlan(clear, 1, 0)
eq(nightPlan.night_scale, Wiring.NIGHT_AMBIENT_FLOOR_PERMILLE, "midnight makes the outdoors its declared floor")
eq(nightPlan.Ambient[1], noonPlan.Ambient[1], "while the FLOORED indoor ambient is untouched")
check(nightPlan.OutdoorAmbient[1] < nightPlan.Ambient[1], "so a night is visibly darker outside than inside")
check(nightPlan.OutdoorAmbient[1] > 0, "but not pitch black -- 250 permille of it")
eq(Wiring.lightPlan(clear, 1).night_scale, nil, "with no sun passed, there is no night split at all")
eq(Wiring.lightPlan(clear, 1, -50).night_scale, Wiring.NIGHT_AMBIENT_FLOOR_PERMILLE, "a negative sun clamps")
eq(Wiring.lightPlan(clear, 1, 5000).night_scale, 1000, "and so does one past noon")

local model = { cover = 1000, rain = 1000, storm = 1000, fog_wash = 1000, visibility = 3000,
                ambient_level = 5, flash = 0, interior = 0 }
local merged = Wiring.mergeSky(model, { rain = 0 })
eq(merged.rain, 0, "a place that published rain=0 really meant it")
eq(merged.cover, 1000, "a field it never mentioned comes from the model, not from a default")
eq(merged.visibility, 3000, "including the visibility reading")
eq(Wiring.mergeSky(model, {}).cover, 1000, "an empty override changes nothing")
eq(Wiring.mergeSky(model, nil).cover, 1000, "and neither does no override")
eq(Wiring.mergeSky(nil, { cover = 250 }).cover, 250, "an override with no model still lands")

-- ---- 4. surfaces: an explicit attribute beats a name, and the vocabulary is closed --------------------
eq(Wiring.surfaceForName("Mirror"), Material.MIRROR, "a mirror is a mirror")
eq(Wiring.surfaceForName("glass pane"), Material.GLASS, "a name containing glass is glass")
eq(Wiring.surfaceForName("MetalPipe"), Material.METAL, "so is metal")
eq(Wiring.surfaceForName("Brick"), Material.OTHER, "brick reflects nothing")
eq(Wiring.surfaceForName(nil), Material.OTHER, "an unnamed part reflects nothing either")
eq(Wiring.surfaceForName("GLASS"), Material.GLASS, "the name match ignores case")

local explicit = { Name = "Brick", GetAttribute = function(_, k) return (k == "SHANKPIT_Surface") and 2 or nil end }
eq(Wiring.surfaceForPart(explicit), Material.GLASS, "an explicit attribute beats the name convention")
local clampedHigh = { Name = "x", GetAttribute = function() return 99 end }
eq(Wiring.surfaceForPart(clampedHigh), Material.OTHER, "an out-of-range surface clamps to the vocabulary")
local clampedLow = { Name = "x", GetAttribute = function() return -4 end }
eq(Wiring.surfaceForPart(clampedLow), Material.MIRROR, "at both ends")
local noApi = { Name = "Mirror" }
eq(Wiring.surfaceForPart(noApi), Material.MIRROR, "a part without GetAttribute still classifies by name")
eq(Wiring.surfaceForPart(nil), Material.OTHER, "no part at all is not a crash")

local part = { Name = "Mirror", GetAttribute = function() return nil end }
eq(Wiring.applySurface(part, Material.MIRROR), 0.9, "the mirror's reflection is 0.9")
eq(part.Reflectance, 0.9, "and it landed on the part")
eq(Wiring.applySurface(part, Material.OTHER), 0, "a brick gets 0, not a leftover 0.9")
eq(part.Reflectance, 0, "the value really changed")
eq(Wiring.applySurface(nil, Material.MIRROR), nil, "no part, no write")

-- ---- 5. fixtures: the rules' brightness, in the engine's units ---------------------------------------
local light = {}
local lit = Wiring.applyFixture(light, Material.STROBE, 0, 900)
eq(lit.level, 1000, "a strobe on its on-tick is fully bright")
eq(light.Brightness, 1, "which is 1.0 for a Roblox PointLight")
Wiring.applyFixture(light, Material.STROBE, 6, 900)
eq(light.Brightness, 0.12, "and on its off-tick it drops to the .prn's own floor in a LIT room (120), not to zero")
check(light.Brightness < lit.brightness, "which is still a strobe: much dimmer than its on-tick")
check(light.Brightness >= 0 and light.Brightness <= 1, "brightness never leaves 0..1")
local darkRoom = Wiring.applyFixture(light, Material.STROBE, 6, 100)
check(darkRoom.brightness >= 0.35, "in a dark room the fixture keeps its floor, so the place is not pitch black")
eq(Wiring.applyFixture(nil, 0, 0, 0), nil, "no light, no write")

if fails > 0 then
    print("wiring_test: " .. fails .. " of " .. checks .. " FAILED")
    os.exit(1)
end
print("wiring_test OK (" .. checks .. " checks)")
