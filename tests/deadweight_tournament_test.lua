-- tests/deadweight_tournament_test.lua -- THE STAGE, plain Lua, no Roblox:
--     lua tests/deadweight_tournament_test.lua
--
-- src/deadweight_tournament.lua is the bracket behind the esports stage: entrants seeded from the ladder's
-- own rating, a fold pairing, byes for a short field, matches played through the REAL sequencer so a stage
-- result is a ladder result, and a champion. Everything here is hand-derived from those rules rather than
-- read back out of the module -- if the seeding fold ever changes, these numbers say so.
--
-- The ratings are set by hand so the seeding is a fact rather than a consequence of the match RNG: four
-- citizens at 1200 / 1100 / 1050 / 1000 are seeds 1..4, so the fold pairs 1-vs-4 and 2-vs-3 and the top two
-- cannot meet before the final.

package.path = "./src/?.lua;" .. package.path

local Ladder = require("deadweight_ladder")
local Board = require("deadweight_board")
local Tour = require("deadweight_tournament")

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

-- A ladder with `n` citizens whose ratings are the given list, in pid order from 10.
local function field(ratings)
    local l = Ladder.new(4242)
    local b = Board.new()
    for i, rating in ipairs(ratings) do
        local pid = 10 + (i - 1)
        Ladder.addCitizen(l, pid, i - 1, 500, 0)
        l.members[Ladder.memberForPid(l, pid)].rating = rating
    end
    return l, b
end

local function totalRating(l)
    local sum = 0
    for i = 1, Ladder.MAX_MEMBERS do
        if l.members[i].active == 1 then sum = sum + l.members[i].rating end
    end
    return sum
end

-- ---- 1. seeding: the fold, not the arrival order ------------------------------------------------

