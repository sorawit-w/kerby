#!/usr/bin/env bash
# Tests for scripts/validate-rulebook.py against the .eval/rulebooks fixtures.
# Convention matches the hook tests: pass()/fail() counters, exit non-zero on
# any failure. Run from anywhere: bash scripts/validate-rulebook.test.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VALIDATOR="$REPO_ROOT/skills/kerby/resources/scripts/validate-rulebook.py"
FIXTURES="$REPO_ROOT/.eval/rulebooks"
BUILTIN_ROOT="$FIXTURES/builtin"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

run() { # run <dir> [extra args...] -> sets RC and OUT
  local dir="$1"; shift
  OUT="$(python3 "$VALIDATOR" "$dir" --builtin-root "$BUILTIN_ROOT" "$@" 2>&1)"
  RC=$?
}

# --- Valid fixtures pass -----------------------------------------------------
for dir in "$FIXTURES"/valid-*/; do
  name="$(basename "$dir")"
  run "$dir"
  if [[ "$RC" -eq 0 ]]; then pass "valid fixture accepted: $name"; else fail "valid fixture rejected: $name — $OUT"; fi
done

# The fixture builtin base validates as a builtin
run "$BUILTIN_ROOT/base" --origin builtin
[[ "$RC" -eq 0 ]] && pass "builtin base fixture accepted" || fail "builtin base fixture rejected — $OUT"

# --- Invalid fixtures rejected with their exact catalog code -----------------
for dir in "$FIXTURES"/invalid-E*/; do
  name="$(basename "$dir")"
  code="$(echo "$name" | sed -E 's/invalid-(E[0-9]+).*/\1/')"
  run "$dir"
  if [[ "$RC" -eq 1 ]] && echo "$OUT" | grep -q "$code:"; then
    pass "invalid fixture rejected with $code: $name"
  else
    fail "invalid fixture $name — expected exit 1 + '$code:', got exit $RC: $OUT"
  fi
done

# --- Warn-only paths keep exit 0 ---------------------------------------------
run "$FIXTURES/valid-e11-warn"
if [[ "$RC" -eq 0 ]] && echo "$OUT" | grep -q "warning E11:"; then
  pass "E11 prose-injection lint warns without failing"
else
  fail "E11 — expected exit 0 + 'warning E11:', got exit $RC: $OUT"
fi

# [detect] on a local rulebook warns (builtin-only auto-selection, D19)
TMP_DETECT="$(mktemp -d)"; trap 'rm -rf "$TMP_DETECT" "$TMP_UNREADABLE" 2>/dev/null' EXIT
cp -R "$FIXTURES/valid-minimal/." "$TMP_DETECT/"
printf '\n[detect]\nmarkers = ["package.json"]\n' >> "$TMP_DETECT/rulebook.toml"
run "$TMP_DETECT"
if [[ "$RC" -eq 0 ]] && echo "$OUT" | grep -q "warning E12:"; then
  pass "E12 warns on [detect] from a local rulebook, still valid"
else
  fail "E12 local-detect warn — expected exit 0 + 'warning E12:', got exit $RC: $OUT"
fi

# partial without gap warns, stays valid
TMP_GAP="$(mktemp -d "$TMP_DETECT/gap.XXXX")"
cp -R "$FIXTURES/valid-extends/." "$TMP_GAP/"
python3 - "$TMP_GAP/rulebook.toml" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read().replace('enforcement = "hard"', 'enforcement = "partial"')
open(p, "w").write(s)
EOF
run "$TMP_GAP"
if [[ "$RC" -eq 0 ]] && echo "$OUT" | grep -q "warning E09:"; then
  pass "E09 warns on partial-without-gap, still valid"
else
  fail "E09 gap warn — expected exit 0 + 'warning E09:', got exit $RC: $OUT"
fi

# --- Fail-closed: unreadable declared file -> invalid (generated, not stored) -
TMP_UNREADABLE="$(mktemp -d)"
cp -R "$FIXTURES/valid-minimal/." "$TMP_UNREADABLE/"
chmod 000 "$TMP_UNREADABLE/rules/one-rule.md"
run "$TMP_UNREADABLE"
chmod 644 "$TMP_UNREADABLE/rules/one-rule.md"
if [[ "$RC" -eq 1 ]] && echo "$OUT" | grep -q "E04:"; then
  pass "fail-closed: unreadable declared file is invalid (E04)"
