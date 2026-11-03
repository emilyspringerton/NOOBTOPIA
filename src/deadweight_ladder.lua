-- src/deadweight_ladder.lua -- WHO PLAYS WHOM, AND WHAT THEY BUILD.
--
-- Ported from SHANKPIT/packages/simulation/dw_ladder.c. The founder's ask was one sentence with four
-- directions in it: "CITIZENS CAN CHALLENGE EACHOTHER ... CITIZENS CAN CHALLENGE PLAYERS ... PLAYERS
-- CAN CHALLENGE CITIZENS ... PLAYERS CAN CHALLENGE PLAYERS ... CITIZENS WILL CRAFT THEIR OWN DECKS
-- BASED ON THEIR WIN RATE AND THE CURRENT META." So there is ONE entry point (`challenge`) and the
-- direction is CLASSIFIED from who the two ends are -- four parallel APIs could disagree with each
-- other, one classification cannot disagree with itself.
--
-- THE DECKS ARE NOT STORED PREFERENCES. A deck is a FUNCTION of the member's own record (wins/games)
-- and the POPULATION'S meta (the kind mix of every card actually played), evaluated by PARENA's
-- cp_deck_card -- the same function SHANKPIT calls. A citizen losing to the current top deck rebuilds
-- toward the answer by itself; one that keeps winning keeps its identity. A restart with the same
-- record and the same meta therefore reproduces the same sixteen cards, which is why the save format
-- below deliberately does NOT contain a deck.
--
-- DATA ONLY: no `workspace`, no `game`, no file IO. `serialize`/`deserialize` hand back plain tables
-- because that is what a Roblox host puts in a DataStore; SHANKPIT writes a text file instead. Same
-- facts, two storage stories.
--
-- PARITY: `PARENA/stdlib/deadweight/ladder_parity.txt` carries a scripted sequence of ladder
-- operations AND their outcomes. SHANKPIT's `dw_ladder_parity_test.c` (`make test-dw-ladder-parity`)
-- and `tests/deadweight_ladder_test.lua` both EXECUTE THE SCRIPT FROM THE FILE, so the two worlds
-- cannot drift by one of them re-typing the scenario.

local Rules = require("generated.deadweight_rules")
local Policy = require("generated.deadweight_policy")
local Game = require("deadweight_game")

local M = {}

M.MAX_MEMBERS = 48
M.MAX_CHALLENGES = 16
M.CHALLENGE_TTL_MS = 45000
M.CITIZEN_INTERVAL_MS = 4000
M.PLAYER_PATH = 2        -- DUEL: a person came to play

M.CHAL = {
    NONE = 0,
    CITIZEN_CITIZEN = 1,
    CITIZEN_PLAYER = 2,
    PLAYER_CITIZEN = 3,
    PLAYER_PLAYER = 4,
}

local U32 = 4294967296
local RNG_SEED = 2654435769

M.CHAL_NAMES = {
    [0] = "none", [1] = "citizen-vs-citizen", [2] = "citizen-vs-player",
    [3] = "player-vs-citizen", [4] = "player-vs-player",
}

-- C uses `^` for XOR on uint32; in Lua `^` is exponentiation, so the seed mixer has to say what it
-- means. Arithmetic, not bit32: the rules' own LCG is arithmetic for the same reason (identical in
-- Luau's doubles and in 64-bit-integer Lua).
local function xor32(a, b)
    local out, bit = 0, 1
    for _ = 1, 32 do
        local abit = a % 2
        local bbit = b % 2
        if abit ~= bbit then out = out + bit end
        a = (a - abit) // 2
        b = (b - bbit) // 2
        bit = bit * 2
    end
    return out
end
M.xor32 = xor32

local function next_rng(l)
    l.rng = (l.rng * 1664525 + 1013904223) % U32
    return l.rng
end

local function blank_member()
    return { active = 0, isPlayer = 0, pid = 0, path = 0, aggression = 500,
             wins = 0, games = 0, deck = {}, lastCraftMs = 0 }
end

local function blank_challenge()
    return { active = 0, id = 0, from = 0, to = 0, kind = 0, opened = 0, expires = 0 }
