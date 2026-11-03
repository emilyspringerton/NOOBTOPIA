-- tests/deadweight_match_test.lua -- the SEQUENCER, plain Lua, no Roblox:
--     lua tests/deadweight_match_test.lua
--
-- src/deadweight_game.lua is the round-by-round game ported from SHANKPIT's
-- packages/simulation/dw_match.c. The rules and the policy it decides with are NOT reimplemented here:
-- they are src/generated/deadweight_{rules,policy}.lua, emitted from PARENA. The sequencer is the one
-- piece still hand-written per world, so this file exists to catch the moment the two drift.
--
-- THE PARITY CLAIM: every row of PARENA/stdlib/deadweight/match_parity.txt. The same file is asserted
-- by SHANKPIT's dw_match_parity_test.c (`make test-dw-parity`). The vectors are the C answers, because
-- the C emitted from the .prn is authoritative and this port is the bug if it disagrees
-- (../docs/THREE_WAY_MERGE.md §5).
--
-- The rest is the properties a player would notice: the same seed plays the same match twice, no card
-- that is not in the catalogue ever reaches a screen, hulls never climb above the start value, energy
-- stays inside its cap, a match always ends, and a match read one round at a time is the same match.

package.path = "./src/?.lua;" .. package.path

local Rules = require("generated.deadweight_rules")
local Game = require("deadweight_game")

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

-- ---- 1. the shared fixture ---------------------------------------------------------------------

local function parity_path()
    local dir = os.getenv("PARENA_DIR")
    if dir and dir ~= "" then return dir .. "/stdlib/deadweight/match_parity.txt" end
    return "../PARENA/stdlib/deadweight/match_parity.txt"
end