else
  fail "fail-closed — expected exit 1 + E04 on unreadable body, got exit $RC: $OUT"
fi

# --- Hashing: 64-hex, sensitive to declared-file content ----------------------
H1="$(python3 "$VALIDATOR" "$FIXTURES/valid-minimal" --builtin-root "$BUILTIN_ROOT" --hash)"
if echo "$H1" | grep -Eq '^[0-9a-f]{64}$'; then
  pass "--hash prints a sha256 for a valid rulebook"
else
  fail "--hash output not a sha256: $H1"
fi
TMP_HASH="$(mktemp -d "$TMP_DETECT/hash.XXXX")"
cp -R "$FIXTURES/valid-minimal/." "$TMP_HASH/"
printf 'x' >> "$TMP_HASH/rules/one-rule.md"
H2="$(python3 "$VALIDATOR" "$TMP_HASH" --builtin-root "$BUILTIN_ROOT" --hash)"
if [[ -n "$H2" && "$H1" != "$H2" ]]; then
  pass "hash covers declared bodies, not just the manifest"
else
  fail "hash unchanged after mutating a declared body ($H1 vs $H2)"
fi
python3 "$VALIDATOR" "$FIXTURES/invalid-E03-contract" --builtin-root "$BUILTIN_ROOT" --hash >/dev/null 2>&1
[[ $? -eq 1 ]] && pass "--hash refuses an invalid rulebook (fail-closed)" || fail "--hash hashed an invalid rulebook"

# --- Real builtin rulebooks validate and cover the ENGINE-MAP declared set ----
REAL_ROOT="$REPO_ROOT/skills/kerby/resources/rulebooks"
if [[ -d "$REAL_ROOT/base" ]]; then
  for rb in base code; do
    OUT="$(python3 "$VALIDATOR" "$REAL_ROOT/$rb" --origin builtin 2>&1)"; RC=$?
    [[ "$RC" -eq 0 ]] && pass "real builtin rulebook validates: $rb" || fail "real builtin rulebook invalid: $rb — $OUT"
  done
  # Coverage: declared check ids match docs/ENGINE-MAP.md § 9 exactly.
  BASE_IDS="$(grep -E '^id = "' "$REAL_ROOT/base/rulebook.toml" | sed -E 's/id = "(.*)".*/\1/' | tail -n +2 | sort | tr '\n' ' ')"
  CODE_IDS="$(grep -E '^id = "' "$REAL_ROOT/code/rulebook.toml" | sed -E 's/id = "(.*)".*/\1/' | tail -n +2 | sort | tr '\n' ' ')"
  EXPECT_BASE="approval-for-irreversible iron-law-claims no-print-secret secrets-staged untrusted-agent-artifacts "
  EXPECT_CODE="destructive-git env-read-warning guardrails-scope-security high-stakes-routing hollow-test-heuristic operating-rules protect-env protected-branch-commit quality-gate-tiers security-lens verification-before-completion "
  [[ "$BASE_IDS" == "$EXPECT_BASE" ]] && pass "base declares the ENGINE-MAP check set" || fail "base check-set drift — got: $BASE_IDS expected: $EXPECT_BASE"
  [[ "$CODE_IDS" == "$EXPECT_CODE" ]] && pass "code declares the ENGINE-MAP check set" || fail "code check-set drift — got: $CODE_IDS expected: $EXPECT_CODE"
fi

# --- Validator stays stdlib-only ----------------------------------------------
BAD_IMPORTS="$(grep -E '^(import|from) ' "$VALIDATOR" | grep -vE '^(import|from) (argparse|hashlib|sys|tomllib|pathlib)\b')"
if [[ -z "$BAD_IMPORTS" ]]; then
  pass "validator imports are stdlib-only"
else
  fail "non-allowlisted imports in validator: $BAD_IMPORTS"
fi

echo "---"
if [[ "$FAILS" -eq 0 ]]; then echo "All assertions passed."; exit 0; else echo "$FAILS assertion(s) failed."; exit 1; fi
