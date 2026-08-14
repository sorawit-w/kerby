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
# A quoted span holding ONE word is still that word: `git 'commit'` is a commit,
# so the quotes are removed and the content kept. A span holding whitespace is a
# message or format string, not an invocation, so it is dropped entirely — that
# is what keeps `--format='run git commit now'` from reading as a commit.
unquote() {
  printf '%s' "$1" \
    | sed -E "s/'([^' ]*)'/\1/g; s/\"([^\" ]*)\"/\1/g" \
    | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g"
}

# Split a command segment into shell WORDS, honouring quotes and backslash
# escapes. `set -- $SEG` was used before and word-splits on whitespace whatever
# the quoting, so `git -C "/p with space" commit` produced the fragments `/p`,
# `with`, `space` — the scan then ran against a path that does not exist,
# returned empty, and the secret was read as clean. Every previous attempt to
# patch around that with per-token quote stripping failed on the next form.
# Sets the global TOKENS array. No eval: characters are copied, never executed.
tokenize() {
  local s="$1" i=0 n=${#1} c q="" cur="" open=0
  TOKENS=()
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=""; else cur="$cur$c"; fi
    elif [ "$c" = "\\" ]; then
      i=$((i+1)); cur="$cur${s:$i:1}"; open=1
    elif [ "$c" = '"' ] || [ "$c" = "'" ]; then
      q="$c"; open=1
    elif [ "$c" = " " ] || [ "$c" = "$(printf '\t')" ]; then
      if [ -n "$cur" ] || [ "$open" = 1 ]; then TOKENS[${#TOKENS[@]}]="$cur"; fi
      cur=""; open=0
    else
      cur="$cur$c"
    fi
    i=$((i+1))
  done
  if [ -n "$cur" ] || [ "$open" = 1 ]; then TOKENS[${#TOKENS[@]}]="$cur"; fi
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

# `\s` and `\x27` are GNU/PCRE spellings that BSD `grep -E` does not support:
# the password branch silently never matched on macOS, which is exactly where
# this floor runs when no scanner is installed. POSIX classes only.
# The prefixes are assembled, not written whole: this file is itself committed,
# and spelling a live-key prefix out here makes the floor flag its own pattern
# the moment this line is edited.
SQ="'"; SK="sk""_"
REGEX_FLOOR="(${SK}live_|${SK}test_|AKIA[A-Z0-9]{16}|-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----|password[[:space:]]*=[[:space:]]*[\"${SQ}][^[:space:]]+)"

# Run a git command in the effective location for a commit segment: replay the
# accumulated `cd` chain in a subshell (literal args — NEVER eval, so a path
# cannot smuggle in a command), then apply the invocation's own -C/--git-dir.
# `git $LOC` is unquoted only for arg-splitting; variable values are not
# re-tokenized, so `;`/`&` inside a path stay literal.
# LOC_ARR (global) carries the target-selecting globals. It is an ARRAY because
# a string re-split on `git $loc` would undo the tokenizer's work for any path
# containing a space.
git_at() { # $1=cdlist  $2=envassigns  $3.. = git args
  local cdlist="$1" envs="$2"; shift 2
  (
    while IFS= read -r _d; do
      [ -n "$_d" ] && { cd "$_d" 2>/dev/null || exit 0; }
    done <<< "$cdlist"
    # Git's own environment selectors redirect the real commit; honour them so
    # the scan reads the same repo/index the commit will use.
    while IFS= read -r _e; do
      [ -n "$_e" ] && export "$_e"
    done <<< "$envs"
    git ${LOC_ARR[@]+"${LOC_ARR[@]}"} "$@" 2>/dev/null
  )
}

# Scan one target. Echoes nothing; returns 0 = clean, 7 = finding.
scan_target() { # $1=cdlist  $2=envassigns (LOC_ARR is global)
  # The DIFF keeps the commit's full context (cd chain + globals + GIT_* env):
  # resolving to a toplevel and dropping the rest lost alternate state such as
  # GIT_INDEX_FILE, and a detached --git-dir/--work-tree pair. The toplevel is
  # used ONLY as the scanner's cwd, so it reads the target's .gitleaks.toml.
  local cdlist="$1" envs="$2" rc names top diff raw drc rawi rci raww rcw
  # Scan the UNION of two diffs, because a commit can draw from either side and
  # no single diff covers both:
  #   --cached  index vs HEAD      — what a bare `git commit` writes
  #   (bare)    worktree vs index  — what `-a`, a pathspec or `--include` adds
  # A single `git diff HEAD` was tried and is WRONG: it compares HEAD to the
  # working tree, so staging a secret and then restoring the file to its HEAD
  # contents nets to an EMPTY diff while the index still commits the secret.
  # The union also needs no argument parsing to decide which side a form uses,
  # and works on an unborn HEAD where `git diff HEAD` cannot run at all.
  # It over-blocks a bare `git commit` when an unstaged tracked file holds a
  # secret. That is the accepted direction for a floor, and documented.
  #
  # `--text` is required, not cosmetic: without it a blob containing a NUL byte
  # diffs as "Binary files ... differ" with NO content, so a secret sitting in
  # one was never shown to the scanner at all. Forcing a textual diff is what
  # makes the bytes visible; git's own binary detection is not a safety signal.
  #
  # Prefixes/ext-diff/textconv are FORCED: the target repo's own config
  # (diff.noprefix, diff.external, a textconv filter) would otherwise change the
  # format this header filter reads, or hand the scanner converted text.
  rawi=$(git_at "$cdlist" "$envs" diff --cached --diff-filter=ACMR -U0 --text \
          --src-prefix=a/ --dst-prefix=b/ --no-ext-diff --no-textconv); rci=$?
  raww=$(git_at "$cdlist" "$envs" diff --diff-filter=ACMR -U0 --text \
          --src-prefix=a/ --dst-prefix=b/ --no-ext-diff --no-textconv); rcw=$?
  raw="$rawi
$raww"
  drc=$(( rci | rcw ))
  # A diff that FAILS on a real repo must fail CLOSED: treating git's failure as
  # "no diff" meant any command this hook mis-parsed reported clean and
  # committed. But only on a real repo — if the target does not resolve at all,
  # the actual `git commit` fails too, so no commit can happen and blocking
  # would only punish text that merely looks like a broken invocation.
  top=$(git_at "$cdlist" "$envs" rev-parse --show-toplevel)
  [ -n "$top" ] || return 0
  if [[ "$drc" -ne 0 ]]; then
    echo "WARNING: kerby could not read the staged diff for this commit (git exited $drc)." >&2
    echo "Blocking rather than assuming clean. Run the commit as a separate, simpler command." >&2
    return 7
  fi
  diff=$(printf '%s\n' "$raw" \
           | awk '/^--- (a\/|\/dev\/null)/{prev=1;next} /^\+\+\+ (b\/|\/dev\/null)/&&prev{prev=0;next} {prev=0} /^\+/')
  [ -n "$diff" ] || return 0

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
# relative -C/--git-dir, or a quoted path that itself contains a separator.
# Quoted paths and paths with spaces ARE handled (see tokenize).
CDLIST=""
SEGTXT="$COMMAND"
# All three separators split the same way. `||` is NOT modelled as "the left
# side failed": whether `cd /missing || git commit` actually runs the commit in
# the ORIGINAL directory depends on a runtime exit status this hook cannot see.
# The cd is therefore carried forward, and `git_at` exits its subshell when the
# replayed cd fails — an empty diff, so the scan FAILS OPEN. That is residual
# (d) in swe's threat-model.md, pinned by a test. Modelling it the other way was
# tried and produced false blocks, which is the worse direction for a floor.
SEGTXT="${SEGTXT//||/$'\n'}"; SEGTXT="${SEGTXT//&&/$'\n'}"; SEGTXT="${SEGTXT//;/$'\n'}"
while IFS= read -r SEG; do
  tokenize "$SEG"
  NTOK=${#TOKENS[@]}
  [ "$NTOK" -eq 0 ] && continue

  # `cd <path>` → remember for later bare commits. `cd --` is a real form and
  # was rejected by an "argument must not start with -" test, so `cd -- <repo>
  # && git commit` scanned the caller's repo and let the secret through. Bare
  # `cd` and `cd -` stay unhandled on purpose: neither names a directory the
  # hook can resolve statically.
  if [ "${TOKENS[0]}" = "cd" ]; then
    CDARG=""
    [ "$NTOK" -ge 2 ] && CDARG="${TOKENS[1]}"
    [ "$CDARG" = "--" ] && [ "$NTOK" -ge 3 ] && CDARG="${TOKENS[2]}"
    case "$CDARG" in
      ""|-|--) : ;;
      *) CDLIST="${CDLIST}${CDARG}
" ;;
    esac
    continue
  fi
  unquote "$SEG" | tr '[:upper:]' '[:lower:]' | grep -qE "$GIT_COMMIT_RE" || continue

  SEEN_GIT=0; IS_COMMIT=0; ENVS=""; skip_val=0; take_val=0
  LOC_ARR=()
  for tok in ${TOKENS[@]+"${TOKENS[@]}"}; do
    if [[ "$SEEN_GIT" -eq 0 ]]; then
      # The invocation must BE git, not merely mention it: `echo git commit` is
      # not a commit. Env assignments (VAR=val) may precede it.
      case "$tok" in
        GIT_DIR=*|GIT_WORK_TREE=*|GIT_INDEX_FILE=*|GIT_COMMON_DIR=*|GIT_OBJECT_DIRECTORY=*)
          ENVS="${ENVS}${tok}
"; continue ;;
        *=*) continue ;;
        git|*/git) SEEN_GIT=1; continue ;;
        *) break ;;
      esac
    fi
    # Target selectors are the global options BETWEEN `git` and `commit`.
    # Position is load-bearing: `-C` is ALSO a `git commit` option (reuse a
    # message), so `git commit -C HEAD` has NO target selector — reading that
    # trailing `-C HEAD` as a directory made the scan run against a nonexistent
    # path and report clean.
    if [[ "$tok" == "commit" ]]; then IS_COMMIT=1; break; fi
    if [[ "$take_val" -eq 1 ]]; then take_val=0; LOC_ARR[${#LOC_ARR[@]}]="$tok"; continue; fi
    if [[ "$skip_val" -eq 1 ]]; then skip_val=0; continue; fi
    # LOC_ARR is a WHITELIST of the globals that redirect WHICH repo/index git
    # uses. Collecting every pre-`commit` token instead dragged unrelated
    # globals' values in and broke the scan's own git command; anything that
    # cannot change the target is simply dropped.
    case "$tok" in
      -C|--git-dir|--work-tree|--namespace)
        LOC_ARR[${#LOC_ARR[@]}]="$tok"; take_val=1 ;;
      --git-dir=*|--work-tree=*|--namespace=*)
        LOC_ARR[${#LOC_ARR[@]}]="$tok" ;;
      -c|--config-env|--exec-path|--attr-source|--super-prefix) skip_val=1 ;;
      *) : ;;
    esac
  done
  [[ "$IS_COMMIT" -eq 1 ]] || continue

  # There is deliberately NO `--dry-run`/`--help` exemption. Text-inspecting
  # git's arguments cannot tell an OPTION from an option's VALUE — `git commit
  # -m "--help"` skipped the scan entirely and committed the secret. The same
  # unsoundness killed pathspec scoping. Since the hook only fires when a secret
  # is actually staged, blocking a dry run costs the agent one true warning.


  EFF_CD="$CDLIST"

  # Resolve the repo ONCE, from the caller's position, honouring the cd chain,
  # the invocation's globals and git's env selectors. Everything downstream then
  # works with an absolute path, which is what removed the relative-`-C` class of
  # bug (cd into the target AND pass -C -> git resolved repo/repo and failed).
  scan_target "$EFF_CD" "$ENVS" || exit 2   # Hard-block on findings
done <<< "$SEGTXT"

# Scan clean (or degraded to the regex floor, which found nothing). This is a
# pure floor: no additionalContext, no reminder — those coding-specific soft
# advisories are swe's (hollow-test-check.sh). Silent success.
exit 0
