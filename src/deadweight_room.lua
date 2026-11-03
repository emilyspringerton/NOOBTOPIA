-- src/deadweight_room.lua -- THE TABLE: who is sitting at it, who is being asked, and what the screen says.
--
-- This is the pure half of the Roblox surface, split out for the reason every module here is split: a Roblox
-- host cannot be run or tested on this box, and the bugs that actually reach a player are not "the part was
-- the wrong colour" -- they are "the offer expired before it drew", "the answer resolved against a stale
-- challenge", "the board showed a player who had left". Those are decidable here, in plain Lua, so they are
-- decided here.
--
-- `src/deadweight_ui.lua` builds Instances from `frame()` and nothing else; `src/deadweight_server.lua`
-- wires the two together. Nothing in THIS file touches workspace, game, Instance, or the network.
--
-- THE AFFORDANCE, and why it is one prompt. A server Script cannot see a click (the same constraint
-- src/noobtopia.lua's own Punch event documents), so a ProximityPrompt is the only input a server can
-- actually receive. One prompt therefore does the whole thing, in the order that reads naturally:
--   1. you are not seated                -> you sit down
--   2. somebody is asking you to play    -> you accept
--   3. otherwise                         -> you challenge the citizen nearest your own rating
-- That is one button and no menu, and every branch is a decision this file owns rather than the host.

local Ladder = require("deadweight_ladder")
local Board = require("deadweight_board")
local Tour = require("deadweight_tournament")

local M = {}

M.MAX_SEATS = 4
M.OFFER_INTERVAL_MS = 12000   -- how often a citizen at the table asks a person to play
M.LOG_LINES = 3               -- results kept on the frame
M.STAGE_INTERVAL_MS = 4000    -- how often the world plays a stage match nobody is in

local function norm(now)
    -- Luau has no os.clock in a server tick context and the host passes milliseconds; be forgiving about
    -- a fractional or missing clock rather than doing arithmetic on nil.
    if type(now) ~= "number" then return 0 end
    return math.floor(now)
end

function M.new(ladder, board, opts)
    opts = opts or {}
    local room = {
        ladder = ladder or Ladder.new(1),
        board = board or Board.new(),
        seats = {},             -- seat index -> pid
        pids = {},              -- pid -> seat index
        lastOfferMs = 0,
        offerInterval = opts.offerInterval or M.OFFER_INTERVAL_MS,
        tournament = nil,               -- the esports stage, when one is running
        lastStageMs = 0,
        stageInterval = opts.stageInterval or M.STAGE_INTERVAL_MS,
        log = {},
        joined = 0,
    }
    for i = 1, M.MAX_SEATS do room.seats[i] = nil end
    return room
end

local function free_seat(room)
    for i = 1, M.MAX_SEATS do
        if room.seats[i] == nil then return i end
    end
    return -1
end

-- Sits a pid down. `isPlayer` decides whether it is a person (a human seat) or a citizen standing at the table.
function M.join(room, pid, isPlayer, now)
    if room.pids[pid] then return room.pids[pid] end
    -- A NEGATIVE pid is "nobody" to the ladder -- the same -1 sentinel dw_member_for_pid keeps in C -- so seating
    -- one produced a body at the table that could never be ranked, challenged or paid: every press answered "busy"
    -- and the board never showed it. Refuse it here, where it is one line, rather than three screens later.
    if type(pid) ~= "number" or pid < 0 then return -1 end
    local seat = free_seat(room)
    if seat < 0 then return -1 end
    if isPlayer then
        Ladder.addPlayer(room.ladder, pid, norm(now))
    else
        Ladder.addCitizen(room.ladder, pid, Ladder.PLAYER_PATH, 500, norm(now))
    end
    room.seats[seat] = pid
    room.pids[pid] = seat
    room.joined = room.joined + 1
    return seat
end

function M.leave(room, pid)
    local seat = room.pids[pid]
    if not seat then return end
    Ladder.removePid(room.ladder, pid)
    room.seats[seat] = nil
    room.pids[pid] = nil
end

function M.isSeated(room, pid)
    return room.pids[pid] ~= nil
end

function M.seated(room)
    local out = {}
    for i = 1, M.MAX_SEATS do
        if room.seats[i] then out[#out + 1] = room.seats[i] end
    end
    return out
end

-- The challenge waiting on this pid, or nil.
function M.pending(room, pid)
    local slot = Ladder.pendingFor(room.ladder, pid)
    if slot < 0 then return nil end
    local c = room.ladder.challenges[slot]
    return { slot = slot, from = c.from, to = c.to, kind = c.kind, expires = c.expires }
end

-- Asks somebody to play. Both ends must be at the table: a challenge to somebody who has walked away would sit
-- in the book until it expired, which is exactly the "offer that nobody can answer" bug a screen must not show.
function M.challengeTo(room, fromPid, toPid, now)
    if not room.pids[fromPid] or not room.pids[toPid] then return -1 end
    return Ladder.challenge(room.ladder, fromPid, toPid, norm(now))
end

-- The nearest citizen by rating, which is the one worth playing: the point of a per-server board is that the
-- next rung is visible and one prompt away.
function M.rivalFor(room, pid)
    local mine = nil
    for _, row in ipairs(Board.rows(room.board, room.ladder)) do
        if row.pid == pid then mine = row end
    end
    local best, bestGap = nil, nil
    for _, row in ipairs(Board.rows(room.board, room.ladder)) do
        if row.pid ~= pid and room.pids[row.pid] then
            local gap = math.abs(row.rating - ((mine and mine.rating) or 1000))
            if best == nil or gap < bestGap then best, bestGap = row.pid, gap end
        end
    end
    return best
end

local function note(room, text, now)
    table.insert(room.log, { text = text, at = norm(now) })
    while #room.log > M.LOG_LINES do table.remove(room.log, 1) end
end

-- The one prompt. Returns a short string saying what happened, which the host shows and the test asserts.
function M.press(room, pid, now)
    now = norm(now)
    if not room.pids[pid] then
        local seat = M.join(room, pid, true, now)
        if seat < 0 then return "full" end
        note(room, "sat down", now)
        return "seated"
    end
    local waiting = M.pending(room, pid)
    if waiting then
        local winner = Ladder.accept(room.ladder, waiting.slot, now)
        -- the ticker takes the ladder's OWN record of what happened (both pids in the challenge's order and the
        -- real winner), not this function's guess at it
        local last = room.ladder.last
        Board.noteMatch(room.board, last.pid0, last.pid1, last.winner, last.kind, now)
        note(room, "played", now)
        return "played:" .. tostring(winner)
    end
    -- THE STAGE comes before a friendly challenge: if the bracket is waiting on you, that is the game
    local stage = room.tournament
    if stage and not Tour.done(stage) then
        local m = Tour.next(stage)
        if m and (m.a == pid or m.b == pid) then
            local advanced = Tour.playNext(stage, now)
            if advanced then
                note(room, "stage", now)
                return "stage:" .. tostring(advanced)
            end
        end
    end

    local rival = M.rivalFor(room, pid)
    if not rival then return "nobody" end
    if M.challengeTo(room, pid, rival, now) < 0 then return "busy" end
    note(room, "challenged", now)
    return "challenged"
end

-- Turning a challenge down. Its own call because the prompt only ever says yes: walking away from an offer has
-- to be possible without the offer sitting in the book for 45 seconds and then stealing the prompt back.
function M.decline(room, pid, now)
    local waiting = M.pending(room, pid)
    if not waiting then return false end
    Ladder.decline(room.ladder, waiting.slot)
    note(room, "declined", norm(now))
    return true
end

-- A citizen at the table asks a person to play, on its own clock -- so a player who walks up is asked to play
-- rather than having to find the right row in a menu.
local function offerRound(room, now)
    if room.joined < 2 then return nil end
    if room.lastOfferMs ~= 0 and (now - room.lastOfferMs) < room.offerInterval then return nil end
    local citizens, players = {}, {}
    for _, pid in ipairs(M.seated(room)) do
        local idx = Ladder.memberForPid(room.ladder, pid)
        if idx >= 0 then
            if room.ladder.members[idx].isPlayer == 1 then
                players[#players + 1] = pid
            else
                citizens[#citizens + 1] = pid
            end
        end
    end
    if #citizens == 0 or #players == 0 then return nil end
    local citizen = citizens[(math.floor(now / room.offerInterval) % #citizens) + 1]
    local player = players[(math.floor(now / room.offerInterval) % #players) + 1]
    -- never stack a second ask on somebody who already has one
    if M.pending(room, player) then
        room.lastOfferMs = now
        return nil
    end
    if M.challengeTo(room, citizen, player, now) >= 0 then
        room.lastOfferMs = now
        note(room, "asked", now)
        return citizen
    end
    return nil
end

-- Opens a stage: the bracket is seeded from the ladder the moment it is called, so the field is the
-- population as it stands rather than a snapshot somebody took earlier.
function M.startTournament(room, now, size)
    local t = Tour.new(room.ladder, room.board, { size = size or 4 })
    if not Tour.seed(t, norm(now)) then return nil end
    room.tournament = t
    room.lastStageMs = norm(now)
    note(room, "bracket", norm(now))
    return t
end

-- The stage as a screen needs it, or nil when there is no stage.
function M.stage(room)
    if not room.tournament then return nil end
    return Tour.frame(room.tournament)
end

function M.tick(room, now)
    now = norm(now)
    Ladder.tick(room.ladder, now)     -- expiry, and citizens starting games among themselves
    offerRound(room, now)

    -- the world plays its own bracket, on its own clock -- but never a match a PERSON is in: that one waits
    -- for the prompt, because a stage game resolved behind the player's back is a game they did not play
    local t = room.tournament
    if t and not Tour.done(t) then
        local m = Tour.next(t)
        if m then
            local ai = Ladder.memberForPid(room.ladder, m.a)
            local bi = Ladder.memberForPid(room.ladder, m.b)
            local human = (ai >= 0 and room.ladder.members[ai].isPlayer == 1)
                or (bi >= 0 and room.ladder.members[bi].isPlayer == 1)
            if not human and (room.lastStageMs == 0 or (now - room.lastStageMs) >= room.stageInterval) then
                Tour.playNext(t, now)
                room.lastStageMs = now
                note(room, "stage", now)
            end
        end
    end
end

-- EVERYTHING A SCREEN NEEDS, as plain values. The host turns these into TextLabels; it never decides anything.
function M.frame(room, pid)
    local rows = Board.rows(room.board, room.ladder)
    local lines = {}
    for _, row in ipairs(rows) do
        local who = (row.pid == pid) and "YOU" or ("P" .. tostring(row.pid))
        lines[#lines + 1] = string.format("%d. %-4s %4d  %d-%d", row.rank, who, row.rating, row.wins, row.games)
    end
    local waiting = M.pending(room, pid)
    local stage = M.stage(room)
    local prompt
    if not room.pids[pid] then
        prompt = "Press E to sit down"
    elseif waiting then
        local from = waiting.from
        prompt = "Press E to play P" .. tostring(from)
    elseif stage and stage.match and (stage.match.a == pid or stage.match.b == pid) then
        prompt = "Press E to play your stage match"
    else
        local rival = M.rivalFor(room, pid)
        prompt = rival and ("Press E to challenge P" .. tostring(rival)) or "Nobody here to play"
    end
    local ticker = {}
    for i = math.max(1, #room.log - M.LOG_LINES + 1), #room.log do
        ticker[#ticker + 1] = room.log[i].text
    end
    return {
        title = "DEADWEIGHT",
        seated = #M.seated(room),
        seats = M.MAX_SEATS,
        prompt = prompt,
        waiting = waiting ~= nil,
        lines = lines,
        log = ticker,
        tournament = stage,
        you = (function()
            for _, row in ipairs(rows) do if row.pid == pid then return row end end
            return nil
        end)(),
    }
end

return M
