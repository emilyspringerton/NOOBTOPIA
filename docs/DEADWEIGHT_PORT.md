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
3. ~~The Roblox surface.~~ **DONE (2026-11-03, founder: "byukd the roblox ui and rating in the c ladder").**
   `src/deadweight_room.lua` (seats, the 45-second offer cycle, ONE prompt, decline, `frame()`),
   `src/deadweight_ui.lua` (a tabletop with a `ProximityPrompt` and a server-written `ScreenGui`) and
   `src/deadweight_server.lua` (one ladder and one table per server, a `Heartbeat` tick, a frame per
   player). A `RemoteEvent` was deliberately NOT used: a client firing one is a client-trusted input,
   and the only thing the design needs from the player is "I pressed the thing at the table".
   Three facts worth keeping:
   * the prompt is ONE button with three branches (not seated ⇒ sit, an offer waiting ⇒ accept,
     otherwise ⇒ challenge the nearest rating), because a server Script cannot see a click;
   * the rating moved into the LADDER in the same change (`member.rating`, one zero-sum delta applied
     by the single recorder every finished match goes through, carried by the save) — the board is now
     a VIEW, not a second copy of the number, and SHANKPIT's `dw_rating.c` comes from the same `.prn`;
   * **a citizen pid must be non-negative.** `Ladder.memberForPid` answers -1 below zero (the C's own
     "-1 means nobody"), so the server's original negative citizen pids produced bodies at the table
     that were invisible to the ladder: unranked, unchallengeable, every press `busy`. Citizens now
     mint from `1e12 + i`, `Room.join` refuses a negative pid, and `start` asserts each one landed.
   **Still not run:** `deadweight_ui.lua`/`deadweight_server.lua` need Studio, and there is no
   DataStore — a per-server board that resets with the server is the accepted design.
4. **The internet of SHANKPIT.** `SHANKPIT/packages/simulation/dw_net.c` publishes the ladder as schema-1
   JSON and WOTAN's `/shankpit-citizens.html` reads it. If Roblox's ladder is meant to be visible on the
   same page, it has to publish the same schema — one contract, two producers, and a schema bump touches
   both repos at once.

4. ~~A tournament stage.~~ **DONE (2026-11-03, founder: "can we make a stage for esports tournoments
   inside of noobtopia").** `src/deadweight_tournament.lua` is a fold-seeded bracket over the ladder's own
   rating order (`Board.rows`), with byes for a short field, every match played through
   `Ladder.challenge`/`accept` so a stage result IS a ladder result, and draws advanced by seed order.
   `deadweight_room` wires it (the world plays its own bracket but never a match a person is in; the
   prompt's third branch is "Press E to play your stage match"), `deadweight_ui` builds the platform,
   podiums, stands and banner, and `deadweight_server` opens the next bracket when three members exist
   and leaves the champion up for a minute. `lua tests/deadweight_tournament_test.lua` — 56 checks.
   *Not done:* it has never been rendered (Studio), it is best-of-one with no losers' bracket or
   spectator camera.
   **Published (2026-11-03, founder: "publish the stage")**, and publishing it is what closed a real
   duplication: SHANKPIT needed a bracket too, so the FOLD moved to
   `PARENA/stdlib/deadweight/stage.prn` and is emitted to both worlds
   (`dw_stage_rules.c` / `src/generated/deadweight_stage.lua`). The world's own bracket
   (`SHANKPIT/packages/simulation/dw_stage.c`) is published through `dw_net` schema 3 and drawn on
   WOTAN's Citizens page. This module still owns the Roblox stage (seats, offers, the prompt); the two
   share the arithmetic and nothing else, because a Roblox server and a SHANKPIT world are different
   populations.

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
