#!/bin/bash
# STATUS.md holds position, never provenance.
#
# `.kerby/STATUS.md` answers "where do things stand". It must NOT restate a fact
# that already has an authority: a version (the manifests), a commit or review
# SHA (git), or a working branch (`git branch --show-current`). A second copy one
# tier below its authority can only drift — which is exactly what happened: a
# STATUS.md shipped naming a release two patch versions behind what the release
# manifests said, written from memory an hour after the author bumped them.
#
# This guard asserts an ABSENCE, so it matches shapes, not phrasings. That is why
# it is mechanically checkable where the commit-time gate-tier rule is not (see
# `skills/kerby/CLAUDE.md` — "guard a constant, not a sentence"): there is no
# wording a status-file author writes without thinking that defeats a semver
# pattern.
#
# Run: bash skills/kerby/rulebooks/swe/scripts/check-status-provenance.sh [file]
# Default file: .kerby/STATUS.md relative to the current directory.
# Exit 0 has TWO cases, and only one is a pass: either the file was scanned and
# stated no version or SHA-shaped token, or the path does not exist at all and a
# SKIP line says so in words. Exit 1 = a token was found, or the path exists and
# could not be scanned — unreadable, or not a regular file (a directory, device
# or FIFO). Exit 0 says nothing about branch names — see below. A guard that
# cannot read its subject must never report a pass, so every "exists but I did
# not scan it" state fails closed.
#
# WHAT IT MATCHES — two things, both unambiguous shapes:
#   version  a whole dotted token of exactly three parts, optional `v` prefix
#   sha      a whole hex token 6-40 chars containing BOTH a digit and a hex letter
#
# WHY THERE IS NO BRANCH CHECK. There was one, through three designs and three
# review rounds, and it never converged:
#   1. an unanchored regex        -> matched the `fix` inside "prefix/name"
#   2. word boundary + path-shape -> missed `branch=feature/x`, fired on
#      rejection                     `docs/README`, skipped git-valid `fix/v2.1`
#   3. keyed on a "branch" label  -> missed `Working on feature/x now.` and a
#                                    `| Git ref |` field, fired on "Review branch
#                                    policy, then edit docs/README"
# Each design fixed the cited cases and produced new ones, because the question
# is undecidable from the text: `docs/README` is a valid branch name AND a common
# file path, and no pattern separates them. This is exactly the case
# `skills/kerby/CLAUDE.md` names — "ask what the guard extracts; if the answer is
# a phrasing, don't" — and the reason its predecessor guard was deleted rather
# than sharpened. A guard that under-matches is worse than no guard: it turns
# *nobody checked* into *the check passed*.
#
# The branch field is already deleted from the STATUS.md template, so the failure
# this would have caught is structurally prevented rather than merely detected.
# A branch name written into a hand-edited STATUS.md is left to the rule text
# (`references/communication.md` § Status Tracking) and to review — the same
# place the wrong-`Phase`-sentence residual already sits.
#
# CEILINGS — stated rather than papered over. The PASS message is worded to
# match these, so it never claims more than the guard checks:
#   - It says NOTHING about branch names. See above.
#   - It cannot catch a wrong `Phase` SENTENCE. "Shipped" when nothing shipped is
#     prose, and prose is what the doctrine says not to guard. The independent
#     review covers that residual.
#   - A hex token with no digit ("defaced") or no letter ("123456") is not
#     matched — those two exclusions are what keep English words and ordinary
#     numbers from firing. The cost is a SHA abbreviation that happens to be all
#     letters or all digits. Bounded: a seven-character abbreviation contains
#     both about 96% of the time, and a full-length SHA effectively always.
#     Deliberate — both false-positive classes are frequent in a status file and
#     these misses are not.
#   - A four-part version ("1.2.3.4") is not matched. That shape is exactly what
#     separates an IP address from a semver, and this repo ships semver.

set -u

FILE="${1:-.kerby/STATUS.md}"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

finish() {
  echo "---"
  if [[ "$FAILS" -eq 0 ]]; then
    echo "All assertions passed."
    exit 0
  fi
  echo "$FAILS assertion(s) failed."
  exit 1
}

