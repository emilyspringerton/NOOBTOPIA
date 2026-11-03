-- src/deadweight_board.lua -- the LEADERBOARD a Roblox server shows.
--
-- Founder, real-time: "we port the internet of shankpit bits so there can be an on server IDUNA and WOTAN
-- leaderboard on ROBLOX until we get a permanent home the leaderboard can be per server and reset its fine it
-- lets players face the noobs and also eachother to climb the elos", then "we dont need iduna i guess just the
-- leaderboard for now whatever you think".
--
-- THE NUMBER IS NOT THIS FILE'S. It belongs to the ladder (src/deadweight_ladder.lua reads
-- `member.rating`, set by src/generated/deadweight_rating.lua, emitted from
-- PARENA/stdlib/deadweight/rating.prn -- the same .prn SHANKPIT compiles to C). This module is a VIEW: it ranks
-- the ladder's members, formats their rows, and keeps a short ticker of matches. It deliberately owns no
-- ratings, because a second copy of the number is exactly how a board and a ladder start disagreeing about what
-- a win was worth.
--
-- PER SERVER, AND THAT IS THE DESIGN. A ladder lives in one server's memory (src/deadweight_server.lua seeds
-- it from the job id), so its board resets with the server. No IDUNA, no DataStore schema, no HTTP: the founder
-- accepted a resetting board until there is a permanent home, and inventing persistence now would mean choosing
-- a storage contract nobody has agreed to.
--
-- DATA ONLY: no `workspace`, no `game`, no network. src/deadweight_ui.lua draws this; nothing here knows a
-- screen exists.

local Ladder = require("deadweight_ladder")

local M = {}

M.HISTORY_LINES = 20

-- The kinds, matching dw_net's schema-1 strings so a page could render either source.
M.KIND_NAMES = {
    [0] = "none",
    [1] = "citizen-vs-citizen",
    [2] = "citizen-vs-player",
    [3] = "player-vs-citizen",
    [4] = "player-vs-player",
}

function M.new()
    return { history = {} }
end

-- Records that a match happened, for the ticker only. The ratings already moved inside the ladder, in the one
-- place a match stops being live -- so this cannot be the thing that forgets to move them.
function M.noteMatch(board, pid0, pid1, winner, kind, at)
    board.history[#board.history + 1] = {
        kind = kind or 0, pid0 = pid0, pid1 = pid1, winner = winner or 2, at = at or 0,
    }
    while #board.history > M.HISTORY_LINES do table.remove(board.history, 1) end
end

-- The ranked table. Deterministic -- rating desc, wins desc, pid asc -- so two renders of the same facts agree
-- and a re-draw never shuffles rows under a player's cursor.
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
                rating = m.rating,
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

-- One player's row ("you are 3rd of 9"), or nil when that pid is not on this ladder.
function M.rowFor(board, ladder, pid)
    for _, row in ipairs(M.rows(board, ladder)) do
        if row.pid == pid then return row end
    end
    return nil
end

function M.ratingOf(board, ladder, pid)
    local row = M.rowFor(board, ladder, pid)
    if row then return row.rating end
    return nil
end

-- The same information dw_net's schema 1 carries, as plain values a Roblox GUI reads directly.
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

return M
