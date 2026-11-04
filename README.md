# NOOBTOPIA

Autonomous noob life for Roblox — and the data half of a three-way merge.

Three repos, one world (see [`../docs/THREE_WAY_MERGE.md`](../docs/THREE_WAY_MERGE.md)):

| Repo | Role |
|---|---|
| **BIG_O** | the IP: witnessing, decorum, the campaign |
| **SHANKPIT** | the agile implementation: the engine those systems run on |
| **NOOBTOPIA** | the data and the Roblox surface: what a noob *says*, and a cheap place to try an interaction |

**PARENA is the glue.** Rules that both worlds must agree on are written once, in a `.prn`, and emitted twice — to C
for SHANKPIT, to Luau for this repo. Nothing here restates a threshold.

## Quick start

```bash
# emit this repo's Luau rules from PARENA (needs a sibling ../PARENA checkout)
scripts/gen_rules.sh
# -> src/generated/ambient_life.lua, src/generated/arena_rules.lua   (committed; regenerate after editing a .prn)

# ...and DEADWEIGHT's card rules + citizen policy, the same two .prn SHANKPIT compiles to C
scripts/gen_deadweight.sh
# -> src/generated/deadweight_rules.lua, deadweight_policy.lua, deadweight_rating.lua, deadweight_stage.lua

# tests (plain Lua, no Roblox needed)
lua tests/ambient_test.lua
lua tests/walk_test.lua
lua tests/lighting_test.lua             # the environment matrix, parity against the C in SHANKPIT
lua tests/material_test.lua             # reflection / light styles / tints, same parity fixtures
lua tests/deadweight_test.lua          # the rules + the citizen policy (287)
lua tests/deadweight_match_test.lua    # whole matches vs SHANKPIT's C (903, 117 rounds)
lua tests/deadweight_ladder_test.lua   # the ladder, script and all (107)
lua tests/deadweight_board_test.lua    # the per-server leaderboard + its Elo (65)
lua tests/deadweight_room_test.lua     # the table: seats, offers, one prompt (55)
lua tests/deadweight_tournament_test.lua  # the esports stage: seeding, byes, champion (56)
```

In Roblox: put `src/noobtopia.lua` in `ServerScriptService`, `src/ambient.lua`, `src/big_o_witness.lua` and
`src/generated/*.lua` beside it as ModuleScripts, `data/noob_lines.lua` too, and a rig named `Noob` in
`ReplicatedStorage`. Add a **RemoteEvent named `Punch`** in `ReplicatedStorage` and fire it from a LocalScript on
click (that three-line client script is the ONE piece this repo does not ship — a server Script cannot see a click).
The host warns in the output if the RemoteEvent is missing, so the gap announces itself instead of failing quietly.

## What it does

- **Ambient talking** — the original script's 20 lines, now categorised (greeting / question / banter / complaint /
  self) and scheduled by PARENA (`ambient_life.prn`): moods pick the category, the surface of the rules decides the
  cooldown, so a crowd does not chant in unison.
- **Wandering** — where a noob drifts, and when, is `walk_rules.prn`: a shared idle timer per mood, one of 8 compass
  headings, a leg length, and a leash it may not leave. A startled noob is *frozen* (0 permille, a state rather than a
  slow speed), a curious one pauses least and roams furthest. The C host in SHANKPIT integrates with the identical
  integer rule, and both sides assert the same `walk_parity.txt` vectors.
- **Slippery physics** — movement is a speed integrated by `arena_rules.prn`'s own `stepSpeed`/`slideDecay`, per
  surface. Ice keeps you moving and barely lets you accelerate; concrete starts and stops hard. The same numbers
  drive SHANKPIT's own C build, so this is the game's physics, not Roblox's.
- **Combat** — fists / bat / pistol / rocket: damage, knockback, cooldown, distance falloff on to-hit, all from the
  same rules file.
