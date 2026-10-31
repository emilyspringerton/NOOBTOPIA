#!/usr/bin/env bash
# gen_rules.sh -- emit NOOBTOPIA's Luau rules from PARENA. THIS IS THE GLUE.
#
# The decisions are not written in Lua. They are written once, in PARENA, and emitted twice:
#
#   PARENA/stdlib/noobtopia/ambient_life.prn --> src/generated/ambient_life.lua  (Roblox talks)
#                                             --> SHANKPIT/packages/simulation/ambient_life.c
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
"$parena_bin" build "$parena_dir/stdlib/noobtopia/arena_rules.prn"  -o "$root/src/generated/arena_rules.lua"
echo "regenerated src/generated/{ambient_life,arena_rules}.lua"
