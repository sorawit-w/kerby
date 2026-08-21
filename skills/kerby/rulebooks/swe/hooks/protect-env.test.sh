#!/bin/bash
# Self-test for protect-env.sh — zero-framework, self-contained.
#
# Run from anywhere: bash protect-env.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/protect-env.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# Real files on disk — the create-if-absent rule is an existence test, so these
# assertions are meaningless against invented paths.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run() { # $1=file_path ; sets RC, ERR
  ERR=$(echo "{\"tool_input\":{\"file_path\":\"$1\"}}" | bash "$HOOK" 2>&1 >/dev/null); RC=$?
}

blocks()  { run "$1"; [[ "$RC" -eq 2 ]] && pass "$2" || fail "$2 (exit $RC)"; }
allows()  { run "$1"; [[ "$RC" -eq 0 ]] && pass "$2" || fail "$2 (exit $RC)"; }

# --- 1. Existing credential files stay hard-blocked -------------------------
: > "$TMP/.env"
blocks "$TMP/.env" "existing .env blocks"

: > "$TMP/.env.local"
blocks "$TMP/.env.local" ".env.local blocks — template-shaped name, real credentials"

: > "$TMP/.env.production"
blocks "$TMP/.env.production" "existing .env.production blocks"

# --- 2. Template carve-out --------------------------------------------------
: > "$TMP/.env.example"
allows "$TMP/.env.example" ".env.example allowed (committed, no secrets)"

: > "$TMP/.env.template"
allows "$TMP/.env.template" ".env.template allowed"

mkdir -p "$TMP/config" && : > "$TMP/config/.env.sample"
allows "$TMP/config/.env.sample" "nested .env.sample allowed"

# The carve-out is anchored on the basename suffix, not a substring.
: > "$TMP/.env.example.bak"
blocks "$TMP/.env.example.bak" "existing .env.example.bak blocks — not a template"

# --- 3. Create-if-absent ----------------------------------------------------
allows "$TMP/does-not-exist/.env" "absent .env allowed (nothing to overwrite)"

: > "$TMP/populated.env"
blocks "$TMP/populated.env" "existing .env file blocks even when absent-path sibling allows"

# --- 4. Relative paths fail closed ------------------------------------------
# Cannot be resolved against the agent's cwd, so an existence test would be a
# guess. Blocking is the safe answer and costs nothing (the tools pass absolute).
blocks ".env" "relative .env blocks (fail closed)"
blocks "some/dir/.env" "relative nested .env blocks (fail closed)"

# --- 5. Non-env files untouched ---------------------------------------------
allows "$TMP/environment.ts" "environment.ts allowed"
allows "$TMP/src/env.ts" "src/env.ts allowed"
allows "$TMP/.environment" ".environment allowed"

# --- 6. Empty payload -------------------------------------------------------
RC=0; echo '{"tool_input":{}}' | bash "$HOOK" >/dev/null 2>&1 || RC=$?
[[ "$RC" -eq 0 ]] && pass "empty file_path exits 0" || fail "empty file_path should exit 0 (got $RC)"

# --- 7. Not disablable ------------------------------------------------------
RC=0
ERR=$(CODING_RULES_HOOK_DISABLED=protect-env \
  bash -c "echo '{\"tool_input\":{\"file_path\":\"$TMP/.env\"}}' | bash '$HOOK'" 2>&1 >/dev/null) || RC=$?
[[ "$RC" -eq 2 ]] \
  && pass "CODING_RULES_HOOK_DISABLED does not disable this hook" \
  || fail "hook must stay non-disablable (exit $RC)"

# --- 8. Block message quality ----------------------------------------------
# The old message sent the agent to DEVELOPER_TODO.md for placeholder vars,
# which routed around the file that actually holds them. Guard the fix.
run "$TMP/.env"
printf '%s' "$ERR" | grep -q "DEVELOPER_TODO" \
  && fail "block message must not point at DEVELOPER_TODO.md for placeholders" \
  || pass "block message does not route placeholders to DEVELOPER_TODO.md"
printf '%s' "$ERR" | grep -q "\.env\.example" \
  && pass "block message names the template file the agent may edit" \
  || fail "block message should name .env.example (got '$ERR')"
printf '%s' "$ERR" | grep -qi "cannot be undone" \
  && pass "block message states why (unrecoverable overwrite)" \
  || fail "block message should state the irreversibility reason"

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
fi
echo "$FAILS assertion(s) failed."
exit 1
