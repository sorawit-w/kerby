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
# Exit 0 = no provenance found; 1 = provenance found, or the file could not be
# scanned. It never exits 0 on an unreadable file: a guard that cannot read its
# subject must not report a pass.
#
# WHAT IT MATCHES
#   version  a whole dotted token of exactly three parts, optional `v` prefix
#   sha      a whole hex token 6-40 chars containing BOTH a digit and a hex letter
#   branch   ONLY on a line containing the word "branch": a `<type>/<name>` token
#            for the seven types in `references/communication.md` § Branch Naming,
#            or a bare protected-branch name
#
# WHY THE BRANCH CHECK KEYS ON A LABEL, NOT A SHAPE. `docs/README` is a valid
# branch name and a common file path, and nothing in the token tells you which.
# Two rounds of path-shape heuristics (reject a second slash, reject a dot
# suffix) each traded a false positive for a missed branch without converging —
# the "if what it extracts is a phrasing, don't" case in `skills/kerby/CLAUDE.md`.
# Keying on the label matches how the field actually appears ("Working Branch",
# "branch=...") and removes the whole ambiguity class instead of patching it.
#
# CEILINGS — stated rather than papered over. The PASS message is worded to
# match these, so it never claims more than the guard checks:
#   - It cannot catch a wrong `Phase` SENTENCE. "Shipped" when nothing shipped is
#     prose, and prose is what the doctrine says not to guard. The independent
#     review covers that residual.
#   - A branch named on a line that never says "branch" is missed. That is the
#     deliberate cost of the label rule above.
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

if [[ ! -f "$FILE" ]]; then
  # Say this plainly. A missing file reported as a bare PASS is how "nobody
  # checked" turns into "the check passed".
  echo "SKIP: $FILE does not exist — nothing to check (this is not a pass)."
  echo "---"
  exit 0
fi

# The file exists but may still be unreadable. Check before scanning, and check
# awk's status after: an awk that cannot open its input writes to stderr and
# exits non-zero, leaving the capture EMPTY — which is indistinguishable from a
# clean file unless the status is tested. That is a guard reporting a pass on a
# file it never read.
if [[ ! -r "$FILE" ]]; then
  fail "cannot read $FILE — the file exists but is not readable, so it was NOT scanned"
  finish
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
  BEGIN {
    # The seven branch types in references/communication.md § Branch Naming.
    # Keep this list in step with that table — a type missing here is a branch
    # the guard silently allows.
    split("feature fix refactor test docs chore wip", ty, " ")
    for (k in ty) TYPE[ty[k]] = 1
    # Protected branches, named bare on a branch-labelled line.
    split("main master dev develop staging trunk", pb, " ")
    for (k in pb) PROTECTED[pb[k]] = 1
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

    # --- branch: ONLY on a line that says "branch". A bare <type>/<name> token
    # is not decidable — `docs/README` is a valid branch name AND a common file
    # path, and two rounds of path-shape heuristics traded false positives for
    # missed branches without converging. So the guard stops guessing from shape
    # and keys on the label instead, which is how the field actually appears
    # ("Working Branch", "branch=..."). On such a line no path-shape filtering is
    # needed, so the deep-path and dot-suffix misses go away too.
    if (tolower(line) ~ /branch/) {
      # Split on everything a branch name cannot contain, not on whitespace:
      # `branch=feature/x` is one whitespace word but two tokens.
      nw = split(line, w, /[^A-Za-z0-9._\/-]+/)
      for (i = 1; i <= nw; i++) {
        t = strip(w[i])
        if (t ~ /^[A-Za-z]+\//) {
          head = substr(t, 1, index(t, "/") - 1)
          if (head in TYPE) { printf "%d\tbranch\t%s\n", NR, t; continue }
        }
        if (tolower(t) in PROTECTED) printf "%d\tbranch\t%s\n", NR, t
      }
    }
  }
' "$FILE" 2>"$ERRFILE")
awk_status=$?

if [[ "$awk_status" -ne 0 ]]; then
  fail "cannot scan $FILE — awk exited $awk_status: $(tr '\n' ' ' < "$ERRFILE")"
  finish
fi

if [[ -z "$HITS" ]]; then
  pass "$FILE states no version, no SHA-shaped hex token, and no branch reference on a line saying \"branch\""
else
  while IFS=$'\t' read -r ln kind tokentext; do
    [[ -n "$ln" ]] || continue
    fail "$FILE:$ln states a $kind ('$tokentext') — that fact's authority is elsewhere"
  done <<< "$HITS"
fi

finish
