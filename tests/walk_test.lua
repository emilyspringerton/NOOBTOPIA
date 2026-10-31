-- tests/walk_test.lua -- plain Lua, no Roblox required:  lua tests/walk_test.lua
--
-- The movement half of the three-way merge. Two jobs:
--
--   1. PARITY. Read the vectors in ../PARENA/stdlib/noobtopia/walk_parity.txt and assert this Luau port returns the
--      exact integers generated from the same .prn's C. Those vectors are the C side's answers, because the C is
--      authoritative and the port is the bug if they disagree (docs/THREE_WAY_MERGE.md). The C test asserts the
--      SAME file, so the two halves cannot drift without one of them going red.
--
--   2. PROPERTIES. The things a designer means by "it wanders": a startled noob freezes, a curious one roams
--      further than a tired one, nobody leaves its leash, and the same seed walks the same path twice.
--
-- Run from the repo root. PARENA_DIR overrides where the vectors are read from.

package.path = "./src/?.lua;" .. package.path

local Wander = require("wander")

local fails = 0
local function check(cond, msg)
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

local function parityPath()
    local dir = os.getenv("PARENA_DIR")
    if dir and #dir > 0 then return dir .. "/stdlib/noobtopia/walk_parity.txt" end
    return "../PARENA/stdlib/noobtopia/walk_parity.txt"
end

-- ---- 1. parity vectors ---------------------------------------------------------------------------------------
-- Format, one row per line, '#' comments: mood since seed idle shouldChoose heading legLen speedPermille tdx tdy
local path = parityPath()
local fh = io.open(path, "r")
if not fh then
    print("walk_test: cannot open " .. path .. " (set PARENA_DIR to the PARENA checkout)")
    os.exit(1)
end

local rows = 0
for line in fh:lines() do
    local body = line:gsub("#.*$", "")
    local mood, since, seed, idle, choose, heading, legLen, speed, tdx, tdy =
        body:match("^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*$")
    if mood then
        rows = rows + 1
        mood, since, seed, idle, choose = tonumber(mood), tonumber(since), tonumber(seed), tonumber(idle), tonumber(choose)
        heading, legLen, speed = tonumber(heading), tonumber(legLen), tonumber(speed)
        tdx, tdy = tonumber(tdx), tonumber(tdy)
        local tag = "row " .. rows .. " (mood " .. mood .. ", since " .. since .. ", seed " .. seed .. ")"
        check(Wander.idleTicks(mood, seed) == idle, tag .. " idleTicks " .. Wander.idleTicks(mood, seed) .. " ~= " .. idle)
        check(Wander.shouldChoose(mood, since, seed) == choose, tag .. " shouldChoose " .. Wander.shouldChoose(mood, since, seed) .. " ~= " .. choose)
        check(Wander.heading(seed) == heading, tag .. " heading " .. Wander.heading(seed) .. " ~= " .. heading)
        check(Wander.legLength(mood) == legLen, tag .. " legLength " .. Wander.legLength(mood) .. " ~= " .. legLen)
        check(Wander.moodSpeedPermille(mood) == speed, tag .. " speedPermille " .. Wander.moodSpeedPermille(mood) .. " ~= " .. speed)
        check(Wander.headingDx(heading) == tdx and Wander.headingDy(heading) == tdy,
            tag .. " unit vector " .. Wander.headingDx(heading) .. "," .. Wander.headingDy(heading) .. " ~= " .. tdx .. "," .. tdy)
    end
end
fh:close()
check(rows >= 12, "read at least 12 parity vectors, got " .. rows)

-- ---- 2. the compass -------------------------------------------------------------------------------------------
for seed = 0, 500 do
    local h = Wander.heading(seed)
    check(h >= 0 and h < Wander.headingCount(), "heading in range for seed " .. seed)
end
check(Wander.heading(-1) == 0, "negative seed is heading 0")
check(Wander.headingCount() == 8, "8 headings")

local seenHeading = {}
for seed = 0, 500 do seenHeading[Wander.heading(seed)] = true end
local distinct = 0
for _ in pairs(seenHeading) do distinct = distinct + 1 end
check(distinct == 8, "all 8 headings reachable, got " .. distinct)

for h = 0, Wander.headingCount() - 1 do
    local dx, dy = Wander.headingDx(h), Wander.headingDy(h)
    check(dx >= -1 and dx <= 1 and dy >= -1 and dy <= 1, "unit vector for heading " .. h)
    check(not (dx == 0 and dy == 0), "heading " .. h .. " actually points somewhere")
end

