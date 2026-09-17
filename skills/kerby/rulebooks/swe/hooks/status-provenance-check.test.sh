#!/bin/bash
# Self-test for status-provenance-check.sh — zero-framework, self-contained.
#
# Run from anywhere: bash status-provenance-check.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.
#
# Every case runs inside a fresh `git init` fixture so the index-vs-working-tree
# distinction is real, not simulated: the hook's whole reason to exist is that
# the STAGED file is what a commit records.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/status-provenance-check.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/.kerby" "$REPO/sub"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name t
mkdir -p "$REPO/src"; printf "x\n" > "$REPO/src/other.ts"; git -C "$REPO" add src/other.ts; git -C "$REPO" commit -q -m "seed other"

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

# 1. Not a commit → exit 0 regardless of state.
printf '%s' "$DIRTY_ISSUE" > "$REPO/.kerby/STATUS.md"; git -C "$REPO" add .kerby/STATUS.md
allows 'git status' "a non-commit command is ignored even with a dirty STATUS staged"

# 2. Staged STATUS.md with an issue number → blocked, and the message names line + token.
blocks 'git commit -m "x"' "staged STATUS.md naming #54 is blocked"
echo "$ERR" | grep -q 'states a PR/issue number' && pass "block names the token kind" || fail "block message lacks the token kind: $ERR"
echo "$ERR" | grep -q '\.kerby/STATUS\.md:3 ' && pass "block names the file and line, not the temp path" || fail "block message lacks .kerby/STATUS.md:3: $ERR"
echo "$ERR" | grep -q '^BLOCKED:' && pass "block opens with BLOCKED:" || fail "no BLOCKED: line"

# 3. Staged clean STATUS.md → allowed. Commit it so later cases have a HEAD.
printf '%s' "$CLEAN" > "$REPO/.kerby/STATUS.md"; git -C "$REPO" add .kerby/STATUS.md
allows 'git commit -m "x"' "staged clean STATUS.md is allowed"
git -C "$REPO" commit -q -m "clean baseline"

# 4. Nothing staged → allowed.
allows 'git commit -m "x"' "nothing staged → allowed"

# 5. Working tree dirty, index clean, plain commit → the INDEX is what commits → allowed.
printf '%s' "$DIRTY_PR" > "$REPO/.kerby/STATUS.md"
allows 'git commit -m "x"' "dirty working tree over a clean index is allowed for a plain commit"

# 6. …but `-a` commits the working tree → blocked.
blocks 'git commit -am "x"' "git commit -am scans the working tree and blocks PR 7552"
blocks 'git commit --all -m "x"' "git commit --all scans the working tree"
# 7. …and a pathspec naming the file commits the working tree → blocked.
blocks 'git commit .kerby/STATUS.md -m "x"' "pathspec commit of STATUS.md scans the working tree"

# 7b. Pathspecs are RESOLVED, not text-matched (independent-review P1): a directory,
#     `.`, `:/`, and a relative path from a subdirectory all reach STATUS.md;
#     a pathspec that does not cover it records nothing of the file.
blocks 'git commit .kerby -m "x"' "directory pathspec .kerby commits the working-tree STATUS.md → blocked"
blocks 'git commit . -m "x"' "pathspec . commits the working-tree STATUS.md → blocked"
blocks 'git commit :/ -m "x"' "magic pathspec :/ commits the working-tree STATUS.md → blocked"
blocks 'git commit ../.kerby -m "x"' "relative pathspec from a subdirectory resolves to STATUS.md → blocked" sub
blocks 'git commit -m "x" -- .kerby/STATUS.md' "pathspec after -- is honoured → blocked"
printf 'y\n' > "$REPO/src/other.ts"
allows 'git commit src/other.ts -m "x"' "pathspec that does not cover STATUS.md records nothing of it → allowed"
allows 'git commit -m "x" src/other.ts' "pathspec after the message, not covering STATUS.md → allowed"
# -i/--include: the named paths are refreshed AND the index is recorded.
printf '%s' "$CLEAN" > "$REPO/.kerby/STATUS.md"
allows 'git commit --include src/other.ts -m "x"' "--include other with a clean index → allowed"
printf '%s' "$DIRTY_ISSUE" > "$REPO/.kerby/STATUS.md"; git -C "$REPO" add .kerby/STATUS.md; printf '%s' "$CLEAN" > "$REPO/.kerby/STATUS.md"
blocks 'git commit --include src/other.ts -m "x"' "--include other still records the dirty index STATUS.md → blocked"
blocks 'git commit -i src/other.ts -m "x"' "-i short form, same → blocked"
git -C "$REPO" reset -q .kerby/STATUS.md; printf '%s' "$DIRTY_PR" > "$REPO/.kerby/STATUS.md"
blocks 'git commit -m "unbalanced src/other.ts' "an unbalanced quote is undecidable → both sources scanned → blocked"
printf 'x\n' > "$REPO/src/other.ts"; printf '%s' "$CLEAN" > "$REPO/.kerby/STATUS.md"

