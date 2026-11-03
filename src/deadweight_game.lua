-- src/deadweight_game.lua -- the DEADWEIGHT SEQUENCER: a match, round by round.
--
-- Ported from SHANKPIT/packages/simulation/dw_match.c, which is the same sequencer SHANKPIT runs.
-- The RULES are not restated here: every number (105 cards, costs, powers, credits, the kind
-- triangle, the round economy, every effect word and its condition engine) comes from
-- src/generated/deadweight_rules.lua, emitted from PARENA/stdlib/deadweight/card_rules.prn by
-- scripts/gen_deadweight.sh. The citizen's CHOICE comes from src/generated/deadweight_policy.lua,
-- emitted from stdlib/deadweight/citizen_policy.prn. So this file owns exactly one thing: the ORDER
-- effects happen in.
--
-- DATA ONLY, on purpose -- no `workspace`, no `game`, no `wait`, no `Vector3`. That is what lets
-- tests/deadweight_match_test.lua run it under a plain interpreter, and it is the same layering
-- src/wander.lua and src/big_o_witness.lua already use: the Roblox host (src/noobtopia.lua's family)
-- may DRAW a match, but it must not decide one.
--
-- THE PARITY CLAIM: tests/deadweight_match_test.lua and SHANKPIT's dw_match_parity_test.c assert the
-- SAME rows of PARENA/stdlib/deadweight/match_parity.txt -- same seed, same two crafted decks, same
-- per-round cards, hulls, energy, credits and damage. If the two ever disagree, the .prn is right and
-- one of the two sequencers is the bug.
--
-- 1-BASED SEATS (seat[1], seat[2]). Lua's arrays are 1-based and this file is Lua; the C's 0-based
-- seats are a detail of the C, not of the game. Card ids inside seat state are card ids (-1 = pass),
-- which are the SAME numbers in both worlds.

local Rules = require("generated.deadweight_rules")
local Policy = require("generated.deadweight_policy")

local M = {}

M.HAND = 4
M.DECK = 16

-- The C's 32-bit LCG, exactly: `rng = rng * 1664525 + 1013904223`, mod 2^32. This is deliberately
-- arithmetic and not bit ops, because it has to be IDENTICAL in Luau (doubles) and in Lua 5.4
-- (64-bit integers). It is exact in doubles: the largest product is 4294967295 * 1664525 ~= 7.1e15,
-- well under 2^53, so no step rounds. The mixer bug in src/ambient.lua is the precedent for why this
-- is stated rather than assumed.
local RNG_MUL = 1664525
local RNG_ADD = 1013904223
local RNG_MOD = 4294967296
local RNG_SEED = 2654435769 -- 0x9e3779b9, the C's fallback for seed 0

local function new_seat()
    return {
        hull = 0,
        energy = 0,
        vault = 0,          -- credits; below -6 is bankruptcy
        armor = 0,          -- soaks incoming damage until spent
        burn = 0,
        burnRounds = 0,
        regen = 0,
        regenRounds = 0,
        pendingEnergy = 0,  -- banked by channels 25/26/27, applied next round
        disabledNext = 0,   -- hand slots the opponent's DISABLE costs next round
        blindRounds = 0,    -- meters hidden from the opponent (state a UI reads)
        hand = { -1, -1, -1, -1 },
    }
end

local function new_fx()
    return {
        card = -1, oppCard = -1,
        dealt = 0, taken = 0, energyLeft = 0,
        ignoreArmor = false, trueDamage = false, immune = false, lifeline = false,
        cancel = false, halve = false, copy = false,
        reflect = 0, bypassFloor = 0, bypassNoReflect = false,
    }
end

-- Builds a match from two 16-card decks. Both seats start from the rules' own start values.
function M.new(seed, deck0, deck1)
    local m = {
        seat = { new_seat(), new_seat() },
        deck = { {}, {} },
        deckPos = { 0, 0 },          -- 0-based cursor, exactly like the C's deck_pos
        round = 0,
        roll = 0,                    -- 0..99, this round's roll for conditions 18/21
        lastCard = { -1, -1 },
        roundStartHull = { 0, 0 },
        lastDamage = { 0, 0 },
        lastBurn = { 0, 0 },
        over = false,
        started = false,             -- a round has been BEGUN but not FINISHED (the policy seam)
        winner = -1,                 -- -1 live, 1/2 seat, 3 draw
        rng = ((seed % RNG_MOD) ~= 0) and (seed % RNG_MOD) or RNG_SEED,
        kindPlays = { 0, 0, 0 },     -- every card actually played, by kind -- the meta tally
        unsupportedFx = { 0, 0 },
        roundsPlayed = 0,
    }
    for s = 1, 2 do
        local st = m.seat[s]
        st.hull = Rules.startHull()
        st.energy = Rules.startEnergy()
        st.vault = Rules.startVault()
        m.roundStartHull[s] = st.hull
        local src = (s == 1) and deck0 or deck1
        for i = 1, M.DECK do m.deck[s][i] = src[i] end
    end
    return m
end

local function next_rng(m)
    m.rng = (m.rng * RNG_MUL + RNG_ADD) % RNG_MOD
    return m.rng
end

local function draw_hand(m, s)
    local n = Rules.handSize()
    if n > M.HAND then n = M.HAND end
    local st = m.seat[s]
    for i = 1, n do
        if m.deckPos[s] >= M.DECK then m.deckPos[s] = 0 end -- deterministic reshuffle
        m.deckPos[s] = m.deckPos[s] + 1
        st.hand[i] = m.deck[s][m.deckPos[s]]
    end
    for i = n + 1, M.HAND do st.hand[i] = -1 end
    return n
end

-- A channel this sequencer does not recognise sets a bit instead of being silently ignored, so a
-- future card cannot quietly play a different game.
local function raise(m, s, ch)
    m.unsupportedFx[s] = m.unsupportedFx[s] + 2 ^ (ch % 32)
end

local function phase1_channel(ch)
    return ch == 1 or ch == 2 or ch == 3 or ch == 4 or ch == 5
        or ch == 6 or ch == 7 or ch == 8 or ch == 9 or ch == 22
end

-- One seat's view of the round, so the rules' own condition engine can be asked about it. The hulls,
-- energy and credits are read LIVE (`m`), exactly as the C does -- a phase-2 heal earlier in the
-- round can change the amount a later condition computes.
local function fx_amount_for(m, f, s, word)
    local opp = 3 - s
    local own = m.seat[s]
    local other = m.seat[opp]
    local myKind = -1
    if f.card >= 0 then myKind = Rules.cardKind(f.card) end
    local oppKind = -1
    local oppCost = 0
    if f.oppCard >= 0 then
        oppKind = Rules.cardKind(f.oppCard)
        oppCost = Rules.cardCost(f.oppCard)
    end
    return Rules.fxAmount(word, f.dealt, f.taken,
        myKind, oppKind, oppCost,
        own.hull, other.hull,
        f.energyLeft, other.energy,
        own.vault, other.vault,
        m.round, m.roll)
end

local function phase1(m, fx, pass)
    for s = 1, 2 do
        local f = fx[s]
        if f.card >= 0 then
            for w = 1, 2 do
                local word
                if w == 1 then word = Rules.cardFxA(f.card) else word = Rules.cardFxB(f.card) end
                if word ~= 0 then
                    local ch = Rules.fxCh(word)
                    if Rules.fxPhase(ch) == 1 then
                        if not phase1_channel(ch) then
                            raise(m, s, ch)
                        else
                            local amt = fx_amount_for(m, f, s, word)
                            if pass == 0 then
                                if ch == 7 and amt > 0 then f.cancel = true end
                                if ch == 9 and amt > 0 then f.halve = true end
                                if ch == 4 and amt > 0 then f.immune = true end
                                if ch == 5 and amt > 0 then f.lifeline = true end
                                if ch == 3 and amt > f.bypassFloor then f.bypassFloor = amt end
                                if ch == 8 and amt > 0 then f.copy = true end
                            else
                                if ch == 1 and amt > 0 then f.dealt = f.dealt + amt end
                                if ch == 2 and amt > 0 then f.ignoreArmor = true end
                                if ch == 6 and amt > 0 then f.reflect = f.reflect + amt end
                                if ch == 22 and amt > 0 then f.trueDamage = true end
                                if ch == 3 and amt > 0 then f.bypassNoReflect = true end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Phase 2: everything that changes the seats rather than the exchange.
local function phase2(m, fx)
    for s = 1, 2 do
        local opp = 3 - s
        local f = fx[s]
        if f.card >= 0 then
            for w = 1, 2 do
                local word
                if w == 1 then word = Rules.cardFxA(f.card) else word = Rules.cardFxB(f.card) end
                if word ~= 0 then
                    local ch = Rules.fxCh(word)
                    if Rules.fxPhase(ch) == 2 then
                        local amt = fx_amount_for(m, f, s, word)
                        if amt > 0 or ch == 43 then
                            local own = m.seat[s]
                            local other = m.seat[opp]
                            if ch == 20 then
                                local h = own.hull + amt
                                own.hull = (h > Rules.startHull()) and Rules.startHull() or h
                            elseif ch == 21 then
                                own.hull = own.hull - amt
                            elseif ch == 23 then
                                local en = own.energy + amt
                                own.energy = (en > 6) and 6 or en
                            elseif ch == 24 then
                                local en = other.energy - amt
                                other.energy = (en < 0) and 0 or en
                            elseif ch == 25 then
                                own.pendingEnergy = own.pendingEnergy + amt
                            elseif ch == 26 then
                                own.pendingEnergy = own.pendingEnergy - amt
                            elseif ch == 27 then
                                other.pendingEnergy = other.pendingEnergy - amt
                            elseif ch == 28 then
                                own.armor = own.armor + amt
                            elseif ch == 29 then
                                own.vault = own.vault + amt
                            elseif ch == 30 then
                                own.vault = own.vault - amt
                            elseif ch == 31 then
                                other.vault = other.vault - amt
                            elseif ch == 32 then
                                other.burn = other.burn + amt // 16
                                other.burnRounds = other.burnRounds + amt % 16
                            elseif ch == 33 then
                                own.regen = own.regen + amt // 16
                                own.regenRounds = own.regenRounds + amt % 16
                            elseif ch == 34 then
                                local n = other.disabledNext + amt
                                other.disabledNext = (n > M.HAND) and M.HAND or n
                            elseif ch == 35 then
                                own.blindRounds = own.blindRounds + amt
                            elseif ch == 36 then
                                local tmp = {}
                                for i = 1, M.HAND do tmp[i] = own.hand[i] end
                                for i = 1, M.HAND do own.hand[i] = other.hand[i] end
                                for i = 1, M.HAND do other.hand[i] = tmp[i] end
                            elseif ch == 37 then
                                draw_hand(m, s)
                            elseif ch == 38 then
                                local left = amt
                                local i = 1
                                while i <= M.HAND and left > 0 do
                                    if other.hand[i] >= 0 then
                                        other.hand[i] = -1
                                        left = left - 1
                                    end
                                    i = i + 1
                                end
                            elseif ch == 39 then
                                -- equalize hulls: both to the average, rounded down
                                local avg = (m.seat[1].hull + m.seat[2].hull) // 2
                                m.seat[1].hull = avg
                                m.seat[2].hull = avg
                            elseif ch == 40 then
                                -- chronobreak: back to the hull held at the start of this round
                                if m.roundStartHull[s] > 0 then own.hull = m.roundStartHull[s] end
                            elseif ch == 41 then
                                local use = (own.energy < amt) and own.energy or amt
                                own.energy = own.energy - use
                                own.armor = own.armor + use
                            elseif ch == 42 then
                                own.burn = 0
                                own.burnRounds = 0
                            elseif ch == 43 then
                                if own.vault < 0 then own.vault = 0 end
                            else
                                raise(m, s, ch)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function end_of_round_dots(m)
    for s = 1, 2 do
        local st = m.seat[s]
        local b = 0
        if st.burnRounds > 0 and st.burn > 0 then
            b = st.burn
            st.burnRounds = st.burnRounds - 1
            if st.burnRounds <= 0 then
                st.burnRounds = 0
                st.burn = 0
            end
        end
        m.lastBurn[s] = b
        st.hull = st.hull - b
        if st.regenRounds > 0 and st.regen > 0 then
            local h = st.hull + st.regen
            st.hull = (h > Rules.startHull()) and Rules.startHull() or h
            st.regenRounds = st.regenRounds - 1
            if st.regenRounds <= 0 then
                st.regenRounds = 0
                st.regen = 0
            end
        end
    end
end

-- BEGIN: the clock, the roll, the economy, the deal and DISABLE.
--
-- Split from the exchange so a policy can choose from the hand it will ACTUALLY play. That is not a
-- stylistic preference: SHANKPIT's sequencer used to pick before the deal, so it read the previous
-- round's hand (and, on a fresh match, four zero slots -- meaning round 1 played a card neither seat
-- held). The C and this file shared the shape and the bug; the parity vectors found it in both.
-- Returns true when there is nothing left to play (over, or the round cap just closed the match).
function M.beginRound(m)
    if m.over then return true end
    if m.started then return true end
    if m.round >= Rules.maxRounds() then
        m.over = true
        m.winner = Rules.roundWinner(m.seat[1].hull, m.seat[2].hull, m.seat[1].vault, m.seat[2].vault) + 1
        return true
    end

    m.round = m.round + 1
    m.roundsPlayed = m.roundsPlayed + 1
    m.roll = next_rng(m) % 100

    -- Start of round: energy refills and banks, credits accrue, hands are dealt, chronobreak
    -- remembers the hull it has to be able to restore.
    for s = 1, 2 do
        local st = m.seat[s]
        local en = Rules.roundStartEnergy(st.energy) + st.pendingEnergy
        st.pendingEnergy = 0
        st.energy = (en < 0) and 0 or en
        if st.energy > 6 then st.energy = 6 end
        st.vault = Rules.roundStartVault(st.vault)
        m.roundStartHull[s] = st.hull
        draw_hand(m, s)
        -- DISABLE is applied AFTER the deal: the mechanic is "you were dealt a hand you cannot use".
        if st.disabledNext > 0 then
            local n = st.disabledNext
            if n > M.HAND then n = M.HAND end
            for i = 1, n do st.hand[i] = -1 end
            st.disabledNext = 0
        end
        if st.blindRounds > 0 then st.blindRounds = st.blindRounds - 1 end
    end

    m.started = true
    return false
