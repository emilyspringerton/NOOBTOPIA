-- src/wander.lua -- where a noob drifts, and when. The NOOBTOPIA half of the movement slice.
--
-- Same split as src/ambient.lua: the DECISIONS are not here. They live in PARENA
-- (stdlib/noobtopia/walk_rules.prn), emitted to src/generated/walk_rules.lua by scripts/gen_rules.sh, and SHANKPIT
-- compiles the SAME .prn to packages/simulation/walk_rules.c. So "how long does a bored noob stand still before it
-- wanders, and how far does it go" is edited in exactly one place.
--
-- What stays here is the part that is NOOBTOPIA's own: holding a position and integrating it. The integration is the
-- SAME integer algorithm SHANKPIT's walk_rules.h runs (whole units, permille credit), on purpose -- a seeded noob
-- walks the same path in Roblox as it does in the C build, and tests/walk_test.lua pins that against the shared
-- parity vectors. Deliberately headless: no `game`, no `Instance`, no `wait`, no Vector3.
--
-- Headings are a compass, clockwise from +X:  0 E  1 NE  2 N  3 NW  4 W  5 SW  6 S  7 SE
-- Moods are MISHRI's 8-state enum:           0 IDLE 1 CURIOUS 2 BORED 3 TIRED 4 STARTLED

local Rules = require("generated.walk_rules")

local Wander = {}

-- Straight through to PARENA's own names, so there is one answer per question and it is not restated here.
Wander.headingCount = Rules.walkHeadingCount
Wander.mod = Rules.walkMod
Wander.jitter = Rules.walkJitter
Wander.idleTicks = Rules.walkIdleTicks
Wander.shouldChoose = Rules.walkShouldChoose
Wander.legLength = Rules.walkLegLength
Wander.heading = Rules.walkHeading
Wander.headingDx = Rules.walkHeadingDx
Wander.headingDy = Rules.walkHeadingDy
Wander.targetDx = Rules.walkTargetDx
Wander.targetDy = Rules.walkTargetDy
Wander.moodSpeedPermille = Rules.walkMoodSpeedPermille
Wander.withinLeash = Rules.walkWithinLeash

Wander.IDLE, Wander.CURIOUS, Wander.BORED, Wander.TIRED, Wander.STARTLED = 0, 1, 2, 3, 4

-- The seed mixer SHANKPIT's walk_rules.h uses, digit for digit. MINSTD (48271 mod 2^31-1), not the 1103515245
-- mixer src/ambient.lua uses: `seed * 1103515245` needs ~61 bits and a Lua number holds 53 exactly, so the two
-- worlds would disagree on the low bits and take different paths for the same seed. This one peaks near 1e14.
function Wander.nextSeed(seed)
    if seed < 0 then seed = 0 end
    return (seed * 48271) % 2147483647
end

-- A noob's wander state. Positions are whole world units (the host scales them to studs), never floats.
function Wander.new(homeX, homeY, mood, seed, leash)
    return {
        x = homeX, y = homeY,
        homeX = homeX, homeY = homeY,
        targetX = homeX, targetY = homeY,
        dx = 0, dy = 0,
        leg = 0,
        sinceChoice = 0,
        credit = 0,
        mood = mood,
        seed = seed,
        leash = leash,
        walking = false,
    }
end

-- The current position, so a host does not have to remember whether the agent is mid-leg.
function Wander.position(a)
    return a.x, a.y
end

-- Pick a target whose whole leg stays inside the leash, or stand still if none of the 8 do.
function Wander.choose(a)
    local leg = Wander.legLength(a.mood)
    for attempt = 0, Wander.headingCount() - 1 do
        local h = Wander.heading(a.seed + attempt * 7)
        local tx = Wander.targetDx(h, leg)
        local ty = Wander.targetDy(h, leg)
        if Wander.withinLeash(a.x + tx - a.homeX, a.y + ty - a.homeY, a.leash) == 1 then
            a.walking = true
            a.dx = Wander.headingDx(h)
            a.dy = Wander.headingDy(h)
            a.leg = leg
            a.targetX = a.x + tx
            a.targetY = a.y + ty
            a.sinceChoice = 0
            a.seed = Wander.nextSeed(a.seed)
            return true
        end
    end
    return false
end

-- Is a leg in progress? Distinct from "did it move this tick": a STARTLED noob is committed to a walk it never takes.
function Wander.isWalking(a)
    return a.walking
end

-- One tick. Returns stepped, x, y -- stepped is true only when a whole unit was actually walked THIS tick, which is
-- what a host should draw and what the tests pin. `Wander.isWalking(a)` is the leg-in-progress flag.
function Wander.tick(a)
    a.sinceChoice = a.sinceChoice + 1
    if not a.walking and Wander.shouldChoose(a.mood, a.sinceChoice, a.seed) == 1 then
        Wander.choose(a)
    end
    if not a.walking then return false, a.x, a.y end

    -- Whole units only, from the permille credit: a STARTLED noob (0 permille) never spends a credit and so never
    -- moves; a TIRED one (400) moves twice every five ticks; nobody ever moves half a unit.
    a.credit = a.credit + Wander.moodSpeedPermille(a.mood)
    local stepped = false
    while a.credit >= 1000 and a.walking do
        a.credit = a.credit - 1000
        a.x = a.x + a.dx
        a.y = a.y + a.dy
        stepped = true
        if a.x == a.targetX and a.y == a.targetY then a.walking = false end
    end
    return stepped, a.x, a.y
end

return Wander
