-- tests/ambient_test.lua -- plain Lua, no Roblox required:  lua tests/ambient_test.lua
--
-- These pin the SAME properties the C side pins in SHANKPIT (make test-ambient-life). If the two ever disagree, this
-- file is the one that is wrong, because PARENA/stdlib/noobtopia/ambient_life.prn is the source of truth.

package.path = "./src/?.lua;" .. package.path

local Ambient = require("ambient")
local Witness = require("big_o_witness")

local fails = 0
local function check(cond, msg)
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

-- data/noob_lines.lua returns a table, so it can be required directly.
local lines = require("data.noob_lines")

-- 1. the data parses, and every category has at least one line (a category with none would silence NPCs)
local byCat = Ambient.group(lines)
check(#lines >= 20, "at least the original 20 lines survive")
for cat = 0, Ambient.categoryCount() - 1 do
    check(#byCat[cat] > 0, "category " .. cat .. " has at least one line")
end

-- 2. picks are always in range, including edges
for _, n in ipairs({ 1, 2, 5, 7, 32 }) do
    for seed = 0, 200 do
        local i = Ambient.pick(n, seed)
        check(i >= 0 and i < n, "pick(" .. n .. "," .. seed .. ") in range, got " .. tostring(i))
    end
end
check(Ambient.pick(0, 99) == 0, "pick from an empty bucket is 0")
check(Ambient.pick(5, -1) == 0, "negative seed is 0")

-- 3. mood -> category mapping is total and stable
check(Ambient.categoryForMood(3) == Ambient.COMPLAINT, "tired complains")
check(Ambient.categoryForMood(4) == Ambient.SELF, "startled talks to itself")
check(Ambient.categoryForMood(1) == Ambient.QUESTION, "curious asks")
check(Ambient.categoryForMood(0) == Ambient.GREETING, "idle greets")
check(Ambient.categoryForMood(99) == Ambient.GREETING, "unknown mood is total")

-- 4. cooldowns live in the documented range, and tired noobs are quieter than idle ones on the same seed
for _, mood in ipairs({ 0, 2, 3, 4 }) do
    for seed = 0, 100 do
        local ms = Ambient.cooldownMs(mood, seed)
        check(ms >= 3000 and ms <= 22000, "cooldown in 3-22s, got " .. ms)
    end
end
check(Ambient.cooldownMs(3, 1234) > Ambient.cooldownMs(0, 1234), "tired waits longer than idle")

-- 5. shouldSpeak is exactly the cooldown comparison
check(Ambient.shouldSpeak(0, 0, 5) == 0, "not immediately")
check(Ambient.shouldSpeak(0, Ambient.cooldownMs(0, 5), 5) == 1, "exactly at the cooldown is allowed")
check(Ambient.shouldSpeak(0, 999999, 5) == 1, "long quiet speaks")
check(Ambient.shouldSpeak(0, -5, 5) == 0, "a negative clock never speaks")

-- 6. determinism: same seed -> same line, and two different seeds eventually differ
local text1 = Ambient.speak(byCat, 0, 99999, 42)
local text2 = Ambient.speak(byCat, 0, 99999, 42)
check(text1 == text2, "same seed, same line")
local seen = {}
local seed = 7
for _ = 1, 200 do
    local line
    line, seed = Ambient.speak(byCat, 0, 99999, seed)
    seen[line] = true
end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
check(distinct >= 3, "200 draws hit at least 3 distinct lines, got " .. distinct)

-- 7. a silent NPC says nothing at all (nil), rather than repeating itself early
local quiet = Ambient.speak(byCat, 0, 0, 42)
check(quiet == nil, "below the cooldown returns nil")

-- 8. the port covers every mood the C side covers, with a line that exists
for mood = 0, 7 do
    local line = Ambient.speak(byCat, mood, 999999, 1234)
    check(type(line) == "string" and #line > 0, "mood " .. mood .. " produces a line")
end

-- 9. BIG_O's witness rule: 1 witness = denial, 5 = silencing, compromise is one-way and helps
local one = { { state = Witness.DENIAL } }
local four = { { state = Witness.DENIAL }, { state = Witness.DENIAL }, { state = Witness.DENIAL }, { state = Witness.DENIAL } }
local five = { { state = Witness.DENIAL }, { state = Witness.DENIAL }, { state = Witness.DENIAL }, { state = Witness.DENIAL }, { state = Witness.DENIAL } }
check(Witness.resolve(one) == Witness.DENIAL, "one witness denies")
check(Witness.resolve(four) == Witness.DENIAL, "four witnesses still deny")
check(Witness.resolve(five) == Witness.SILENCING, "five witnesses silence")
check(Witness.resolve({}) == Witness.UNAWARE, "nothing seen, nothing real")
check(Witness.compromise(one[1]) == true, "a denying witness can be compromised")
check(one[1].state == Witness.COMPROMISED, "compromised witness becomes an asset")
check(Witness.helpsCoverUp(one) == true, "an asset helps cover it up")
check(Witness.compromise(one[1]) == false, "compromise is not repeatable")
check(Witness.resolve(five) == Witness.SILENCING, "a crowd past the threshold cannot be bought back")

-- 10. the seed mixer is the C host's own, digit for digit -- every value below is also asserted by SHANKPIT's
-- ambient_life_test.c (make test-ambient-life). MINSTD, not the 1103515245 generator this repo used to carry: that
-- one loses its low bits in a 53-bit double, and the near-2^31 row is the seed that proved it.
check(Ambient.nextSeed(0) == 0, "mixer(0)")
check(Ambient.nextSeed(42) == 2027382, "mixer(42)")
check(Ambient.nextSeed(999999) == 1026311495, "mixer(999999)")
check(Ambient.nextSeed(2147483646) == 2147435376, "mixer near 2^31 -- the seed that used to diverge")
check(Ambient.nextSeed(-1) == 0, "negative seed clamps to 0")

if fails > 0 then
    print("ambient_test: " .. fails .. " FAILED")
    os.exit(1)
end
print("ambient_test OK (" .. #lines .. " lines, " .. Ambient.categoryCount() .. " categories)")