local specs, cur = {}, nil
do
    local f = io.open(parity_path(), "r")
    if not f then
        print("SKIP: no parity vectors at " .. parity_path() .. " (a standalone checkout; set PARENA_DIR)")
    else
        for line in f:lines() do
            line = line:gsub("%s+$", "")
            if line ~= "" and line:sub(1, 1) ~= "#" then
                local kw = line:match("^(%a+)")
                if kw == "match" then
                    -- match id seed path0 lean0 path1 lean1 aggr0 aggr1 metaKind metaShare winner rounds h0 h1 v0 v1
                    local t = {}
                    for v in line:gmatch("(%-?%d+)") do t[#t + 1] = tonumber(v) end
                    check(#t == 16, "a match line has " .. #t .. "/16 fields: " .. line)
                    if #t == 16 then
                        cur = {
                            id = t[1], seed = t[2],
                            path = { t[3], t[5] }, lean = { t[4], t[6] },
                            aggr = { t[7], t[8] }, metaKind = t[9], metaShare = t[10],
                            winner = t[11], rounds = t[12],
                            hull = { t[13], t[14] }, vault = { t[15], t[16] },
                            rows = {},
                        }
                        specs[#specs + 1] = cur
                    end
                elseif kw == "round" then
                    check(cur ~= nil, "a round line before any match line")
                    if cur then
                        local t = {}
                        for v in line:gmatch("(%-?%d+)") do t[#t + 1] = tonumber(v) end
                        check(#t == 12, "a round line has " .. #t .. "/12 fields: " .. line)
                        if #t == 12 then
                            check(t[1] == cur.id, "a round line names match " .. t[1] ..
                                " inside match " .. cur.id)
                            local r = {}
                            for i = 2, 12 do r[#r + 1] = t[i] end
                            cur.rows[#cur.rows + 1] = r
                        end
                    end
                else
                    check(false, "unrecognised line: " .. line)
                end
            end
        end
        f:close()
    end
end

-- Plays a scenario and hands back the transcript in the fixture's own column order.
local function run_spec(sp)
    local d0 = Game.craftDeck(sp.path[1], sp.lean[1], sp.metaKind, sp.metaShare)
    local d1 = Game.craftDeck(sp.path[2], sp.lean[2], sp.metaKind, sp.metaShare)
    local m = Game.new(sp.seed, d0, d1)
    local rows = {}
    local guard = Rules.maxRounds()
    while not m.over and guard > 0 do
        guard = guard - 1
        Game.stepPolicy(m, sp.aggr[1], sp.aggr[2])
        rows[#rows + 1] = {
            m.round, m.lastCard[1], m.lastCard[2],
            m.seat[1].hull, m.seat[2].hull,
            m.seat[1].energy, m.seat[2].energy,
            m.seat[1].vault, m.seat[2].vault,
            m.lastDamage[1], m.lastDamage[2],
        }
    end
    return m, rows
end

local COLUMNS = { "round", "card0", "card1", "hull0", "hull1", "energy0", "energy1",
                  "vault0", "vault1", "damage0", "damage1" }

if #specs > 0 then
    for _, sp in ipairs(specs) do
        local m, rows = run_spec(sp)
        check(#rows == #sp.rows, "match " .. sp.id .. " played " .. #rows ..
            " rounds, the fixture records " .. #sp.rows)
        check(m.roundsPlayed == sp.rounds, "match " .. sp.id .. " reports " .. m.roundsPlayed ..
            " rounds, the fixture " .. sp.rounds)
        -- the C's winner is 0/1/2 (2 = draw); this file's seats are 1-based and a draw is 3.
        check(m.winner - 1 == sp.winner, "match " .. sp.id .. " winner " .. (m.winner - 1) ..
            ", the fixture " .. sp.winner)
        check(m.seat[1].hull == sp.hull[1] and m.seat[2].hull == sp.hull[2],
            "match " .. sp.id .. " hulls " .. m.seat[1].hull .. "/" .. m.seat[2].hull ..
            ", the fixture " .. sp.hull[1] .. "/" .. sp.hull[2])
        check(m.seat[1].vault == sp.vault[1] and m.seat[2].vault == sp.vault[2],
            "match " .. sp.id .. " credits " .. m.seat[1].vault .. "/" .. m.seat[2].vault ..
            ", the fixture " .. sp.vault[1] .. "/" .. sp.vault[2])

        local compare = math.min(#rows, #sp.rows)
        local reported = false
        for r = 1, compare do
            for f = 1, #COLUMNS do
                if rows[r][f] ~= sp.rows[r][f] then
                    if not reported then
                        reported = true
                        print(string.format(
                            "  match %d round %d (%s): played %d, the fixture says %d  [played: %s]",
                            sp.id, r, COLUMNS[f], rows[r][f], sp.rows[r][f], table.concat(rows[r], " ")))
                    end
                    check(false, "match " .. sp.id .. " round " .. r .. " column " .. COLUMNS[f])
                end
            end
        end
        -- covered by the per-column checks above; this keeps the tally honest either way
        if not reported then checks = checks + 1 end
    end
    print(string.format("deadweight match: %d parity matches, %d rounds asserted", #specs,
        (function() local n = 0; for _, s in ipairs(specs) do n = n + #s.rows end; return n end)()))
end

-- ---- 2. a seeded match is the same match twice -------------------------------------------------

do
    local sp = { path = { 2, 0 }, lean = { 500, 300 }, aggr = { 700, 400 }, metaKind = -1, metaShare = 0 }
    local a, ra = run_spec({ seed = 1234, path = sp.path, lean = sp.lean, aggr = sp.aggr,
                             metaKind = sp.metaKind, metaShare = sp.metaShare })
    local b, rb = run_spec({ seed = 1234, path = sp.path, lean = sp.lean, aggr = sp.aggr,
                             metaKind = sp.metaKind, metaShare = sp.metaShare })
    check(#ra == #rb, "the same seed played " .. #ra .. " and " .. #rb .. " rounds")
    local same = true
    for i = 1, math.min(#ra, #rb) do
        for f = 1, #COLUMNS do
            if ra[i][f] ~= rb[i][f] then same = false end
        end
    end
    check(same, "the same seed and decks played two different matches")
    check(a.winner == b.winner and a.seat[1].hull == b.seat[1].hull and a.seat[2].hull == b.seat[2].hull,
        "the replay's end state diverged")

    -- ...and reading it one round at a time is the SAME match (the round clock, not a second game)
    local d0 = Game.craftDeck(2, 500, -1, 0)
    local d1 = Game.craftDeck(0, 300, -1, 0)
    local played = Game.new(1234, d0, d1)
    local winner = Game.playOut(played, 700, 400)
    check(winner == a.winner, "playOut says " .. winner .. ", stepping says " .. a.winner)
    check(played.seat[1].hull == a.seat[1].hull and played.seat[2].hull == a.seat[2].hull,
        "playOut and a stepped match ended on different hulls")
end

-- ---- 3. nothing reaches a screen that is not in the catalogue ----------------------------------

do
    for _, sp in ipairs(specs) do
        local _, rows = run_spec(sp)
        for r = 1, #rows do
            for seat = 1, 2 do
                local c = rows[r][seat + 1]
                check(c == -1 or (c >= 0 and c < Rules.numCards()),
                    "match " .. sp.id .. " round " .. r .. " seat " .. seat .. " played card " .. c)
            end
        end
    end
end

-- ---- 4. the meters stay inside the rules' own bounds -------------------------------------------

do
    local ok_hull, ok_energy = true, true
    for _, sp in ipairs(specs) do
        local _, rows = run_spec(sp)
        for r = 1, #rows do
            if rows[r][4] > Rules.startHull() or rows[r][5] > Rules.startHull() then ok_hull = false end
            for e = 6, 7 do
                if rows[r][e] < 0 or rows[r][e] > 6 then ok_energy = false end
            end
        end
    end
    check(ok_hull, "a hull climbed above the start value")
    check(ok_energy, "energy left its 0..6 band")
end

-- ---- 5. a match always ends: two seats that only pass run out the clock as a draw ---------------
-- 100 rounds, no damage, both credits +1 a round, so hull and credits are equal and the cap decides.
do
    local d = Game.craftDeck(4, 500, -1, 0)
    local m = Game.new(99, d, d)
    local ended_at = 0
    for i = 1, Rules.maxRounds() do
        local done = Game.round(m, -1, -1)
        if done then ended_at = i; break end
    end
    check(ended_at == Rules.maxRounds(), "a pass-only match ended at round " .. ended_at ..
        ", expected the " .. Rules.maxRounds() .. "-round cap")
    check(m.over, "a capped match is still live")
    check(m.winner == 3, "a dead-even capped match is winner " .. m.winner .. ", expected a draw (3)")
    check(m.seat[1].hull == Rules.startHull() and m.seat[2].hull == Rules.startHull(),
        "passing dealt damage (" .. m.seat[1].hull .. "/" .. m.seat[2].hull .. ")")
    check(m.seat[1].vault == m.seat[2].vault, "the cap's tiebreak sees different credits (" ..
        m.seat[1].vault .. "/" .. m.seat[2].vault .. ")")
    check(Game.round(m, -1, -1) == true, "rounding a finished match did not report it as over")
end

-- ---- 6. a crafted deck is sixteen real cards, for every playstyle -------------------------------

do
    for path = 0, 4 do
        for _, lean in ipairs({ 100, 500, 900 }) do
            local deck = Game.craftDeck(path, lean, 0, 700)
            check(#deck == Game.DECK, "path " .. path .. " lean " .. lean .. " built " .. #deck .. " cards")
            for i = 1, #deck do
                check(deck[i] >= 0 and deck[i] < Rules.numCards(),
                    "path " .. path .. " lean " .. lean .. " slot " .. i .. " is card " .. deck[i])
            end
            -- a deck nobody can afford in round 1 is not a deck: at least one card must cost 1
            local cheapest = 99
            for i = 1, #deck do
                local c = Rules.cardCost(deck[i])
                if c < cheapest then cheapest = c end
            end
            check(cheapest <= Rules.startEnergy(), "path " .. path .. " lean " .. lean ..
                " has no card playable on 2 energy (cheapest costs " .. cheapest .. ")")
        end
    end
end

print(string.format("deadweight match (luau): %d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
print("deadweight match (luau): ALL PASS")