end

function M.new(seed)
    local l = {
        members = {},
        challenges = {},
        nextId = 1,
        meta = { 0, 0, 0 },
        metaPlays = 0,
        results = { 0, 0, 0, 0 },
        last = { valid = 0, kind = 0, pid0 = 0, pid1 = 0, winner = -1, rounds = 0,
                 hull = { 0, 0 }, at = 0 },
        heroPid = -1,
        rng = ((seed % U32) ~= 0) and (seed % U32) or RNG_SEED,
        nowMs = 0,
        lastCitizenMs = 0,
        count = 0,
    }
    for i = 1, M.MAX_MEMBERS do l.members[i] = blank_member() end
    for i = 1, M.MAX_CHALLENGES do l.challenges[i] = blank_challenge() end
    return l
end

function M.memberForPid(l, pid)
    if pid < 0 then return -1 end
    for i = 1, M.MAX_MEMBERS do
        if l.members[i].active == 1 and l.members[i].pid == pid then return i end
    end
    return -1
end

local function free_member(l)
    for i = 1, M.MAX_MEMBERS do
        if l.members[i].active == 0 then return i end
    end
    return -1
end

function M.metaKind(l)
    if l.metaPlays <= 0 then return -1 end
    local best = 1
    for k = 2, 3 do
        if l.meta[k] > l.meta[best] then best = k end
    end
    return best - 1
end

function M.metaShare(l)
    if l.metaPlays <= 0 then return 0 end
    local best = M.metaKind(l)
    if best < 0 then return 0 end
    return (l.meta[best + 1] * 1000) // l.metaPlays
end

function M.winrateOf(l, idx)
    local m = l.members[idx]
    if not m then return 500 end
    return Policy.cpWinratePermille(m.wins, m.games)
end

-- The only writer of a member's deck.
function M.craftDeck(l, idx, now)
    local m = l.members[idx]
    if not m or m.active == 0 then return -1 end
    local winrate = Policy.cpWinratePermille(m.wins, m.games)
    local metaKind = M.metaKind(l)
    local metaShare = M.metaShare(l)
    for slot = 0, Game.DECK - 1 do
        m.deck[slot + 1] = Policy.cpDeckCard(slot, m.path, winrate, metaKind, metaShare)
    end
    m.lastCraftMs = now or 0
    return m.deck[1]
end

function M.addCitizen(l, pid, path, aggression, now)
    local existing = M.memberForPid(l, pid)
    if existing >= 0 then return existing end   -- a respawned body, already on the ladder
    local idx = free_member(l)
    if idx < 0 then return -1 end
    local m = blank_member()
    m.active = 1
    m.isPlayer = 0
    m.pid = pid
    m.path = path
    if aggression < 0 then aggression = 0 end
    if aggression > 1000 then aggression = 1000 end
    m.aggression = aggression
    l.members[idx] = m
    l.count = l.count + 1
    M.craftDeck(l, idx, now)
    return idx
end

function M.addPlayer(l, pid, now)
    local existing = M.memberForPid(l, pid)
    if existing >= 0 then
        l.members[existing].isPlayer = 1
        return existing
    end
    local idx = free_member(l)
    if idx < 0 then return -1 end
    local m = blank_member()
    m.active = 1
    m.isPlayer = 1
    m.pid = pid
    m.path = M.PLAYER_PATH
    m.aggression = 500
    l.members[idx] = m
    l.count = l.count + 1
    M.craftDeck(l, idx, now)
    return idx
end

function M.removePid(l, pid)
    local idx = M.memberForPid(l, pid)
    if idx >= 0 then
        l.members[idx].active = 0
        if l.count > 0 then l.count = l.count - 1 end
    end
    for i = 1, M.MAX_CHALLENGES do
        local c = l.challenges[i]
        if c.active == 1 and (c.from == pid or c.to == pid) then c.active = 0 end
    end
end

function M.setHero(l, pid)
    l.heroPid = pid
    if pid >= 0 then M.addPlayer(l, pid, l.nowMs) end