end

-- FINISH: the declared cards, every effect channel, and the end of the match. `card0`/`card1` are card
-- ids or -1 to pass; an illegal card is treated as a pass (the rules say it cannot be played, and the
-- sequencer must not invent a different card). Returns true when the match ended on this round.
function M.finishRound(m, card0, card1)
    m.started = false

    local card = { card0, card1 }
    for s = 1, 2 do
        local st = m.seat[s]
        card[s] = Rules.cardSubstitute(card[s], m.roll)
        if card[s] >= 0 and not Rules.isLegalPlay(card[s], st.energy, st.vault) then
            card[s] = -1 -- unplayable is a pass, never a different card
        end
    end
    for s = 1, 2 do
        local st = m.seat[s]
        local credit = 0
        if card[s] >= 0 then credit = Rules.cardCredit(card[s]) end
        st.energy = Rules.energyAfterPlay(st.energy, card[s])
        st.vault = st.vault - credit
        if card[s] >= 0 then
            local k = Rules.cardKind(card[s])
            m.kindPlays[k + 1] = m.kindPlays[k + 1] + 1
        end
    end

    local fx = { new_fx(), new_fx() }
    for s = 1, 2 do
        fx[s].card = card[s]
        fx[s].oppCard = card[3 - s]
        fx[s].energyLeft = m.seat[s].energy
    end

    -- Pass A: cancels and flags, before any damage exists.
    phase1(m, fx, 0)
    for s = 1, 2 do
        local opp = 3 - s
        if fx[s].cancel then
            fx[opp].card = -1
            fx[opp].oppCard = fx[s].card
            card[opp] = -1
        end
    end

    -- COPY (08): play the opponent's declared card instead. Resolved AFTER the cancels, because a
    -- cancel makes the opponent's card "treated as a pass" and a copy of a pass is a pass.
    for s = 1, 2 do
        local opp = 3 - s
        if fx[s].copy then
            fx[s].card = fx[opp].card
            card[s] = fx[s].card
            fx[opp].oppCard = fx[s].card
        end
    end

    -- The exchange, as the rules compute it (triangle only; riders are the fx words).
    for s = 1, 2 do fx[s].dealt = Rules.damageDealt(card[s], card[3 - s]) end
    for s = 1, 2 do fx[s].taken = fx[3 - s].dealt end

    -- Pass B: the riders that change the damage itself.
    phase1(m, fx, 1)

    local dealt = { 0, 0 }
    for s = 1, 2 do
        local d = fx[s].dealt
        if fx[s].bypassFloor > d then d = fx[s].bypassFloor end -- channel 03: at least AA lands
        dealt[s] = d
    end
    for s = 1, 2 do
        local receiver = m.seat[3 - s]
        local d = dealt[s]
        if fx[3 - s].immune then d = 0 end -- the receiver is immune: nothing lands
        if not fx[s].ignoreArmor and not fx[s].trueDamage and d > 0 then
            local use = (receiver.armor < d) and receiver.armor or d
            receiver.armor = receiver.armor - use
            d = d - use
        end
        if fx[1].halve or fx[2].halve then d = d // 2 end
        m.lastDamage[3 - s] = d -- damage seat s deals is TAKEN by the other seat
        receiver.hull = receiver.hull - d
        -- reflect returns damage to the attacker
        if fx[3 - s].reflect > 0 and not fx[s].bypassNoReflect then
            m.seat[s].hull = m.seat[s].hull - fx[3 - s].reflect
            m.lastDamage[s] = m.lastDamage[s] + fx[3 - s].reflect
        end
    end

    phase2(m, fx)
    end_of_round_dots(m)

    -- Lifeline: survive lethal at 1 hull (checked after everything that could have killed it).
    for s = 1, 2 do
        if fx[s].lifeline and m.seat[s].hull <= 0 then m.seat[s].hull = 1 end
    end

    m.lastCard[1] = card[1]
    m.lastCard[2] = card[2]

    -- ---- the match ends by hull, by bankruptcy, or by the round cap ----
    local b0 = Rules.bankrupt(m.seat[1].vault)
    local b1 = Rules.bankrupt(m.seat[2].vault)
    if b0 or b1 then
        m.over = true
        if b0 and b1 then
            m.winner = Rules.roundWinner(m.seat[1].hull, m.seat[2].hull,
                                         m.seat[1].vault, m.seat[2].vault) + 1
        elseif b0 then
            m.winner = 2
        else
            m.winner = 1
        end
        return true
    end
    if Rules.matchDecided(m.seat[1].hull, m.seat[2].hull) then
        m.over = true
        m.winner = Rules.roundWinner(m.seat[1].hull, m.seat[2].hull,
                                     m.seat[1].vault, m.seat[2].vault) + 1
        return true
    end
    if m.round >= Rules.maxRounds() then
        m.over = true
        m.winner = Rules.roundWinner(m.seat[1].hull, m.seat[2].hull,
                                     m.seat[1].vault, m.seat[2].vault) + 1
        return true
    end
    return false
