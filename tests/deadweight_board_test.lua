-- tests/deadweight_board_test.lua -- the per-server LEADERBOARD, plain Lua:
--     lua tests/deadweight_board_test.lua
--
-- src/deadweight_board.lua is the Roblox-facing half of the internet-of-SHANKPIT shim: SHANKPIT serialises its
-- ladder to JSON and serves it to WOTAN; a Roblox server has neither, so the board is built in-server from the
-- same facts and ranked by the one number everybody climbs.
--
-- THE NUMBER BELONGS TO THE LADDER, not to the board. It is `member.rating`, set by
-- src/generated/deadweight_rating.lua (PARENA/stdlib/deadweight/rating.prn, emitted to this world and compiled
-- into SHANKPIT's C from the same file). So these checks are about two things: the rating ARITHMETIC (every
-- value hand-derived from that .prn) and the VIEW (ordering, ranks, ticker, the per-server reset).
--
-- `ratingTerm(mine, theirs)` is (theirs - mine) / 50 clamped to +/-8, and that division is INTEGER TRUNCATION
-- because that is what the C target does: 930 vs 1000 is a -1 term (gain 15), not -2 (gain 14). A floor-division
-- port would print a different table for the same server, which is why it is asserted here.

package.path = "./src/?.lua;" .. package.path

local Rating = require("generated.deadweight_rating")
local Ladder = require("deadweight_ladder")
local Board = require("deadweight_board")

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

-- ---- 1. the rating arithmetic, hand-derived -----------------------------------------------------

check(Rating.ratingStart() == 1000, "a newcomer starts at 1000")
check(Rating.ratingFloor() == 100, "the floor is 100")
check(Rating.ratingGain(1000, 1000) == 16, "beating an equal pays 16 (not " .. Rating.ratingGain(1000, 1000) .. ")")
check(Rating.ratingGain(1000, 1200) == 20, "beating somebody 200 stronger pays 20 (not " .. Rating.ratingGain(1000, 1200) .. ")")
check(Rating.ratingGain(1200, 1000) == 12, "beating somebody 200 weaker pays 12 (not " .. Rating.ratingGain(1200, 1000) .. ")")
check(Rating.ratingGain(1000, 3000) == 24, "the clamp caps a huge upset at 24")
check(Rating.ratingGain(3000, 1000) == 8, "the clamp floors a hopeless mismatch at 8")
-- TRUNCATION, not floor division: -70/50 is -1
check(Rating.ratingGain(1000, 930) == 15, "a -70 term must truncate to -1 (gain 15, not " ..
    Rating.ratingGain(1000, 930) .. ")")
check(Rating.ratingGain(930, 1000) == 17, "a +70 term is 1 (gain 17, not " .. Rating.ratingGain(930, 1000) .. ")")

-- zero-sum, for every pair -- the whole reason rating-loss takes the WINNER's view
for _, pair in ipairs({ { 1000, 1200 }, { 1200, 1000 }, { 1000, 1000 }, { 300, 2900 } }) do
    local w, l = pair[1], pair[2]
    check(Rating.ratingGain(w, l) == Rating.ratingLoss(l, w),
        "gain(" .. w .. "," .. l .. ") is not loss(" .. l .. "," .. w .. ")")
end

check(Rating.ratingDraw(1000, 1500) == 4, "a draw's term is clamped at 4")
check(Rating.ratingDraw(1000, 1000) == 0, "a draw between equals moves nothing")
check(Rating.ratingDraw(1000, 1200) == -Rating.ratingDraw(1200, 1000), "a draw is not zero-sum")
check(Rating.ratingApply(105, -20) == 100, "the floor catches a drop below 100")
check(Rating.ratingApply(100, -20) == 100, "the floor holds at 100")
check(Rating.ratingApply(1000, 24) == 1024, "a gain applies plainly")

-- ---- 2. the ladder owns the number, and a match moves it both ways -------------------------------

local function build()
    local l = Ladder.new(1234)
    Ladder.setHero(l, 0)
    Ladder.addCitizen(l, 5, 0, 300, 0)
    Ladder.addCitizen(l, 6, 2, 800, 0)
    return l
end

do
    local l = build()
    local hero = Ladder.memberForPid(l, 0)
    check(l.members[hero].rating == 1000, "a member starts at " .. tostring(l.members[hero].rating))
    check(l.members[Ladder.memberForPid(l, 5)].rating == 1000, "a citizen starts at 1000")

    local slot = Ladder.challenge(l, 5, 6, 1000)
    local winner = Ladder.accept(l, slot, 2000)
    local i5, i6 = Ladder.memberForPid(l, 5), Ladder.memberForPid(l, 6)
    local r5, r6 = l.members[i5].rating, l.members[i6].rating
    -- equal ratings, so the winner's delta is exactly the base 16
    if winner == 5 then
        check(r5 == 1016 and r6 == 984, "the winner is " .. r5 .. " and the loser " .. r6 .. ", expected 1016/984")
    elseif winner == 6 then
        check(r6 == 1016 and r5 == 984, "the winner is " .. r6 .. " and the loser " .. r5 .. ", expected 1016/984")
    else
        check(false, "a two-citizen match came back as a draw (" .. tostring(winner) .. ")")
    end
    check((r5 - 1000) == -(r6 - 1000), "the match was not zero-sum (" .. (r5 - 1000) .. "/" .. (r6 - 1000) .. ")")

    -- ...and the loser has not been reset, moved to the winner's side, or left un-rated
    check(r5 ~= r6, "both ends of a decided match came out with the same rating")
    -- the player, who did not play, is untouched
    check(l.members[hero].rating == 1000, "a match between two citizens moved an absent player's rating")
