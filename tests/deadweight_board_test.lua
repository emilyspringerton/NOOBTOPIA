-- tests/deadweight_board_test.lua -- the per-server LEADERBOARD, plain Lua:
--     lua tests/deadweight_board_test.lua
--
-- src/deadweight_board.lua is the Roblox-facing half of the internet-of-SHANKPIT shim: SHANKPIT
-- serialises its ladder to JSON and serves it to WOTAN; a Roblox server has neither, so the board is
-- built in-server from the same facts and ranked by the one number everybody climbs.
--
-- THE NUMBER IS PARENA's: PARENA/stdlib/deadweight/rating.prn, emitted here by gen_deadweight.sh. Every
-- expected value below is hand-derived from that file, not read back out of the generated module.
--
-- `ratingTerm(mine, theirs)` is (theirs - mine) / 50 clamped to +/-8. That division is INTEGER TRUNCATION
-- on purpose -- it is what the C target does -- so 930 vs 1000 is a -1 term (gain 15), not -2 (gain 14).
-- The board asserts that because the two worlds must agree on it; a floor-division port would print a
-- different table for the same server.

package.path = "./src/?.lua;" .. package.path

local Rules = require("generated.deadweight_rules")
local Rating = require("generated.deadweight_rating")
local Ladder = require("deadweight_ladder")
local Board = require("deadweight_board")

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

-- ---- 1. the rating itself, hand-derived -------------------------------------------------------

check(Rating.ratingStart() == 1000, "a newcomer starts at 1000")
check(Rating.ratingFloor() == 100, "the floor is 100")

-- equal ratings: the base 16, no term
check(Rating.ratingGain(1000, 1000) == 16, "beating an equal pays 16 (not " .. Rating.ratingGain(1000, 1000) .. ")")
-- +200 to the opponent: term = 4
check(Rating.ratingGain(1000, 1200) == 20, "beating somebody 200 stronger pays 20 (not " .. Rating.ratingGain(1000, 1200) .. ")")
check(Rating.ratingGain(1200, 1000) == 12, "beating somebody 200 weaker pays only 12 (not " .. Rating.ratingGain(1200, 1000) .. ")")
-- the term is clamped at +/-8, so a 2000-point gap still swings 24
check(Rating.ratingGain(1000, 3000) == 24, "the clamp should cap a huge upset at 24")
check(Rating.ratingGain(3000, 1000) == 8, "the clamp should floor a hopeless mismatch at 8")
-- TRUNCATION, not floor division: -70/50 is -1
check(Rating.ratingGain(1000, 930) == 15, "a -70 term must truncate to -1 (gain 15, not " ..
    Rating.ratingGain(1000, 930) .. ")")
check(Rating.ratingGain(930, 1000) == 17, "a +70 term is 1 (gain 17, not " .. Rating.ratingGain(930, 1000) .. ")")

-- zero-sum: the winner's gain IS the loser's loss, for the same pair
for _, pair in ipairs({ { 1000, 1200 }, { 1200, 1000 }, { 1000, 1000 }, { 300, 2900 } }) do
    local w, l = pair[1], pair[2]
    check(Rating.ratingGain(w, l) == Rating.ratingLoss(l, w),
        "gain(" .. w .. "," .. l .. ") is not loss(" .. l .. "," .. w .. ")")
end

-- draws move both by a tenth of the gap, and are zero-sum too
check(Rating.ratingDraw(1000, 1200) == 2, "a draw against 200 stronger pays 2 (not " .. Rating.ratingDraw(1000, 1200) .. ")")
check(Rating.ratingDraw(1000, 1500) == 4, "a draw's term is clamped at 4")
check(Rating.ratingDraw(1200, 1000) == -2, "a draw against 200 weaker costs 2")
check(Rating.ratingDraw(1000, 1200) == -Rating.ratingDraw(1200, 1000), "a draw is not zero-sum")

-- the floor holds, and a gain is never lost to it
check(Rating.ratingApply(105, -20) == 100, "the floor should catch a drop below 100")
check(Rating.ratingApply(100, -20) == 100, "the floor should hold at 100")
check(Rating.ratingApply(1000, 24) == 1024, "a gain applies plainly")

-- ---- 2. the board: zero-sum, and it climbs -----------------------------------------------------

local board = Board.new()
check(Board.ratingOf(board, 5) == 1000, "a pid with no history starts at 1000")

local n0, n1 = Board.record(board, 0, 5, 0, 2, 1000)   -- pid 0 (a player) beats pid 5
check(n0 == 1016 and n1 == 984, "the first win moved " .. tostring(n0) .. "/" .. tostring(n1) ..
    ", expected 1016/984")
check(Board.ratingOf(board, 0) == 1016, "the winner's rating did not stick")
check(Board.ratingOf(board, 5) == 984, "the loser's rating did not stick")
check(board.played[0] == 1 and board.played[5] == 1, "the matches played were not counted")

