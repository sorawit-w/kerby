#!/bin/bash
# Self-test for route-high-stakes.sh — zero-framework, self-contained.
#
# Run from anywhere: bash route-high-stakes.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/route-high-stakes.sh"
BOOTSTRAP="$SCRIPT_DIR/../BOOTSTRAP.md"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

run() { # $1=file path ; sets RC and ERR
  ERR=$(printf '{"tool_input":{"file_path":%s}}' "$(printf '%s' "$1" | jq -R .)" | bash "$HOOK" 2>&1 >/dev/null); RC=$?
}

# --- One positive per globbable §3 category: reminder + exit 0 ----------------
POS=(
  "app/migrations/0001_init.sql"            # schema migrations
  "src/auth/login.ts"                       # authentication (dir glob)
  "src/UserToken.ts"                        # authentication (filename glob *token*)
  "services/payments/charge.go"             # payments
  "infra/main.tf"                           # infrastructure (extension glob)
  "Dockerfile"                              # infrastructure (root Dockerfile*)
  ".github/workflows/ci.yml"                # CI/CD
  "ci/Jenkinsfile"                          # CI/CD
)
for p in "${POS[@]}"; do
  run "$p"
  if [[ "$RC" -eq 0 ]] && echo "$ERR" | grep -q "high-stakes path"; then
    pass "high-stakes triggers reminder: $p"
  else
    fail "should trigger (rc=$RC, err='$ERR'): $p"
  fi
done

# --- Negatives: ordinary paths are silent, exit 0 ----------------------------
NEG=(
  "src/util.ts"
  "README.md"
  "lib/helpers/format.js"
)
for p in "${NEG[@]}"; do
  run "$p"
  if [[ "$RC" -eq 0 && -z "$ERR" ]]; then
    pass "ordinary path silent: $p"
  else
    fail "should be silent exit 0 (rc=$RC, err='$ERR'): $p"
  fi
done

# --- Missing path -> silent exit 0 -------------------------------------------
ERR=$(echo '{"tool_input":{}}' | bash "$HOOK" 2>&1 >/dev/null); RC=$?
[[ "$RC" -eq 0 && -z "$ERR" ]] && pass "missing path silent exit 0" \
  || fail "missing path should be silent (rc=$RC, err='$ERR')"

# --- Disabled via env var -> silent even on a high-stakes path ---------------
ERR=$(printf '{"tool_input":{"file_path":"src/auth/login.ts"}}' | CODING_RULES_HOOK_DISABLED=route-high-stakes bash "$HOOK" 2>&1 >/dev/null); RC=$?
[[ "$RC" -eq 0 && -z "$ERR" ]] && pass "disabled -> silent exit 0" \
  || fail "disabled should be silent (rc=$RC, err='$ERR')"

# --- Glob parity with BOOTSTRAP §3 (teeth-bearing) ---------------------------
# Extract the high-stakes override block, pull every backticked token that looks
# like a glob (contains a '*'), and assert each is embedded verbatim in the hook.
# The prod-traffic-shaping bullet has no backticked globs, so it is naturally and
# correctly excluded — see the COVERAGE GAP note in route-high-stakes.sh.
if [[ ! -f "$BOOTSTRAP" ]]; then
  fail "cannot find BOOTSTRAP.md at $BOOTSTRAP for parity check"
else
  BLOCK=$(sed -n '/High-stakes path override/,/blast radius/p' "$BOOTSTRAP")
  GLOBS_IN_SPEC=$(printf '%s\n' "$BLOCK" | grep -oE '`[^`]+`' | tr -d '`' | grep '\*' | sort -u)
  if [[ -z "$GLOBS_IN_SPEC" ]]; then
    fail "parity: extracted zero globs from §3 — extraction is broken"
  fi
  MISSING=0
  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    if grep -qF "'$g'" "$HOOK"; then
      pass "parity: §3 glob covered: $g"
    else
      fail "parity: §3 glob NOT in hook GLOBS array: $g"
      MISSING=$((MISSING + 1))
    fi
  done <<< "$GLOBS_IN_SPEC"
  [[ "$MISSING" -eq 0 ]] && pass "parity: all §3 globs covered by the hook"
fi

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
