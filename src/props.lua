-- src/props.lua -- WHAT stands in the street, and what pressing on it does.
--
-- `src/cozy.lua` knows the two verbs and nothing about the world; `src/noobtopia.lua` knows the world and cannot be
-- run on this box. This module is the missing middle, and it is plain Lua so `tests/props_test.lua` can execute it:
-- the list of props, how a prop's geometry turns into the number the rules ask for, and the decision a prompt press
-- produces -- including WHY a press was refused, which is the difference between a cosy world and one where nothing
-- happens and the player learns not to try.
--
-- Two things deliberately live here rather than in PARENA:
--
--   * THE REFERENCE TRUNK. `cozy_rules.prn` speaks in permille of a reference trunk, because a rule about girth
--     should not know about studs. Six studs is what reads as "a grown tree" in this place; change the constant and
--     every tree in the street is re-measured. The threshold itself (400 permille) is still the .prn's.
--   * THE WORDS. Same split as `cozy.lua`'s `line()`: the rules pick an index, the host owns the sentence.
--
-- Nothing in here can hurt anything, and nothing in here is allowed to change comfort on a refusal.

local Cozy = require("cozy")

local Props = {}

-- The trunk girth that measures as 1000 permille. A presentation decision, so it is here, once, named.
Props.TRUNK_FULL_STUDS = 6

-- Geometry -> the rules' own units. Negative or absent girth measures as nothing, never as a tree.
function Props.trunkMilli(studs)
    local s = tonumber(studs) or 0
    if s <= 0 then return 0 end
    return math.floor((s * 1000) / Props.TRUNK_FULL_STUDS)
end

-- What a kind of prop offers a press. The verb words and the reach are the host's business; the kind is not.
Props.KINDS = {
    dandelion = { action = "Kick", object = "Dandelion", radius = 8 },
    tree = { action = "Hug", object = "Tree", radius = 10 },
}

-- THE STREET. Deterministic, because a test that reads it should get the same street twice, and because a world
-- whose props move between runs cannot be reasoned about. Placed outside the ice rink (|x| < 60, |z| < 60) so a cosy
-- verb is not performed on skates.
--
-- `tree-sapling` is deliberate. `cozy_rules.prn` refuses a trunk under 400 permille, and a world that contained only
-- huggable trees would hide a rule that exists -- a small tree you cannot reach around is the refusal, shown.
local STREET = {
    { id = "dandelion-a", kind = "dandelion", x = 70, z = 6 },
    { id = "dandelion-b", kind = "dandelion", x = 84, z = -22 },
    { id = "dandelion-c", kind = "dandelion", x = 66, z = -46 },
    { id = "tree-oak", kind = "tree", x = 78, z = 26, trunk_studs = 7 },
    { id = "tree-elm", kind = "tree", x = 104, z = 8, trunk_studs = 5 },
    { id = "tree-sapling", kind = "tree", x = 68, z = 48, trunk_studs = 1.5 },
}

local function copy(spec)
    local out = {}
    for key, value in pairs(spec) do out[key] = value end
    return out
end

-- The street, as copies: a caller may move a prop without rewriting the world for everybody else.
function Props.default()
    local out = {}
    for i, spec in ipairs(STREET) do out[i] = copy(spec) end
    return out
end

-- Everything a host or a test needs about one prop, in the rules' vocabulary. An unknown kind still describes
-- itself honestly (`kind` is whatever was written) so the caller can report it rather than crash on it.
function Props.describe(spec)
    local s = type(spec) == "table" and spec or {}
    local kind = s.kind
    local meta = Props.KINDS[kind]
    local trunk = (kind == "tree") and Props.trunkMilli(s.trunk_studs) or 0
    return {
        id = s.id or "?",
        kind = kind,
        x = tonumber(s.x) or 0,
        z = tonumber(s.z) or 0,
        trunk_studs = tonumber(s.trunk_studs) or 0,
        trunk_milli = trunk,
        is_dandelion = (kind == "dandelion") and 1 or 0,
        action = meta and meta.action or nil,
        object = meta and meta.object or nil,
        radius = meta and meta.radius or 0,
        known = meta ~= nil,
    }
end

-- A press on a prop, decided. `state` is a `Cozy.new` state (the noob or the player it belongs to), `now_ms` the
-- caller's clock and `sun_permille` the sky's own reading -- all three are the host's to supply, because none of
-- them is a rule.
--
-- Returns { verb, ok, amount, comfort, reason, wait_ms }. `reason` is nil when the verb happened, and otherwise one
-- of the words below: the host says it out loud instead of leaving a press unexplained.
function Props.interact(spec, state, now_ms, sun_permille)
    if type(spec) ~= "table" or state == nil then
        return { verb = "none", ok = false, reason = "unknown", comfort = state and state.comfort }
    end
    local d = Props.describe(spec)
    local sun = math.floor(tonumber(sun_permille) or 0)

    if d.kind == "dandelion" then
        local left = Cozy.kickCooldownLeft(state, now_ms)
        if Cozy.kickAllowed(1, left, sun) ~= 1 then
            -- NIGHT BEFORE COOLDOWN. At night the flower is shut for hours; telling the player "not again just yet"
            -- would send them straight back to it. A closed dandelion is the durable reason, so it is the one said
            -- -- the opposite order was a real bug here, caught by tests/props_test.lua.
            local closed = sun < Cozy.daylightMilli()
            return {
                verb = "kick", ok = false, comfort = state.comfort, wait_ms = left,
                reason = closed and "closed" or "wait",
            }
        end
        local puffs = Cozy.kick(state, 1, now_ms, sun)
        return {
            verb = "kick", ok = puffs > 0, amount = puffs, comfort = state.comfort,
            wait_ms = Cozy.KICK_COOLDOWN_MS,
        }
    end

    if d.kind == "tree" then
        local left = Cozy.hugCooldownLeft(state, now_ms)
        if Cozy.hugAllowed(d.trunk_milli, left) ~= 1 then
            -- girth before cooldown: a sapling is not on cooldown, it is a sapling, and saying "wait" would lie
            local thin = d.trunk_milli < Cozy.trunkHuggableMilli()
            return {
                verb = "hug", ok = false, comfort = state.comfort, wait_ms = left,
                reason = thin and "thin" or "wait",
            }
        end
        local gain = Cozy.hug(state, d.trunk_milli, now_ms)
        return {
            verb = "hug", ok = gain > 0, amount = gain, comfort = state.comfort,
            wait_ms = Cozy.HUG_COOLDOWN_MS,
        }
    end

    return { verb = "none", ok = false, reason = "unknown", comfort = state.comfort }
end

-- The explanations. Short, and none of them pretends a refusal was a small success.
Props.WORDS = {
    closed = "The dandelion has closed for the night.",
    wait = "Not again just yet.",
    thin = "Too thin to reach around.",
    unknown = "There is nothing here to do that to.",
}

-- What a player reads after a press. Returns nil when there is nothing honest to say.
function Props.reply(result)
    if type(result) ~= "table" then return nil end
    if not result.ok then return Props.WORDS[result.reason] end
    local comfort = tostring(result.comfort)
    if result.verb == "kick" then
        return "Kicked the dandelion: " .. tostring(result.amount) .. " seeds. Comfort " .. comfort .. "/1000."
    end
    if result.verb == "hug" then
        return "Hugged the tree: +" .. tostring(result.amount) .. ". Comfort " .. comfort .. "/1000."
    end
    return nil
end

return Props
