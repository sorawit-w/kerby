#!/bin/bash
# Hook: Secret scan on staged files before a git commit (the universal floor).
# Type: PreToolUse on Bash matching git commit
# Name: pre-commit-check  (base's secrets-staged enforcer)
#
# This is the base floor's ONE enforcer: a pure, non-disablable secret scan.
# Clean commit -> exit 0, silent. Possible secret -> exit 2 + stderr (the
# blocking path IS shown to the agent). base merges under every rulebook, so this
# scan runs for every selection.
#
# It cannot be disabled via env var — it is a security guardrail. To bypass,
# remove the hook from settings.json.
#
# The coding-specific soft advisories (hollow-test heuristic + lint/test/build
# reminder) do NOT live here — they are swe's, in
# rulebooks/swe/hooks/hollow-test-check.sh, registered only when swe is selected.
#
# COMMAND RECOGNITION (issue #46). This hook used to match `^git commit`, so
# `git -C <repo> commit`, `git --git-dir=… commit` and `cd <repo> && git commit`
# all walked a staged secret straight past a check documented as a hard floor.
# It now parses the invocation the same way swe's protect-git.sh does, and — the
# half that is easy to get wrong — resolves WHICH repo each commit targets and
# scans THAT repo's index. Recognising `git -C other commit` while still scanning
# the cwd would be worse than the original bug: a check that runs, reports clean,
# and proves nothing.
#
# GIT_COMMIT_RE below is byte-identical to protect-git.sh's. Two copies exist
# because `base` is the floor and cannot depend on `swe`; the duplication is held
# by a parity assertion in pre-commit-check.test.sh, which fails if they drift.
# A regex literal is a constant, so that guard is mechanically checkable — unlike
# a prose invariant, which is not (see skills/kerby/CLAUDE.md § Guard a constant).

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Subcommand matcher: `git`, zero or more global options (some take an arg), then
# `commit` as the subcommand (\b…([[:space:]]|$) so `commit-graph`/`commit-tree`
# don't match). Matches option SHAPES, not a hardcoded list, so an unlisted or
# future global before `commit` is still skipped.
# KEEP BYTE-IDENTICAL to rulebooks/swe/hooks/protect-git.sh (parity-tested).
GIT_GLOBAL_OPT='(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir[=[:space:]][^[:space:]]+|--work-tree[=[:space:]][^[:space:]]+|--namespace[=[:space:]][^[:space:]]+|--super-prefix[=[:space:]][^[:space:]]+|--config-env[=[:space:]][^[:space:]]+|--exec-path[=[:space:]][^[:space:]]+|--attr-source[=[:space:]][^[:space:]]+|--[A-Za-z][A-Za-z-]*=[^[:space:]]+|--[A-Za-z][A-Za-z-]*|-[A-Za-z])'
GIT_COMMIT_RE="\\bgit\\b([[:space:]]+${GIT_GLOBAL_OPT})*[[:space:]]+commit\\b([[:space:]]|\$)"

LC=$(printf '%s' "$COMMAND" | tr '[:upper:]' '[:lower:]')
if ! echo "$LC" | grep -qE "$GIT_COMMIT_RE"; then
  exit 0
fi

# Pick a scanner by BINARY presence, not vendor (capability-gated). Prefer
# betterleaks (gitleaks' feature-frozen successor, same author) when installed,
# else gitleaks, else the built-in regex floor.
SCANNER=""
if command -v betterleaks >/dev/null 2>&1; then
  SCANNER=betterleaks
elif command -v gitleaks >/dev/null 2>&1; then
  SCANNER=gitleaks
fi

REGEX_FLOOR='(sk_live_|sk_test_|AKIA[A-Z0-9]{16}|-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----|password\s*=\s*["\x27][^\s]+)'

# Run a git command in the effective location for a commit segment: replay the
# accumulated `cd` chain in a subshell (literal args — NEVER eval, so a path
# cannot smuggle in a command), then apply the invocation's own -C/--git-dir.
# `git $LOC` is unquoted only for arg-splitting; variable values are not
# re-tokenized, so `;`/`&` inside a path stay literal.
git_at() { # $1=cdlist  $2=loc  $3.. = git args
  local cdlist="$1" loc="$2"; shift 2
  (
    while IFS= read -r _d; do
      [ -n "$_d" ] && { cd "$_d" 2>/dev/null || exit 0; }
    done <<< "$cdlist"
    git $loc "$@" 2>/dev/null
  )
}

