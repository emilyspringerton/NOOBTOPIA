-- src/deadweight_board.lua -- the LEADERBOARD a Roblox server shows.
--
-- Founder, real-time: "we port the internet of shankpit bits so there can be an on server IDUNA and
-- WOTAN leaderboard on ROBLOX until we get a permanent home the leaderboard can be per server and reset
-- its fine it lets players face the noobs and also eachother to climb the elos", then "we dont need iduna
-- i guess just the leaderboard for now whatever you think".
--
-- So this is the CONSUMER half of the internet-of-SHANKPIT shim, in the shape Roblox can actually use:
-- on SHANKPIT's side `dw_net.c` serialises the ladder to schema-1 JSON and `tools/shankpit_netd.c`
-- serves it to WOTAN's page. Roblox has no HTTP daemon in this repo and no IDUNA account for a noob, so
-- the board lives IN THE SERVER instead: it is built from the same ladder facts, ranked by a number
-- everybody can climb, and it resets with the server. Nothing here talks to a network.
--
-- WHAT MAKES IT A LEADERBOARD AND NOT A TABLE OF RECORDS: the rating. `PARENA/stdlib/deadweight/
-- rating.prn` is the one place the number is defined, emitted here to Luau (and available to the C side
-- from the same file -- wiring that up is the named follow-up, not a second implementation).
--
-- THE RATING IS PER SERVER, deliberately. Ratings live in this module's own table, updated from the
-- matches the caller reports, so each server climbs its own ladder and a restart starts everyone at
-- 1000. That is the founder's "per server and reset its fine": no persistence, no cross-server merge,
-- and therefore no way for one server's population to poison another's table.
--
-- DATA ONLY, like every other rules module here: no `workspace`, no `game`, no DataStore call. A host
-- that wants persistence can keep `dump`/`load` in a DataStore; nothing in this file requires it.

local Rating = require("generated.deadweight_rating")
local Ladder = require("deadweight_ladder")

local M = {}

-- The kinds, matching dw_net's schema-1 `kind` strings so a page can render either source.
M.KIND_NAMES = {
    [0] = "none",
    [1] = "citizen-vs-citizen",
    [2] = "citizen-vs-player",
    [3] = "player-vs-citizen",
    [4] = "player-vs-player",
}

function M.new()
    return {
        ratings = {},     -- pid -> rating
        played = {},      -- pid -> matches counted in THIS board
        history = {},     -- newest last: { kind, pid0, pid1, winner, at }
    }
end

function M.reset(board)
    board.ratings = {}
    board.played = {}
    board.history = {}
end

function M.ratingOf(board, pid)
    local r = board.ratings[pid]
    if r == nil then return Rating.ratingStart() end
    return r
end

-- Counts one finished match. `winner` is the ladder's own convention: 0 = seat 0 (pid0), 1 = seat 1
-- (pid1), 2 = draw. A draw moves both by the same small amount; a win is zero-sum by construction (the
-- winner's gain and the loser's loss come from the same term in rating.prn).
function M.record(board, pid0, pid1, winner, kind, at)
    local r0 = M.ratingOf(board, pid0)
    local r1 = M.ratingOf(board, pid1)
    local n0, n1
    if winner == 0 then
        local delta = Rating.ratingGain(r0, r1)
        n0 = Rating.ratingApply(r0, delta)
        n1 = Rating.ratingApply(r1, -delta)
    elseif winner == 1 then
        local delta = Rating.ratingGain(r1, r0)
        n1 = Rating.ratingApply(r1, delta)
        n0 = Rating.ratingApply(r0, -delta)
    else
        local delta = Rating.ratingDraw(r0, r1)
        n0 = Rating.ratingApply(r0, delta)
        n1 = Rating.ratingApply(r1, -delta)
    end
    board.ratings[pid0] = n0
    board.ratings[pid1] = n1
    board.played[pid0] = (board.played[pid0] or 0) + 1
    board.played[pid1] = (board.played[pid1] or 0) + 1
    board.history[#board.history + 1] = {
        kind = kind or 0, pid0 = pid0, pid1 = pid1, winner = winner or 2, at = at or 0,
        delta = { n0 - r0, n1 - r1 },
    }
    -- bounded: a board is a screen, not a log
    while #board.history > 20 do table.remove(board.history, 1) end
    return n0, n1
end

-- The ranked table. Deterministic: rating desc, then wins desc, then pid asc, so two servers holding the
-- same facts print the same board and a re-render never shuffles rows under a player's cursor.
function M.rows(board, ladder, limit)
    local rows = {}
    for i = 1, Ladder.MAX_MEMBERS do
        local m = ladder.members[i]
        if m.active == 1 then
            rows[#rows + 1] = {
                pid = m.pid,
                isPlayer = m.isPlayer,
                path = m.path,
                wins = m.wins,
                games = m.games,
                rating = M.ratingOf(board, m.pid),
                winrate = (m.games > 0) and ((m.wins * 1000) // m.games) or 0,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.rating ~= b.rating then return a.rating > b.rating end
        if a.wins ~= b.wins then return a.wins > b.wins end
        return a.pid < b.pid
    end)
    for i = 1, #rows do rows[i].rank = i end
    if limit and limit > 0 and #rows > limit then
        local cut = {}
        for i = 1, limit do cut[i] = rows[i] end
        return cut
    end
    return rows
end

-- A row for one player ("you are 3rd of 9"), or nil when that pid is not on this ladder.
function M.rowFor(board, ladder, pid)
    for _, row in ipairs(M.rows(board, ladder)) do
        if row.pid == pid then return row end
    end
    return nil
end

-- The facts a page or a DataStore would want. NOT schema-1 JSON: that is dw_net.c's job on a box that
-- has a filesystem and an HTTP daemon. This is the same information as plain values a Roblox GUI can
-- read directly, which is the whole point of doing the board in the server.
function M.snapshot(board, ladder)
    local rows = M.rows(board, ladder)
    local out = { entries = {}, recent = {}, population = { citizens = 0, players = 0 } }
    for _, row in ipairs(rows) do
        out.entries[#out.entries + 1] = row
        if row.isPlayer == 1 then
            out.population.players = out.population.players + 1
        else
            out.population.citizens = out.population.citizens + 1
        end
    end
    for i, h in ipairs(board.history) do
        out.recent[i] = {
            kind = M.KIND_NAMES[h.kind] or "none",
            pid0 = h.pid0, pid1 = h.pid1, winner = h.winner, at = h.at,
        }
    end
    return out
end

-- Ratings only, for whatever a host wants to persist. Decks are not here and never were: a deck is a
-- function of a record and a meta, not a stored preference.
function M.dump(board)
    return { ratings = board.ratings, played = board.played }
end

function M.load(board, saved)
    board.ratings = {}
    board.played = {}
    if not saved then return board end
    for pid, r in pairs(saved.ratings or {}) do board.ratings[pid] = r end
    for pid, n in pairs(saved.played or {}) do board.played[pid] = n end
    return board
end

return M
