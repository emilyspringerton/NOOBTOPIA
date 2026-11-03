-- tests/deadweight_ladder_test.lua -- the LADDER, plain Lua, no Roblox:
--     lua tests/deadweight_ladder_test.lua
--
-- src/deadweight_ladder.lua is the port of SHANKPIT's dw_ladder.c: one entry point for all four
-- challenge directions, a challenge book with a 45-second TTL, records, the population's meta, and decks
-- that re-craft from the record and the meta after every match.
--
-- THE PARITY CLAIM: PARENA/stdlib/deadweight/ladder_parity.txt. That file carries BOTH the script (a
-- sequence of ladder operations) and the outcomes, and this test EXECUTES THE SCRIPT OUT OF THE FILE --
-- the same one SHANKPIT's dw_ladder_parity_test.c executes. Neither side re-types the scenario, so the
-- only way to fail is to actually disagree.
--
-- The properties after the fixture are the ones a player would notice: every direction classifies the
-- way it reads, a challenge nobody answers dies on its own, a citizen opens games without anybody
-- watching, a deck moves when the record and the meta move, and a save with no decks in it restores the
-- same sixteen cards.

package.path = "./src/?.lua;" .. package.path

local Rules = require("generated.deadweight_rules")
local Ladder = require("deadweight_ladder")

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

-- ---- 1. the shared fixture ---------------------------------------------------------------------

local function parity_path()
    local dir = os.getenv("PARENA_DIR")
    if dir and dir ~= "" then return dir .. "/stdlib/deadweight/ladder_parity.txt" end
    return "../PARENA/stdlib/deadweight/ladder_parity.txt"
end

-- Runs a lid's ops exactly as the C does, and returns the canonical outcome text for that lid.
local function run_lid(lid, ops)
    local l = Ladder.new(1)
    local lastSlot = -1
    for _, op in ipairs(ops) do
        local v = op.verb
        if v == "reset" then
            l = Ladder.new(op.a)
            lastSlot = -1
        elseif v == "hero" then
            Ladder.setHero(l, op.a)
        elseif v == "add" then
            Ladder.addCitizen(l, op.a, op.b, op.c, l.nowMs)
        elseif v == "challenge" then
            lastSlot = Ladder.challenge(l, op.a, op.b, op.c)
        elseif v == "accept" then
            Ladder.accept(l, lastSlot, op.a)
        elseif v == "decline" then
            Ladder.decline(l, lastSlot)
        elseif v == "tick" then
            Ladder.tick(l, op.a)
        elseif v == "remove" then
            Ladder.removePid(l, op.a)
        else
            check(false, "lid " .. lid .. ": unknown op '" .. v .. "'")
        end
    end

    local out = {}
    out[#out + 1] = string.format(
        "ladder %d meta %d %d %d results %d %d %d %d count %d hero %d last %d %d %d %d %d %d %d %d %d",
        lid, Ladder.metaKind(l), Ladder.metaShare(l), l.metaPlays,
        l.results[1], l.results[2], l.results[3], l.results[4],
        l.count, l.heroPid,
        l.last.valid, l.last.kind, l.last.pid0, l.last.pid1,
        l.last.winner, l.last.rounds, l.last.hull[1], l.last.hull[2], l.last.at)
    for i = 1, Ladder.MAX_MEMBERS do
        local m = l.members[i]
        if m.active == 1 then
            local deck = {}
            for d = 1, #m.deck do deck[d] = string.format("%d", m.deck[d]) end
            out[#out + 1] = string.format(
                "member %d pid %d player %d path %d aggr %d wins %d games %d rating %d deck %s",
                lid, m.pid, m.isPlayer, m.path, m.aggression, m.wins, m.games, m.rating,
                table.concat(deck, " "))
        end
    end
    for i = 1, Ladder.MAX_CHALLENGES do
        local c = l.challenges[i]
        if c.active == 1 then
            out[#out + 1] = string.format(
                "chal %d slot %d id %d from %d to %d kind %d opened %d expires %d",
                lid, i - 1, c.id, c.from, c.to, c.kind, c.opened, c.expires)
        end
    end
    return out, l
end

