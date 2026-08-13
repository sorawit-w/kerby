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

# Detection runs on the command with QUOTED SPANS REMOVED. `git commit` inside a
# quoted argument is text, not an invocation: `git log --format='run git commit
# now'` must not be treated as a commit. This hook is non-disablable, so a false
# block can only be escaped by editing settings.json — over-blocking is as much a
# defect as under-blocking. Stripping happens before matching, so GIT_COMMIT_RE
# itself stays byte-identical to protect-git.sh (parity-tested below).
# Quoted spans are removed for DETECTION only; path extraction still reads the
# original text (a quoted path remains a documented residual).
# A quoted span holding ONE word is still that word: `git 'commit'` is a commit,
# so the quotes are removed and the content kept. A span holding whitespace is a
# message or format string, not an invocation, so it is dropped entirely — that
# is what keeps `--format='run git commit now'` from reading as a commit.
unquote() {
  printf '%s' "$1" \
    | sed -E "s/'([^' ]*)'/\1/g; s/\"([^\" ]*)\"/\1/g" \
    | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g"
}

LC=$(unquote "$COMMAND" | tr '[:upper:]' '[:lower:]')
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
git_at() { # $1=cdlist  $2=loc  $3=envassigns  $4.. = git args
  local cdlist="$1" loc="$2" envs="$3"; shift 3
  (
    while IFS= read -r _d; do
      [ -n "$_d" ] && { cd "$_d" 2>/dev/null || exit 0; }
    done <<< "$cdlist"
    # Git's own environment selectors redirect the real commit; honour them so
    # the scan reads the same repo/index the commit will use.
    while IFS= read -r _e; do
      [ -n "$_e" ] && export "$_e"
    done <<< "$envs"
    git $loc "$@" 2>/dev/null
  )
}

# Scan one target. Echoes nothing; returns 0 = clean, 7 = finding.
scan_target() { # $1=cdlist  $2=loc  $3=envassigns
  # The DIFF keeps the commit's full context (cd chain + globals + GIT_* env):
  # resolving to a toplevel and dropping the rest lost alternate state such as
  # GIT_INDEX_FILE, and a detached --git-dir/--work-tree pair. The toplevel is
  # used ONLY as the scanner's cwd, so it reads the target's .gitleaks.toml.
  local cdlist="$1" loc="$2" envs="$3" rc names top diff
  diff=$(git_at "$cdlist" "$loc" "$envs" diff --cached --diff-filter=ACMR -U0 \
           | grep '^+' | grep -v '^+++')
  [ -n "$diff" ] || return 0
  top=$(git_at "$cdlist" "$loc" "$envs" rev-parse --show-toplevel)

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
    # Both the diff AND the scanner run INSIDE the resolved repo: gitleaks reads
    # its allowlist (.gitleaks.toml) from cwd, so scanning a `-C other` target
    # from the caller's directory would apply the CALLER's allowlist. The
    # toplevel is already resolved, so plain `git` is correct here — an earlier
    # version cd'd into a RELATIVE `-C` target and then still passed `-C`, so
    # git resolved repo/repo, failed, and the scanner saw empty input and
    # reported clean.
    printf '%s\n' "$diff" \
      | ( cd "${top:-.}" 2>/dev/null || true
          "$SCANNER" stdin --no-banner --exit-code 7 >/dev/null 2>&1 )
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

  # ADDED lines only. `git diff -G --name-only` also selects a file when the
  # pattern appears in a REMOVED line, so it blocked the very commit that takes
  # a secret OUT — the opposite of the intent the scanner path already had.
  names=$(printf '%s\n' "$diff" | grep -oE "$REGEX_FLOOR" | head -3)
  if [[ -n "$names" ]]; then
    echo "WARNING: Possible secrets detected in staged changes." >&2
    echo "Matched the built-in secret pattern; inspect the staged diff locally." >&2
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
# `&&` and `;` chain forward; `||` does NOT. For `cd /missing || git commit` the
# real shell runs the commit in the ORIGINAL directory precisely because the cd
# failed — carrying the failed cd forward would scan a path that does not exist
# and report clean. A sentinel marks `||` so the walk can reset the chain there.
SEGTXT="${SEGTXT//||/$'\n'__KERBY_OR__$'\n'}"
SEGTXT="${SEGTXT//&&/$'\n'}"; SEGTXT="${SEGTXT//;/$'\n'}"
while IFS= read -r SEG; do
  # After `||` the preceding command failed, so any directory it established did
  # not take effect. Reset to the invocation's cwd — conservative by design: a
  # wrong guess here scans cwd rather than silently scanning nothing.
  if [[ "$SEG" == "__KERBY_OR__" ]]; then
    # `A || B` runs B only when A failed, so a `cd` immediately before the `||`
    # did NOT take effect for the segment right after it. Scope that to ONE
    # segment: resetting the whole chain broke `cd repo || exit; git commit`,
    # where the cd succeeded and the commit two segments later does run in repo.
    SKIP_CD_ONCE=1
    UNCERTAIN_CD="$CDLIST"     # the chain as it stood BEFORE the conditional
    CDLIST="$PREV_CDLIST"      # ...and as it stood before the cd that may have failed
    continue
  fi
  # Any real segment consumes the one-shot `||` skip — read it and clear it HERE,
  # because the `continue`s below would otherwise jump past a reset placed at the
  # end of the loop body (that bug made `cd repo || exit; git commit` scan cwd).
  USE_SKIP=${SKIP_CD_ONCE:-0}; SKIP_CD_ONCE=0
  PREV_CDLIST="$CDLIST"
  # `cd <path>` (not `cd -` / bare `cd`) → remember for later bare commits
  if printf '%s' "$SEG" | grep -qE '^[[:space:]]*cd[[:space:]]+[^[:space:]-]'; then
    CDLIST="${CDLIST}$(printf '%s' "$SEG" | sed -E 's/^[[:space:]]*cd[[:space:]]+//; s/[[:space:]].*$//')
"
    continue
  fi
  unquote "$SEG" | tr '[:upper:]' '[:lower:]' | grep -qE "$GIT_COMMIT_RE" || continue

  # Walk the segment's tokens. Done with a token walk rather than sed because
  # BSD sed (macOS) does not support `\b`, so a `\bcommit\b` strip silently
  # matched nothing and left the subcommand in the option prefix. Globbing is
  # disabled around the split so a `*` in the command cannot expand.
  set -f
  # shellcheck disable=SC2086
  set -- $SEG
  set +f
  SEEN_GIT=0; SEEN_WRAPPER=0; SKIP_NEXT=0; WRAPPER=""; LOC=""; IS_COMMIT=0; ENVS=""
  for rawtok in "$@"; do
    # Strip surrounding quotes: the shell removes them before git ever sees the
    # token, so `git 'commit'` is a commit and `'git' commit` is git.
    tok="${rawtok%\'}"; tok="${tok#\'}"; tok="${tok%\"}"; tok="${tok#\"}"
    if [[ "$SEEN_GIT" -eq 0 ]]; then
      # The invocation must BE git, not merely mention it: `echo git commit` is
      # not a commit. Env assignments (VAR=val) may precede it.
      # A skipped wrapper-option's ARGUMENT is never `git`. `-n` takes a value
      # for nice but not for sudo, so a per-wrapper option table would be wrong
      # either way; this rule needs no table and cannot swallow the invocation.
      if [[ "${SKIP_NEXT:-0}" -eq 1 ]]; then
        SKIP_NEXT=0
        case "$tok" in git|*/git) ;; *) continue ;; esac
      fi
      case "$tok" in
        GIT_DIR=*|GIT_WORK_TREE=*|GIT_INDEX_FILE=*|GIT_COMMON_DIR=*|GIT_OBJECT_DIRECTORY=*)
          ENVS="${ENVS}${tok}