- **BIG_O's witness rule** — a noob killed in front of others leaves witnesses. One or two go into denial and say so;
  five or more stop pretending and turn on the killer; a compromised witness helps cover it up. `big_o_witness.lua`
  is the IP's first system ported to Roblox.

## Files

| Path | What |
|---|---|
| `src/noobtopia.lua` | the Roblox host — the only file that touches `workspace` |
| `src/ambient.lua` | data-facing helpers (grouping, speak); decisions delegated to PARENA |
| `src/wander.lua` | where a noob drifts, and when; same integer integration SHANKPIT's C host runs |
| `src/big_o_witness.lua` | BIG_O's witness/decorum rule, pure |
| `src/generated/*.lua` | **generated** from PARENA — never edit by hand |
| `src/generated/deadweight_rules.lua` | DEADWEIGHT's 105-card rules, emitted from `PARENA/stdlib/deadweight/card_rules.prn` |
| `src/generated/deadweight_policy.lua` | the citizen policy (win rate, the answer to a meta, deck crafting) |
| `src/deadweight_game.lua` | the **sequencer** — a match, round by round; ported from SHANKPIT's `dw_match.c` |
| `src/deadweight_ladder.lua` | challenges in all four directions, records, the meta, decks that re-craft |
| `src/deadweight_board.lua` | the **per-server leaderboard** — a ranked view over the ladder's own ratings |
| `src/deadweight_room.lua` | the table: seats, the offer cycle, ONE prompt, and the `frame()` a GUI draws |
| `src/deadweight_tournament.lua` | **the esports stage**: a fold-seeded bracket over the ladder's ratings |
| `src/deadweight_ui.lua` | the tabletop, the `ProximityPrompt`, and the server-written board panel |
| `src/deadweight_server.lua` | the glue: one ladder + one table per server, the tick, a frame per player |
| `src/generated/deadweight_rating.lua` | the shared rating, emitted from `PARENA/stdlib/deadweight/rating.prn` |
| `src/generated/deadweight_stage.lua` | the shared **bracket arithmetic** (fold, size, draw tie-break), emitted from `PARENA/stdlib/deadweight/stage.prn` |
| `tests/deadweight_test.lua` | hand-derived parity checks against those two modules (287 assertions) |
| `tests/deadweight_match_test.lua` | whole matches against the shared fixture (903 assertions, 117 rounds) |
| `tests/deadweight_ladder_test.lua` | the ladder, executing the shared script (107 assertions) |
| `tests/deadweight_board_test.lua` | the leaderboard, the zero-sum Elo and the per-server reset (65 assertions) |
| `tests/deadweight_room_test.lua` | the table's seats, offers, single prompt and stage wiring (55 assertions) |
| `tests/deadweight_tournament_test.lua` | the stage: seeding, byes, draws, champion (56 assertions) |
| `docs/DEADWEIGHT_PORT.md` | what is ported and what is not, in order |

## What is wired now (2026-11-03)

The two engine upgrades reach the engine. `src/noobtopia.lua` -- still the only file that touches a service -- now,
on a 0.25 s tick:

- publishes its weather through attributes on `workspace` or `Lighting` (`SHANKPIT_cover`, `_rain`, `_storm`,
  `_fog_wash`, `_visibility`, `_ambient_level`, `_flash`, `_interior`), resolves ONE scene through
  `src/lighting.lua`, and writes `Lighting.Ambient`, `OutdoorAmbient` and `Brightness`. `FogEnd` is written only
  when the place published a visibility reading, because "no fog reading" is not "zero fog";
- classifies parts by name (mirror / metal / glass, else nothing) or by an explicit `SHANKPIT_Surface` attribute,
  and writes `BasePart.Reflectance` from `src/material.lua` (mirror 0.9, metal 0.38, glass 0.32);
- drives any `PointLight` carrying `SHANKPIT_LightStyle` (0..7) at 60 Hz ticks, so a strobe really strobes.

