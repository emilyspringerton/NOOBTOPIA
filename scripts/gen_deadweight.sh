#!/usr/bin/env bash
# gen_deadweight.sh -- emit DEADWEIGHT's Luau from PARENA. THIS IS THE GLUE, and it is the whole point:
# the card game is not being rewritten in Lua. Its rules and its citizen policy already exist once, in
# PARENA, and are emitted TWICE:
#
#   PARENA/stdlib/deadweight/card_rules.prn     --> src/generated/deadweight_rules.lua   (this repo)
#                                               --> SHANKPIT/packages/simulation/dw_rules.c (the C game)
#   PARENA/stdlib/deadweight/citizen_policy.prn --> src/generated/deadweight_policy.lua  (this repo)
#                                               --> SHANKPIT/packages/simulation/dw_citizen_rules.c
#
# So 105 cards, the kind triangle, every cost/power/credit and the deck-crafting thresholds are edited
# in exactly one place and Roblox follows the C game. If this output and SHANKPIT's C ever disagree,
# the .prn is right and the copy is the bug (see ../docs/THREE_WAY_MERGE.md).
#
# Usage: scripts/gen_deadweight.sh            (needs a sibling ../PARENA with .parena-bootstrap, or PARENA_DIR)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
parena_dir="${PARENA_DIR:-$root/../PARENA}"

if [ -x "$parena_dir/.parena-bootstrap" ]; then
    parena_bin="$parena_dir/.parena-bootstrap"
elif [ -x "$parena_dir/parena" ]; then
    parena_bin="$parena_dir/parena"
else
    echo "gen_deadweight: no parena binary at $parena_dir (build it with: cd ../PARENA && make .parena-bootstrap)" >&2
    exit 1
fi

mkdir -p "$root/src/generated"
"$parena_bin" build "$parena_dir/stdlib/deadweight/card_rules.prn" \
    -o "$root/src/generated/deadweight_rules.lua"
"$parena_bin" build "$parena_dir/stdlib/deadweight/citizen_policy.prn" \
    -o "$root/src/generated/deadweight_policy.lua"
"$parena_bin" build "$parena_dir/stdlib/deadweight/rating.prn" \
    -o "$root/src/generated/deadweight_rating.lua"
# The BRACKET's arithmetic -- the same .prn SHANKPIT emits to dw_stage_rules.c, so the Roblox stage
# and the world's own stage pair a field identically instead of each keeping a fold.
"$parena_bin" build "$parena_dir/stdlib/deadweight/stage.prn" \
    -o "$root/src/generated/deadweight_stage.lua"

# The emitter writes nothing on a construct it cannot express (no partial file), so a missing output is
# the real failure signal -- parena's own exit code is not enough, which this check makes explicit.
for f in deadweight_rules.lua deadweight_policy.lua deadweight_rating.lua deadweight_stage.lua; do
    if [ ! -s "$root/src/generated/$f" ]; then
        echo "gen_deadweight: $f was not produced (an unsupported PRN form, not a silent pass)" >&2
        exit 1
    fi
done
echo "regenerated src/generated/{deadweight_rules,deadweight_policy,deadweight_rating,deadweight_stage}.lua"
