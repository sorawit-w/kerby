#!/bin/bash
# Self-test for status-provenance-check.sh — zero-framework, self-contained.
#
# Run from anywhere: bash status-provenance-check.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.
#
# Every case runs inside a fresh `git init` fixture so the index-vs-working-tree
# distinction is real. The hook scans BOTH copies on every commit, whatever the
# flags, so the cases are about the two copies and the command shapes that once
# fooled a classifier — each of which must now scan, never skip.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/status-provenance-check.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/.kerby" "$REPO/sub" "$REPO/src"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name t
printf "x\n" > "$REPO/src/other.ts"; git -C "$REPO" add src/other.ts; git -C "$REPO" commit -q -m "seed other"

CLEAN='# Project Status

| **Phase** | Feature — null guard in parseUser |
'
DIRTY_ISSUE='# Project Status

| 1 | Fresh-session pass for #54, #56 | none |
'
DIRTY_PR='# Project Status

Position: revision 2 on PR 7552, awaiting review.
'

run() { # $1=command $2=subdir(optional) ; sets RC, ERR, OUT
  local json sub="${2:-}"
  json=$(jq -n --arg c "$1" '{tool_input:{command:$c}}')
  OUT=$(cd "$REPO/$sub" && printf '%s' "$json" | bash "$HOOK" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
blocks() { run "$1" "${3:-}"; [[ "$RC" -eq 2 ]] && pass "$2" || fail "$2 (exit $RC; err: $(echo "$ERR" | head -2 | tr '\n' ' '))"; }
allows() { run "$1" "${3:-}"; [[ "$RC" -eq 0 ]] && pass "$2" || fail "$2 (exit $RC; err: $(echo "$ERR" | head -2 | tr '\n' ' '))"; }
stage()   { printf '%s' "$1" > "$REPO/.kerby/STATUS.md"; git -C "$REPO" add .kerby/STATUS.md; }
worktree(){ printf '%s' "$1" > "$REPO/.kerby/STATUS.md"; }
reset_all(){ git -C "$REPO" reset -q .kerby/STATUS.md 2>/dev/null; rm -f "$REPO/.kerby/STATUS.md"; git -C "$REPO" checkout -q -- .kerby/STATUS.md 2>/dev/null || true; }

# 1. Not a commit → exit 0 regardless of state.
stage "$DIRTY_ISSUE"
allows 'git status' "a non-commit command is ignored even with a dirty STATUS staged"

# 2. Staged copy with an issue number → blocked; the message names copy, line and token.
blocks 'git commit -m "x"' "staged STATUS.md naming #54 is blocked"
echo "$ERR" | grep -q '^BLOCKED: .kerby/STATUS.md (staged)' && pass "block names the staged copy" || fail "block does not name the copy: $ERR"
echo "$ERR" | grep -q 'states a PR/issue number' && pass "block names the token kind" || fail "block message lacks the token kind"
echo "$ERR" | grep -q '\.kerby/STATUS\.md:3 ' && pass "block names the file and line, not the temp path" || fail "block message lacks .kerby/STATUS.md:3"

# 3. Staged clean copy → allowed. Commit it so later cases have a HEAD version.
stage "$CLEAN"
allows 'git commit -m "x"' "staged clean STATUS.md is allowed"
git -C "$REPO" commit -q -m "clean baseline"

# 4. Nothing staged, working tree equal to HEAD → allowed.
allows 'git commit -m "x"' "nothing changed → allowed"

# 5. Working-tree copy dirty (unstaged) → blocked on EVERY command shape: the hook
#    does not guess which copy the commit records.
worktree "$DIRTY_PR"
for cmd in 'git commit -m "x"' 'git commit -am "x"' 'git commit src/other.ts -m "x"' 'git commit --only --amend --no-edit' \
           'git commit --dry-run -m "x"' 'git commit -m ">" .kerby/STATUS.md' 'git commit -m x; echo ok' 'git commit -m x>/dev/null 2>&1' \
           'git commit -m "$(printf x)" src/other.ts' 'git commit -m {x,y}' 'git commit {fd}>out -m x' 'git commit -m \> x' \
           'git commit --inc src/other.ts -m x' 'git commit -uall -m x' 'git commit -p -m x' 'git commit -F - <<EOF
fix: something
EOF'; do
  blocks "$cmd" "working-tree copy naming PR 7552 blocks: $(printf '%s' "$cmd" | head -1 | cut -c1-48)"
done
echo "$ERR" | grep -q '^BLOCKED: .kerby/STATUS.md (working tree)' && pass "block names the working-tree copy" || fail "block does not name the working-tree copy: $ERR"
blocks 'git commit -m "x"' "commit from a subdirectory still finds the file" sub

# 6. Staged copy dirty, working tree restored to HEAD → still blocked (the staged copy).
stage "$DIRTY_ISSUE"; worktree "$CLEAN"
blocks 'git commit -m "x"' "dirty staged copy under a clean working tree is blocked"
blocks 'git commit src/other.ts -m "x"' "…even for a pathspec commit that would not record it (the state itself is forbidden)"
echo "$ERR" | grep -q '(staged)' && pass "the message names the staged copy" || fail "message does not name the staged copy"

# 7. Both copies clean again → allowed, whatever the flags.
reset_all
for cmd in 'git commit -m "x"' 'git commit -am "x"' 'git commit --amend --no-edit -q -v -s -n' 'git commit -m "fix #12 closes PR 3" src/other.ts'; do
  allows "$cmd" "both copies clean → allowed: $cmd"
done

# 8. Type changes: a symlink commits as its target text — staged and in the working tree.
rm -f "$REPO/.kerby/STATUS.md"; ln -s "PR 123" "$REPO/.kerby/STATUS.md"; git -C "$REPO" add .kerby/STATUS.md
blocks 'git commit -m x' "a staged type change (symlink blob) is scanned → blocked"
git -C "$REPO" reset -q .kerby/STATUS.md
blocks 'git commit -a -m x' "a working-tree symlink is scanned as its target text → blocked"
echo "$ERR" | grep -q 'symlink target' && pass "the message names the symlink target" || fail "message does not name the symlink target"
reset_all

# 9. Guard script missing → visible fail-open: exit 0 + additionalContext naming it.
FAKE="$TMP/fake/hooks"; mkdir -p "$FAKE"; cp "$HOOK" "$FAKE/status-provenance-check.sh"
stage "$DIRTY_ISSUE"
json=$(jq -n --arg c 'git commit -m "x"' '{tool_input:{command:$c}}')
OUT=$(cd "$REPO" && printf '%s' "$json" | bash "$FAKE/status-provenance-check.sh" 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && pass "missing guard → exit 0 (fail open)" || fail "missing guard → exit $rc"
echo "$OUT" | jq -e '.hookSpecificOutput.additionalContext | test("NOT checked")' >/dev/null 2>&1 \
  && pass "missing guard → visible additionalContext warning" || fail "missing guard → no warning JSON: $OUT"
reset_all

# 10. A repo with no .kerby/STATUS.md at all → allowed.
git -C "$REPO" rm -q --cached .kerby/STATUS.md; rm -f "$REPO/.kerby/STATUS.md"; git -C "$REPO" commit -q -m "drop status"
allows 'git commit -m "x"' "no STATUS.md → allowed"

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