The deciding lives in `src/wiring.lua`, which is duck-typed and tested under plain Lua (`tests/wiring_test.lua`,
55 checks): it says WHICH keys to write, reports what it left alone (`kept_fog`), and leaves the host with nothing
but a `Color3` wrapper.

**A bug this last mile found, in the module rather than the wiring:** `Lighting.roblox()` clamped brightness to
1.0, but the matrix's exposure runs 1000..1936 permille -- it LIFTS the low end -- so the clamp silently deleted the
entire compensation term and handed a storm the same brightness as a clear sky. It is now clamped to the Lighting
service's own range (0..3), and both suites pin that a dimmed world gets MORE than 1.0.

**The sky is wired too** (same day): the host holds a clock and a weather (`SHANKPIT_minutes`, `SHANKPIT_weather`),
advances it at `MINUTES_PER_SECOND` pacing, and `src/sky.lua` asks `sky_rules.prn` for the sun, each weather's
intensities and the visibility through fog. The sun goes to `Lighting.ClockTime` and to `OutdoorAmbient` only — the
matrix's legibility floor still governs indoor light, so night is dark outside without making a match unreadable.
A place that publishes `SHANKPIT_cover`/`_rain`/... overrides just that field; `wiring.mergeSky` is what keeps a
reading and a default distinguishable.

Still unverified: **none of this has run in a place.** No Studio here, and `src/noobtopia.lua` is Luau (it uses
`+=`), so it cannot even be syntax-checked on this box -- the numbers and the assignment decisions are tested, the
assignment itself is not.

Placement: `src/wiring.lua`, `src/lighting.lua` and `src/material.lua` go beside `src/noobtopia.lua`, with the
generated modules under `src/generated/`.

## DEADWEIGHT (2026-11-03)

SHANKPIT plays DEADWEIGHT — a card game where citizens challenge each other, challenge you, and build their
own decks from their win rate and the current meta. **The rules are not being rewritten for Roblox.** The
same two `.prn` files that SHANKPIT emits to C are emitted here to Luau by `scripts/gen_deadweight.sh`:
105 cards, the kind triangle, every cost/power/credit, the packed effect engine, and the policy that picks
cards and crafts decks. `lua tests/deadweight_test.lua` runs the real numbers (287 checks) and pins the same
values SHANKPIT's `make test-deadweight` pins — start hull 20 / energy 2 / credits 3, four-card hands, 100
rounds, the base line's tier→cost table, the triangle's antisymmetry, and the policy's 500/666 win-rate
smoothing.

**The sequencer is here too** (2026-11-03): `src/deadweight_game.lua` plays a whole match — 20 hull,
the round economy, 4-card hands off a 16-card deck, all 32 effect channels in both phases, bankruptcy,
and the 100-round draw — as a data module with no `workspace` in it. The sequencer is the one piece still
hand-written per world, so it is pinned by DATA: `PARENA/stdlib/deadweight/match_parity.txt` holds five
whole matches and **both** SHANKPIT's `make test-dw-parity` and `lua tests/deadweight_match_test.lua`
assert the same rows (117 rounds, every card, hull, energy and credit). Writing it found a real bug in
each world, both fixed: the emitter's `if` lowering mangled Bool ladders, and SHANKPIT's policy chose
its card before the round dealt.