-- ...and now pid 5 is 32 behind, so winning pays a little more than the base
local m0, m5 = Board.record(board, 0, 5, 1, 2, 2000)   -- pid 5 wins this time
check(m5 - 984 == 16 + ((1016 - 984) // 50), "the comeback paid " .. tostring(m5 - 984) ..
    ", expected " .. tostring(16 + ((1016 - 984) // 50)))
check((m5 - 984) == (1016 - m0), "a rated match is not zero-sum (" .. tostring(m5 - 984) ..
    " gained, " .. tostring(1016 - m0) .. " lost)")

-- a draw moves both by the same small amount, in opposite directions
local before = Board.ratingOf(board, 0)
local d0, d5 = Board.record(board, 0, 5, 2, 1, 3000)
check(d0 - before == -(d5 - Board.ratingOf(board, 5)), "a draw is not zero-sum on the board")
check(math.abs(d0 - before) <= 4, "a draw moved more than the 4-point clamp")

-- ---- 3. the table: ranked, and deterministic ---------------------------------------------------

do
    local l = Ladder.new(1234)
    Ladder.setHero(l, 0)
    Ladder.addCitizen(l, 5, 0, 300, 0)
    Ladder.addCitizen(l, 6, 2, 800, 0)
    l.members[Ladder.memberForPid(l, 5)].wins = 1
    l.members[Ladder.memberForPid(l, 5)].games = 1
    l.members[Ladder.memberForPid(l, 6)].wins = 0
    l.members[Ladder.memberForPid(l, 6)].games = 1

    local b = Board.new()
    Board.record(b, 5, 6, 0, 1, 1000)   -- citizen beats citizen
    local rows = Board.rows(b, l)
    check(#rows == 3, "the table holds " .. #rows .. " rows, expected the player + two citizens")
    check(rows[1].pid == 5, "the winner is not first (" .. tostring(rows[1].pid) .. ")")
    check(rows[1].rank == 1 and rows[#rows].rank == #rows, "the ranks are not 1..n")
    check(rows[1].rating > rows[2].rating, "the rows are not sorted by rating")
    check(rows[1].winrate == 1000, "a 1-0 record is not 1000 permille (" .. rows[1].winrate .. ")")
    check(rows[2].winrate == 0, "a 0-1 record is not 0 permille (" .. rows[2].winrate .. ")")

    -- a tie is broken the same way twice, so a re-render never shuffles rows under a cursor
    local l2 = Ladder.new(9)
    Ladder.setHero(l2, 0)
    Ladder.addCitizen(l2, 5, 0, 300, 0)
    Ladder.addCitizen(l2, 6, 2, 800, 0)
    local b2 = Board.new()
    local r1 = Board.rows(b2, l2)
    local r2 = Board.rows(b2, l2)
    check(#r1 == #r2, "two renders of the same board disagree on the row count")
    local same = true
    for i = 1, #r1 do if r1[i].pid ~= r2[i].pid then same = false end end
    check(same, "two renders of the same board disagree on the order")
    check(r1[1].pid < r1[2].pid or r1[1].rating > r1[2].rating,
        "an equal-rating tie is not broken by pid")

    local you = Board.rowFor(b, l, 5)
    check(you ~= nil and you.rank == 1, "the pid's own row is not the winner's")
    check(Board.rowFor(b, l, 999) == nil, "a pid that is not on the ladder got a row")

    local snap = Board.snapshot(b, l)
    check(#snap.entries == 3, "the snapshot holds " .. #snap.entries .. " entries")
    check(snap.population.players == 1 and snap.population.citizens == 2,
        "the population is " .. snap.population.players .. "/" .. snap.population.citizens)
    check(#snap.recent == 1, "the ticker holds " .. #snap.recent .. " matches, expected 1")
    check(snap.recent[1].kind == "citizen-vs-citizen", "the ticker kind is " .. tostring(snap.recent[1].kind))
end

-- ---- 4. per-server means per-server: a reset is a fresh table ----------------------------------

do
    local b = Board.new()
    Board.record(b, 0, 5, 0, 2, 1000)
    check(Board.ratingOf(b, 0) ~= 1000, "the fixture did not move the rating")
    Board.reset(b)
    check(Board.ratingOf(b, 0) == 1000 and Board.ratingOf(b, 5) == 1000,
        "a reset did not put everyone back on 1000")
    check(#b.history == 0, "a reset kept the old ticker")
end

-- ---- 5. ratings are the only thing worth keeping -----------------------------------------------

do
    local b = Board.new()
    Board.record(b, 0, 5, 0, 2, 1000)
    local saved = Board.dump(b)
    check(saved.ratings ~= nil and saved.ratings[0] == 1016, "the dump lost a rating")
    local b2 = Board.load(Board.new(), saved)
    check(Board.ratingOf(b2, 0) == 1016, "the load did not restore a rating")
    check(#b2.history == 0, "the load invented a ticker")
end

-- ---- 6. every rating is inside the rules' own band ---------------------------------------------

do
    local b = Board.new()
    local r = 500
    for i = 1, 80 do
        r = Board.record(b, 0, 5, 0, 2, i * 1000) and Board.ratingOf(b, 0) or r
        check(Board.ratingOf(b, 0) >= Rating.ratingFloor(), "the winner fell under the floor")
        check(Board.ratingOf(b, 5) >= Rating.ratingFloor(), "the loser fell under the floor")
        check(Board.ratingOf(b, 0) <= 1000 + 24 * 80, "the winner climbed past the swing ceiling")
        check(Board.ratingOf(b, 0) <= Rules.numCards() * 1000, "a rating left the integer band")
    end
end

print(string.format("deadweight board (luau): %d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
print("deadweight board (luau): ALL PASS")
