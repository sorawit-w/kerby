#!/bin/bash
# Self-test for hollow-test-check.sh — zero-framework, self-contained.
# swe's soft pre-commit advisory: hollow-test heuristic + lint/test/build reminder.
# This hook does NO secret scanning (base's floor owns that), so no gitleaks stubs
# are needed — a real PATH is enough.
#
# Run from anywhere: bash hollow-test-check.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/hollow-test-check.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Fixture git repo --------------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q

COMMIT_INPUT='{"tool_input":{"command":"git commit -m test"}}'

reset_index() { git -C "$REPO" rm -r --cached -q -f . >/dev/null 2>&1 || true; rm -f "$REPO"/*.js "$REPO"/*.go; }

stage_clean() {
  echo "const port = 3000;" > "$REPO/app.js"
  git -C "$REPO" add app.js
}
stage_secret() {
  # A fake Stripe-style key. This hook must NOT scan for it (that is base's floor).
  echo 'const k = "sk_live_ABCDEFG1234567890fake";' > "$REPO/secret.js"
  git -C "$REPO" add secret.js
}

# Hollow-test fixtures — staged test/spec files exercising the soft heuristic.
stage_test_focus() { # focused test (.only) silently disables the rest of the suite
  printf 'describe.only("x", () => { it("y", () => { expect(sum(1,1)).toBe(2); }); });\n' > "$REPO/widget.test.js"
  git -C "$REPO" add widget.test.js
}
stage_test_true() { # always-true assertion verifies nothing
  printf 'test("hollow", () => { expect(true).toBe(true); });\n' > "$REPO/hollow.spec.js"
  git -C "$REPO" add hollow.spec.js
}
stage_test_clean() { # a real assertion in a test file — must NOT trip the heuristic
  printf 'test("real", () => { expect(sum(2,2)).toBe(4); });\n' > "$REPO/real.test.js"
  git -C "$REPO" add real.test.js
}
stage_nontest_only() { # .only outside a test/spec path — must NOT trip the heuristic
  printf 'foo.only(bar);\n' > "$REPO/config.js"
  git -C "$REPO" add config.js
}
stage_test_chained() { # chained focus marker (Jest/Vitest parameterized): test.only.each
  printf 'test.only.each([[1,1]])("p", (a,b) => { expect(a).toBe(b); });\n' > "$REPO/chained.test.js"
  git -C "$REPO" add chained.test.js
}
stage_test_subdir() { # focused test staged at repo root — committed FROM a subdirectory
  mkdir -p "$REPO/src"
  printf 'describe.only("x", () => { it("y", () => { expect(sum(1,1)).toBe(2); }); });\n' > "$REPO/pkg.test.js"
  git -C "$REPO" add pkg.test.js
}
stage_test_focus_bsd() { # markers caught ONLY by the \b focus branches (no .only/.skip present)
  printf 'fit("a", () => { expect(x).toBe(y); });\nxit("b", () => {});\nfdescribe("c", () => {});\n' > "$REPO/bsd_focus.test.js"
  git -C "$REPO" add bsd_focus.test.js
}
stage_test_misc_bsd() { # \b-dependent markers across langs: t.Skip(, @Disabled, assert True\b
  printf 'func TestX(t *testing.T) { t.Skip("wip") }\n@Disabled\nassert True\n' > "$REPO/bsd_misc_test.go"
  git -C "$REPO" add bsd_misc_test.go
}

# additionalContext for a commit on the current index. $1 = optional value for
# CODING_RULES_HOOK_DISABLED; $2 = optional subdir (under REPO) to run from.
hook_ctx() {
  local disabled="${1:-}" subdir="${2:-}" out
  out=$( cd "$REPO/$subdir" && echo "$COMMIT_INPUT" | CODING_RULES_HOOK_DISABLED="$disabled" bash "$HOOK" 2>/dev/null )
  printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# --- Assertions --------------------------------------------------------------

# A. The lint/test/build reminder is emitted as JSON additionalContext on STDOUT,
#    exit 0, no stderr, no permissionDecision (moved from base's floor in v9.3).
reset_index; stage_clean
ERRF="$TMP/reminder_err"
OUT=$( cd "$REPO" && echo "$COMMIT_INPUT" | bash "$HOOK" 2>"$ERRF" ); rc=$?
CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
DEC=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
ERRTXT=$(cat "$ERRF")
{ [[ "$rc" -eq 0 ]] && printf '%s' "$CTX" | grep -q "REMINDER (kerby)"; } \
  && pass "reminder emitted as JSON additionalContext on stdout" \
  || fail "reminder should be JSON additionalContext (rc=$rc, out='$OUT')"
[[ -z "$DEC" ]] && pass "reminder sets no permissionDecision (no auto-approve)" \
  || fail "reminder must not set permissionDecision (got '$DEC')"
[[ -z "$ERRTXT" ]] && pass "reminder writes nothing to stderr (uses stdout JSON)" \
  || fail "reminder should not write to stderr (got '$ERRTXT')"

# B. Never hard-blocks — always exit 0 (soft check). Even a hollow test commit.
reset_index; stage_test_true
rc=0; ( cd "$REPO" && echo "$COMMIT_INPUT" | bash "$HOOK" >/dev/null 2>&1 ) || rc=$?
[[ "$rc" -eq 0 ]] && pass "soft check always exits 0 (never hard-blocks)" || fail "should exit 0 (got $rc)"

# C. Does NO secret scanning — a staged secret still exits 0 with no block (proves
#    the scan is base's floor, not duplicated here).
reset_index; stage_secret
rc=0; ( cd "$REPO" && echo "$COMMIT_INPUT" | bash "$HOOK" >/dev/null 2>&1 ) || rc=$?
[[ "$rc" -eq 0 ]] && pass "staged secret is NOT scanned here (exit 0, base owns the floor)" \
  || fail "hollow-test hook must not scan secrets (got $rc)"

# D. Non-commit command exits 0 early (no advisory).
reset_index; stage_test_true
OUT=$( cd "$REPO" && echo '{"tool_input":{"command":"git status"}}' | bash "$HOOK" 2>/dev/null )
[[ -z "$OUT" ]] && pass "non-commit command exits 0 early (no advisory)" \
  || fail "non-commit should emit nothing (got '$OUT')"

# E. Disable token `hollow-test-check` silences ALL soft output (reminder + note).
reset_index; stage_test_true
CTX=$(hook_ctx "hollow-test-check")
[[ -z "$CTX" ]] && pass "CODING_RULES_HOOK_DISABLED=hollow-test-check silences the hook" \
  || fail "hollow-test-check token should silence the hook (ctx='$CTX')"

# E2. Legacy token `pre-commit-check` ALSO silences it (additive grace for anyone
#     who disabled the pre-v9.3 base bundle under that name).
reset_index; stage_test_true
CTX=$(hook_ctx "pre-commit-check")
[[ -z "$CTX" ]] && pass "legacy CODING_RULES_HOOK_DISABLED=pre-commit-check still silences the hook" \
  || fail "legacy pre-commit-check token should silence the hook (ctx='$CTX')"

# J. Focused test (.only) in a staged *test* file -> hollow-test advisory fires.
reset_index; stage_test_focus
CTX=$(hook_ctx)
printf '%s' "$CTX" | grep -q "HOLLOW-TEST CHECK" \
  && pass "focused test (.only) triggers hollow-test advisory" \
  || fail "hollow-test advisory should fire on .only (ctx='$CTX')"

# K. Always-true assertion in a staged *spec* file -> advisory fires.
reset_index; stage_test_true
CTX=$(hook_ctx)
printf '%s' "$CTX" | grep -q "HOLLOW-TEST CHECK" \
  && pass "always-true assertion triggers hollow-test advisory" \
  || fail "hollow-test advisory should fire on expect(true).toBe(true) (ctx='$CTX')"

# L. Clean test file with a real assertion -> NO hollow-test advisory (no false positive).
reset_index; stage_test_clean
CTX=$(hook_ctx)
printf '%s' "$CTX" | grep -q "HOLLOW-TEST CHECK" \
  && fail "hollow-test advisory should NOT fire on a real assertion" \
  || pass "clean test file does not trigger hollow-test advisory"

# M. .only in a NON-test file -> NO advisory (path filter scopes to *test*/*spec*).
reset_index; stage_nontest_only
CTX=$(hook_ctx)
printf '%s' "$CTX" | grep -q "HOLLOW-TEST CHECK" \
  && fail "hollow-test advisory should NOT fire outside test/spec files" \
  || pass "non-test file with .only does not trigger advisory"