end

-- The four directions, one call. Returns the challenge slot or -1.
function M.challenge(l, fromPid, toPid, now)
    if fromPid == toPid then return -1 end
    local fromM = M.memberForPid(l, fromPid)
    local toM = M.memberForPid(l, toPid)
    if fromM < 0 or toM < 0 then return -1 end
    local fromPlayer = l.members[fromM].isPlayer
    local toPlayer = l.members[toM].isPlayer
    local slot = -1
    for i = 1, M.MAX_CHALLENGES do
        if l.challenges[i].active == 0 then slot = i break end
    end
    if slot < 0 then return -1 end
    local c = l.challenges[slot]
    c.active = 1
    c.id = l.nextId
    l.nextId = l.nextId + 1
    c.from = fromPid
    c.to = toPid
    if fromPlayer == 1 then
        c.kind = (toPlayer == 1) and M.CHAL.PLAYER_PLAYER or M.CHAL.PLAYER_CITIZEN
    else
        c.kind = (toPlayer == 1) and M.CHAL.CITIZEN_PLAYER or M.CHAL.CITIZEN_CITIZEN
    end
    c.opened = now
    c.expires = now + M.CHALLENGE_TTL_MS
    return slot
end

function M.pendingFor(l, pid)
    for i = 1, M.MAX_CHALLENGES do
        local c = l.challenges[i]
        if c.active == 1 and c.to == pid then return i end
    end
    return -1
end

function M.decline(l, slot)
    if slot < 1 or slot > M.MAX_CHALLENGES then return end
    l.challenges[slot].active = 0
end

-- The match's seed comes from the CHALLENGE and the two pids, never from the ladder's rng: a replay
-- must not depend on how many people wandered past the table.
local function match_seed(cid, pid0, pid1)
    local a = xor32((cid * 2654435761) % U32, ((pid0 + 1) * 7919) % U32)
    return xor32(a, (pid1 + 3) % U32)
end
M.matchSeed = match_seed

-- THE recorder: the one place a finished match becomes ladder state -- the meta tally, both records,
-- the last-match record and both re-crafted decks. An instant match and a watched one land here.
function M.record(l, i0, i1, kind, winner, m, now)
    local a, b = l.members[i0], l.members[i1]

    -- the meta is the cards that were actually PLAYED, not the decks that were built
    for k = 1, 3 do l.meta[k] = l.meta[k] + m.kindPlays[k] end
    l.metaPlays = l.metaPlays + m.kindPlays[1] + m.kindPlays[2] + m.kindPlays[3]
    l.results[kind] = l.results[kind] + 1

    local pid = -2
    if winner == 0 or winner == 1 then
        local w = (winner == 0) and a or b
        local lose = (winner == 0) and b or a
        w.wins = w.wins + 1
        w.games = w.games + 1
        lose.games = lose.games + 1
        pid = w.pid
    else
        a.games = a.games + 1
        b.games = b.games + 1
    end

    l.last = {
        valid = 1,
        kind = kind,
        pid0 = a.pid,
        pid1 = b.pid,
        winner = (winner == 0) and 0 or ((winner == 1) and 1 or 2),
        rounds = m.roundsPlayed,
        hull = { m.seat[1].hull, m.seat[2].hull },
        at = now,
    }

    -- both records moved, so both decks re-craft from the new record and the new meta
    M.craftDeck(l, i0, now)
    M.craftDeck(l, i1, now)
    l.nowMs = now
    return pid
end

-- Plays the challenge out now. Returns the winning pid, -2 on a draw, -3 if the slot was not live.
function M.accept(l, slot, now)
    if slot < 1 or slot > M.MAX_CHALLENGES then return -3 end
    local c = l.challenges[slot]
    if c.active == 0 then return -3 end
    local i0 = M.memberForPid(l, c.from)
    local i1 = M.memberForPid(l, c.to)
    if i0 < 0 or i1 < 0 then
        c.active = 0
        return -3
    end
    local a, b = l.members[i0], l.members[i1]
    local m = Game.new(match_seed(c.id, a.pid, b.pid), a.deck, b.deck)
    local w = Game.playOut(m, a.aggression, b.aggression)
    local winner = -1
    if w == 1 or w == 2 then winner = w - 1 end
    local kind = c.kind
    c.active = 0
    return M.record(l, i0, i1, kind, winner, m, now)
