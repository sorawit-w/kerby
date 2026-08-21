#!/bin/bash
# Self-test for protect-env.sh — zero-framework, self-contained.
#
# Run from anywhere: bash protect-env.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.
#
# Every "alias" case below (symlink, hard link, case-variant) was a real bypass
# found in review, not a hypothetical. Keep them.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/protect-env.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# Real files on disk — existence, symlink and link-count tests are meaningless
# against invented paths.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run() { # $1=file_path ; sets RC, ERR
  # Build the payload with jq, not string interpolation: a path containing a
  # newline or a quote produces INVALID JSON by hand, jq returns empty, and the
  # hook exits 0 having never seen the path — an assertion that passes for
  # entirely the wrong reason. That is how the embedded-newline case first
  # "passed".
  local json
  json=$(jq -n --arg p "$1" '{tool_input:{file_path:$p}}')
  ERR=$(printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null); RC=$?
}
blocks() { run "$1"; [[ "$RC" -eq 2 ]] && pass "$2" || fail "$2 (exit $RC)"; }
allows() { run "$1"; [[ "$RC" -eq 0 ]] && pass "$2" || fail "$2 (exit $RC)"; }

# --- 1. Existing credential files stay hard-blocked -------------------------
: > "$TMP/.env";            blocks "$TMP/.env"            "existing .env blocks"
: > "$TMP/.env.local";      blocks "$TMP/.env.local"      ".env.local blocks — template-shaped name, real credentials"
: > "$TMP/.env.production"; blocks "$TMP/.env.production" "existing .env.production blocks"
: > "$TMP/production.env";  blocks "$TMP/production.env"  "existing production.env blocks (suffix form)"

# --- 2. Case-insensitivity (macOS filesystems are case-insensitive) ---------
# `.ENV` IS `.env` there, so a case-sensitive test let a blocked agent retry in
# caps and clobber the same inode.
blocks "$TMP/.ENV" ".ENV blocks — same file as .env on a case-insensitive volume"
blocks "$TMP/.Env" ".Env blocks"
: > "$TMP/.ENV.LOCAL"
blocks "$TMP/.ENV.LOCAL" ".ENV.LOCAL blocks"

# --- 3. Template carve-out --------------------------------------------------
: > "$TMP/.env.example";  allows "$TMP/.env.example"  ".env.example allowed (committed, no secrets)"
: > "$TMP/.env.template"; allows "$TMP/.env.template" ".env.template allowed"
mkdir -p "$TMP/config" && : > "$TMP/config/.env.sample"
allows "$TMP/config/.env.sample" "nested .env.sample allowed"
allows "$TMP/.env.EXAMPLE" ".env.EXAMPLE allowed — carve-out is case-insensitive too"

# Anchored on the basename suffix, so a near-miss is not a template.
: > "$TMP/.env.example.bak"
blocks "$TMP/.env.example.bak" "existing .env.example.bak blocks — not a template"

# `case` has no line semantics. A grep -E '…$' anchored at the embedded newline
# and let this through as a template.
NL_NAME=$'.env.example\n.live'
: > "$TMP/$NL_NAME"
blocks "$TMP/$NL_NAME" "basename with an embedded newline is not a template"

# --- 4. Alias attacks on the allow-listed template names --------------------
# A template NAME pointing at the credential FILE. Trusting the name hands over
# the inode; the commit scan cannot recover overwritten uncommitted contents.
ln -s "$TMP/.env" "$TMP/sym.env.example"
blocks "$TMP/sym.env.example" "symlinked template blocks — name may not alias another path"

ln "$TMP/.env" "$TMP/hard.env.sample"
blocks "$TMP/hard.env.sample" "hard-linked template blocks — inode shared with .env"

# A dangling symlink is just as bad on the create path: the write follows it.
ln -s "$TMP/nowhere-at-all" "$TMP/dangling.env"
blocks "$TMP/dangling.env" "dangling env symlink blocks — the write would follow it"

# A plain regular-file template with one link is still fine.
: > "$TMP/plain.env.example"
allows "$TMP/plain.env.example" "regular single-link template still allowed"

# --- 5. Create-if-absent, in a directory that actually exists ---------------
# The parent must exist, or the case proves nothing: Write could not create the
# file anyway, so absence would pass for the wrong reason.
mkdir -p "$TMP/project"
[[ -d "$TMP/project" ]] || fail "fixture: project dir missing"
allows "$TMP/project/.env" "absent .env in an EXISTING dir allowed (the scaffold case)"
: > "$TMP/project/.env"
blocks "$TMP/project/.env" "the same path blocks once the file exists"

# --- 5b. Trailing slashes are stripped before the basename ------------------
# `${p##*/}` on `/x/.env/` yields an EMPTY basename, which matched nothing and
# fell out the allow door.
blocks "$TMP/.env/"   "trailing slash on .env blocks (basename not emptied)"
blocks "$TMP/.env//"  "multiple trailing slashes block"
allows "$TMP/project/" "trailing slash on a non-env dir is still allowed"