# Scan one target. Echoes nothing; returns 0 = clean, 7 = finding.
scan_target() { # $1=cdlist  $2=loc
  local cdlist="$1" loc="$2" rc names

  if [[ -n "$SCANNER" ]]; then
    # Scan the staged diff's ADDED lines via `stdin` mode — the version-stable
    # invocation that survives gitleaks' 8.19 CLI reorg and works the same on
    # betterleaks. Added-only (-U0 + leading-'+' filter) is deliberate: scanning
    # context or REMOVED lines would block the very commit that refactors a
    # secret OUT into env vars.
    # --exit-code 7 gives a DISTINCT leak code: the scanners' default exit 1
    # means "leaks OR error", so a malformed config would otherwise phantom-block
    # this NON-disablable hook. 7 = finding; any other nonzero = tool error ->
    # fall through to the regex floor (degrade, never wedge). Output suppressed:
    # the scanner prints the matched secret, which must not enter agent context.
    git_at "$cdlist" "$loc" diff --cached --diff-filter=ACMR -U0 \
      | grep -E '^\+[^+]' \
      | "$SCANNER" stdin --no-banner --exit-code 7 >/dev/null 2>&1
    rc=$?
    if [[ "$rc" -eq 7 ]]; then
      echo "WARNING: $SCANNER detected possible secrets in staged changes." >&2
      echo "Output suppressed so the secret isn't echoed here — inspect locally with '$SCANNER stdin --redact', or allowlist a false positive in the scanner's config." >&2
      echo "See kerby security guardrails." >&2
      return 7
    elif [[ "$rc" -eq 0 ]]; then
      return 0   # scanner ran clean; trust it, skip the narrower regex
    else
      echo "NOTE (kerby): $SCANNER exited $rc (tool error, not a finding); using built-in secret regex." >&2
    fi
  fi

  names=$(git_at "$cdlist" "$loc" diff --cached --diff-filter=ACMR -G "$REGEX_FLOOR" --name-only)
  if [[ -n "$names" ]]; then
    echo "WARNING: Possible secrets detected in staged files:" >&2
    echo "$names" >&2
    echo "Review these files before committing. See kerby security guardrails." >&2
    return 7
  fi
  return 0
}

# Walk the command left-to-right by segment (split on && || ; via bash expansion
# — portable; BSD sed makes literal-\n unreliable). A `cd <path>` segment updates
# the effective directory for later BARE commits; a commit segment resolves its
# own target (explicit --git-dir/-C wins, else the accumulated cd chain, else
# cwd). EVERY commit is scanned, not just the first.
#
# Residual, shared with protect-git.sh and recorded in swe's threat-model.md: a
# static pass cannot model pipes, subshells, `cd -`/bare `cd`, cumulative
# relative -C/--git-dir, or quoted separators/paths.
CDLIST=""
SEGTXT="$COMMAND"
SEGTXT="${SEGTXT//&&/$'\n'}"; SEGTXT="${SEGTXT//||/$'\n'}"; SEGTXT="${SEGTXT//;/$'\n'}"
while IFS= read -r SEG; do
  # `cd <path>` (not `cd -` / bare `cd`) → remember for later bare commits
  if printf '%s' "$SEG" | grep -qE '^[[:space:]]*cd[[:space:]]+[^[:space:]-]'; then
    CDLIST="${CDLIST}$(printf '%s' "$SEG" | sed -E 's/^[[:space:]]*cd[[:space:]]+//; s/[[:space:]].*$//')
"
    continue
  fi
  printf '%s' "$SEG" | tr '[:upper:]' '[:lower:]' | grep -qE "$GIT_COMMIT_RE" || continue

  GITDIR=$(printf '%s' "$SEG" | grep -oE '(^|[[:space:]])--git-dir[=[:space:]][^[:space:]]+' | tail -1 | sed -E 's/.*--git-dir[=[:space:]]//')
  CPATH=$(printf '%s' "$SEG" | grep -oE '(^|[[:space:]])-C[[:space:]]+[^[:space:]]+' | tail -1 | sed -E 's/.*-C[[:space:]]+//')
  if [[ -n "$GITDIR" ]]; then LOC="--git-dir=$GITDIR"
  elif [[ -n "$CPATH" ]]; then LOC="-C $CPATH"
  else LOC=""; fi

  scan_target "$CDLIST" "$LOC" || exit 2   # Hard-block on findings
done <<< "$SEGTXT"

# Scan clean (or degraded to the regex floor, which found nothing). This is a
# pure floor: no additionalContext, no reminder — those coding-specific soft
# advisories are swe's (hollow-test-check.sh). Silent success.
exit 0