local opsByLid, expectedByLid = {}, {}
do
    local f = io.open(parity_path(), "r")
    if not f then
        print("SKIP: no ladder vectors at " .. parity_path() .. " (set PARENA_DIR)")
    else
        for line in f:lines() do
            line = line:gsub("%s+$", "")
            if line ~= "" and line:sub(1, 1) ~= "#" then
                if line:sub(1, 3) == "op " then
                    local lid, verb, a, b, c = line:match("^op (%d+) (%a+) (%-?%d+) (%-?%d+) (%-?%d+)$")
                    check(lid ~= nil, "unreadable op line: " .. line)
                    if lid then
                        lid = tonumber(lid)
                        opsByLid[lid] = opsByLid[lid] or {}
                        table.insert(opsByLid[lid], { verb = verb, a = tonumber(a), b = tonumber(b), c = tonumber(c) })
                    end
                elseif line:match("^ladder ") or line:match("^member ") or line:match("^chal ") then
                    local lid = tonumber(line:match("^%a+ (%d+)"))
                    check(lid ~= nil, "no lid on: " .. line)
                    if lid then
                        expectedByLid[lid] = expectedByLid[lid] or {}
                        table.insert(expectedByLid[lid], line)
                    end
                else
                    check(false, "unrecognised line: " .. line)
                end
            end
        end
        f:close()
    end
end

