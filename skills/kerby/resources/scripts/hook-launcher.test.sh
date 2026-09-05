#!/bin/bash
# Self-test for hook-launcher.sh — the user-local launcher `kerby install`
# copies to ~/.claude/kerby/bin/hook. Properties under test:
#   - resolves the install root at run time (KERBY_DIR, else the pointer file)
#   - passes stdin, args and the exit code through to the target untouched
#   - fails OPEN and VISIBLY when the root or target is gone: exit 0 plus one
#     message on the channel the event actually reads (JSON additionalContext
#     for PreToolUse, plain stdout for SessionStart, stderr for git-hook)
#   - confines relpath to the root (no absolute, no `..`)
#   - runs under POSIX sh with no jq on PATH
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

# A PATH holding only what the launcher and the fixture need — and no jq.
SBIN="$TMP/bin"; mkdir -p "$SBIN"
for t in sh sed cat; do ln -s "$(command -v "$t")" "$SBIN/$t"; done
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
printf '#!/bin/sh\ntouch "%s/ran"\n' "$TMP" > "$ROOT/mark.sh"; chmod +x "$ROOT/mark.sh"
PTR="$HOME_T/.claude/kerby/install-root"

run() { HOME="$HOME_T" PATH="$SBIN" KERBY_DIR= sh "$L" "$@"; }

# 0. POSIX syntax, and the sandbox really has no jq.
sh -n "$L" && pass "launcher parses under sh -n" || fail "launcher fails sh -n"
PATH="$SBIN" command -v jq >/dev/null 2>&1 && fail "sandbox PATH still has jq" || pass "sandbox PATH has no jq"

# 1. No pointer, PreToolUse → JSON additionalContext naming the gap; exit 0; stderr empty.
OUT=$(printf '{}' | run PreToolUse rulebooks/x/hooks/echo.sh 2>"$TMP/err"); rc=$?
[[ $rc -eq 0 ]] && pass "no pointer: exit 0" || fail "no pointer: exit $rc"
echo "$OUT" | grep -q '^{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"kerby: .*no pointer.*"}}$' \
  && pass "no pointer: JSON additionalContext on stdout" || fail "no pointer: unexpected stdout: $OUT"
[[ ! -s "$TMP/err" ]] && pass "no pointer: stderr empty" || fail "no pointer: stderr not empty"

# 2. Pointer set, target missing → JSON names relpath and root.
printf '%s\n' "$ROOT" > "$PTR"
OUT=$(printf '{}' | run PreToolUse rulebooks/x/hooks/nope.sh); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'nope.sh not found under install root' && echo "$OUT" | grep -qF "$ROOT" \
  && pass "missing target: names relpath and root, exit 0" || fail "missing target: $rc / $OUT"

# 3. Passthrough: stdin, args and exit code reach the target untouched.
OUT=$(printf 'in' | run PreToolUse rulebooks/x/hooks/echo.sh a b); rc=$?
[[ $rc -eq 3 && "$OUT" == "in a b" ]] && pass "passthrough: stdin, args, exit code" || fail "passthrough: rc=$rc out=$OUT"

# 4. KERBY_DIR overrides a dead pointer.
printf '%s\n' "$TMP/dead" > "$PTR"
OUT=$(printf 'in' | HOME="$HOME_T" PATH="$SBIN" KERBY_DIR="$ROOT" sh "$L" PreToolUse rulebooks/x/hooks/echo.sh); rc=$?
[[ $rc -eq 3 ]] && pass "KERBY_DIR overrides the pointer" || fail "KERBY_DIR override: rc=$rc"
printf '%s\n' "$ROOT" > "$PTR"

# 5. git-hook mode, missing target → stderr only, exit 0.
OUT=$(run git-hook rulebooks/x/hooks/nope.sh --git-hook 2>"$TMP/err"); rc=$?
[[ $rc -eq 0 && -z "$OUT" ]] && grep -q '^kerby: ' "$TMP/err" \
  && pass "git-hook: message on stderr, stdout empty, exit 0" || fail "git-hook: rc=$rc out=$OUT err=$(cat "$TMP/err")"

# 6. SessionStart mode, missing target → plain stdout, not JSON.
OUT=$(run SessionStart rulebooks/x/hooks/nope.sh 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q '^kerby: ' && ! echo "$OUT" | grep -q '^{' \
  && pass "SessionStart: plain stdout line" || fail "SessionStart: rc=$rc out=$OUT"

# 7. relpath confinement: absolute, `..`, and empty are refused; the target never runs.
for r in '../x' '/abs' 'rulebooks/x/hooks/../../../mark.sh' ''; do
  OUT=$(printf '{}' | run PreToolUse "$r"); rc=$?
  [[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'refusing relpath' \
    && pass "refuses relpath '$r'" || fail "did not refuse relpath '$r': rc=$rc out=$OUT"
done
[[ ! -e "$TMP/ran" ]] && pass "confined: escaped target never ran" || fail "confined: escaped target RAN"

# 8. Target present but 0644 → fail-open message (mirrors the -x doctrine).
OUT=$(printf '{}' | run PreToolUse rulebooks/x/hooks/noexec.sh); rc=$?
[[ $rc -eq 0 ]] && echo "$OUT" | grep -q 'noexec.sh not found under install root' \
  && pass "non-executable target: fail-open message" || fail "non-executable target: rc=$rc out=$OUT"

# 9. The root path with a space resolved (case 3 ran against it).
pass "install root containing a space resolves"

# 10. Ownership marker.
grep -q '^# kerby-managed:launcher' "$L" && pass "ownership marker present" || fail "ownership marker missing"

echo "---"
if [[ "$FAILS" -eq 0 ]]; then echo "All assertions passed."; exit 0; else echo "$FAILS assertion(s) failed."; exit 1; fi
