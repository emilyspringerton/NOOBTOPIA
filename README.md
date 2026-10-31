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
| `src/big_o_witness.lua` | BIG_O's witness/decorum rule, pure |
| `src/generated/*.lua` | **generated** from PARENA — never edit by hand |
| `data/noob_lines.lua` | the words. **Source of truth** for every line, in both worlds |
| `tests/ambient_test.lua` | plain-Lua test of the rules, the data and the witness rule |
| `noobtopia.lua`, `_.js`, `package.json` | the original single-file script and its JS stub, kept for the record |

## Regenerating

- **Words** — edit `data/noob_lines.lua`, then in SHANKPIT run `scripts/gen_ambient_lines.sh`; C picks the lines up
  from there. No second copy exists.
- **Rules** — edit `PARENA/stdlib/noobtopia/*.prn`, then `scripts/gen_rules.sh` here *and*
  `SHANKPIT/scripts/gen_noobtopia_rules.sh` (for the C).

## Honest status

The Roblox side is **written and reviewed, not executed**: no Lua interpreter or Studio exists on the build machine
that produced it. The rules it calls are executed — SHANKPIT tests the C emitted from the same `.prn`
(`make test-ambient-life`, `make test-noobtopia-arena`) — so the numbers are proven and the host is not. Getting it
into a live place is a separate, later step.