# EXIT 0 WITHOUT SCANNING HAS EXACTLY ONE HONEST CASE: the path genuinely is not
# there. Everything else — a directory, a dangling symlink, an unreadable file, a
# parent we cannot search — is "I did not scan it" and must fail closed. Three
# fail-opens on this branch all came from one predicate answering two questions
# and the silent answer winning, so the tests below are deliberately narrow and
# the SCAN ITSELF is the final authority (see the redirect further down).
if [[ -e "$FILE" || -L "$FILE" ]]; then
  # -L is not redundant: a DANGLING symlink is false to -e while plainly existing,
  # and reporting it as absent is a pass on an unresolvable path.
  if [[ -L "$FILE" && ! -e "$FILE" ]]; then
    fail "$FILE is a symlink whose target does not resolve — it was NOT scanned"
    finish
  fi
  if [[ ! -f "$FILE" ]]; then
    fail "$FILE exists but is not a regular file — it was NOT scanned"
    finish
  fi
  if [[ ! -r "$FILE" ]]; then
    fail "cannot read $FILE — it exists but is not readable, so it was NOT scanned"
    finish
  fi
else
  # -e and -L are both false, which usually means absent — but it ALSO means
  # "cannot be stat'd", and a parent directory without search permission produces
  # exactly that for a file that is really there. Absence has to be provable, not
  # merely unfalsifiable.
  _parent=$(dirname -- "$FILE")
  if [[ -d "$_parent" && ! -x "$_parent" ]]; then
    fail "cannot determine whether $FILE exists — its parent directory is not searchable, so it was NOT scanned"
    finish
  fi
  # Say this plainly. A missing file reported as a bare PASS is how "nobody
  # checked" turns into "the check passed".
  echo "SKIP: $FILE does not exist — nothing to check (this is not a pass)."
  echo "---"
  exit 0
fi

ERRFILE=$(mktemp) || { echo "FAIL: cannot create a temp file"; exit 1; }
trap 'rm -f "$ERRFILE"' EXIT

HITS=$(awk '
  # A whole-token test everywhere. Matching a bare pattern anywhere inside a line
  # is what made the first version read 127.0.0.1 as a semver and the "fix" inside
  # "prefix/name" as a branch.
  function strip(s) {                       # drop surrounding markup/punctuation
    gsub(/^[^A-Za-z0-9_\/.-]+|[^A-Za-z0-9_\/.-]+$/, "", s)
    gsub(/^\.+|\.+$/, "", s)                # leading ellipsis, trailing full stop
    return s
  }
  {
    line = $0

    # --- version: whole dotted token, exactly three parts.
    nv = split(line, vt, /[^0-9A-Za-z.]+/)
    for (i = 1; i <= nv; i++) {
      t = strip(vt[i])
      if (t ~ /^[vV]?[0-9]+\.[0-9]+\.[0-9]+$/)
        printf "%d\tversion\t%s\n", NR, t
    }

    # --- sha: hex token, 6-40 chars, containing BOTH a digit and a hex letter.
    # The digit keeps English words spelled in hex letters out ("defaced"); the
    # letter keeps ordinary numbers out ("Milestone 123456"). Both classes are
    # frequent in a status file, so both are excluded. See the header for what
    # this misses.
    n = split(line, tok, /[^0-9A-Za-z]+/)
    for (i = 1; i <= n; i++) {
      t = tok[i]
      if (length(t) >= 6 && length(t) <= 40 && t ~ /^[0-9a-fA-F]+$/ \
          && t ~ /[0-9]/ && t ~ /[a-fA-F]/)
        printf "%d\tsha\t%s\n", NR, t
    }

    # There is deliberately NO branch check here. See the header.\n    # Input arrives by REDIRECT, never as an awk operand: an operand named `-`\n    # is read as stdin and one containing `=` as a variable assignment, so both\n    # would scan nothing and exit 0 on a file that does exist.
  }
' < "$FILE" 2>"$ERRFILE")
awk_status=$?

if [[ "$awk_status" -ne 0 ]]; then
  fail "cannot scan $FILE — awk exited $awk_status: $(tr '\n' ' ' < "$ERRFILE")"
  finish
fi

if [[ -z "$HITS" ]]; then
  pass "$FILE states no version and no SHA-shaped hex token (branch names are not checked — see this script's header)"
else
  while IFS=$'\t' read -r ln kind tokentext; do
    [[ -n "$ln" ]] || continue
    fail "$FILE:$ln states a $kind ('$tokentext') — that fact's authority is elsewhere"
  done <<< "$HITS"
fi

finish