# 7c. Second independent-review round: redirections are not pathspecs, -p/--interactive
#     scan both sources, --pathspec-from-file contributes pathspecs, --no-all negates.
printf '%s' "$DIRTY_ISSUE" > "$REPO/.kerby/STATUS.md"; git -C "$REPO" add .kerby/STATUS.md; printf '%s' "$CLEAN" > "$REPO/.kerby/STATUS.md"
blocks 'git commit -m "x" >/dev/null 2>&1' "attached redirections do not turn a plain commit into a pathspec commit → index scanned → blocked"
blocks 'git commit -m "x" > /dev/null' "a bare redirection operator consumes its target → index scanned → blocked"
blocks 'git commit --all --no-all -m "x"' "--no-all negates --all → index recorded → blocked"
blocks 'git commit -F - <<'"'"'EOF'"'"'
fix: something
EOF' "a heredoc is undecidable → both sources scanned → blocked"
git -C "$REPO" reset -q .kerby/STATUS.md; printf '%s' "$DIRTY_PR" > "$REPO/.kerby/STATUS.md"
allows 'git commit --all --no-all -m "x"' "--all --no-all with a clean index → allowed"
blocks 'git commit -p -m "x"' "-p picks worktree hunks → both sources scanned → blocked"
blocks 'git commit --interactive -m "x"' "--interactive picks worktree hunks → blocked"
printf '.kerby/STATUS.md\n' > "$REPO/paths.txt"
blocks 'git commit --pathspec-from-file=paths.txt -m "x"' "--pathspec-from-file naming STATUS.md → worktree scanned → blocked"
blocks 'git commit --pathspec-from-file paths.txt -m "x"' "--pathspec-from-file with a separate value → blocked"
printf 'src/other.ts\n' > "$REPO/paths.txt"
allows 'git commit --pathspec-from-file=paths.txt -m "x"' "--pathspec-from-file naming only other paths → allowed"
blocks 'git commit --pathspec-from-file=- -m "x"' "--pathspec-from-file=- (stdin) is undecidable → both scanned → blocked"
rm -f "$REPO/paths.txt"; printf '%s' "$CLEAN" > "$REPO/.kerby/STATUS.md"

# 8. Index dirty, working tree clean → plain commit records the INDEX → blocked.
printf '%s' "$DIRTY_ISSUE" > "$REPO/.kerby/STATUS.md"; git -C "$REPO" add .kerby/STATUS.md
printf '%s' "$CLEAN" > "$REPO/.kerby/STATUS.md"
blocks 'git commit -m "x"' "clean working tree over a dirty index is blocked (the index commits)"
# `-a` here re-stages the clean working tree → allowed.
allows 'git commit -a -m "x"' "git commit -a with a clean working tree is allowed"

# 9. Commit from a subdirectory still finds the file.
blocks 'git commit -m "x"' "commit from a subdirectory still scans the staged STATUS.md" sub

# 10. --amend with nothing staged → allowed (not an index bypass).
git -C "$REPO" reset -q .kerby/STATUS.md
allows 'git commit --amend --no-edit' "--amend with nothing staged is allowed"

# 11. Guard script missing → visible fail-open: exit 0 + additionalContext naming it.
FAKE="$TMP/fake/hooks"; mkdir -p "$FAKE"; cp "$HOOK" "$FAKE/status-provenance-check.sh"
printf '%s' "$DIRTY_ISSUE" > "$REPO/.kerby/STATUS.md"; git -C "$REPO" add .kerby/STATUS.md
json=$(jq -n --arg c 'git commit -m "x"' '{tool_input:{command:$c}}')
OUT=$(cd "$REPO" && printf '%s' "$json" | bash "$FAKE/status-provenance-check.sh" 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && pass "missing guard → exit 0 (fail open)" || fail "missing guard → exit $rc"
echo "$OUT" | jq -e '.hookSpecificOutput.additionalContext | test("NOT checked")' >/dev/null 2>&1 \
  && pass "missing guard → visible additionalContext warning" || fail "missing guard → no warning JSON: $OUT"

# 12. A repo with no .kerby/STATUS.md at all → allowed.
git -C "$REPO" reset -q .kerby/STATUS.md; rm -f "$REPO/.kerby/STATUS.md"
allows 'git commit -m "x"' "no STATUS.md → allowed"

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
