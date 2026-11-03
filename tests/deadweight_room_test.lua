-- tests/deadweight_room_test.lua -- THE TABLE, plain Lua, no Roblox:
--     lua tests/deadweight_room_test.lua
--
-- src/deadweight_room.lua is the pure half of the Roblox surface: seats, offers, answers, and the frame a GUI
-- draws. The Roblox half (src/deadweight_ui.lua, src/deadweight_server.lua) cannot be run on this box -- no
-- Studio, no place file, no `luau` -- so every decision that a screen can get WRONG lives in the room, where
-- this file can check it: an offer that outlives its challenge, an answer for a challenge that moved, a row for
-- somebody who left, a prompt that says "sit down" while you are already seated.

package.path = "./src/?.lua;" .. package.path

local Ladder = require("deadweight_ladder")
local Board = require("deadweight_board")
local Room = require("deadweight_room")

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

local PLAYER = 42
local function table_(opts)
    local ladder = Ladder.new(1234)
    local board = Board.new()
    return Room.new(ladder, board, opts)
end

-- ---- 1. seating ---------------------------------------------------------------------------------

do
    local room = table_()
    check(Room.join(room, PLAYER, true, 0) == 1, "the first person did not get seat 1")
    check(Room.isSeated(room, PLAYER), "a seated player is not seated")
    check(Room.join(room, PLAYER, true, 0) == 1, "seating the same pid twice moved it")
    check(#Room.seated(room) == 1, "seating the same pid twice took a second seat")

    for i = 1, Room.MAX_SEATS - 1 do
        check(Room.join(room, 500 + i, false, 0) >= 0, "citizen " .. i .. " could not sit down")
    end
    check(#Room.seated(room) == Room.MAX_SEATS, "the table is not full (" .. #Room.seated(room) .. ")")
    check(Room.join(room, 999, false, 0) == -1, "a fifth body got a seat at a four-seat table")

    Room.leave(room, 501)
    check(not Room.isSeated(room, 501), "a player who left is still seated")
    check(Ladder.memberForPid(room.ladder, 501) == -1, "a player who left is still on the ladder")
    check(Room.join(room, 600, false, 0) == 2, "the free seat was not reused")

    -- a pid the ladder cannot see is refused at the door, not seated and then invisible
    check(Room.join(room, -7, false, 0) == -1, "a negative pid was seated but is unreachable on the ladder")
end

-- ---- 2. one prompt, three branches --------------------------------------------------------------

do
    local room = table_()
    Room.join(room, 501, false, 0)
    Room.join(room, 502, false, 0)

    local f = Room.frame(room, PLAYER)
    check(f.prompt == "Press E to sit down", "an unseated player is told: " .. f.prompt)
    check(f.seated == 2 and f.seats == Room.MAX_SEATS, "the frame counts seats as " .. f.seated .. "/" .. f.seats)

    check(Room.press(room, PLAYER, 1000) == "seated", "the first press did not sit the player down")
    f = Room.frame(room, PLAYER)
    check(f.prompt:find("challenge") ~= nil, "a seated player with no offer is told: " .. f.prompt)
    check(f.you ~= nil and f.you.pid == PLAYER, "the frame does not carry the player's own row")
    -- exactly one row is the player's, and it says so -- wherever the tie-break put it
    local marked = 0
    for _, line in ipairs(f.lines) do if line:find("YOU") then marked = marked + 1 end end
    check(marked == 1, "the player's row is marked " .. marked .. " times")

    local answer = Room.press(room, PLAYER, 2000)
    check(answer == "challenged", "the second press answered " .. tostring(answer) .. ", expected a challenge")
    check(#Room.seated(room) == 3, "challenging somebody changed who is seated")
end

-- ---- 3. a citizen asks, the player answers, and the board moves --------------------------------

do
    local room = table_({ offerInterval = 5000 })
    Room.join(room, PLAYER, true, 0)
    Room.join(room, 501, false, 0)

    -- nothing has happened yet: no offer
    check(Room.pending(room, PLAYER) == nil, "an offer exists before any clock ran")
    Room.tick(room, 5000)
    local waiting = Room.pending(room, PLAYER)
    check(waiting ~= nil, "the citizen never asked the player to play")
    if waiting then
        check(waiting.from ~= PLAYER, "the player was asked by themselves")
        check(waiting.expires > 5000, "the offer was already expired when it opened")
    end

    local f = Room.frame(room, PLAYER)
    check(f.waiting, "the frame does not say there is an offer")
    check(f.prompt:find("play") ~= nil, "the prompt does not offer to play: " .. f.prompt)

    local before = Board.rows(room.board, room.ladder)
    local answer = Room.press(room, PLAYER, 6000)
    check(answer:match("^played") ~= nil, "accepting returned " .. tostring(answer))
    check(Room.pending(room, PLAYER) == nil, "the offer survived being played")
    check(#room.board.history == 1, "the played match did not reach the ticker")

    -- the RECORD moved, always: a game was played
    local mine = Board.rowFor(room.board, room.ladder, PLAYER)
    check(mine ~= nil and mine.games == 1, "the played match did not reach the player's record")
    -- the RATINGS are zero-sum, so the table's total cannot move whether the game was won or drawn
    local total = 0
    for _, row in ipairs(Board.rows(room.board, room.ladder)) do total = total + row.rating end
    check(total == 2000, "the table's ratings sum to " .. total .. ", expected 2000 (zero-sum across two members)")
    -- and a DECIDED game moves both ends; a draw between two 1000s legitimately moves neither
    local last = room.ladder.last
    check(last.valid == 1, "the ladder recorded no match")
    if last.valid == 1 and (last.winner == 0 or last.winner == 1) then
        check(mine ~= nil and mine.rating ~= 1000, "a decided game left the player on 1000")
    end
    check(#before > 0, "the preview board was empty")
end

-- ---- 4. declining leaves every record alone ----------------------------------------------------

do
    local room = table_({ offerInterval = 5000 })
    Room.join(room, PLAYER, true, 0)
    Room.join(room, 501, false, 0)
    Room.tick(room, 5000)
    local waiting = Room.pending(room, PLAYER)
    check(waiting ~= nil, "no offer to decline")

    local myGames = room.ladder.members[Ladder.memberForPid(room.ladder, PLAYER)].games
    local myRating = room.ladder.members[Ladder.memberForPid(room.ladder, PLAYER)].rating
    check(Room.decline(room, PLAYER, 5500), "declining a live offer reported nothing to decline")
    check(Room.pending(room, PLAYER) == nil, "a declined offer is still pending")
    check(room.ladder.members[Ladder.memberForPid(room.ladder, PLAYER)].games == myGames,
        "declining a match moved a record")
    check(room.ladder.members[Ladder.memberForPid(room.ladder, PLAYER)].rating == myRating,
        "declining a match moved a rating")
    check(not Room.decline(room, PLAYER, 5600), "declining nothing claimed to have declined something")
end

-- ---- 5. an offer cannot outlive its challenge --------------------------------------------------

do
    local room = table_({ offerInterval = 5000 })
    Room.join(room, PLAYER, true, 0)
    Room.join(room, 501, false, 0)
    Room.tick(room, 5000)
    local waiting = Room.pending(room, PLAYER)
    check(waiting ~= nil, "no offer to age out")
    -- the room's own clock is what expires it, exactly as the C ladder's TTL does. A NEW offer may well have
    -- replaced it on the same tick -- the interval has elapsed -- so the claim is that THIS challenge is dead.
    -- the slot NUMBER is reused (the ladder hands out its first free one), so identity is the challenge id
    local oldId = room.ladder.challenges[waiting.slot].id
    local reopened = 5000 + Ladder.CHALLENGE_TTL_MS + 1
    Room.tick(room, reopened)
    local slotNow = Ladder.pendingFor(room.ladder, PLAYER)
    check(slotNow < 0 or room.ladder.challenges[slotNow].id ~= oldId,
        "the expired offer is still the one pending (id " .. oldId .. ")")
    local fresh = Room.pending(room, PLAYER)
    if fresh then
        check(fresh.expires > reopened, "the replacement offer is already stale")
        check(room.ladder.challenges[fresh.slot].opened >= reopened, "the pending offer was opened before the sweep")
    end
end

-- ---- 6. a table with only citizens offers nobody a prompt -------------------------------------

do
    local room = table_({ offerInterval = 1000 })
    Room.join(room, 501, false, 0)
    Room.join(room, 502, false, 0)
    for t = 1000, 8000, 1000 do Room.tick(room, t) end
    local f = Room.frame(room, PLAYER)
    check(f.prompt == "Press E to sit down", "a spectator is not told to sit down: " .. f.prompt)
    check(f.lines[1] ~= nil and f.lines[1]:find("1%.") ~= nil, "the board does not number its rows")
end


-- ---- 7. the esports stage, as the table sees it --------------------------------------------------

do
    local room = table_({ stageInterval = 1000 })
    Room.join(room, PLAYER, true, 0)
    Room.join(room, 501, false, 0)
    Room.join(room, 502, false, 0)
    Room.join(room, 503, false, 0)

    check(Room.stage(room) == nil, "a stage exists before one was opened")
    local t = Room.startTournament(room, 1000, 4)
    check(t ~= nil, "a four-member table could not open a stage")
    check(t ~= nil and t.byes == 0, "a full field recorded a bye")
    local f = Room.frame(room, PLAYER)
    check(f.tournament ~= nil and f.tournament.entrants == 4, "the frame does not describe the stage")
    -- the player is the top seed (1000, no wins, lowest pid), so the fold puts them in the first match
    check(f.tournament.match ~= nil and f.tournament.match.a == PLAYER,
        "the stage did not seed the player into a live match")
    check(f.prompt == "Press E to play your stage match", "the prompt does not offer the stage match: " .. f.prompt)
    local answer = Room.press(room, PLAYER, 2000)
    check(answer:match("^stage") ~= nil, "pressing did not play the stage match (got " .. tostring(answer) .. ")")
    check(#room.tournament.log == 1, "the stage match did not reach the bracket log")
    -- the other half of the round is two citizens, so the world may play it on its own clock -- but never a
    -- match a person is in
    local before = #room.tournament.log
    Room.tick(room, 5000)
    check(#room.tournament.log >= before, "ticking the world lost a stage result")
end

print(string.format("deadweight room (luau): %d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
print("deadweight room (luau): ALL PASS")
