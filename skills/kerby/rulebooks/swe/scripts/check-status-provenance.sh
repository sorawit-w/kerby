#!/bin/bash
# STATUS.md holds position, never provenance.
#
# `.kerby/STATUS.md` answers "where do things stand". It must NOT restate a fact
# that already has an authority: a version (the manifests), a commit or review
# SHA (git), or a working branch (`git branch --show-current`). A second copy one
# tier below its authority can only drift — which is exactly what happened: a
# STATUS.md shipped naming a release two patch versions behind what six manifests
# said, written from memory an hour after the author bumped them.
#
# This guard asserts an ABSENCE, so it matches shapes, not phrasings. That is why
# it is mechanically checkable where the commit-time gate-tier rule is not (see
# `skills/kerby/CLAUDE.md` — "guard a constant, not a sentence"): there is no
# wording a status-file author writes without thinking that defeats a semver
# pattern.
#
# Run: bash skills/kerby/rulebooks/swe/scripts/check-status-provenance.sh [file]
# Default file: .kerby/STATUS.md relative to the current directory.
# Exit 0 = no provenance found; 1 = provenance found (each hit named with its line).
#
# Ceilings, stated rather than papered over:
#   - It cannot catch a wrong `Phase` SENTENCE. "Shipped" when nothing shipped is
#     prose, and prose is what the doctrine says not to guard. The independent
#     review covers that residual.
#   - The branch check knows `feature|fix|refactor|chore`, deliberately NOT `docs`
#     or `test`: those two collide with ordinary directory names, and a guard that
#     fires on `docs/rulebook-contract.md` would be edited away rather than obeyed.
#   - A 7+ char all-hex English word ("defaced") is a false positive. Accepted: a
#     visible false positive is fixable, a silent false negative is not.

set -u

FILE="${1:-.kerby/STATUS.md}"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

if [[ ! -f "$FILE" ]]; then
  # Say this plainly. A missing file reported as a bare PASS is how "nobody
  # checked" turns into "the check passed".
  echo "SKIP: $FILE does not exist — nothing to check (this is not a pass)."
  echo "---"
  exit 0
fi

# One awk pass, three shape tests, exact line numbers.
#   version  a semver anywhere on the line
#   sha      a bare token of 7-40 chars, all [0-9a-f]
#   branch   <type>/<name> for the branch types that are not also directory names
HITS=$(awk '
  {
    line = $0

    if (match(line, /[0-9]+\.[0-9]+\.[0-9]+/))
      printf "%d\tversion\t%s\n", NR, substr(line, RSTART, RLENGTH)

    # Tokenise on anything that is not alphanumeric, then test each token whole.
    n = split(line, tok, /[^0-9A-Za-z]+/)
    for (i = 1; i <= n; i++) {
      t = tok[i]
      if (length(t) >= 7 && length(t) <= 40 && t ~ /^[0-9a-f]+$/)
        printf "%d\tsha\t%s\n", NR, t
    }

    if (match(line, /(feature|fix|refactor|chore)\/[A-Za-z0-9_-]+/))
      printf "%d\tbranch\t%s\n", NR, substr(line, RSTART, RLENGTH)
  }
' "$FILE")

if [[ -z "$HITS" ]]; then
  pass "$FILE states no version, commit SHA, or branch name"
else
  while IFS=$'\t' read -r ln kind tokentext; do
    [[ -n "$ln" ]] || continue
    fail "$FILE:$ln states a $kind ('$tokentext') — that fact's authority is elsewhere"
  done <<< "$HITS"
fi

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
