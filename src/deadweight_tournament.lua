-- src/deadweight_tournament.lua -- THE STAGE: an esports bracket inside NOOBTOPIA, seeded from the ladder.
--
-- Founder, real-time: "can we make a stage for esports tournoments inside of noobtopia". A stage is three
-- things and this file is the odd one out of the three: the BRACKET (who plays whom, in what order, and who
-- is still alive), the MATCHES (played through the real sequencer, so a tournament result is a ladder result
-- and the ratings move), and the SCREEN (which belongs in deadweight_ui.lua, and draws only what this file
-- says). It is pure data and pure decisions: no `workspace`, no `game`, no clock of its own -- every entry
-- point takes `now`, so a whole tournament can be played in a test in microseconds.
--
-- WHY A SEPARATE MODULE FROM THE LADDER. The ladder answers "who can I challenge right now"; a bracket
-- answers "who is left, and what happens next". Putting the second inside the first would make every ladder
-- caller carry tournament state, and it would hide the one thing that can genuinely go wrong on a stage:
-- a bracket that advances somebody who already lost, or asks a winner to play again in the same round.
--
-- THE RULES, all stated rather than implied:
--   * ENTRANTS are the ladder's top `size` by RATING (then wins, then pid) -- the same order the board and
--     the WOTAN page use, from Board.rows, so the stage cannot seed differently from the table it stands on.
--   * SEEDING is the standard fold: 1 plays the LAST seed, 2 plays the second-last, and so on. The strongest
--     entrant cannot meet the second-strongest before the final, which is the entire point of seeding.
--   * A SHORT FIELD gets BYES, not a smaller bracket: a 3-entrant stage is a 4-slot bracket whose top seed
--     waits. A bye is recorded as a decided match (`winner` set, `played = false`), so "advance the winner"
--     is one rule everywhere and no round can stall on a slot that has nobody in it.
--   * A DRAW is resolved by SEED ORDER (the higher seed advances). A bracket needs a body, and a coin flip
--     would be worse than a rule a spectator can predict. The match is still a real draw on the ladder --
--     both ratings move by a tenth of the gap -- so the stage and the table agree about what happened even
--     though only one of them advances.
--   * Every match goes through `Ladder.challenge` + `Ladder.accept`, which is the same path a friendly
--     challenge takes: records, the meta and the ratings all move, and `Board.noteMatch` puts it on the
--     ticker. Nothing here re-implements a match.
--
-- NOT RUNNABLE IN ROBLOX TERMS: like every module in this repo it is plain Lua and needs no Studio; the
-- screen half (the raised platform, the podiums, the bracket board) is in deadweight_ui.lua and has never
-- been seen, which is said there rather than here.

local Ladder = require("deadweight_ladder")
local Board = require("deadweight_board")

local M = {}

M.NAME = "THE PIT"
M.SIZES = { 4, 8 }
M.MAX_LOG = 12

local function norm(now)
    if type(now) ~= "number" then return 0 end
    return math.floor(now)
end

-- The higher seed (the SMALLER rank number) advances a drawn match. Pure, so the rule can be tested without
-- playing a hundred matches hoping for a draw.
function M.advanceByRank(rank, a, b)
    if a == nil then return b end
    if b == nil then return a end
    local ra, rb = rank[a] or 999, rank[b] or 999
    if ra == rb then return (a < b) and a or b end   -- same rank cannot happen with distinct entrants; be total
    return (ra < rb) and a or b
end

function M.new(ladder, board, opts)
    opts = opts or {}
    local size = opts.size or 4
    if size ~= 4 and size ~= 8 then size = 4 end
    return {
        name = opts.name or M.NAME,
        ladder = ladder,
        board = board,
        size = size,
        entrants = {},      -- pids in seed order, 1..n
        rank = {},          -- pid -> seed (1 = top seed)
        rounds = {},        -- rounds[r] = { {a,b,winner,played,rankA,rankB} }
        round = 1,
        champion = nil,
        startedMs = 0,
        log = {},           -- finished matches, oldest first
        byes = 0,
    }
end

local function round_done(r)
    for _, m in ipairs(r) do
        if m.winner == nil then return false end
    end
    return true
end