# N. Chained focus marker (test.only.each / describe.skip.each) -> advisory fires.
reset_index; stage_test_chained
CTX=$(hook_ctx)
printf '%s' "$CTX" | grep -q "HOLLOW-TEST CHECK" \
  && pass "chained focus marker (.only.each) triggers advisory" \
  || fail "advisory should fire on test.only.each (ctx='$CTX')"

# O. Focused test staged at repo root, hook RUN FROM a subdirectory -> still
#    detected. Regression guard for the :(top)-anchored pathspec (a cwd-relative
#    '*test*' would return no diff from src/ and silently miss the file).
reset_index; stage_test_subdir
CTX=$(hook_ctx "" src)
printf '%s' "$CTX" | grep -q "HOLLOW-TEST CHECK" \
  && pass "advisory fires for root test file when committing from a subdir (:(top) pathspec)" \
  || fail "top-anchored pathspec should catch test files regardless of cwd (ctx='$CTX')"

# P. \b-boundary focus markers (fit(/xit(/fdescribe() are counted by the REAL grep the
#    hook uses (/usr/bin/grep on macOS). Proves \b works on stock BSD grep.
reset_index; stage_test_focus_bsd
CTX=$(hook_ctx)
printf '%s' "$CTX" | grep -q "3 focused/disabled" \
  && pass "BSD grep counts fit(/xit(/fdescribe( — 3 \\b focus markers" \
  || fail "BSD grep should count 3 \\b focus markers (ctx='$CTX')"

# Q. \b-dependent markers across languages (t.Skip(, @Disabled, assert True\\b) fire too.
reset_index; stage_test_misc_bsd
CTX=$(hook_ctx)
printf '%s' "$CTX" | grep -q "HOLLOW-TEST CHECK" \
  && pass "BSD grep fires on t.Skip(/@Disabled/assert True (\\b-dependent markers)" \
  || fail "BSD grep should fire on \\b-dependent markers (ctx='$CTX')"

# --- Summary -----------------------------------------------------------------
echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