end

-- a draw is symmetric and small, and only among members whose ratings differ
do
    local l = build()
    local i5, i6 = Ladder.memberForPid(l, 5), Ladder.memberForPid(l, 6)
    -- force a gap so the draw has something to move (a draw between equals is exactly 0, asserted above)
    l.members[i6].rating = 1200
    -- replay the same seed twice: the draw branch is deterministic
    local slot = Ladder.challenge(l, 5, 6, 1000)
    Ladder.accept(l, slot, 2000)
    local r5, r6 = l.members[i5].rating, l.members[i6].rating
    check(-6 <= r5 and r5 <= 1024, "a rating left the plausible band (" .. r5 .. ")")
    check(r6 >= 100, "the floor did not hold (" .. r6 .. ")")
end

-- ---- 3. the table: ranked, and deterministic ---------------------------------------------------

do
    local l = build()
    l.members[Ladder.memberForPid(l, 5)].wins = 1
    l.members[Ladder.memberForPid(l, 5)].games = 1
    l.members[Ladder.memberForPid(l, 6)].wins = 0
    l.members[Ladder.memberForPid(l, 6)].games = 1
    local b = Board.new()

    local rows = Board.rows(b, l)
    check(#rows == 3, "the table holds " .. #rows .. " rows, expected the player + two citizens")
    check(rows[1].rank == 1 and rows[#rows].rank == #rows, "the ranks are not 1..n")
    check(rows[1].rating >= rows[2].rating and rows[2].rating >= rows[3].rating, "the rows are not sorted by rating")

    local r1 = Board.rows(b, l)
    local same = (#r1 == #rows)
    for i = 1, math.min(#r1, #rows) do if r1[i].pid ~= rows[i].pid then same = false end end
    check(same, "two renders of the same board disagree on the order")

    local w5 = Board.rowFor(b, l, 5)
    check(w5 ~= nil and w5.winrate == 1000, "a 1-0 record is not 1000 permille (" .. tostring(w5 and w5.winrate) .. ")")
    local w6 = Board.rowFor(b, l, 6)
    check(w6 ~= nil and w6.winrate == 0, "a 0-1 record is not 0 permille (" .. tostring(w6 and w6.winrate) .. ")")
    check(Board.rowFor(b, l, 999) == nil, "a pid that is not on the ladder got a row")

    Board.noteMatch(b, 5, 6, 0, Ladder.CHAL.CITIZEN_CITIZEN, 2500)
    local snap = Board.snapshot(b, l)
    check(#snap.entries == 3, "the snapshot holds " .. #snap.entries .. " entries")
    check(snap.population.players == 1 and snap.population.citizens == 2,
        "the population is " .. snap.population.players .. "/" .. snap.population.citizens)
    check(#snap.recent == 1 and snap.recent[1].kind == "citizen-vs-citizen",
        "the ticker does not hold the one match, as a kind string")
end

-- ---- 4. per-server means per-server: a new ladder is a fresh table ------------------------------

do
    local l = build()
    local slot = Ladder.challenge(l, 5, 6, 1000)
    Ladder.accept(l, slot, 2000)
    check(l.members[Ladder.memberForPid(l, 5)].rating ~= 1000 or l.members[Ladder.memberForPid(l, 6)].rating ~= 1000,
        "the fixture did not move a rating")

    -- A new server = a new ladder, which is the whole persistence story on Roblox.
    local fresh = build()
    for i = 1, Ladder.MAX_MEMBERS do
        if fresh.members[i].active == 1 then
            check(fresh.members[i].rating == 1000, "a fresh ladder did not start a member at 1000")
        end
    end

    -- within one server the rating survives a save with no decks in it
    local snap = Ladder.serialize(l)
    local back = Ladder.deserialize(snap, 1234, 3000)
    for i = 1, Ladder.MAX_MEMBERS do
        if l.members[i].active == 1 then
            local j = Ladder.memberForPid(back, l.members[i].pid)
            check(j >= 0, "pid " .. l.members[i].pid .. " did not come back")
            if j >= 0 then
                check(back.members[j].rating == l.members[i].rating,
                    "pid " .. l.members[i].pid .. " came back on " .. back.members[j].rating ..
                    ", saved " .. l.members[i].rating)
            end
        end
    end
end

-- ---- 5. the band holds over a long climb --------------------------------------------------------

do
    local l = build()
    local a, b = Ladder.memberForPid(l, 5), Ladder.memberForPid(l, 6)
    for i = 1, 6 do
        local slot = Ladder.challenge(l, 5, 6, 1000 + i * 100)
        if slot >= 0 then Ladder.accept(l, slot, 1500 + i * 100) end
        check(l.members[a].rating >= Rating.ratingFloor(), "a rating fell under the floor")
        check(l.members[b].rating >= Rating.ratingFloor(), "a rating fell under the floor")
        check(l.members[a].rating <= 1000 + 24 * 6, "a rating climbed past the swing ceiling")
    end
end

print(string.format("deadweight board (luau): %d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
print("deadweight board (luau): ALL PASS")
