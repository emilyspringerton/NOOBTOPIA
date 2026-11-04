-- src/cozy.lua -- kicking a dandelion and hugging a tree, the NOOBTOPIA half.
--
-- The decisions are PARENA's (`stdlib/shankpit/cozy_rules.prn`, emitted to `src/generated/cozy_rules.lua` here
-- and to C in SHANKPIT): when a verb is allowed, what it gives, how fast the comfort drains. This file is the
-- host's own layer -- it holds the two cooldown timestamps, the day's hug count and the noob's comfort, and asks
-- the rules everything else. Same split as `sky.lua` and `wiring.lua`: no `game`, no instance, plain Lua, so
-- tests/cozy_test.lua exercises every branch.
--
-- Nothing in here can hurt anything. A cosy verb must never be a weapon with a nicer name, so there is no damage,
-- no knockback and no score, and comfort is capped at 1000.
--
-- Moods are the same integers MISHRI simulates: 0 IDLE, 1 CURIOUS, 2 BORED, 3 TIRED, 4 STARTLED.
-- Comfort is permille 0..1000. Timestamps are milliseconds from the caller's clock, never this module's.

local Rules = require("generated.cozy_rules")

local Cozy = {}

Cozy.IDLE, Cozy.CURIOUS, Cozy.BORED, Cozy.TIRED, Cozy.STARTLED = 0, 1, 2, 3, 4

-- Straight through to PARENA's own names: one answer per question, restated nowhere.
Cozy.kickAllowed = Rules.cozyKickAllowed
Cozy.kickPuffs = Rules.cozyKickPuffs
Cozy.hugAllowed = Rules.cozyHugAllowed
Cozy.hugDiminish = Rules.cozyHugDiminish
Cozy.comfortTarget = Rules.cozyComfortTarget
Cozy.comfortDrift = Rules.cozyComfortDrift
Cozy.lineIndex = Rules.cozyLineIndex
Cozy.flavorDaylight = Rules.cozyFlavorDaylight
Cozy.trunkHuggableMilli = Rules.cozyTrunkHuggableMilli
Cozy.daylightMilli = Rules.cozyDaylightMilli

-- The handful of scalars a host or a UI wants without calling a function.
Cozy.KICK_COOLDOWN_MS = Rules.cozyKickCooldownMs()
Cozy.KICK_LIFT_MILLI = Rules.cozyKickLiftMilli()
Cozy.HUG_COOLDOWN_MS = Rules.cozyHugCooldownMs()
Cozy.HUG_COMFORT_MILLI = Rules.cozyHugComfortMilli()
Cozy.LINE_COUNT = Rules.cozyLineCount()

local function int(v, default)
    local n = tonumber(v)
    if n == nil then return default end
    return math.floor(n)
end

local function clamp(lo, hi, v)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- A noob who has not been comforted yet is exactly as comfortable as its mood wants.
function Cozy.new(mood, seed)
    local m = int(mood, Cozy.IDLE)
    return {
        mood = m,
        comfort = Cozy.comfortTarget(m),
        seed = math.max(0, int(seed, 0)),
        kicks = 0,
        hugs_today = 0,
        last_kick_ms = 0,
        last_hug_ms = 0,
        started = false,
    }
end

-- Cooldown arithmetic lives here, once, so the two verbs cannot disagree about the sign. A timestamp of 0 means
-- "never", which is not the same as "just now": without `started`, the FIRST hug is refused for the length of a
-- cooldown measured from time zero. That was a real bug here, caught by tests/cozy_test.lua.
local function cooldownLeft(now_ms, last_ms, ready, started)
    if not started or not ready then return 0 end
    local elapsed = now_ms - last_ms
    if elapsed >= ready then return 0 end
    return ready - elapsed
end

-- Kick a dandelion. Returns how many seeds came off (3..6), or 0 when the world said no: night, not a dandelion,
-- or still on cooldown. The seeds are deterministic in the noob's own seed, so the same noob gets the same puff.
function Cozy.kick(state, is_dandelion, now_ms, sun_permille)
    local left = cooldownLeft(int(now_ms, 0), state.last_kick_ms, Cozy.KICK_COOLDOWN_MS, state.started)
    if Cozy.kickAllowed(int(is_dandelion, 0), left, int(sun_permille, 0)) ~= 1 then return 0 end
    local puffs = Cozy.kickPuffs(state.seed)
    state.comfort = clamp(0, 1000, state.comfort + Cozy.KICK_LIFT_MILLI)
    state.seed = state.seed + 1
    state.kicks = state.kicks + 1
    state.last_kick_ms = int(now_ms, 0)
    state.started = true
    return puffs
end

-- Hug a tree. Returns the comfort actually gained, or 0 when refused (a trunk too thin to reach around, or still
-- on cooldown). Worth less each time in one day, so the fifth hug of the afternoon is a quieter thing.
function Cozy.hug(state, trunk_milli, now_ms)
    local left = cooldownLeft(int(now_ms, 0), state.last_hug_ms, Cozy.HUG_COOLDOWN_MS, state.started)
    if Cozy.hugAllowed(int(trunk_milli, 0), left) ~= 1 then return 0 end
    local gain = math.floor((Cozy.HUG_COMFORT_MILLI * Cozy.hugDiminish(state.hugs_today)) / 1000)
    state.comfort = clamp(0, 1000, state.comfort + gain)
    state.hugs_today = state.hugs_today + 1
    state.last_hug_ms = int(now_ms, 0)
    state.started = true
    return gain
end

-- Morning: a tree does not hold a grudge.
function Cozy.newDay(state)
    state.hugs_today = 0
end

-- Comfort drifts toward what the mood wants, one permille per tick, never overshooting.
function Cozy.tick(state, ticks)
    state.comfort = Cozy.comfortDrift(state.comfort, Cozy.comfortTarget(state.mood), int(ticks, 0))
    return state.comfort
end

-- Which of the world's small replies this moment gets (the host owns the words).
function Cozy.line(state)
    return Cozy.lineIndex(Cozy.LINE_COUNT, state.seed)
end

return Cozy