end

-- Expiry, plus citizens starting games of their own: every interval one citizen challenges another
-- citizen, or the hero more often than not. Citizens do not need a player present to play.
function M.tick(l, now)
    l.nowMs = now
    for i = 1, M.MAX_CHALLENGES do
        local c = l.challenges[i]
        if c.active == 1 then
            if now - c.expires >= 0 then
                c.active = 0
            elseif M.memberForPid(l, c.to) < 0 then
                c.active = 0   -- addressed to somebody who has left the world
            end
        end
    end

    if l.count < 2 then return end
    if l.lastCitizenMs ~= 0 and (now - l.lastCitizenMs) < M.CITIZEN_INTERVAL_MS then return end

    local candidate = -1
    local tries = M.MAX_MEMBERS
    while tries > 0 do
        tries = tries - 1
        local pick = (next_rng(l) % M.MAX_MEMBERS) + 1
        if l.members[pick].active == 1 and l.members[pick].isPlayer == 0 then
            candidate = pick
            break
        end
    end
    if candidate < 0 then return end

    local target = -1
    local wantHero = false
    if l.heroPid >= 0 then wantHero = (next_rng(l) % 100) < 40 end
    if wantHero then
        target = M.memberForPid(l, l.heroPid)
    else
        local tries2 = M.MAX_MEMBERS
        while tries2 > 0 do
            tries2 = tries2 - 1
            local pick = (next_rng(l) % M.MAX_MEMBERS) + 1
            if l.members[pick].active == 1 and pick ~= candidate then
                target = pick
                break
            end
        end
    end
    if target < 0 then return end
    if M.challenge(l, l.members[candidate].pid, l.members[target].pid, now) >= 0 then
        l.lastCitizenMs = now
    end
end

-- A snapshot of the FACTS, not of the decks: a deck is a function of the record and the meta, so a
-- restore re-crafts every one -- which both restores it exactly and proves the function is
-- deterministic. Plain tables, so a Roblox host can hand this straight to a DataStore.
function M.serialize(l)
    local out = {
        meta = { l.meta[1], l.meta[2], l.meta[3] },
        metaPlays = l.metaPlays,
        results = { l.results[1], l.results[2], l.results[3], l.results[4] },
        heroPid = l.heroPid,
        nextId = l.nextId,
        members = {},
    }
    for i = 1, M.MAX_MEMBERS do
        local m = l.members[i]
        if m.active == 1 then
            out.members[#out.members + 1] = {
                pid = m.pid, isPlayer = m.isPlayer, path = m.path,
                aggression = m.aggression, wins = m.wins, games = m.games,
            }
        end
    end
    return out
end

function M.deserialize(snap, seed, now)
    local l = M.new(seed)
    if not snap then return l end
    -- the meta goes in FIRST: every deck re-crafted below is a function of it
    l.meta = { snap.meta[1], snap.meta[2], snap.meta[3] }
    l.metaPlays = snap.metaPlays or 0
    for k = 1, 4 do l.results[k] = snap.results[k] or 0 end
    l.heroPid = snap.heroPid or -1
    l.nextId = snap.nextId or 1
    for _, want in ipairs(snap.members or {}) do
        local idx = M.memberForPid(l, want.pid)
        if idx < 0 then
            idx = free_member(l)
            if idx >= 0 then
                l.count = l.count + 1
                local m = l.members[idx]
                m.active = 1
                m.pid = want.pid
                m.isPlayer = want.isPlayer
                m.path = want.path
                m.aggression = want.aggression
                m.wins = want.wins
                m.games = want.games
                M.craftDeck(l, idx, now)
            end
        end
    end
    if l.heroPid >= 0 and M.memberForPid(l, l.heroPid) < 0 then
        M.addPlayer(l, l.heroPid, now)
    end
    return l
end

return M