end

-- One round in one call: begin, then finish with the cards the caller named. A scripted caller (a
-- replay, a test, a UI that showed the hand and took a click) uses this; the policy uses the halves.
function M.round(m, card0, card1)
    if M.beginRound(m) then return true end
    return M.finishRound(m, card0, card1)
end

-- ONE round, both seats choosing through the citizen policy (cp_pick) with its own aggression
-- (0..1000). This is the seam a WATCHED match needs: one round per clock tick, and the exact same
-- game as one that resolves instantly -- nothing about a match depends on how fast it is read.
function M.stepPolicy(m, aggression0, aggression1)
    -- BEGIN first: a policy that chose before the deal would be reading the wrong hand.
    if M.beginRound(m) then return true end
    local aggr = { aggression0, aggression1 }
    local pick = { -1, -1 }
    for s = 1, 2 do
        local st = m.seat[s]
        local oppLast = m.lastCard[3 - s]
        local oppKind = -1
        if oppLast >= 0 then oppKind = Rules.cardKind(oppLast) end
        local sc = { 0, 0, 0, 0 }
        local ids = { -1, -1, -1, -1 }
        for i = 1, M.HAND do
            local c = st.hand[i]
            ids[i] = c
            if c < 0 then
                sc[i] = 0
            else
                local legal = 1
                if not Rules.isLegalPlay(c, st.energy, st.vault) then legal = 0 end
                sc[i] = Policy.cpCardScore(Rules.cardKind(c), Rules.cardPower(c), Rules.cardCost(c),
                    legal, oppKind, aggr[s])
            end
        end
        pick[s] = Policy.cpPick(sc[1], sc[2], sc[3], sc[4], ids[1], ids[2], ids[3], ids[4])
    end
    return M.finishRound(m, pick[1], pick[2])
end

-- Plays a whole match with both seats choosing through the policy. Returns the winner
-- (-1 if it could not finish).
function M.playOut(m, aggression0, aggression1)
    local guard = Rules.maxRounds() + 1
    while not m.over and guard > 0 do
        guard = guard - 1
        if M.stepPolicy(m, aggression0, aggression1) then break end
    end
    if m.over then return m.winner end
    return -1
end

-- The sixteen cards a seat's deck is built from -- THE SAME FUNCTION a citizen's deck comes from, so
-- a player's deck answers the meta the way the population's do rather than being a fixed hand-in.
function M.craftDeck(path, lean, metaKind, metaShare)
    local deck = {}
    for i = 0, M.DECK - 1 do
        deck[i + 1] = Policy.cpDeckCard(i, path, lean, metaKind, metaShare)
    end
    return deck
end

return M