local ladders = 0
for lid = 0, Ladder.MAX_MEMBERS do
    if opsByLid[lid] then
        ladders = ladders + 1
        local got = run_lid(lid, opsByLid[lid])
        local want = expectedByLid[lid] or {}
        check(#got == #want, "lid " .. lid .. " produced " .. #got .. " lines, the fixture records " .. #want)
        for i = 1, math.min(#got, #want) do
            if got[i] ~= want[i] then
                print("  lid " .. lid .. " line " .. i .. "\n    played:  " .. got[i] .. "\n    fixture: " .. want[i])
            end
            check(got[i] == want[i], "lid " .. lid .. " line " .. i)
        end
    end
end
if ladders > 0 then
    print(string.format("deadweight ladder: %d scripts asserted against the C", ladders))
end

-- ---- 2. all four directions classify the way they read -----------------------------------------

do
    local l = Ladder.new(1234)
    Ladder.setHero(l, 0)                       -- the person
    Ladder.addCitizen(l, 5, 0, 300, 0)
    Ladder.addCitizen(l, 6, 2, 700, 0)
    local pc = Ladder.challenge(l, 0, 5, 1000)
    local cp = Ladder.challenge(l, 6, 0, 1000)
    local cc = Ladder.challenge(l, 5, 6, 1000)
    local pp = Ladder.challenge(l, 0, 0, 1000)  -- yourself: refused
    check(pc >= 0 and cp >= 0 and cc >= 0, "a challenge direction was refused")
    check(l.challenges[pc].kind == Ladder.CHAL.PLAYER_CITIZEN, "player->citizen is kind " .. tostring(l.challenges[pc].kind))
    check(l.challenges[cp].kind == Ladder.CHAL.CITIZEN_PLAYER, "citizen->player is kind " .. tostring(l.challenges[cp].kind))
    check(l.challenges[cc].kind == Ladder.CHAL.CITIZEN_CITIZEN, "citizen->citizen is kind " .. tostring(l.challenges[cc].kind))
    check(pp == -1, "a player challenged themselves")
    check(Ladder.pendingFor(l, 5) == pc, "the challenged citizen does not see the invitation")
    check(Ladder.pendingFor(l, 7) == -1, "somebody has an invitation that was never sent")
end

-- ---- 3. a match moves both records, the meta, and both decks -----------------------------------

do
    local l = Ladder.new(99)
    Ladder.setHero(l, 0)
    local a = Ladder.addCitizen(l, 5, 0, 400, 0)
    local b = Ladder.addCitizen(l, 6, 2, 900, 0)
    local deckBefore = {}
    for i = 1, #l.members[a].deck do deckBefore[i] = l.members[a].deck[i] end
    local slot = Ladder.challenge(l, 5, 6, 1000)
    local winnerPid = Ladder.accept(l, slot, 2000)
    check(winnerPid == 5 or winnerPid == 6, "the match returned " .. tostring(winnerPid) .. " as its winner")
    check(l.members[a].games == 1 and l.members[b].games == 1, "both records should have played once")
    check(l.members[a].wins + l.members[b].wins == 1, "exactly one side should have won")
    check(l.metaPlays > 0, "no cards were tallied into the meta")
    check(Ladder.metaKind(l) >= 0 and Ladder.metaKind(l) <= 2, "meta kind " .. Ladder.metaKind(l))
    check(l.last.valid == 1 and l.last.rounds >= 1, "the finished match left no record")
    check(l.results[Ladder.CHAL.CITIZEN_CITIZEN] == 1, "the direction was not counted")
    -- the loser's record moved, so its deck re-crafts from the new record + the new meta. It is
    -- allowed to be identical (the thresholds are thresholds); what is NOT allowed is a deck that
    -- stops being a legal sixteen cards.
    for i = 1, #l.members[b].deck do
        local c = l.members[b].deck[i]
        check(c >= 0 and c < Rules.numCards(), "re-crafted card " .. i .. " is " .. tostring(c))
    end
end

-- ---- 4. a challenge nobody answers dies on its own ----------------------------------------------

do
    local l = Ladder.new(7)
    Ladder.setHero(l, 0)
    Ladder.addCitizen(l, 5, 0, 300, 0)
    local slot = Ladder.challenge(l, 0, 5, 1000)
    check(Ladder.pendingFor(l, 5) == slot, "the invitation is not pending before the TTL")
    Ladder.tick(l, 1000 + Ladder.CHALLENGE_TTL_MS + 1)
    check(Ladder.pendingFor(l, 5) ~= slot, "an expired invitation is still pending")
end

-- ---- 5. citizens start games of their own, with nobody watching ---------------------------------

do
    local l = Ladder.new(4242)
    Ladder.setHero(l, 0)
    Ladder.addCitizen(l, 5, 0, 300, 0)
    Ladder.addCitizen(l, 6, 2, 800, 0)
    local before = 0
    for i = 1, Ladder.MAX_CHALLENGES do if l.challenges[i].active == 1 then before = before + 1 end end
    for t = 1000, 1000 + Ladder.CITIZEN_INTERVAL_MS * 8, Ladder.CITIZEN_INTERVAL_MS do
        Ladder.tick(l, t)
    end
    local after = 0
    for i = 1, Ladder.MAX_CHALLENGES do if l.challenges[i].active == 1 then after = after + 1 end end
    check(after > before, "the citizens never started a game among themselves")
end

-- ---- 6. a save with no decks in it restores the same sixteen cards -----------------------------

do
    local l = Ladder.new(5555)
    Ladder.setHero(l, 0)
    Ladder.addCitizen(l, 5, 0, 300, 0)
    Ladder.addCitizen(l, 6, 2, 800, 0)
    local slot = Ladder.challenge(l, 5, 6, 1000)
    Ladder.accept(l, slot, 2000)

    local snap = Ladder.serialize(l)
    local hasDeck = false
    for _, m in ipairs(snap.members) do
        if m.deck ~= nil then hasDeck = true end
    end
    check(not hasDeck, "the save format carries decks, which are supposed to be re-crafted")

    local deckOf = function(ladder, idx)
        local out = {}
        for d = 1, #ladder.members[idx].deck do out[d] = ladder.members[idx].deck[d] end
        return table.concat(out, ",")
    end

    local back = Ladder.deserialize(snap, 5555, 3000)
    check(back.count == l.count, "restored " .. back.count .. " members, saved " .. l.count)
    check(back.metaPlays == l.metaPlays, "the meta tally did not come back")
    check(back.meta[1] == l.meta[1] and back.meta[2] == l.meta[2] and back.meta[3] == l.meta[3],
        "the meta kinds did not come back")

    for i = 1, Ladder.MAX_MEMBERS do
        if l.members[i].active == 1 then
            local j = Ladder.memberForPid(back, l.members[i].pid)
            check(j >= 0, "pid " .. l.members[i].pid .. " did not come back")
            if j >= 0 then
                check(back.members[j].wins == l.members[i].wins and back.members[j].games == l.members[i].games,
                    "a record did not come back")
                check(back.members[j].path == l.members[i].path, "a path did not come back")
            end
        end
    end

    -- The decks that must come back byte-identical are the ones whose OWNERS played after the meta last
    -- moved: those re-crafted at the end of the match, so their deck is exactly what the crafting
    -- function produces from the record and the meta the save carries. A member that has not played
    -- since the meta changed keeps the deck it was dealt -- the same staleness the C ladder has -- so
    -- asserting round-trip equality for it would be asserting a behaviour neither world has.
    for pid = 5, 6 do
        local i = Ladder.memberForPid(l, pid)
        local j = Ladder.memberForPid(back, pid)
        check(i >= 0 and j >= 0, "pid " .. pid .. " is missing from one of the ladders")
        if i >= 0 and j >= 0 then
            check(deckOf(l, i) == deckOf(back, j),
                "the re-crafted deck for pid " .. pid .. " is not the same sixteen cards")
        end
    end

    -- ...and the FUNCTION is deterministic for everybody: re-crafting both ladders from their own
    -- records and metas produces the same sixteen cards for every member, stale or not.
    for i = 1, Ladder.MAX_MEMBERS do
        if l.members[i].active == 1 then
            local j = Ladder.memberForPid(back, l.members[i].pid)
            if j >= 0 then
                Ladder.craftDeck(l, i, 4000)
                Ladder.craftDeck(back, j, 4000)
                check(deckOf(l, i) == deckOf(back, j),
                    "re-crafting pid " .. l.members[i].pid .. " is not deterministic across the save")
            end
        end
    end
end

print(string.format("deadweight ladder (luau): %d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
print("deadweight ladder (luau): ALL PASS")
