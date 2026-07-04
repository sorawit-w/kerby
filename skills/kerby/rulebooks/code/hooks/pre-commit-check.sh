#!/bin/bash
# V14 shim: the pre-commit check is base's floor enforcer (secrets-staged owns the
# script); code's hollow-test-heuristic rides the same scan. This shim keeps code's
# declaration folder-confined (E04) while executing the base-owned floor script.
#
# Resolution: `code` extends `base` (the floor rides along from the host install), so
# the real target is the host floor's pre-commit-check.sh. In the builtin layout base
# is code's sibling and the relative path below resolves it. `kerby install` never
# runs this shim at commit time — it follows the shim to base's RESOLVED absolute path
# and registers THAT (shared-script dedup, base-first); see SKILL.md § install.
#
# The relative sibling only dangles when `code` is relocated away from its co-shipped
# base (a remote/copied code fork under .kerby/rulebooks/<id>/). base is a warn-level
# soft heuristic (gap: "runtime fakes stay agent-judged"), and the secret-scan FLOOR
# is unaffected — base's secrets-staged registers base's own path directly, not via
# this shim. So on a missing floor script we degrade honestly (exit 0, non-blocking),
# never a cryptic exit 127 and never a hard commit block for a soft check.
target="$(dirname "$0")/../../base/hooks/pre-commit-check.sh"
if [ ! -x "$target" ]; then
  echo "kerby: base floor hook not found beside this rulebook (${target}); hollow-test heuristic degrades to behavioral — load 'code' into a kerby install that provides base." >&2
  exit 0
fi
exec "$target" "$@"