"; continue ;;
        *=*) continue ;;
        git|*/git) SEEN_GIT=1; continue ;;
        # Wrapper commands that merely prefix the real invocation. An explicit
        # allowlist, not a generic skip: the first non-wrapper, non-assignment
        # token must still BE git, so `env echo git commit` is still not a commit.
        env|sudo|command|nice|time|/usr/bin/env|/usr/bin/sudo)
          SEEN_WRAPPER=1; WRAPPER="${tok##*/}"; continue ;;
        # A wrapper's OWN options (`sudo -n`, `env -i`, `nice -n 5`, `command --`)
        # sit between it and git. Skipped only AFTER a wrapper was seen, so a
        # command that merely starts with an option is still not a git commit.
        -*)
          [[ "$SEEN_WRAPPER" -eq 1 ]] || break
          # Whether an option consumes the next token depends on WHICH wrapper:
          # `-n` takes a value for nice but not for sudo, so one shared list gets
          # it wrong in one direction or the other (swallowing `git`, or reading
          # a value as the command). Table it per wrapper.
          case "${WRAPPER:-}:$tok" in
            *:--*=*) ;;   # self-contained, consumes nothing
            nice:-n|nice:--adjustment|sudo:-u|sudo:--user|sudo:-g|sudo:--group|sudo:-p|sudo:--prompt|sudo:-C|sudo:--close-from|sudo:-h|sudo:--host|sudo:-r|sudo:--role|sudo:-t|sudo:--type|sudo:-U|sudo:--other-user|env:-u|env:--unset|env:-C|env:--chdir|env:-S|env:--split-string)
              SKIP_NEXT=1 ;;
          esac
          continue ;;
        *) break ;;
      esac
    fi
    # Target selectors are the global options BETWEEN `git` and `commit`.
    # Position is load-bearing: `-C` is ALSO a `git commit` option (reuse a
    # message), so `git commit -C HEAD` has NO target selector — reading that
    # trailing `-C HEAD` as a directory made the scan run against a nonexistent
    # path and report clean. Collecting the prefix in order also preserves git's
    # own semantics when several combine (`git -C repo --git-dir=.git commit`).
    if [[ "$tok" == "commit" ]]; then IS_COMMIT=1; break; fi
    LOC="$LOC $tok"
  done
  [[ "$IS_COMMIT" -eq 1 ]] || continue

  EFF_CD="$CDLIST"
  if [[ "$USE_SKIP" -eq 1 ]]; then EFF_CD=""; fi

  # Resolve the repo ONCE, from the caller's position, honouring the cd chain,
  # the invocation's globals and git's env selectors. Everything downstream then
  # works with an absolute path, which is what removed the relative-`-C` class of
  # bug (cd into the target AND pass -C -> git resolved repo/repo and failed).
  scan_target "$EFF_CD" "$LOC" "$ENVS" || exit 2   # Hard-block on findings
  # A conditional `cd` leaves two possible working directories and a static pass
  # cannot know which the shell took. Scan the other one too: over-scanning costs
  # a redundant read, under-scanning costs a leaked secret.
  if [[ -n "${UNCERTAIN_CD:-}" && "$UNCERTAIN_CD" != "$EFF_CD" ]]; then
    scan_target "$UNCERTAIN_CD" "$LOC" "$ENVS" || exit 2
  fi
done <<< "$SEGTXT"

# Scan clean (or degraded to the regex floor, which found nothing). This is a
# pure floor: no additionalContext, no reminder — those coding-specific soft
# advisories are swe's (hollow-test-check.sh). Silent success.
exit 0
