-- tests/cozy_test.lua -- plain Lua, no Roblox required:  lua tests/cozy_test.lua
--
-- The cosy slice. Two jobs, the same two as every merge slice:
--   1. PARITY against ../PARENA/stdlib/shankpit/cozy_parity.txt, which SHANKPIT's
--      packages/simulation/cozy_test.c asserts from the C side (make test-cozy).
--   2. BEHAVIOUR: a dandelion is only kickable by day and off cooldown, a tree only if it is thick enough, the
--      same tree gives less each time in one day, and comfort never overshoots or leaves its bounds.
--
-- Run from the repo root. PARENA_DIR overrides where the vectors are read from.

package.path = "./src/?.lua;" .. package.path

local Cozy = require("cozy")

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
    if dir and #dir > 0 then return dir .. "/stdlib/shankpit/cozy_parity.txt" end
    return "../PARENA/stdlib/shankpit/cozy_parity.txt"
end

local function ints(line)
    local out = {}
    for n in line:gsub("#.*$", ""):gmatch("-?%d+") do out[#out + 1] = tonumber(n) end
    return out
end

-- ---- 1. parity vectors: the C's answers, from the same .prn ----------------------------------------------
-- Format: question a b c | answer
local fh = io.open(parityPath(), "r")
if not fh then
    print("cozy_test: cannot open " .. parityPath() .. " (set PARENA_DIR to the PARENA checkout)")
    os.exit(1)
end

local answered = {
    [0] = function() return Cozy.KICK_COOLDOWN_MS end,
    [1] = function() return Cozy.KICK_LIFT_MILLI end,
    [2] = function(a) return Cozy.kickPuffs(a) end,
    [3] = function(a, b, c) return Cozy.kickAllowed(a, b, c) end,
    [4] = function() return Cozy.HUG_COOLDOWN_MS end,
    [5] = function() return Cozy.HUG_COMFORT_MILLI end,
    [6] = function(a, b) return Cozy.hugAllowed(a, b) end,
    [7] = function(a) return Cozy.hugDiminish(a) end,
    [8] = function(a) return Cozy.comfortTarget(a) end,
    [9] = function(a, b, c) return Cozy.comfortDrift(a, b, c) end,
    [10] = function() return Cozy.LINE_COUNT end,
    [11] = function(a, b) return Cozy.lineIndex(a, b) end,
    [12] = function(a) return Cozy.flavorDaylight(a) end,
    [13] = function() return Cozy.trunkHuggableMilli() end,
    [14] = function() return Cozy.daylightMilli() end,
}

local rows = 0
for line in fh:lines() do
    local v = ints(line)
    if #v == 5 then
        rows = rows + 1
        local f = answered[v[1]]
        if not f then
            check(false, "row " .. rows .. " names an unknown question " .. v[1])
        else
            eq(f(v[2], v[3], v[4]), v[5], "row " .. rows .. " q=" .. v[1] ..
                " (" .. v[2] .. "," .. v[3] .. "," .. v[4] .. ")")
        end
    end
end
fh:close()
check(rows >= 20, "read at least 20 cozy parity rows, got " .. rows)

-- ---- 2. kicking a dandelion ----------------------------------------------------------------------------
local a = Cozy.new(Cozy.IDLE, 7)
eq(a.comfort, Cozy.comfortTarget(Cozy.IDLE), "a noob starts at its mood's comfort target")

local puffs = Cozy.kick(a, 1, 1000, 1000)
check(puffs >= 3 and puffs <= 6, "a daylight kick gives 3..6 seeds")
eq(puffs, Cozy.kickPuffs(7), "and the seeds come from the noob's own seed")
eq(a.comfort, Cozy.comfortTarget(Cozy.IDLE) + Cozy.KICK_LIFT_MILLI, "the kick lifts comfort")
eq(a.kicks, 1, "and is counted")

eq(Cozy.kick(a, 1, 1100, 1000), 0, "a second kick inside the cooldown is refused")
check(Cozy.kick(a, 1, 1000 + Cozy.KICK_COOLDOWN_MS, 1000) > 0, "after the cooldown it works again")
eq(Cozy.kick(a, 0, 999999, 1000), 0, "something that is not a dandelion cannot be kicked")
eq(Cozy.kick(a, 1, 99999999, 100), 0, "and at night the dandelion is closed")
check(Cozy.kick(a, 1, 99999999, Cozy.daylightMilli()) > 0, "at exactly the daylight threshold it is open")

local cap = Cozy.new(Cozy.CURIOUS, 1)
cap.comfort = 990
Cozy.kick(cap, 1, 1000, 1000)
eq(cap.comfort, 1000, "comfort clamps at 1000")

-- ---- 3. hugging a tree --------------------------------------------------------------------------------
local h = Cozy.new(Cozy.TIRED, 3)
eq(Cozy.hug(h, 100, 5000), 0, "a sapling is too thin to hug")
eq(Cozy.hug(h, Cozy.trunkHuggableMilli(), 5000), Cozy.HUG_COMFORT_MILLI,
   "a trunk at the threshold is huggable at full worth")
eq(Cozy.hug(h, 900, 5100), 0, "a second hug inside the cooldown is refused")
eq(Cozy.hug(h, 900, 5000 + Cozy.HUG_COOLDOWN_MS), math.floor(Cozy.HUG_COMFORT_MILLI * 700 / 1000),
   "the second hug of the day is worth less")
eq(h.hugs_today, 2, "hugs are counted for the day")

local at = 5000
for _ = 2, 7 do
    at = at + Cozy.HUG_COOLDOWN_MS
    Cozy.hug(h, 900, at)
end
eq(Cozy.hug(h, 900, at + Cozy.HUG_COOLDOWN_MS), math.floor(Cozy.HUG_COMFORT_MILLI * 200 / 1000),
   "the hundredth hug keeps a floor")
Cozy.newDay(h)
eq(h.hugs_today, 0, "morning resets the tree's count")
eq(Cozy.hug(h, 900, at + 2 * Cozy.HUG_COOLDOWN_MS), Cozy.HUG_COMFORT_MILLI,
   "so the first hug of a new day is worth full again")

-- ---- 4. comfort drifts, and never overshoots ----------------------------------------------------------
local d = Cozy.new(Cozy.STARTLED, 0)
d.comfort = 1000
Cozy.tick(d, 10000)
eq(d.comfort, Cozy.comfortTarget(Cozy.STARTLED), "a long tick lands exactly on the mood's target")
d.comfort = 1000
Cozy.tick(d, 10)
eq(d.comfort, 990, "a short tick moves one permille per tick")
d.comfort = Cozy.comfortTarget(Cozy.STARTLED)
Cozy.tick(d, 500)
eq(d.comfort, Cozy.comfortTarget(Cozy.STARTLED), "drift does not overshoot its target")
check(Cozy.comfortDrift(-50, 500, 10) >= 0, "a negative comfort is clamped into range")
check(Cozy.comfortDrift(5000, 500, 10) <= 1000, "and so is one above the maximum")

-- ---- 5. the small reply is deterministic ---------------------------------------------------------------
eq(Cozy.line(a), Cozy.lineIndex(Cozy.LINE_COUNT, a.seed), "the reply comes from the noob's own seed")
local line_before = Cozy.line(a)
local b = Cozy.new(Cozy.IDLE, 0)
eq(Cozy.line(b), Cozy.line(b), "and the same noob gets the same reply twice")
eq(Cozy.lineIndex(0, 5), 0, "there is no line zero when the world offers none")
check(line_before >= 0 and line_before < Cozy.LINE_COUNT, "every line index is inside the table")

-- ---- 6. the world cannot be made unreadable by comfort --------------------------------------------------
for _, mood in ipairs({ Cozy.IDLE, Cozy.CURIOUS, Cozy.BORED, Cozy.TIRED, Cozy.STARTLED }) do
    local n = Cozy.new(mood, mood)
    for _ = 1, 40 do Cozy.kick(n, 1, 100000, 1000) end
    check(n.comfort <= 1000, "mood " .. mood .. " stays within 0..1000 after a lot of kicking")
end

if fails > 0 then
    print("cozy_test: " .. fails .. " of " .. checks .. " FAILED")
    os.exit(1)
end
print("cozy_test OK (" .. checks .. " checks, " .. rows .. " parity rows)")
