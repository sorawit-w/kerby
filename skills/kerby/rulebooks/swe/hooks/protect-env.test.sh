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
SKIPS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
# A platform-unavailable fixture is NOT a pass. Counting it as one lets the suite
# print "All assertions passed" while a regression guard never ran — the exact
# hollow-green this suite exists to prevent.
skip() { echo "SKIP: $1"; SKIPS=$((SKIPS + 1)); }

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

# --- 2. Case-insensitivity --------------------------------------------------
# On a case-insensitive volume `.ENV` IS `.env`, so a case-sensitive test let a
# blocked agent retry in caps and clobber the same inode. On a case-SENSITIVE
# volume those paths are genuinely absent and correctly take create-if-absent —
# asserting "blocks" there would be a false red. Probe, then assert accordingly.
CASE_INSENSITIVE=0
: > "$TMP/.caseprobe"; [[ -e "$TMP/.CASEPROBE" ]] && CASE_INSENSITIVE=1
rm -f "$TMP/.caseprobe"
echo "     (filesystem is case-$([[ $CASE_INSENSITIVE -eq 1 ]] && echo insensitive || echo sensitive))"

if [[ "$CASE_INSENSITIVE" -eq 1 ]]; then
  blocks "$TMP/.ENV" ".ENV blocks — same inode as .env here"
  blocks "$TMP/.Env" ".Env blocks"
else
  allows "$TMP/.ENV" ".ENV is a distinct absent file here — create-if-absent applies"
fi
# This one is unconditional: the file is created under the exact name tested, so
# it exercises mixed-case classification on any filesystem.
: > "$TMP/.ENV.LOCAL"
blocks "$TMP/.ENV.LOCAL" ".ENV.LOCAL blocks (created under that exact name)"

# --- 3. Template carve-out --------------------------------------------------
: > "$TMP/.env.example";  allows "$TMP/.env.example"  ".env.example allowed (committed, no secrets)"
: > "$TMP/.env.template"; allows "$TMP/.env.template" ".env.template allowed"
mkdir -p "$TMP/config" && : > "$TMP/config/.env.sample"
allows "$TMP/config/.env.sample" "nested .env.sample allowed"
# Must be CREATED, and in a FRESH dir: on a case-insensitive volume, creating
# `.env.EXAMPLE` beside an existing `.env.example` just reuses that entry, so the
# byte-exact rule below would (correctly) block and this would test the wrong
# thing. Alone in its own directory the on-disk name really is `.env.EXAMPLE`.
mkdir -p "$TMP/mixedcase" && : > "$TMP/mixedcase/.env.EXAMPLE"
allows "$TMP/mixedcase/.env.EXAMPLE" ".env.EXAMPLE allowed — carve-out is case-insensitive"

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

# --- 5d. Trailing-newline path (command substitution strips final LFs) ------
# `$(...)` eats every trailing LF and `jq -r` adds one, so a file named
# `.env.example<LF>` arrived as `.env.example`, was inspected as an absent
# template, and returned 0 — while the real target was a symlink to .env.
NLF=$'.env.example\n'
ln -s "$TMP/.env" "$TMP/$NLF"
blocks "$TMP/$NLF" "trailing-newline path is not truncated into a template name"

# --- 5e. Templates must be REGULAR files ------------------------------------
# -L rules out symlinks, but a FIFO has nlink=1 and sailed through, against the
# "plain regular file" contract the docs state.
mkfifo "$TMP/fifo.env.example" 2>/dev/null \
  && blocks "$TMP/fifo.env.example" "FIFO named like a template blocks (not a regular file)" \
  || skip "FIFO case skipped — mkfifo unavailable"

# --- 5f. Byte-exact on-disk name (filesystem case folding) ------------------
# `-e` succeeds through the filesystem's own folding, and APFS folds more than
# ASCII: a real `.env.<U+017F>ample` is reachable as `.env.sample`, so the ASCII
# spelling hit the allow-list and wrote to an inode blocked under its true name.
# bash nocasematch folds ASCII only and can never mirror the filesystem.
# NOTE: `$'\u017f'` is bash 4.2+; macOS ships bash 3.2, which runs these hooks.
# Build the UTF-8 bytes with printf so the fixture works on both.
mkdir -p "$TMP/fold"
printf 'x\n' > "$TMP/fold/$(printf '.env.\xc5\xbfample')" 2>/dev/null
if [[ -e "$TMP/fold/.env.sample" ]]; then
  blocks "$TMP/fold/.env.sample" "ASCII spelling of a unicode-folded template blocks (name must match byte-exactly)"
else
  skip "unicode-fold case skipped — this filesystem does not fold U+017F"
fi

