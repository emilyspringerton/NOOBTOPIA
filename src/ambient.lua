-- src/ambient.lua -- ambient life, the NOOBTOPIA half of the three-way merge.
--
-- This file used to be a hand-copy of the rules. It is not any more: the DECISIONS come from PARENA
-- (stdlib/noobtopia/ambient_life.prn), emitted to src/generated/ambient_life.lua by scripts/gen_rules.sh, and
-- SHANKPIT compiles the SAME .prn to C. So a cooldown or a category mapping is edited in exactly one place.
--
-- What stays here is the part that is NOOBTOPIA's own: grouping the data by category and turning a decision into a
-- line of text. Deliberately headless (no `game`, no `Instance`, no `wait`), so tests/ambient_test.lua can run it.
--
-- Categories: 0 GREETING  1 QUESTION  2 BANTER  3 COMPLAINT  4 SELF

local Rules = require("generated.ambient_life")

local Ambient = {}

Ambient.GREETING, Ambient.QUESTION, Ambient.BANTER, Ambient.COMPLAINT, Ambient.SELF = 0, 1, 2, 3, 4
Ambient.IDLE, Ambient.CURIOUS, Ambient.BORED, Ambient.TIRED, Ambient.STARTLED = 0, 1, 2, 3, 4

-- Straight through to PARENA's own names, so there is one answer per question and it is not restated here.
Ambient.categoryCount = Rules.ambientCategoryCount
Ambient.categoryForMood = Rules.ambientCategoryForMood
Ambient.pick = Rules.ambientPick
Ambient.cooldownMs = Rules.ambientCooldownMs
Ambient.shouldSpeak = Rules.ambientShouldSpeak

-- The same deterministic mixer SHANKPIT uses (packages/simulation/ambient_life.h), so a seed means the same thing
-- in both worlds. NOT math.random: a test has to be able to pin the exact line a seed produces.
function Ambient.nextSeed(seed)
    return (seed * 1103515245 + 12345) % 2147483648
end

-- Lines grouped by category. `data` is data/noob_lines.lua (a list of {cat = N, text = "..."}).
function Ambient.group(data)
    local byCat = {}
    for i = 1, Ambient.categoryCount() do byCat[i - 1] = {} end
    for _, line in ipairs(data) do
        local bucket = byCat[line.cat]
        if bucket then table.insert(bucket, line.text) end
    end
    return byCat
end

function Ambient.countIn(byCat, cat)
    local bucket = byCat[cat]
    return bucket and #bucket or 0
end

-- What should this NPC say, given its mood and how long it has been quiet?
-- Returns text, newSeed -- or nil, seed when it stays quiet (below its cooldown).
-- Falls back to GREETING when its own category has no lines, rather than going silent forever.
function Ambient.speak(byCat, mood, sinceMs, seed)
    if Ambient.shouldSpeak(mood, sinceMs, seed) ~= 1 then return nil, seed end
    local bucket = byCat[Ambient.categoryForMood(mood)]
    if not bucket or #bucket == 0 then bucket = byCat[Ambient.GREETING] end
    if not bucket or #bucket == 0 then return nil, seed end
    seed = Ambient.nextSeed(seed)
    return bucket[Ambient.pick(#bucket, seed) + 1], seed
end

return Ambient
