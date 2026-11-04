-- tests/props_test.lua -- plain Lua, no Roblox required:  lua tests/props_test.lua
--
-- The last mile of the cosy slice. `cozy_test.lua` proves the rules and the host's two timestamps; this proves the
-- layer that was missing between them: that the street's props measure up in the rules' own units, that a press on
-- one produces the right verb with the right amount, and -- the part a player actually notices -- that a refusal
-- comes with an honest reason and changes NOTHING.
--
-- Nothing here is Roblox. The parts, the prompts and the puffs are in src/noobtopia.lua, which this box cannot run.

package.path = "./src/?.lua;" .. package.path

local Cozy = require("cozy")
local Props = require("props")

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

local DAY = 1000
local function fresh(seed) return Cozy.new(Cozy.IDLE, seed or 11) end

-- Every field that a refusal must leave alone. If a refusal is allowed to half-apply, the world drifts from the
-- rules without any test of the rules failing -- which is exactly the class of bug this file exists to catch.
local function snapshot(state)
    return {
        comfort = state.comfort, seed = state.seed, kicks = state.kicks,
        hugs_today = state.hugs_today, last_kick_ms = state.last_kick_ms,
        last_hug_ms = state.last_hug_ms, started = state.started,
    }
end
local function same(a, b)
    for key, value in pairs(a) do
        if b[key] ~= value then return false, key end
    end
    return true
end
local function untouched(state, before, msg)
    local ok, key = same(before, state)
    check(ok, msg .. " (changed " .. tostring(key) .. ")")
end

-- ---- 1. a trunk, measured in the rules' units ----------------------------------------------------------
eq(Props.trunkMilli(0), 0, "no trunk measures as nothing")
eq(Props.trunkMilli(-4), 0, "and neither does a negative one")
eq(Props.trunkMilli(Props.TRUNK_FULL_STUDS), 1000, "the reference trunk is 1000 permille")
eq(Props.trunkMilli(3), 500, "half the reference is 500")
check(Props.trunkMilli(7) > Props.trunkMilli(5), "a thicker trunk measures thicker")
check(Props.trunkMilli(nil) == 0, "a missing girth is nothing, not an error")

-- The two thresholds must be the SAME threshold: the .prn's 400 permille, reached by a trunk of 2.4 studs here.
local threshold_studs = Props.TRUNK_FULL_STUDS * Cozy.trunkHuggableMilli() / 1000
eq(Props.trunkMilli(threshold_studs), Cozy.trunkHuggableMilli(), "the stud threshold lands exactly on the rules' own")