# --- 5c. stat fallback order (portability regression guard) -----------------
# GNU `stat -f` is --file-system, where %l is "max filename length" (255 on
# ext4) — a NUMBER. Probing BSD-first therefore succeeds on Linux with a value
# that is not a link count, never falls through, and blocks every template.
# Assert the hook's chain is GNU-first, matching the rest of the repo.
grep -q 'stat -c %h .* || stat -f %l' "$HOOK" \
  && pass "nlink probe is GNU-first (stat -c %h before stat -f %l)" \
  || fail "nlink probe must try 'stat -c %h' BEFORE 'stat -f %l' — BSD-first returns 255 on Linux"
# And prove the chain actually yields a link count on THIS platform.
: > "$TMP/nlink-probe"
PROBE=$(stat -c %h "$TMP/nlink-probe" 2>/dev/null || stat -f %l "$TMP/nlink-probe" 2>/dev/null || echo 2)
[[ "$PROBE" == "1" ]] && pass "nlink probe returns 1 for a single-link file here" \
  || fail "nlink probe returned '$PROBE', expected 1 — templates would wrongly block"

# --- 6. Relative paths fail closed, templates included ----------------------
blocks ".env"              "relative .env blocks (fail closed)"
blocks "some/dir/.env"     "relative nested .env blocks"
blocks ".env.example"      "relative template blocks — docs promise relative fails closed"

# --- 7. Non-env files untouched --------------------------------------------
allows "$TMP/environment.ts" "environment.ts allowed"
allows "$TMP/src/env.ts"     "src/env.ts allowed"
allows "$TMP/.environment"   ".environment allowed"
# Classification is on the BASENAME: a .env.d/ directory component must not drag
# ordinary files in and report them as credential files.
mkdir -p "$TMP/.env.d" && : > "$TMP/.env.d/ordinary.txt"
allows "$TMP/.env.d/ordinary.txt" ".env.d/ordinary.txt allowed — dir component is not the basename"
# ...but a real env file inside such a directory still blocks.
: > "$TMP/.env.d/.env"
blocks "$TMP/.env.d/.env" ".env.d/.env blocks — basename is what counts"

# --- 8. Payload edge cases --------------------------------------------------
RC=0; echo '{"tool_input":{}}' | bash "$HOOK" >/dev/null 2>&1 || RC=$?
[[ "$RC" -eq 0 ]] && pass "missing file_path exits 0" || fail "missing file_path should exit 0 (got $RC)"

RC=0; printf '' | bash "$HOOK" >/dev/null 2>&1 || RC=$?
[[ "$RC" -eq 0 ]] && pass "empty stdin exits 0" || fail "empty stdin should exit 0 (got $RC)"

RC=0; printf 'not json at all' | bash "$HOOK" >/dev/null 2>&1 || RC=$?
[[ "$RC" -eq 0 ]] && pass "malformed JSON exits 0 (never wedges the tool call)" \
  || fail "malformed JSON should exit 0 (got $RC)"

# --- 9. Not disablable ------------------------------------------------------
RC=0
CODING_RULES_HOOK_DISABLED=protect-env \
  bash -c "echo '{\"tool_input\":{\"file_path\":\"$TMP/.env\"}}' | bash '$HOOK'" >/dev/null 2>&1 || RC=$?
[[ "$RC" -eq 2 ]] && pass "CODING_RULES_HOOK_DISABLED does not disable this hook" \
  || fail "hook must stay non-disablable (exit $RC)"

# --- 10. Block message accuracy ---------------------------------------------
# The old message asserted the file "holds live credentials and is not in git",
# which is false for an empty or tracked file, and sent placeholder vars to
# DEVELOPER_TODO.md instead of the file that holds them.
run "$TMP/.env"
printf '%s' "$ERR" | grep -q "DEVELOPER_TODO" \
  && fail "block message must not route placeholders to DEVELOPER_TODO.md" \
  || pass "block message does not route placeholders to DEVELOPER_TODO.md"
printf '%s' "$ERR" | grep -q "\.env\.example" \
  && pass "block message names the template files the agent may edit" \
  || fail "block message should name .env.example (got '$ERR')"
printf '%s' "$ERR" | grep -q "already exists" \
  && pass "block message states the specific reason (already exists)" \
  || fail "block message should name the reason (got '$ERR')"
run ".env"
printf '%s' "$ERR" | grep -q "relative path" \
  && pass "relative block names its own distinct reason" \
  || fail "relative block should say 'relative path' (got '$ERR')"
run "$TMP/sym.env.example"
printf '%s' "$ERR" | grep -q "symlink" \
  && pass "symlink block names its own distinct reason" \
  || fail "symlink block should say 'symlink' (got '$ERR')"

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
fi
echo "$FAILS assertion(s) failed."
exit 1
