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
#   sha      a whole hex token 6-40 chars that contains at least one digit
#   branch   a whole word `<type>/<name>` for the seven types in
#            `references/communication.md` § Branch Naming, excluding anything
#            shaped like a file path
#
# CEILINGS — stated rather than papered over. The PASS message is worded to
# match these, so it never claims more than the guard checks:
#   - It cannot catch a wrong `Phase` SENTENCE. "Shipped" when nothing shipped is
#     prose, and prose is what the doctrine says not to guard. The independent
#     review covers that residual.
#   - It cannot catch a BARE protected-branch name (`main`, `dev`). Those are
#     ordinary English words; matching them would fire on "the main reason".
#     Only the `<type>/<name>` shape is detectable, which is what the guard says.
#   - A hex token with NO digit at all is not matched. That is what keeps
#     "decade", "facade" and "defaced" from firing. The cost is a real SHA whose
#     abbreviation happens to be all letters: (6/16)^6, about 0.3% of six-char
#     abbreviations, less for longer ones. Deliberate — the English-word false
#     positives are frequent and this miss is rare.
#   - A four-part version ("1.2.3.4") is not matched. That shape is exactly what
#     separates an IP address from a semver, and this repo ships semver.
#   - A branch whose name ends in a dot-suffix (`fix/v2.1`) reads as a file path
#     and is skipped, because that is how `docs/x.md` is kept from firing.

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

    # --- sha: hex token, 6-40 chars, containing at least one digit. The digit
    # requirement is what separates a real abbreviated SHA from an English word
    # that happens to be spelled in hex letters.
    n = split(line, tok, /[^0-9A-Za-z]+/)
    for (i = 1; i <= n; i++) {
      t = tok[i]
      if (length(t) >= 6 && length(t) <= 40 && t ~ /^[0-9a-fA-F]+$/ && t ~ /[0-9]/)
        printf "%d\tsha\t%s\n", NR, t
    }

    # --- branch: a whole whitespace-delimited word of the form <type>/<name>.
    # Anything path-shaped is skipped: a second slash (test/fixtures/a.md) or a
    # dot-suffix tail (docs/guide.md). Testing whole words is also what keeps
    # src/feature/parser.ts out — it starts with "src/", not with a type.
    nw = split(line, w, /[ \t]+/)
    for (i = 1; i <= nw; i++) {
      t = strip(w[i])
      if (t !~ /^[A-Za-z]+\//) continue
      slash = index(t, "/")
      head = substr(t, 1, slash - 1)
      tail = substr(t, slash + 1)
      if (!(head in TYPE)) continue
      if (tail == "" || index(tail, "/") > 0) continue      # deeper path
      if (tail ~ /\.[A-Za-z0-9]+$/) continue                # file extension
      if (tail !~ /^[A-Za-z0-9._-]+$/) continue
      printf "%d\tbranch\t%s\n", NR, t
    }
  }
' "$FILE" 2>"$ERRFILE")
awk_status=$?

if [[ "$awk_status" -ne 0 ]]; then
  fail "cannot scan $FILE — awk exited $awk_status: $(tr '\n' ' ' < "$ERRFILE")"
  finish
fi

if [[ -z "$HITS" ]]; then
  pass "$FILE states no version, commit SHA, or <type>/<name> branch reference"
else
  while IFS=$'\t' read -r ln kind tokentext; do
    [[ -n "$ln" ]] || continue
    fail "$FILE:$ln states a $kind ('$tokentext') — that fact's authority is elsewhere"
  done <<< "$HITS"
fi

finish
