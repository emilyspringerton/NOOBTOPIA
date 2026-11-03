-- tests/deadweight_test.lua -- plain Lua, no Roblox required:  lua tests/deadweight_test.lua
--
-- DEADWEIGHT, running from the SAME source SHANKPIT compiles to C. The rules and the citizen policy are
-- not reimplemented here: src/generated/deadweight_{rules,policy}.lua are emitted from
-- PARENA/stdlib/deadweight/*.prn by scripts/gen_deadweight.sh, and SHANKPIT emits the C from the same
-- two files. So every number below is a cross-world parity claim: if this file and `make test-deadweight`
-- in SHANKPIT ever disagree, the .prn is right and one of the two copies is the bug.
--
-- Every expected value here is hand-derived from those two .prn files (the start values, the base line's
-- tier -> cost table, the triangle's `(b == (a == 2 ? 0 : a + 1))`, the Laplace-smoothed win rate), not
-- read back out of the modules under test.

package.path = "./src/?.lua;" .. package.path

local Rules = require("generated.deadweight_rules")
local Policy = require("generated.deadweight_policy")

local fails = 0
local checks = 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

-- 1. the match constants: 20 hull, 2 energy, 3 credits, 4-card hands, 100 rounds, 105 cards
check(Rules.startHull() == 20, "start hull is 20")
check(Rules.startEnergy() == 2, "start energy is 2")
check(Rules.startVault() == 3, "start credits are 3")
check(Rules.handSize() == 4, "hands are 4 cards")
check(Rules.maxRounds() == 100, "a match is capped at 100 rounds")
check(Rules.numCards() == 105, "the catalogue holds 105 cards")

-- 2. the base line: ids 0-8 are three cards per kind, tiers 0/1/2, and the tier sets the cost (1/2/4)
check(Rules.cardKind(0) == 0 and Rules.cardKind(3) == 1 and Rules.cardKind(6) == 2,
      "the base line is three contiguous cards per kind")
check(Rules.cardTier(0) == 0 and Rules.cardTier(1) == 1 and Rules.cardTier(2) == 2,
      "the base line's tiers are 0/1/2")
check(Rules.cardCost(0) == 1 and Rules.cardCost(1) == 2 and Rules.cardCost(2) == 4,
      "base-line cost follows the tier: 1 / 2 / 4")
check(Rules.cardCost(3) == 1, "the same cost table applies to the second kind")

-- 3. the triangle is total and antisymmetric: kind k beats (k + 1) mod 3, and never itself
for a = 0, 2 do
    for b = 0, 2 do
        if a == b then
            check(Rules.kindBeats(a, b) == false, "kind " .. a .. " does not beat itself")
        else
            local ab = Rules.kindBeats(a, b)
            local ba = Rules.kindBeats(b, a)
            check((ab and not ba) or (ba and not ab), "exactly one of " .. a .. "/" .. b .. " beats the other")
        end
    end
end
check(Rules.kindBeats(0, 1) == true, "Offense beats Operations")
check(Rules.kindBeats(2, 0) == true, "Defense beats Offense")

-- 4. a pass deals nothing, and Defense deals nothing into a live play
check(Rules.damageDealt(-1, 3) == 0, "a pass deals no damage")
check(Rules.damageDealt(3, -1) == Rules.cardPower(3), "a live card hits a passing opponent for its power")

-- 5. legal plays: cost is paid from energy, and a card that needs credits needs them in the vault
check(Rules.isLegalPlay(0, 0, 0) == false, "a cost-1 card is not playable with no energy")
check(Rules.isLegalPlay(0, 1, 0) == true, "a cost-1 card is playable with 1 energy")
check(Rules.isLegalPlay(-1, 6, 6) == false, "a negative id is never legal")
check(Rules.isLegalPlay(105, 6, 6) == false, "an id past the catalogue is never legal")

-- 6. the citizen policy: Laplace-smoothed win rate, so no record is 0 or 1000
check(Policy.cpWinratePermille(0, 0) == 500, "no record reads as an unknown 500")
check(Policy.cpWinratePermille(1, 1) == 666, "one win from one game is 666, not 1000")
check(Policy.cpWinratePermille(0, 4) == 166, "no wins from four games is 166, not 0")

-- 7. identity and answer: DUEL/ENDGAME build Offense, CRAFT/TRADE Operations, IDLE Defense
check(Policy.cpKindIdentity(2) == 0, "a duelist builds Offense")
check(Policy.cpKindIdentity(0) == 1, "a crafter builds Operations")
check(Policy.cpKindIdentity(4) == 2, "an idler builds Defense")
check(Policy.cpKindAnswer(0) == 2, "the answer to an Offense meta is Defense")
check(Policy.cpKindAnswer(2) == 1, "the answer to a Defense meta is Operations")

-- 8. deck kind: no meta, or a divided meta, means identity wins
check(Policy.cpDeckKind(2, 500, -1, 0) == 0, "with no meta a duelist stays on its identity")
check(Policy.cpDeckKind(2, 500, 0, 400) == 0, "a 400-permille meta is not a meta, identity wins")
check(Policy.cpDeckKind(2, 200, 0, 800) == 2, "a losing citizen leans to the answer (lean 800)")
check(Policy.cpDeckKind(2, 900, 0, 800) == 0, "a winning citizen keeps its identity (lean 100)")

-- 9. scoring: an illegal card is masked, a pass scores 0 so it only wins when nothing is better
check(Policy.cpCardScore(0, 5, 1, 0, 0, 500) == -1, "an unplayable card is masked with -1")
check(Policy.cpPick(0, 0, 0, 0, 3, 4, 5, 6) == -1, "when every card ties pass, the citizen passes")
check(Policy.cpPick(10, 5, 1, 0, 7, 8, 9, 10) == 7, "the highest-scoring card is the one played")

-- 10. deck crafting: slots 0-12 are the current kind cycling tiers, 13-15 the kind that answers it
check(Policy.cpDeckCard(0, 2, 500, -1, 0) == 0, "slot 0 is the kind's tier-0 card")
check(Policy.cpDeckCard(1, 2, 500, -1, 0) == 1, "slot 1 is the kind's tier-1 card")
check(Policy.cpDeckCard(3, 2, 500, -1, 0) == 0, "slot 3 cycles back to tier 0, so the deck has a cost curve")
check(Policy.cpDeckCard(13, 2, 500, -1, 0) == 7, "slot 13 is the answering kind's tier-1 card")
check(Policy.cpDeckCard(99, 2, 500, -1, 0) == Policy.cpDeckCard(15, 2, 500, -1, 0),
      "a slot past 15 clamps to the last card rather than reading out of bounds")

-- 11. every crafted deck is inside the catalogue, for every path and both ends of the record
for path = 0, 4 do
    for _, lean in ipairs({ 100, 500, 900 }) do
        for slot = 0, 15 do
            local id = Policy.cpDeckCard(slot, path, lean, 0, 700)
            check(id >= 0 and id < Rules.numCards(),
                  "path " .. path .. " lean " .. lean .. " slot " .. slot .. " is inside the catalogue")
        end
    end
end

print(string.format("deadweight (luau): %d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
print("deadweight (luau): ALL PASS")