**The ladder and a leaderboard are here too** (same day): `src/deadweight_ladder.lua` is the port of
SHANKPIT's `dw_ladder.c` — one `challenge` call for all four directions, a 45-second challenge TTL,
records, the population's meta, and decks that re-craft after every match — pinned the same way, by a
fixture that carries the *script* as well as the outcomes so both worlds execute the same operations
(107 checks). `src/deadweight_board.lua` is the Roblox-side consumer: **a per-server leaderboard** that
ranks the ladder by a rating and resets with the server (the founder's own "per server and reset its
fine"), with no IDUNA and no HTTP — the number is `PARENA/stdlib/deadweight/rating.prn`, emitted here
rather than copied, so SHANKPIT and Roblox print the same table for the same server.

**The table is here too** (same day, founder: *"byukd the roblox ui and rating in the c ladder"*):
`src/deadweight_room.lua` holds the seats, a 45-second offer cycle where a citizen at the table asks
you to play, and ONE `ProximityPrompt` that sits you down, takes a waiting offer, or challenges the
citizen nearest your rating; `src/deadweight_ui.lua` draws the tabletop and a server-written panel;
`src/deadweight_server.lua` ties one ladder and one table to one server. The rating itself moved INTO
the ladder (`member.rating`, zero-sum through the one recorder every finished match goes through, and
carried by the save), so the board is a view rather than a second copy of the number — and SHANKPIT's
C ladder carries the same number from the same `.prn` (`dw_rating.c`), which is the only way two
worlds print the same table.

**And a stage to play it on**: `src/deadweight_tournament.lua` seeds a bracket from the ladder's own
rating, gives a short field byes instead of a smaller bracket, and plays every match through the
same `challenge`/`accept` path a friendly game takes — so a stage result moves both ratings and
lands on the ticker. The world plays its own bracket on its own clock but never a match a person
is in (that one waits for the prompt), and a drawn match advances the higher seed, because a
bracket needs a body. `src/deadweight_ui.lua` builds the platform, podiums, stands and banner.

What is NOT here yet, deliberately and in order: **none of the Roblox files has ever run** (no
Studio, no place file, no `luau` on this box — written and reviewed, never executed), no DataStore (a
per-server board resetting with the server is the accepted design), publishing this board in the
schema WOTAN reads, and drawing the match itself on the table.
`docs/DEADWEIGHT_PORT.md` has the phases and the two real risks (Luau's doubles, and 5.4 not being Luau).
| `data/noob_lines.lua` | the words. **Source of truth** for every line, in both worlds |
| `tests/ambient_test.lua` | plain-Lua test of the rules, the data and the witness rule |
| `tests/walk_test.lua` | plain-Lua test of the walk rule against the shared `walk_parity.txt` vectors |
| `noobtopia.lua`, `_.js`, `package.json` | the original single-file script and its JS stub, kept for the record |

## Regenerating

- **Words** — edit `data/noob_lines.lua`, then in SHANKPIT run `scripts/gen_ambient_lines.sh`; C picks the lines up
  from there. No second copy exists.
- **Rules** — edit `PARENA/stdlib/noobtopia/*.prn`, then `scripts/gen_rules.sh` here *and*
  `SHANKPIT/scripts/gen_noobtopia_rules.sh` (for the C). If the edit changes a walk threshold, update
  `PARENA/stdlib/noobtopia/walk_parity.txt` too — both test suites assert it.

## Honest status

DEADWEIGHT's rules, policy, sequencer, ladder, leaderboard and the Roblox table are generated and
executed here (287 + 903 + 107 + 65 + 55 + 56 checks under a real Lua, the match and ladder halves against
fixtures SHANKPIT's C asserts too), but the game is not *playable* here yet: **the three Roblox files
have never run** — they need Studio — and the leaderboard is not published anywhere outside its own
server. `docs/DEADWEIGHT_PORT.md` says so phase by phase.

The Luau modules are **executed** — `lua tests/ambient_test.lua` and `lua tests/walk_test.lua` run clean on Lua 5.4,
and the walk half is pinned against parity vectors the C asserts too. That is plain Lua, not Luau: 5.4 has 64-bit
integers where Roblox has doubles, which is how the seed-mixer bug in `ambient.lua` was found (see
`../docs/THREE_WAY_MERGE.md` §3b) and why `wander.lua` uses an exactly-representable mixer.

Still unverified: **Roblox itself** — no Studio, no place file, no publishing, and `src/noobtopia.lua` (the host that
touches `workspace`) has never run inside a place.
