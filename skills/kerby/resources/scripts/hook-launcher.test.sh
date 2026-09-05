#!/bin/bash
# Self-test for hook-launcher.sh — the user-local launcher `kerby install`
# copies to ~/.claude/kerby/bin/hook. Properties under test:
#   - resolves the install root at run time from the pointer file ONLY
#     (KERBY_DIR and every other env var are ignored — a project settings file
#     can set env for its hooks)
#   - passes stdin, args and the exit code through to the target untouched
#   - fails OPEN and VISIBLY when the root or target is gone or cannot be
#     launched: exit 0 plus exactly one message on the channel the event reads
#     (valid JSON additionalContext for PreToolUse, plain stdout for
#     SessionStart, stderr for git-hook)
#   - confines relpath to the root: no absolute, no `..`, no symlinked
#     directory that resolves outside
#   - tolerates a CRLF pointer, a symlinked root, an unset HOME
#   - runs under POSIX sh (dash too, when present) with no jq on PATH
#
# Run from anywhere: bash hook-launcher.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
L="$SCRIPT_DIR/hook-launcher.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A PATH holding only what the launcher and the fixtures need — and no jq.
SBIN="$TMP/bin"; mkdir -p "$SBIN"
for t in sh sed cat tr; do ln -s "$(command -v "$t")" "$SBIN/$t"; done
HOME_T="$TMP/home"; mkdir -p "$HOME_T/.claude/kerby"
# The install root deliberately contains a space (a real Desktop-app path does).
ROOT="$TMP/inst root"; mkdir -p "$ROOT/rulebooks/x/hooks"
cat > "$ROOT/rulebooks/x/hooks/echo.sh" <<'FIX'
#!/bin/sh
in=$(cat)
printf '%s %s\n' "$in" "$*"
exit 3
FIX
chmod +x "$ROOT/rulebooks/x/hooks/echo.sh"
printf '#!/bin/sh\nexit 0\n' > "$ROOT/rulebooks/x/hooks/noexec.sh"; chmod 644 "$ROOT/rulebooks/x/hooks/noexec.sh"
printf '#!/nonexistent/interp\nexit 0\n' > "$ROOT/rulebooks/x/hooks/badinterp.sh"; chmod +x "$ROOT/rulebooks/x/hooks/badinterp.sh"
printf '#!/bin/sh\ntouch "%s/ran"\n' "$TMP" > "$ROOT/mark.sh"; chmod +x "$ROOT/mark.sh"
# An escape via a symlinked directory inside the root.
mkdir -p "$TMP/outside"; printf '#!/bin/sh\ntouch "%s/ran-outside"\n' "$TMP" > "$TMP/outside/x.sh"; chmod +x "$TMP/outside/x.sh"
ln -s "$TMP/outside" "$ROOT/rulebooks/esc"
PTR="$HOME_T/.claude/kerby/install-root"
setptr() { printf '%s\n' "$1" > "$PTR"; }

run() { HOME="$HOME_T" PATH="$SBIN" sh "$L" "$@"; }
# Is a string valid JSON? Uses python3 when present; otherwise a shape check.
is_json() {
  if command -v python3 >/dev/null 2>&1; then python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null
  else grep -q '^{"hookSpecificOutput":{"hookEventName":"[^"]*","additionalContext":"[^"]*"}}$'; fi
}
lines() { printf '%s' "$1" | grep -c ''; }

# 0. POSIX syntax, and the sandbox really has no jq.
sh -n "$L" && pass "launcher parses under sh -n" || fail "launcher fails sh -n"
PATH="$SBIN" command -v jq >/dev/null 2>&1 && fail "sandbox PATH still has jq" || pass "sandbox PATH has no jq"

# 1. No pointer, PreToolUse → one line of valid JSON naming the gap; exit 0; stderr empty.
OUT=$(printf '{}' | run PreToolUse rulebooks/x/hooks/echo.sh 2>"$TMP/err"); rc=$?
[[ $rc -eq 0 ]] && pass "no pointer: exit 0" || fail "no pointer: exit $rc"
printf '%s' "$OUT" | is_json && echo "$OUT" | grep -q '"hookEventName":"PreToolUse"' && echo "$OUT" | grep -q 'no pointer' \
  && pass "no pointer: valid JSON additionalContext on stdout" || fail "no pointer: unexpected stdout: $OUT"
[[ $(lines "$OUT") -eq 1 ]] && pass "no pointer: exactly one line" || fail "no pointer: $(lines "$OUT") lines"
[[ ! -s "$TMP/err" ]] && pass "no pointer: stderr empty" || fail "no pointer: stderr not empty"

# 2. KERBY_DIR is ignored: with no pointer it must not rescue the run.
OUT=$(printf '{}' | HOME="$HOME_T" PATH="$SBIN" KERBY_DIR="$ROOT" sh "$L" PreToolUse rulebooks/x/hooks/echo.sh); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'no pointer' && pass "KERBY_DIR is not consulted" || fail "KERBY_DIR steered the launcher: rc=$rc out=$OUT"

# 3. Pointer set, target missing → JSON names relpath and root.
setptr "$ROOT"
OUT=$(printf '{}' | run PreToolUse rulebooks/x/hooks/nope.sh); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'nope.sh not found under install root' && echo "$OUT" | grep -qF "$ROOT" \
  && pass "missing target: names relpath and root, exit 0" || fail "missing target: $rc / $OUT"

# 4. Passthrough: stdin, args and exit code reach the target untouched.
OUT=$(printf 'in' | run PreToolUse rulebooks/x/hooks/echo.sh a b); rc=$?
[[ $rc -eq 3 && "$OUT" == "in a b" ]] && pass "passthrough: stdin, args, exit code" || fail "passthrough: rc=$rc out=$OUT"