-- ---- 3. the moods a designer would notice ----------------------------------------------------------------------
check(Wander.moodSpeedPermille(Wander.STARTLED) == 0, "a startled noob is frozen, not merely slow")
check(Wander.idleTicks(Wander.STARTLED, 1234) > Wander.idleTicks(Wander.IDLE, 1234), "startled stands longer than idle")
check(Wander.idleTicks(Wander.CURIOUS, 1234) < Wander.idleTicks(Wander.IDLE, 1234), "curious pauses less than idle")
check(Wander.legLength(Wander.CURIOUS) > Wander.legLength(Wander.IDLE), "curious roams further than idle")
check(Wander.legLength(Wander.TIRED) < Wander.legLength(Wander.IDLE), "tired shuffles less than idle")
check(Wander.shouldChoose(0, -5, 5) == 0, "a negative clock never chooses")
check(Wander.shouldChoose(0, Wander.idleTicks(0, 5), 5) == 1, "exactly at the idle is allowed")

-- ---- 4. the leash ----------------------------------------------------------------------------------------------
check(Wander.withinLeash(0, 0, 0) == 1, "standing still is inside any leash")
check(Wander.withinLeash(3, 4, 5) == 1, "3-4-5 is exactly on a leash of 5")
check(Wander.withinLeash(4, 4, 20) == 1, "a long leash holds a diagonal")
check(Wander.withinLeash(21, 0, 20) == 0, "past the leash is outside")
check(Wander.withinLeash(-1, -1, -1) == 0, "a negative leash holds nothing")

-- ---- 5. wandering: it terminates, it stays home, and it is repeatable -----------------------------------------
local function runOne(mood, seed, leash, ticks)
    local a = Wander.new(0, 0, mood, seed, leash)
    local furthest = 0
    local legs = 0
    local wasWalking = false
    for _ = 1, ticks do
        Wander.tick(a)
        furthest = math.max(furthest, math.max(math.abs(a.x), math.abs(a.y)))
        check(Wander.withinLeash(a.x, a.y, leash) == 1, "mood " .. mood .. " seed " .. seed .. " left its leash at " .. a.x .. "," .. a.y)
        local walking = Wander.isWalking(a)
        if walking and not wasWalking then legs = legs + 1 end
        wasWalking = walking
    end
    return furthest, legs, a
end

for _, mood in ipairs({ Wander.IDLE, Wander.CURIOUS, Wander.BORED, Wander.TIRED }) do
    local furthest, legs = runOne(mood, 4242, 40, 3000)
    check(legs >= 2, "mood " .. mood .. " took at least 2 legs in 3000 ticks, got " .. legs)
    check(furthest > 0, "mood " .. mood .. " actually moved")
end

-- a startled noob never takes a step, over a long run, even though it keeps choosing legs: the state both worlds
-- share, and the reason tick() returns "stepped" rather than "is walking"
do
    local a = Wander.new(0, 0, Wander.STARTLED, 99, 40)
    local steppedAny = false
    local choseAny = false
    for _ = 1, 5000 do
        if Wander.tick(a) then steppedAny = true end
        if Wander.isWalking(a) then choseAny = true end
        check(a.x == 0 and a.y == 0, "a startled noob drifted to " .. a.x .. "," .. a.y)
    end
    check(not steppedAny, "a startled noob never takes a step")
    check(choseAny, "a startled noob still chooses legs, it just cannot walk them")
end

-- a tired noob covers less ground than a curious one over the same window (400 vs 1100 permille)
do
    local _, _, tired = runOne(Wander.TIRED, 777, 40, 600)
    local _, _, curious = runOne(Wander.CURIOUS, 777, 40, 600)
    local tiredSteps = math.abs(tired.x) + math.abs(tired.y)
    local curiousSteps = math.abs(curious.x) + math.abs(curious.y)
    check(curiousSteps > tiredSteps, "curious out-walks tired (" .. curiousSteps .. " vs " .. tiredSteps .. ")")
end

-- same seed, same path: two agents run side by side never diverge
do
    local a = Wander.new(0, 0, Wander.IDLE, 2026, 40)
    local b = Wander.new(0, 0, Wander.IDLE, 2026, 40)
    for i = 1, 2000 do
        Wander.tick(a)
        Wander.tick(b)
        if a.x ~= b.x or a.y ~= b.y then
            check(false, "same seed diverged at tick " .. i)
            break
        end
    end
end

-- a leash shorter than the leg means it never moves -- declared, not a silent hang
do
    local a = Wander.new(0, 0, Wander.IDLE, 5, 1)
    local steppedAny = false
    for _ = 1, 200 do
        if Wander.tick(a) then steppedAny = true end
    end
    check(not steppedAny, "a leash of 1 with a leg of 14 keeps the noob home")
end

if fails > 0 then
    print("walk_test: " .. fails .. " FAILED")
    os.exit(1)
end
print("walk_test OK (" .. rows .. " parity vectors, " .. Wander.headingCount() .. " headings)")
