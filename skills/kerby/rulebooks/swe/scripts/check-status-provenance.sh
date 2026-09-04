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
#   - SHAs are matched in LOWERCASE only. This is a scope choice, not an oversight:
#     git emits lowercase everywhere (`rev-parse`, `log`, `describe`), so an
#     uppercase SHA is not a real failure mode, while matching uppercase would
#     double the hex-English-word false-positive surface against ALLCAPS headings.
#   - A four-part version ("1.2.3.4") is not matched — that shape is what
#     distinguishes an IP address from a semver, and this repo ships semver.

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

    # version: test WHOLE dotted tokens, never a substring. Matching a bare
    # /[0-9]+\.[0-9]+\.[0-9]+/ anywhere reads the first three octets of an IP
    # address (127.0.0.1) as a semver; requiring the whole token to be exactly
    # three parts rejects the four-part address and still catches a `v` prefix.
    nv = split(line, vt, /[^0-9A-Za-z.]+/)
    for (i = 1; i <= nv; i++) {
      t = vt[i]
      gsub(/^\.+|\.+$/, "", t)          # trailing sentence period, leading ellipsis
      if (t ~ /^[vV]?[0-9]+\.[0-9]+\.[0-9]+$/)
        printf "%d\tversion\t%s\n", NR, t
    }

    # sha: tokenise on anything not alphanumeric, then test each token whole.
    n = split(line, tok, /[^0-9A-Za-z]+/)
    for (i = 1; i <= n; i++) {
      t = tok[i]
      if (length(t) >= 7 && length(t) <= 40 && t ~ /^[0-9a-f]+$/)
        printf "%d\tsha\t%s\n", NR, t
    }

    # branch: the type must start at a word boundary, or the `fix` inside
    # "prefix/name" matches and the guard fires on ordinary prose.
    if (match(line, /(^|[^A-Za-z0-9_-])(feature|fix|refactor|chore)\/[A-Za-z0-9_-]+/)) {
      b = substr(line, RSTART, RLENGTH)
      sub(/^[^A-Za-z0-9_-]/, "", b)     # drop the boundary char from the report
      printf "%d\tbranch\t%s\n", NR, b
    }
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
