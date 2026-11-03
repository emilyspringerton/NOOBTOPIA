# DEADWEIGHT in NOOBTOPIA — the port, in phases

Written 2026-11-03 at the start of the port, so the next session starts from the real state. The rule this
repo already follows holds here: **PARENA is the glue.** A number lives in one `.prn` and is emitted twice
— to C for SHANKPIT, to Luau for Roblox — and neither world keeps its own copy.

## What is ported (phase 0, done)

| Piece | Where it came from | State |
|---|---|---|
| The 105-card rules: kinds, the triangle, costs/powers/credits, the packed fx engine, match constants | `PARENA/stdlib/deadweight/card_rules.prn` | `src/generated/deadweight_rules.lua` — generated, committed, 68 functions |
| The citizen policy: win rate, identity, the answer to a meta, card scoring, deck crafting | `PARENA/stdlib/deadweight/citizen_policy.prn` | `src/generated/deadweight_policy.lua` — generated, committed |
| A real interpreter check | — | `lua tests/deadweight_test.lua` — **287 checks, 0 failed** |
| The sequencer: a whole match, round by round | `SHANKPIT/packages/simulation/dw_match.c` (hand-written in both worlds) | `src/deadweight_game.lua` — data only, no `workspace` |
| The match fixture both worlds assert | — | `PARENA/stdlib/deadweight/match_parity.txt` — `lua tests/deadweight_match_test.lua` **903 checks, 0 failed**, 117 rounds across 5 matches |

Both generated files are emitted by `scripts/gen_deadweight.sh`. SHANKPIT emits the SAME two `.prn` files to C
(`packages/simulation/dw_rules.c`, `dw_citizen_rules.c`), so the parity test here and `make test-deadweight`
there are two ends of one claim. If they ever disagree, the `.prn` is right.

Paid for along the way: PARENA's Lua target gained `let` (an IIFE, so sequences of scoped bindings stay one
expression) and a named refusal for statement forms it cannot express — before that, `(do ...)` emitted
`M.do(...)`, which no test noticed until a real interpreter ran it.

## What is NOT ported, in the order it makes sense to do it

1. ~~The sequencer.~~ **DONE (2026-11-03).** `src/deadweight_game.lua` is the game: 20 hull, 2 energy
   (+2/round capped 6, +1 for passing), 3 credits (+1/round), 4-card hands, all 32 effect channels in
   both phases, bankruptcy below -6, the 100-round draw. It is driven by the generated rules and holds
   no copy of a number. The *Done when* was met as specified: `PARENA/stdlib/deadweight/match_parity.txt`
   holds five whole matches (seed, each seat's deck-crafting inputs, aggression, and every round's cards,
   hulls, energy, credits and damage), written AND read by SHANKPIT's `dw_match_parity_test.c`
   (`make test-dw-parity` / `make regen-dw-parity`) and asserted here by
   `tests/deadweight_match_test.lua`. **Two real bugs came out of that comparison, one in each world,**
   and both are worth remembering as the class of thing this fixture is for:
   * PARENA's Lua emitter lowered `if` to `(cond and then or else)`, so a FALSE branch inside a nested
     Bool ladder fell through into the next `or` — `fx-cond-ok` answered true whenever the ladder's own
     final `roll >= PP` test passed. Fixed in `src/emit_lua.c` (an IIFE: `if c then return A else
     return B end`), which is what made the rules identical in both worlds at all.
   * SHANKPIT's sequencer chose each seat's card BEFORE the round dealt, so it read the previous hand --
     and on a fresh match, four zero-filled slots, so round 1 played card 0, a card neither seat held.
     Both sequencers now split a round into BEGIN (clock, economy, deal, DISABLE) and FINISH, with the
     policy choosing in between. The C fix is in `dw_match.c`.
2. ~~The ladder.~~ **DONE (2026-11-03).** `src/deadweight_ladder.lua` ports `dw_ladder.c`: one
   `challenge` call for all four directions, the 45-second challenge book with its expiry sweep, records,
   the population's meta, decks re-crafted after every match, and `serialize`/`deserialize` as plain
   tables (a DataStore's shape rather than SHANKPIT's text file). `PARENA/stdlib/deadweight/
   ladder_parity.txt` carries the SCRIPT as well as the outcomes and both worlds execute it, so the
   fixture cannot drift by one side re-typing the scenario: `make test-dw-ladder-parity` and
   `lua tests/deadweight_ladder_test.lua` (107 checks). Two design facts worth keeping:
   * a member that has NOT played since the meta moved keeps the deck it was dealt — the same staleness
     the C ladder has — so the round-trip asserts byte-identical decks for the members who played and
     determinism of the crafting function for everyone;
   * `dw_ladder_tick`'s citizen-initiated challenges draw from the ladder's own LCG in a fixed order, so
     the script that exercises them is deterministic and is pinned here.
2b. ~~The Roblox-facing consumer (the leaderboard).~~ **DONE (2026-11-03)** — `src/deadweight_board.lua`:
   a per-server board ranked by `PARENA/stdlib/deadweight/rating.prn` (emitted to Luau, not copied),
   resetting with the server, with `rows`/`rowFor`/`snapshot` and a bounded match ticker. It is the
   CONSUMER half of the internet-of-SHANKPIT shim in the shape Roblox can actually use — the founder's
   own "per server and reset its fine", and "we dont need iduna i guess just the leaderboard for now".
3. **The ladder.** (superseded by 2 above — kept so the numbering below still reads) `dw_ladder.c` owns challenges in four directions, records, the meta tally and decks that
   re-craft from both. In Roblox this is DataStore-shaped rather than process-shaped, and the honest
   question is whether a citizen's record should be per-place-session or persistent across places. Decide it
   before writing it; the deck crafting itself is already here (the policy).
3. **The Roblox surface.** A Noob sitting down at a table (a `ProximityPrompt`), a `RemoteEvent` for
   challenge/accept/decline, and a board GUI reading the same fields the phone shows in SHANKPIT: round,
   both hulls, both energies, and the last few rounds as kind/tier/power. This is the first piece that
   touches `workspace` — it belongs in `src/noobtopia.lua`'s family, not in a rules module.
4. **The internet of SHANKPIT.** `SHANKPIT/packages/simulation/dw_net.c` publishes the ladder as schema-1
   JSON and WOTAN's `/shankpit-citizens.html` reads it. If Roblox's ladder is meant to be visible on the
   same page, it has to publish the same schema — one contract, two producers, and a schema bump touches
   both repos at once.

## Named risks

- **Luau numbers are doubles.** Rules that rely on 32-bit integer overflow would differ here. The card ids,
  permilles and hull arithmetic are all small, but any future rule that multiplies into the 2^31 range must
  be checked on both sides — this is exactly the class of bug the seed mixer already had (`CHANGELOG`,
  2026-10-31), and the reason parity vectors exist rather than good intentions.
- **`bit32` in Luau vs the emitter's operator table.** The rules use arithmetic and comparisons, not bit
  ops, so nothing depends on it today. A future fx word that packs bits must be emitted as Lua bit
  operations deliberately, not by hoping the operator table covers it.
- **Plain Lua 5.4 is not Luau.** The tests here run on 5.4; integer width and library availability differ.
  Parity vectors are arithmetic-exact in both, which is the only claim being made.
