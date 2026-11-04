#!/usr/bin/env bash
# gen_rules.sh -- emit NOOBTOPIA's Luau rules from PARENA. THIS IS THE GLUE.
#
# The decisions are not written in Lua. They are written once, in PARENA, and emitted twice:
#
#   PARENA/stdlib/noobtopia/ambient_life.prn --> src/generated/ambient_life.lua  (Roblox talks)
#                                             --> SHANKPIT/packages/simulation/ambient_life.c
#   PARENA/stdlib/noobtopia/walk_rules.prn   --> src/generated/walk_rules.lua    (where it drifts, and when)
#                                             --> SHANKPIT/packages/simulation/walk_rules.c
#   PARENA/stdlib/noobtopia/arena_rules.prn  --> src/generated/arena_rules.lua   (combat + slippery physics)
#                                             --> SHANKPIT/packages/simulation/arena_rules.c
#
# So a cooldown or a friction value is edited in exactly one place and both worlds follow. If this file and the C
# ever disagree, the .prn is right and the copy is the bug. See MONOREPO/docs/THREE_WAY_MERGE.md.
#
# Usage: scripts/gen_rules.sh   (needs a sibling ../PARENA checkout with .parena-bootstrap, or PARENA_DIR)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
parena_dir="${PARENA_DIR:-$root/../PARENA}"

if [ -x "$parena_dir/.parena-bootstrap" ]; then
    parena_bin="$parena_dir/.parena-bootstrap"
elif [ -x "$parena_dir/parena" ]; then
    parena_bin="$parena_dir/parena"
else
    echo "gen_rules: no parena binary at $parena_dir (build it with: cd ../PARENA && make .parena-bootstrap)" >&2
    exit 1
fi

mkdir -p "$root/src/generated"
"$parena_bin" build "$parena_dir/stdlib/noobtopia/ambient_life.prn" -o "$root/src/generated/ambient_life.lua"
"$parena_bin" build "$parena_dir/stdlib/noobtopia/walk_rules.prn"   -o "$root/src/generated/walk_rules.lua"
"$parena_bin" build "$parena_dir/stdlib/noobtopia/arena_rules.prn"  -o "$root/src/generated/arena_rules.lua"

# The ENGINE upgrades, which live in stdlib/shankpit/ because SHANKPIT owns the engine and this repo consumes it:
# the environment matrix (weather/time/fog/ambient resolved into one state) and the material vocabulary (what a
# surface is, as a function of the tick). Both were emitted to C long ago; this is the other half of the merge.
"$parena_bin" build "$parena_dir/stdlib/shankpit/lighting_rules.prn" -o "$root/src/generated/lighting_rules.lua"
"$parena_bin" build "$parena_dir/stdlib/shankpit/material_rules.prn" -o "$root/src/generated/material_rules.lua"
# ...and the SKY: day/night, what each weather does to the light, and how far you can see through fog.
"$parena_bin" build "$parena_dir/stdlib/shankpit/sky_rules.prn" -o "$root/src/generated/sky_rules.lua"
# ...and the COSY verbs: kicking a dandelion, hugging a tree. Nothing here can hurt anything.
"$parena_bin" build "$parena_dir/stdlib/shankpit/cozy_rules.prn" -o "$root/src/generated/cozy_rules.lua"

echo "regenerated src/generated/{ambient_life,walk_rules,arena_rules,lighting_rules,material_rules,sky_rules,cozy_rules}.lua"