# 5. git-hook mode, missing target → stderr only, exit 0.
OUT=$(run git-hook rulebooks/x/hooks/nope.sh --git-hook 2>"$TMP/err"); rc=$?
[[ $rc -eq 0 && -z "$OUT" ]] && grep -q '^kerby: ' "$TMP/err" && [[ $(grep -c '' "$TMP/err") -eq 1 ]] \
  && pass "git-hook: one message on stderr, stdout empty, exit 0" || fail "git-hook: rc=$rc out=$OUT err=$(cat "$TMP/err")"

# 6. SessionStart mode, missing target → one plain stdout line, not JSON.
OUT=$(run SessionStart rulebooks/x/hooks/nope.sh 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q '^kerby: ' && ! echo "$OUT" | grep -q '^{' && [[ $(lines "$OUT") -eq 1 ]] \
  && pass "SessionStart: one plain stdout line" || fail "SessionStart: rc=$rc out=$OUT"

# 7. relpath confinement: absolute, `..`, and empty are refused; the target never runs.
for r in '../x' '/abs' 'rulebooks/x/hooks/../../../mark.sh' ''; do
  OUT=$(printf '{}' | run PreToolUse "$r"); rc=$?
  [[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'refusing relpath' \
    && pass "refuses relpath '$r'" || fail "did not refuse relpath '$r': rc=$rc out=$OUT"
done
[[ ! -e "$TMP/ran" ]] && pass "confined: escaped target never ran" || fail "confined: escaped target RAN"

# 8. A symlinked directory inside the root that resolves outside is refused.
OUT=$(printf '{}' | run PreToolUse rulebooks/esc/x.sh); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'resolves outside install root' && [[ ! -e "$TMP/ran-outside" ]] \
  && pass "symlinked directory escape refused, target never ran" || fail "symlink escape: rc=$rc out=$OUT ran=$([[ -e "$TMP/ran-outside" ]] && echo yes || echo no)"

# 9. Target present but 0644 → fail-open message (mirrors the -x doctrine).
OUT=$(printf '{}' | run PreToolUse rulebooks/x/hooks/noexec.sh); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'noexec.sh not found under install root' \
  && pass "non-executable target: fail-open message" || fail "non-executable target: rc=$rc out=$OUT"

# 10. Executable target whose interpreter is missing → visible fail-open, not a silent 127.
OUT=$(printf '{}' | run PreToolUse rulebooks/x/hooks/badinterp.sh 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'could not be launched' && printf '%s' "$OUT" | is_json \
  && pass "missing interpreter: visible fail-open, exit 0" || fail "missing interpreter: rc=$rc out=$OUT"

# 11. Control characters and quotes in the relpath still yield one line of valid JSON.
BAD=$(printf 'rulebooks/x/hooks/"bad\\\tname\nmore')
OUT=$(printf '{}' | run PreToolUse "$BAD"); rc=$?
[[ $rc -eq 0 && $(lines "$OUT") -eq 1 ]] && printf '%s' "$OUT" | is_json \
  && pass "quotes/backslash/tab/newline in relpath: one line of valid JSON" || fail "escaping: rc=$rc out=$OUT"

# 12. A CRLF pointer resolves.
printf '%s\r\n' "$ROOT" > "$PTR"
OUT=$(printf 'in' | run PreToolUse rulebooks/x/hooks/echo.sh z); rc=$?
[[ $rc -eq 3 && "$OUT" == "in z" ]] && pass "CRLF pointer tolerated" || fail "CRLF pointer: rc=$rc out=$OUT"

# 13. A symlinked install root resolves (root and target canonicalize together).
ln -s "$ROOT" "$TMP/rootlink"; setptr "$TMP/rootlink"
OUT=$(printf 'in' | run PreToolUse rulebooks/x/hooks/echo.sh y); rc=$?
[[ $rc -eq 3 && "$OUT" == "in y" ]] && pass "symlinked install root resolves" || fail "symlinked root: rc=$rc out=$OUT"
setptr "$ROOT"

# 14. HOME unset → no pointer probe at /.claude, fail-open message, exit 0.
OUT=$(printf '{}' | env -u HOME PATH="$SBIN" sh "$L" PreToolUse rulebooks/x/hooks/echo.sh); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'no pointer' && pass "HOME unset: fail-open, no probe" || fail "HOME unset: rc=$rc out=$OUT"

# 15. The root path with a space resolved (cases 4/12/13 ran against it).
pass "install root containing a space resolves"

# 16. Ownership marker.
grep -q '^# kerby-managed:launcher' "$L" && pass "ownership marker present" || fail "ownership marker missing"

# 17. Under dash, when present: passthrough and the no-pointer message behave the same.
DASH=$(command -v dash || true)
if [[ -n "$DASH" ]]; then
  OUT=$(printf 'in' | HOME="$HOME_T" PATH="$SBIN" "$DASH" "$L" PreToolUse rulebooks/x/hooks/echo.sh d); rc=$?
  [[ $rc -eq 3 && "$OUT" == "in d" ]] && pass "dash: passthrough" || fail "dash passthrough: rc=$rc out=$OUT"
  rm -f "$PTR"
  OUT=$(printf '{}' | HOME="$HOME_T" PATH="$SBIN" "$DASH" "$L" PreToolUse rulebooks/x/hooks/echo.sh); rc=$?
  [[ $rc -eq 0 ]] && printf '%s' "$OUT" | is_json && pass "dash: no-pointer JSON" || fail "dash no-pointer: rc=$rc out=$OUT"
  setptr "$ROOT"
else
  echo "SKIP: dash not installed (not a pass)"
fi

echo "---"
if [[ "$FAILS" -eq 0 ]]; then echo "All assertions passed."; exit 0; else echo "$FAILS assertion(s) failed."; exit 1; fi
