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

Both files are emitted by `scripts/gen_deadweight.sh`. SHANKPIT emits the SAME two `.prn` files to C
(`packages/simulation/dw_rules.c`, `dw_citizen_rules.c`), so the parity test here and `make test-deadweight`
there are two ends of one claim. If they ever disagree, the `.prn` is right.

Paid for along the way: PARENA's Lua target gained `let` (an IIFE, so sequences of scoped bindings stay one
expression) and a named refusal for statement forms it cannot express — before that, `(do ...)` emitted
`M.do(...)`, which no test noticed until a real interpreter ran it.

## What is NOT ported, in the order it makes sense to do it

1. **The sequencer.** `dw_match.c` in SHANKPIT is the game: 20 hull, 2 energy (+2/round capped 6, +1 for
   passing), 3 credits (+1/round), 4-card hands, 32 effect channels, bankruptcy below -6, 100-round draw.
   A Luau port belongs here as `src/deadweight_game.lua` — a DATA module (state transitions only, no
   `workspace`), the same layering `src/wander.lua` and `src/big_o_witness.lua` already use. It must be
   driven by the generated rules, never by its own copy of a number.
   *Done when:* the SAME seed, deck pair and per-round plays produce identical hull/energy/credit numbers
   here and in SHANKPIT — which means a **parity vector file** (`PARENA/stdlib/deadweight/match_parity.txt`,
   the convention `walk_parity.txt` already set) that both suites assert.
2. **The ladder.** `dw_ladder.c` owns challenges in four directions, records, the meta tally and decks that
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
