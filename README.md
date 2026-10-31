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

# tests (plain Lua, no Roblox needed)
lua tests/ambient_test.lua
lua tests/walk_test.lua
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

The Luau modules are **executed** — `lua tests/ambient_test.lua` and `lua tests/walk_test.lua` run clean on Lua 5.4,
and the walk half is pinned against parity vectors the C asserts too. That is plain Lua, not Luau: 5.4 has 64-bit
integers where Roblox has doubles, which is how the seed-mixer bug in `ambient.lua` was found (see
`../docs/THREE_WAY_MERGE.md` §3b) and why `wander.lua` uses an exactly-representable mixer.

Still unverified: **Roblox itself** — no Studio, no place file, no publishing, and `src/noobtopia.lua` (the host that
touches `workspace`) has never run inside a place.