-- Seeds the bracket from the ladder's ranking. Returns true if a bracket exists.
function M.seed(t, now)
    if not t or not t.ladder then return false end
    local rows = Board.rows(t.board, t.ladder)
    local n = math.min(t.size, #rows)
    if n < 2 then return false end

    local slots = 1
    while slots < n do slots = slots * 2 end

    t.entrants = {}
    t.rank = {}
    for i = 1, n do
        t.entrants[i] = rows[i].pid
        t.rank[rows[i].pid] = i
    end

    -- the fold: 1 vs slots, 2 vs slots-1, ...
    local first = {}
    for i = 1, slots / 2 do
        local a = t.entrants[i] or nil
        local b = t.entrants[slots - i + 1] or nil
        local m = { a = a, b = b, winner = nil, played = false, rankA = a and t.rank[a], rankB = b and t.rank[b] }
        if a and not b then m.winner = a; t.byes = t.byes + 1
        elseif b and not a then m.winner = b; t.byes = t.byes + 1 end
        first[#first + 1] = m
    end

    t.rounds = { first }
    t.round = 1
    t.champion = nil
    t.startedMs = norm(now)
    t.log = {}
    t.byes = t.byes or 0
    return true
end

-- Builds the next round out of the current one's winners. Returns false if the current round is unfinished.
function M.advance(t)
    local r = t.rounds[t.round]
    if not r or not round_done(r) then return false end
    local winners = {}
    for _, m in ipairs(r) do winners[#winners + 1] = m.winner end
    if #winners <= 1 then
        t.champion = winners[1]
        return true
    end
    local nxt = {}
    for i = 1, #winners, 2 do
        local a, b = winners[i], winners[i + 1]
        local m = { a = a, b = b, winner = nil, played = false, rankA = a and t.rank[a], rankB = b and t.rank[b] }
        if a and not b then m.winner = a; t.byes = t.byes + 1
        elseif b and not a then m.winner = b; t.byes = t.byes + 1 end
        nxt[#nxt + 1] = m
    end
    t.rounds[#t.rounds + 1] = nxt
    t.round = #t.rounds
    return true
end

-- The next match that needs a result, or nil (the bracket is waiting on a person, or it is over). Advances
-- through completed rounds itself, so a caller never has to know how many byes a short field produced.
function M.next(t)
    if not t or t.champion then return nil end
    for _ = 1, 8 do
        local r = t.rounds[t.round]
        if not r then return nil end
        for _, m in ipairs(r) do
            if m.a and m.b and m.winner == nil then return m end
        end
        if t.champion then return nil end
        if not M.advance(t) then return nil end
        if t.champion then return nil end
    end
    return nil
end

function M.done(t)
    return t ~= nil and t.champion ~= nil
end

-- Plays the next match for real: the same challenge/accept path a friendly game takes, so the result is on
-- both records, moves both ratings and lands on the ticker. Returns the advancing pid, or nil.
function M.playNext(t, now)
    local m = M.next(t)
    if not m then return nil end
    now = norm(now)
    local slot = Ladder.challenge(t.ladder, m.a, m.b, now)
    if slot < 0 then return nil end
    Ladder.accept(t.ladder, slot, now)
    local last = t.ladder.last
    if last and last.valid == 1 then
        Board.noteMatch(t.board, last.pid0, last.pid1, last.winner, last.kind, now)
    end

    local adv, drew
    if last and last.winner == 0 then adv = last.pid0
    elseif last and last.winner == 1 then adv = last.pid1
    else
        -- a draw: the stage still needs a body, and seed order is the rule a spectator can predict
        adv = M.advanceByRank(t.rank, m.a, m.b)
        drew = true
    end
    m.winner = adv
    m.played = true
    t.log[#t.log + 1] = { round = t.round, a = m.a, b = m.b, winner = adv, draw = drew and true or false, ms = now }
    while #t.log > M.MAX_LOG do table.remove(t.log, 1) end

    M.advance(t)
    return adv
end

-- Everything a screen needs about the stage, as plain values. `match` is the game being played (or waiting to
-- be), `bracket` is the current round, and `champion` non-nil means the stage is over.
function M.frame(t)
    if not t then return nil end
    local m = M.next(t)
    local bracket = {}
    local r = t.rounds[t.round]
    if r then
        for _, e in ipairs(r) do
            bracket[#bracket + 1] = { a = e.a, b = e.b, winner = e.winner, played = e.played }
        end
    end
    local lines = {}
    for _, e in ipairs(t.log) do
        local loser = (e.winner == e.a) and e.b or e.a
        lines[#lines + 1] = string.format("R%d  P%s beat P%s%s",
            e.round, tostring(e.winner), tostring(loser), e.draw and " (drawn, higher seed)" or "")
    end
    return {
        name = t.name,
        round = t.round,
        rounds = #t.rounds,
        entrants = #t.entrants,
        byes = t.byes,
        match = m and { a = m.a, b = m.b } or nil,
        bracket = bracket,
        lines = lines,
        champion = t.champion,
        over = M.done(t),
        startedMs = t.startedMs,
    }
end

-- Can a stage be opened at all? Two bodies is the floor; below that there is no bracket to draw.
function M.available(t)
    if not t or not t.ladder then return false end
    return t.ladder.count >= 2
end

return M