-- ---- 2. the street is well formed, and stands outside the rink -----------------------------------------
local street = Props.default()
check(#street >= 4, "the street has props on it, got " .. #street)

local seen, dunes, trees = {}, 0, 0
for _, spec in ipairs(street) do
    local d = Props.describe(spec)
    check(not seen[d.id], "prop id " .. tostring(d.id) .. " is unique")
    seen[d.id] = true
    check(d.known, "prop " .. tostring(d.id) .. " has a known kind (" .. tostring(d.kind) .. ")")
    check(d.action ~= nil and #d.action > 0, "prop " .. tostring(d.id) .. " offers a verb")
    check(d.object ~= nil and #d.object > 0, "prop " .. tostring(d.id) .. " names itself")
    check(d.radius > 0, "prop " .. tostring(d.id) .. " has a reach")
    check(math.abs(d.x) >= 60 or math.abs(d.z) >= 60, "prop " .. tostring(d.id) .. " is not on the ice rink")
    if d.kind == "dandelion" then
        dunes = dunes + 1
        eq(d.is_dandelion, 1, "a dandelion is a dandelion to the rules")
        eq(d.trunk_milli, 0, "and has no trunk")
    elseif d.kind == "tree" then
        trees = trees + 1
        eq(d.is_dandelion, 0, "a tree is not a dandelion")
        check(d.trunk_studs > 0, "tree " .. d.id .. " states its girth")
    end
end
check(dunes >= 2, "at least two dandelions, got " .. dunes)
check(trees >= 2, "at least two trees, got " .. trees)

-- copies, not the world's own table: a caller that moves a prop must not move it for everybody
local moved = Props.default()
moved[1].x = -999
check(Props.default()[1].x ~= -999, "the street is handed out as copies")
eq(moved[1].id, street[1].id, "but a copy is the same prop")

-- ---- 3. kicking a dandelion ---------------------------------------------------------------------------
local dune = nil
for _, spec in ipairs(street) do
    if Props.describe(spec).kind == "dandelion" then dune = spec; break end
end

local a = fresh(7)
local r = Props.interact(dune, a, 1000, DAY)
check(r.ok, "a daytime kick on a dandelion works")
eq(r.verb, "kick", "and reports the kick")
check(r.amount >= 3 and r.amount <= 6, "giving 3..6 seeds, got " .. tostring(r.amount))
eq(r.amount, Cozy.kickPuffs(7), "from the actor's own seed")
eq(a.kicks, 1, "and it is counted")
eq(r.comfort, a.comfort, "the reply carries the comfort actually reached")
eq(r.reason, nil, "a success has no complaint attached")
eq(r.wait_ms, Cozy.KICK_COOLDOWN_MS, "and says how long until the next one")

-- night is a refusal with a reason, not a slightly smaller kick
local before = snapshot(a)
local night = Props.interact(dune, a, 100000000, Cozy.daylightMilli() - 1)
check(not night.ok, "at night the dandelion refuses")
eq(night.reason, "closed", "and says it has closed")
eq(night.verb, "kick", "the verb is still the one that was attempted")
untouched(a, before, "a closed dandelion changes nothing")

-- exactly at the daylight threshold it is open
check(Props.interact(dune, a, 100000000, Cozy.daylightMilli()).ok, "at the threshold it is open again")

-- cooldown
local b = fresh(2)
Props.interact(dune, b, 5000, DAY)
local mid = snapshot(b)
local twice = Props.interact(dune, b, 5000 + Cozy.KICK_COOLDOWN_MS - 1, DAY)
check(not twice.ok, "a second kick inside the cooldown is refused")
eq(twice.reason, "wait", "with 'not again yet'")
untouched(b, mid, "a cooldown refusal changes nothing")
check(Props.interact(dune, b, 5000 + Cozy.KICK_COOLDOWN_MS, DAY).ok, "one millisecond later it works")

-- darkness beats the cooldown. This is the one place the ORDER of the two refusals is visible: `b` kicked at
-- 5900 (the line above) and is therefore busy AND it is night, and "closed" is the sentence that stays true.
local closed_while_busy = Props.interact(dune, b, 5000 + Cozy.KICK_COOLDOWN_MS, 0)
eq(closed_while_busy.reason, "closed", "dark outranks a cooldown")

-- ---- 4. hugging a tree ---------------------------------------------------------------------------------
local mature, sapling = nil, nil
for _, spec in ipairs(street) do
    local d = Props.describe(spec)
    if d.kind == "tree" then
        if d.trunk_milli >= Cozy.trunkHuggableMilli() then mature = mature or spec else sapling = sapling or spec end
    end
end
check(mature ~= nil, "the street has a grown tree")
check(sapling ~= nil, "and a sapling, so the refusal is visible in the world")

local h = fresh(3)
local hug = Props.interact(mature, h, 1000, DAY)
check(hug.ok, "a grown tree can be hugged")
eq(hug.verb, "hug", "and reports the hug")
eq(hug.amount, Cozy.HUG_COMFORT_MILLI, "the first hug of the day is worth full")
eq(h.hugs_today, 1, "and is counted for the day")
eq(hug.reason, nil, "with nothing to complain about")

local thin_state = fresh(3)
local thin_before = snapshot(thin_state)
local no = Props.interact(sapling, thin_state, 1000, DAY)
check(not no.ok, "the sapling refuses")
eq(no.reason, "thin", "because it is too thin -- not because it is busy")
untouched(thin_state, thin_before, "a too-thin tree changes nothing")

-- a synthetic trunk exactly at the rules' threshold is huggable; a hair under is not
local at_edge = { id = "edge", kind = "tree", x = 0, z = 0, trunk_studs = threshold_studs }
check(Props.interact(at_edge, fresh(1), 1000, DAY).ok, "a trunk exactly at 400 permille is huggable")
local under = { id = "under", kind = "tree", x = 0, z = 0, trunk_studs = threshold_studs - 0.1 }
eq(Props.interact(under, fresh(1), 1000, DAY).reason, "thin", "a tenth of a stud under is not")

-- ---- 5. nothing unknown becomes a verb ----------------------------------------------------------------
local u = fresh(4)
local u_before = snapshot(u)
eq(Props.interact({ id = "rock", kind = "rock", x = 0, z = 0 }, u, 1000, DAY).reason, "unknown",
   "an unknown kind is refused")
eq(Props.interact(nil, u, 1000, DAY).reason, "unknown", "and so is nothing at all")
untouched(u, u_before, "and neither changes anything")
check(Props.describe(nil).known == false, "an absent prop does not even claim a kind")

-- ---- 6. the words --------------------------------------------------------------------------------------
check(Props.reply({ ok = false, reason = "closed" }) == Props.WORDS.closed, "a refusal is explained")
check(Props.reply({ ok = false, reason = "thin" }) == Props.WORDS.thin, "in words the world owns")
check(Props.reply({ ok = false, reason = "wait" }) == Props.WORDS.wait, "and never with an empty string")
eq(Props.reply({ ok = false, reason = "unheard-of" }), nil, "an unknown reason says nothing rather than guessing")
eq(Props.reply(nil), nil, "and there is no reply to no result")

local kick_words = Props.reply({ ok = true, verb = "kick", amount = 4, comfort = 710 })
check(string.find(kick_words, "4", 1, true) ~= nil, "the kick reply carries the seed count")
check(string.find(kick_words, "710/1000", 1, true) ~= nil, "and the comfort reached")
local hug_words = Props.reply({ ok = true, verb = "hug", amount = 120, comfort = 770 })
check(string.find(hug_words, "+120", 1, true) ~= nil, "the hug reply carries what it gave")
check(string.find(hug_words, "770/1000", 1, true) ~= nil, "and the comfort reached")

-- ---- 7. comfort still cannot leave its bounds through a prop -------------------------------------------
for _, spec in ipairs(street) do
    local s = fresh(1)
    s.comfort = 995
    for i = 1, 30 do Props.interact(spec, s, 10000 + i * 999999, DAY) end
    check(s.comfort >= 0 and s.comfort <= 1000,
        "prop " .. tostring(spec.id) .. " keeps comfort inside 0..1000 (got " .. tostring(s.comfort) .. ")")
end

if fails > 0 then
    print("props_test: " .. fails .. " of " .. checks .. " FAILED")
    os.exit(1)
end
print("props_test OK (" .. checks .. " checks)")