do
    local l, b = field({ 1200, 1100, 1050, 1000 })
    local t = Tour.new(l, b, { size = 4 })
    check(Tour.seed(t, 0), "a four-member ladder could not open a stage")
    check(#t.entrants == 4, "the stage took " .. #t.entrants .. " entrants, expected 4")
    check(t.entrants[1] == 10 and t.entrants[4] == 13, "the seeds are not rating order (top " ..
        tostring(t.entrants[1]) .. ", bottom " .. tostring(t.entrants[4]) .. ")")
    check(t.byes == 0, "a full field recorded a bye")

    local r1 = t.rounds[1]
    check(#r1 == 2, "a four-slot bracket opened " .. #r1 .. " matches")
    check(r1[1].a == 10 and r1[1].b == 13, "seed 1 did not draw seed 4 (got " ..
        tostring(r1[1].a) .. " vs " .. tostring(r1[1].b) .. ")")
    check(r1[2].a == 11 and r1[2].b == 12, "seed 2 did not draw seed 3 (got " ..
        tostring(r1[2].a) .. " vs " .. tostring(r1[2].b) .. ")")

    local m = Tour.next(t)
    check(m == r1[1], "the first match to play is not the first of the round")
    local f = Tour.frame(t)
    check(f.round == 1 and f.entrants == 4, "the frame miscounts the stage")
    check(f.match ~= nil and f.match.a == 10, "the frame does not name the game being played")
    check(#f.lines == 0 and f.champion == nil, "an unplayed stage already has results")
end

-- an eight-slot stage keeps the top seed away from the second seed
do
    local l, b = field({ 1300, 1200, 1150, 1100, 1050, 1000, 950, 900 })
    local t = Tour.new(l, b, { size = 8 })
    check(Tour.seed(t, 0), "an eight-member ladder could not open an eight-slot stage")
    check(#t.rounds[1] == 4, "an eight-slot bracket opened " .. #t.rounds[1] .. " matches")
    check(t.rounds[1][1].a == t.entrants[1] and t.rounds[1][1].b == t.entrants[8],
        "the top seed did not draw the bottom seed")
    check(t.rounds[1][4].a == t.entrants[4] and t.rounds[1][4].b == t.entrants[5],
        "the middle of the bracket is not the fold's middle")
    -- the two best entrants are in different halves: seeds 1 and 2 never appear in the same first-round
    -- match, which is the property seeding exists for
    for _, m in ipairs(t.rounds[1]) do
        check(not (m.a == t.entrants[1] and m.b == t.entrants[2]), "the top two drew each other in round 1")
    end
end

-- ---- 2. a short field gets byes, and a bye is a decided match ------------------------------------

do
    local l, b = field({ 1200, 1100, 1050 })
    local t = Tour.new(l, b, { size = 4 })
    check(Tour.seed(t, 0), "a three-member ladder could not open a four-slot stage")
    check(t.byes == 1, "a three-entrant stage recorded " .. t.byes .. " byes, expected 1")
    local r1 = t.rounds[1]
    check(r1[1].winner == 10 and r1[1].played == false, "the top seed's bye is not a decided, unplayed match")
    local m = Tour.next(t)
    check(m ~= nil and m.a == 11 and m.b == 12, "the only live match is not 11 vs 12")
    check(m == r1[2], "next() returned a match from nowhere")
end

-- ---- 3. a drawn match still advances somebody, by seed order ------------------------------------

do
    local rank = { [11] = 2, [12] = 3 }
    check(Tour.advanceByRank(rank, 11, 12) == 11, "a draw did not advance the higher seed")
    check(Tour.advanceByRank(rank, 12, 11) == 11, "the rule depends on seat order, which it must not")
    check(Tour.advanceByRank({ [20] = 4 }, 20, nil) == 20, "a bye did not advance the only entrant")
    check(Tour.advanceByRank({}, nil, nil) == nil, "an empty slot produced a winner")
end

-- ---- 4. playing it through: the stage result is a LADDER result --------------------------------

do
    local l, b = field({ 1200, 1100, 1050, 1000 })
    local t = Tour.new(l, b, { size = 4 })
    Tour.seed(t, 0)
    local sumBefore = totalRating(l)

    local first = Tour.playNext(t, 1000)
    check(first == 10 or first == 13, "the first stage match returned " .. tostring(first) .. " as its winner")
    check(#t.log == 1, "the played match did not reach the stage log")
    check(totalRating(l) == sumBefore, "a stage match was not zero-sum on the ratings")
    check(#b.history >= 1, "a stage match did not reach the leaderboard's ticker")
    local m2 = Tour.next(t)
    check(m2 ~= nil and m2.a == 11 and m2.b == 12, "the second half of the round is not the other match")

    Tour.playNext(t, 2000)
    check(t.round == 2, "the bracket did not advance to the final (round " .. t.round .. ")")
    local final = Tour.next(t)
    check(final ~= nil and (#t.rounds[2] == 1), "the final is not a single match")
    check(final.a == first or final.b == first, "the first match's winner is not in the final")

    local champion = Tour.playNext(t, 3000)
    check(Tour.done(t), "the stage did not end after its final")
    check(t.champion == champion, "the champion is not the final's winner")
    check(Tour.next(t) == nil, "a finished stage still offers a match")
    check(Tour.playNext(t, 4000) == nil, "a finished stage played another match")
    check(#t.log == 3, "a four-entrant stage logged " .. #t.log .. " matches, expected 3")
    check(totalRating(l) == sumBefore, "the stage did not keep the ratings zero-sum")

    local f = Tour.frame(t)
    check(f.over and f.champion == champion, "the frame does not report the champion")
    check(f.match == nil, "a finished stage still shows a live match")
    check(#f.lines == 3, "the frame shows " .. #f.lines .. " results, expected 3")
end

-- ---- 5. a bracket cannot ask a winner to play itself --------------------------------------------

do
    local l, b = field({ 1200, 1100, 1050, 1000 })
    local t = Tour.new(l, b, { size = 4 })
    Tour.seed(t, 0)
    Tour.playNext(t, 1000)
    local m = Tour.next(t)
    check(m.a ~= m.b, "the stage paired a body against itself")
    -- and the round cannot advance before it is decided
    check(Tour.advance(t) == false, "an unfinished round advanced")
    check(t.round == 1, "the round number moved while the round was live")
end

-- ---- 6. a stage needs two bodies ----------------------------------------------------------------

do
    local l, b = field({ 1200 })
    local t = Tour.new(l, b, { size = 4 })
    check(Tour.seed(t, 0) == false, "a one-member ladder opened a bracket")
    check(Tour.frame(t) ~= nil, "frame() on an unseeded stage should still describe it")
    check(Tour.available(t) == false, "a one-member stage reported itself available")
end

-- ---- 7. the stage can only seed from the ladder it stands on -----------------------------------

do
    local l, b = field({ 1000, 1000, 1000, 1000 })
    local t = Tour.new(l, b, { size = 4 })
    Tour.seed(t, 0)
    -- equal ratings: the tie-break is wins (all 0), then pid ascending -- the same order the board uses
    check(t.entrants[1] == 10 and t.entrants[2] == 11, "an all-equal field did not fall back to pid order")
    local rows = Board.rows(b, l)
    for i = 1, 4 do
        check(rows[i].pid == t.entrants[i], "seed " .. i .. " disagrees with the board's own order")
    end
end

print(string.format("deadweight stage (luau): %d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
print("deadweight stage (luau): ALL PASS")