# The same rule on a plain ASCII collision: where `.env.example` already exists,
# a differently-cased spelling resolves to it on a case-insensitive volume and is
# refused, because the stored name is not what was asked for.
if [[ "$CASE_INSENSITIVE" -eq 1 ]]; then
  blocks "$TMP/.env.EXAMPLE" "case-variant spelling of an existing template blocks (stored name differs)"
else
  allows "$TMP/.env.EXAMPLE" "case-variant is a distinct absent file here — create-if-absent applies"
fi

# --- 5h. Existence must not rest on stat() alone ----------------------------
# A macOS ACL denying `readattr` makes `-e` FALSE for a file that plainly exists;
# the hook then took create-if-absent and allowed an overwrite of live
# credentials. The directory entry is still listable, so either signal counts.
mkdir -p "$TMP/acl"; printf 'SECRET=live\n' > "$TMP/acl/.env"
if chmod +a "everyone deny readattr" "$TMP/acl/.env" 2>/dev/null; then
  blocks "$TMP/acl/.env" "stat-blinded .env still blocks (directory entry is the second signal)"
else
  skip "ACL case skipped — this platform has no chmod +a"
fi

# An execute-only parent: `-e` succeeds but the glob is blind. Must fail closed.
mkdir -p "$TMP/xo"; printf 'SECRET=live\n' > "$TMP/xo/.env.example"
if chmod 111 "$TMP/xo" 2>/dev/null; then
  blocks "$TMP/xo/.env.example" "template under an unlistable parent blocks (cannot confirm the stored name)"
  chmod 755 "$TMP/xo" 2>/dev/null
else
  skip "execute-only parent case skipped"
fi

# --- 5g. Missing jq must fail CLOSED ----------------------------------------
# A security hook that cannot read its input must not shrug and allow. Without
# jq the path is unknowable, so an env-mentioning payload is refused. The branch
# is pure bash on purpose — it runs precisely when tooling is missing, so it
# must not itself need grep.
# Provision ONLY bash: provisioning `cat` here masked a real dependency —
# `$(cat)` in the hook made the "needs no external tool" branch a lie.
BARE="$TMP/barepath"; mkdir -p "$BARE"
for b in bash; do
  for d in /bin /usr/bin; do [[ -x "$d/$b" ]] && { ln -sf "$d/$b" "$BARE/$b"; break; }; done
done
ENVJSON=$(jq -n --arg p "$TMP/.env" '{tool_input:{file_path:$p}}')
# A JSON-escaped dot is a valid spelling of the same path and must also fail closed.
ESCJSON='{"tool_input":{"file_path":"/tmp/\u002eenv"}}'
RC=0; printf '%s' "$ESCJSON" | PATH="$BARE" bash "$HOOK" >/dev/null 2>&1 || RC=$?
[[ "$RC" -eq 2 ]] && pass "no jq + JSON-escaped .env path -> fail closed" \
  || fail "escaped env path must fail closed, got exit $RC"
RC=0; printf '%s' "$ENVJSON" | PATH="$BARE" bash "$HOOK" >/dev/null 2>&1 || RC=$?
[[ "$RC" -eq 2 ]] && pass "no jq on PATH + env payload -> fail closed (exit 2)" \
  || fail "no jq must fail closed, got exit $RC"
PLAINJSON=$(jq -n --arg p "/tmp/src/app.ts" '{tool_input:{file_path:$p}}')
RC=0; printf '%s' "$PLAINJSON" | PATH="$BARE" bash "$HOOK" >/dev/null 2>&1 || RC=$?
[[ "$RC" -eq 0 ]] && pass "no jq + non-env payload still passes through" \
  || fail "no jq must not block ordinary edits, got exit $RC"

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
[[ "$RC" -eq 0 ]] && pass "malformed JSON with no env mention exits 0 (never wedges the tool call)" \
  || fail "malformed JSON should exit 0 (got $RC)"
# The other half: malformed JSON that DOES name an env file must fail CLOSED.
RC=0; printf 'not json at all but mentions /tmp/.env here' | bash "$HOOK" >/dev/null 2>&1 || RC=$?
[[ "$RC" -eq 2 ]] && pass "malformed JSON mentioning an env file fails closed" \
  || fail "malformed JSON naming an env file must exit 2 (got $RC)"

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
if [[ "$SKIPS" -gt 0 ]]; then
  echo "$SKIPS fixture(s) SKIPPED — unavailable on this platform; those regressions were NOT exercised here."
fi
if [[ "$FAILS" -eq 0 ]]; then
  echo "All run assertions passed${SKIPS:+ ($SKIPS skipped)}."
  exit 0
fi
echo "$FAILS assertion(s) failed."
exit 1
