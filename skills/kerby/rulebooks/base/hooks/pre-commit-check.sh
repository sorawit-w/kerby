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
# It no longer shares protect-git.sh's regex matcher. That matcher reads the
# command as TEXT, and text cannot model shell quoting: escaped spaces, a line
# continuation and an attached selector whose quoted value held a space each
# skipped the scan entirely. Detection here is structural — the command is
# tokenized once, and a token that IS `git` followed by a token that IS `commit`
# is the whole test. protect-git.sh still uses the regex and has the same
# weakness; that is tracked separately, not silently fixed here.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# --- BEGIN SHARED SHELL TOKENIZER ------------------------------------------
# KEEP BYTE-IDENTICAL to rulebooks/swe/hooks/protect-git.sh's copy of this block.
# Two copies exist because `base` is the floor and cannot depend on `swe`, nor swe
# on base. The duplication is held by a parity assertion in BOTH test files, which
# fails if the blocks drift — the same arrangement the old GIT_COMMIT_RE constant
# used, extended to a function body. A shared helper in the engine would break
# rulebook self-containment (docs/rulebook-contract.md), so this is the trade.
# Split the WHOLE command into shell words AND separator tokens in one pass,
# honouring quotes and backslash escapes. Separators (`;` `&` `&&` `|` `||`) are
# emitted as their own tokens ONLY when unquoted and unescaped, so `echo x \; git
# commit` is one command that prints text (it used to be split by a blind string
# replacement and hard-blocked) while `true & git commit` is correctly two.
# Sets the global TOKENS array. No eval: characters are copied, never executed.
# `$(printf '\n')` is the EMPTY string — command substitution strips trailing
# newlines — so every newline comparison silently compared against "".
NL=$'\n'; TAB=$'\t'
tokenize() {
  local s="$1" i=0 n=${#1} c d q="" cur="" open=0 qseen="" hd hdq hdstate HD_PENDING=""
  # TOKSEP marks which entries are SEPARATORS. A separator cannot be identified
  # by its text: `echo x \; git commit` yields a literal `;` WORD, and matching
  # on the string alone cut the command there and hard-blocked a line that only
  # prints text. Position, not spelling, is what makes a token a separator.
  TOKENS=(); TOKSEP=(); TOKQ=()
  _emit() { if [ -n "$cur" ] || [ "$open" = 1 ]; then TOKSEP[${#TOKENS[@]}]=0; TOKQ[${#TOKENS[@]}]="$qseen"; TOKENS[${#TOKENS[@]}]="$cur"; fi; cur=""; open=0; qseen=""; }
  _sep()  { TOKSEP[${#TOKENS[@]}]=1; TOKQ[${#TOKENS[@]}]=""; TOKENS[${#TOKENS[@]}]="$1"; }
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ "$q" = "'" ]; then
      if [ "$c" = "'" ]; then q=""; else cur="$cur$c"; fi
    elif [ "$q" = '"' ]; then
      # Inside double quotes bash still processes `\"` and `\\`. Treating a
      # backslash as literal here ended the token early, so a path containing a
      # quote resolved to nothing and the scan reported clean.
      if [ "$c" = "\\" ]; then
        d="${s:$((i+1)):1}"
        case "$d" in
          "$NL") i=$((i+1)) ;;                                  # line continuation
          '"'|"\\"|'$'|'`') cur="$cur$d"; i=$((i+1)) ;;
          *) cur="$cur$c" ;;
        esac
      elif [ "$c" = '"' ]; then q=""
      else cur="$cur$c"; fi
    elif [ "$c" = "\\" ]; then
      # `\` + newline is a LINE CONTINUATION: both characters vanish. Keeping the
      # newline glued it into the token, so `git \<newline>commit` produced one
      # token that was neither `git` nor `commit` and the scan never ran.
      if [ "${s:$((i+1)):1}" = "$NL" ]; then i=$((i+1))
      else i=$((i+1)); cur="$cur${s:$i:1}"; open=1; fi
    elif [ "$c" = '"' ] || [ "$c" = "'" ]; then
      # Record WHERE the first quote fell. Bash suppresses tilde expansion when
      # anything in the TILDE-PREFIX (the `~` up to the first `/`) is quoted —
      # so `~/"x"` expands but `~""` and `"~"/x` do not. "Did the word start
      # quoted" got `~""` wrong; "did any quote appear" got `~/"x"` wrong.
      # EVERY quote-open position is recorded. Keeping only the first meant a
      # quote in the KEY half of `--git-"dir"="~/x"` erased the value's
      # provenance and the tilde expanded when bash would not have.
      qseen="$qseen ${#cur}"
      q="$c"; open=1
    elif [ "$c" = " " ] || [ "$c" = "$TAB" ]; then
      _emit
    elif [ "$c" = "<" ] && [ "${s:$((i+1)):1}" = "<" ]; then
      # A HEREDOC body is DATA, but the REST OF THE OPENER LINE is not:
      # `cat <<EOF; git commit -m x` really does run that commit. So only the
      # delimiter is consumed here; the body is skipped later, when the newline
      # that ends the opener line is reached. Skipping it immediately swallowed
      # the rest of the line and hid the commit.
      _emit
      i=$((i+2)); [ "${s:$i:1}" = "-" ] && i=$((i+1))
      while [ "$i" -lt "$n" ] && { [ "${s:$i:1}" = " " ] || [ "${s:$i:1}" = "$TAB" ]; }; do i=$((i+1)); done
      # Read the delimiter with the SAME quoting rules as a word: inside single
      # quotes a backslash is LITERAL, so `<<'E\OF'` really does have the
      # delimiter `E\OF`. Stripping backslashes unconditionally queued `EOF`,
      # which then matched the wrong line and swallowed a real commit after it.
      hd=""; hdstate=""
      while [ "$i" -lt "$n" ]; do
        hdq="${s:$i:1}"
        if [ "$hdstate" = "'" ]; then
          if [ "$hdq" = "'" ]; then hdstate=""; else hd="$hd$hdq"; fi
          i=$((i+1)); continue
        fi
        if [ "$hdstate" = '"' ]; then
          if [ "$hdq" = '"' ]; then hdstate=""
          elif [ "$hdq" = "\\" ]; then
            # Bash keeps the backslash before a non-special character inside
            # double quotes, so `<<"E\OF"` has the delimiter `E\OF`. Consuming
            # it unconditionally queued `EOF` and swallowed the rest.
            case "${s:$((i+1)):1}" in
              '"'|"\\"|'$'|'`') i=$((i+1)); hd="$hd${s:$i:1}" ;;
              *) hd="$hd$hdq" ;;
            esac
          else hd="$hd$hdq"; fi
          i=$((i+1)); continue
        fi
        case "$hdq" in
          " "|"$TAB"|"$NL"|";"|"&"|"|"|">"|"<") break ;;
          "'"|'"') hdstate="$hdq"; i=$((i+1)) ;;
          "\\") i=$((i+1)); hd="$hd${s:$i:1}"; i=$((i+1)) ;;
          *) hd="$hd$hdq"; i=$((i+1)) ;;
        esac
      done
      [ -n "$hd" ] && HD_PENDING="${HD_PENDING}${hd}
"
      continue
    elif [ "$c" = "$NL" ]; then
      # A raw newline SEPARATES commands. Treating it as plain whitespace merged
      # `true<newline>git commit` into one segment whose first word was `true`,
      # so the commit was never examined.
      _emit; _sep "$NL"
      # Any heredocs opened on the line just ended consume their bodies now, in
      # the order they were opened.
      while [ -n "$HD_PENDING" ]; do
        hd="${HD_PENDING%%$NL*}"; HD_PENDING="${HD_PENDING#*$NL}"
        [ -z "$hd" ] && { HD_PENDING=""; break; }
        while [ "$i" -lt "$n" ]; do
          i=$((i+1)); hdq=""
          while [ "$i" -lt "$n" ] && [ "${s:$i:1}" != "$NL" ]; do hdq="$hdq${s:$i:1}"; i=$((i+1)); done
          case "${hdq#"${hdq%%[![:space:]]*}"}" in "$hd") break ;; esac
          [ "$i" -ge "$n" ] && break
        done
      done
    elif [ "$c" = "#" ] && [ -z "$cur" ] && [ "$open" = 0 ]; then
      # `#` at the start of a word begins a COMMENT: skip to end of line. Without
      # this, `echo ok # ; git commit` saw a separator inside a comment and
      # hard-blocked a line that only prints text.
      while [ "$i" -lt "$n" ] && [ "${s:$i:1}" != "$NL" ]; do i=$((i+1)); done
      continue
    elif [ "$c" = ";" ]; then
      _emit; _sep ";"
    elif [ "$c" = "&" ] || [ "$c" = "|" ]; then
      _emit
      if [ "${s:$((i+1)):1}" = "$c" ]; then _sep "$c$c"; i=$((i+1))
      else _sep "$c"; fi
    else
      cur="$cur$c"
    fi
    i=$((i+1))
  done
  _emit
}

# `~` is expanded by the SHELL before git sees it, and $HOME is knowable here —
# unlike an arbitrary variable. Leaving it literal made `git -C ~/repo commit`
# scan a directory named `~` and report clean. `~user` needs a passwd lookup and
# is left alone.
untilde() { # $1=word  $2=space-separated positions of the word's quote opens
  local pre qp
  case "$1" in
    "~"|"~/"*) : ;;
    *) printf '%s' "$1"; return ;;
  esac
  # Quoting anywhere in the tilde-prefix (`~` up to the first `/`) suppresses
  # expansion: `~""` is a literal `~`, while `~/"x"` is $HOME/x. An empty quoted
  # string contributes no characters, so positions are tracked rather than a
  # mask over the word's own text.
  pre="${1%%/*}"
  for qp in $2; do
    [ "$qp" -le "${#pre}" ] && { printf '%s' "$1"; return; }
  done
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    *) printf '%s%s' "$HOME" "${1#\~}" ;;
  esac
}

untilde_val() { # $1=key=value  $2=quote-open positions within the whole token
  local k v qp vqs=""
  case "$1" in
    *=*) k="${1%%=*}"; v="${1#*=}"
         # Tilde expansion after `=` happens ONLY in an assignment word — a
         # valid identifier. `GIT_DIR=~/x` expands; `--git-dir=~/x` does NOT,
         # because `--git-dir` is not an identifier. Expanding it anyway sent
         # the scan to $HOME while the real commit used a literal `~` directory.
         case "$k" in
           [A-Za-z_]*) case "$k" in *[!A-Za-z0-9_]*) printf '%s' "$1"; return ;; esac ;;
           *) printf '%s' "$1"; return ;;
         esac
         # Rebase onto the value half and DROP key-half positions. Keeping only
         # the first position meant a quoted key hid a quoted value.
         for qp in $2; do
           qp=$(( qp - ${#k} - 1 ))
           [ "$qp" -ge 0 ] && vqs="$vqs $qp"
         done
         printf '%s=%s' "$k" "$(untilde "$v" "$vqs")" ;;
    *) printf '%s' "$1" ;;
  esac
}

is_sep() { [ "${TOKSEP[$1]:-0}" = 1 ]; }   # $1 = index, not text
# --- END SHARED SHELL TOKENIZER --------------------------------------------

tokenize "$COMMAND"
# Detection is STRUCTURAL, not a regex over de-quoted text. The old pre-filter
# ran `unquote | grep -E` and therefore missed every form whose quoting or
# escaping it did not model — `git -C repo\ with\ space commit`, a line
# continuation, an attached selector whose quoted value contained a space — each
# of which skipped the scan entirely. A token that IS `git` followed by a token
# that IS `commit` is the whole test, and it is exact.
HAS_GIT=0
_i=0
while [ "$_i" -lt "${#TOKENS[@]}" ]; do
  if ! is_sep "$_i"; then
    case "${TOKENS[$_i]}" in git|*/git) HAS_GIT=1; break ;; esac
  fi
  _i=$((_i+1))
done
[ "$HAS_GIT" -eq 1 ] || exit 0

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
# Walk the token stream, cutting a new segment at each separator token. The old
# version replaced `&&`/`||`/`;` in the raw string, which both MISSED a
# single `&` (`true & git commit` ran a real commit the hook never saw) and
# split on an ESCAPED or quoted separator (`echo x \; git commit` was hard-
# blocked though it only prints text).
#
# `||` is NOT modelled as "the left side failed": whether `cd /missing || git
# commit` runs the commit in the ORIGINAL directory depends on a runtime exit
# status this hook cannot see. The cd is carried forward, and `git_at` exits its
# subshell when the replayed cd fails — an empty diff, so the scan FAILS OPEN.
# That is residual (d) in swe's threat-model.md, pinned by a test.
SEG_TOKS=(); SEG_Q=()
TI=0; NALL=${#TOKENS[@]}
while [ "$TI" -le "$NALL" ]; do
  if [ "$TI" -lt "$NALL" ] && ! is_sep "$TI"; then
    SEG_Q[${#SEG_TOKS[@]}]="${TOKQ[$TI]:-}"
    SEG_TOKS[${#SEG_TOKS[@]}]="${TOKENS[$TI]}"; TI=$((TI+1)); continue
  fi
  TI=$((TI+1))
  NTOK=${#SEG_TOKS[@]}
  if [ "$NTOK" -eq 0 ]; then continue; fi

  # `cd <path>` → remember for later bare commits. `cd --` is a real form and
  # was rejected by an "argument must not start with -" test, so `cd -- <repo>
  # && git commit` scanned the caller's repo and let the secret through. Bare
  # `cd` and `cd -` stay unhandled on purpose: neither names a directory the
  # hook can resolve statically.
  if [ "${SEG_TOKS[0]}" = "cd" ]; then
    # Skip cd's OPTIONS to reach the path. `cd -P /target && git commit` took
    # `-P` for the directory, scanned a path that does not exist, and reported
    # clean. Bare `cd` and `cd -` stay unhandled: neither names a directory a
    # static pass can resolve.
    CDI=1; CDARG=""
    while [ "$CDI" -lt "$NTOK" ]; do
      case "${SEG_TOKS[$CDI]}" in
        --) CDI=$((CDI+1)); break ;;
        -[PLe@]*) CDI=$((CDI+1)) ;;
        *) break ;;
      esac
    done
    [ "$CDI" -lt "$NTOK" ] && CDARG="${SEG_TOKS[$CDI]}"
    case "$CDARG" in
      ""|-) : ;;
      *) CDLIST="${CDLIST}$(untilde "$CDARG" "${SEG_Q[$CDI]:-}")
" ;;
    esac
    SEG_TOKS=(); SEG_Q=(); continue
  fi

  SEEN_GIT=0; IS_COMMIT=0; ENVS=""; skip_val=0; take_val=0; redir_val=0; prev_opt_valueless=1
  LOC_ARR=()
  TOKI=-1
  for tok in ${SEG_TOKS[@]+"${SEG_TOKS[@]}"}; do
    TOKI=$((TOKI+1))
    if [[ "$SEEN_GIT" -eq 0 ]]; then
      # The invocation must BE git, not merely mention it: `echo git commit` is
      # not a commit. Env assignments (VAR=val) may precede it.
      # A REDIRECTION may precede the command: `< /dev/null git commit` is an
      # ordinary invocation, but stopping at `<` meant the commit was never
      # reached. Skip the operator, and its target when written separately.
      if [ "$redir_val" -eq 1 ]; then redir_val=0; continue; fi
      case "$tok" in
        [0-9]*'>'*|[0-9]*'<'*|'>'*|'<'*|'&>'*)
          case "$tok" in *[!0-9\<\>\&]*) : ;; *) redir_val=1 ;; esac
          continue ;;
      esac
      case "$tok" in
        GIT_DIR=*|GIT_WORK_TREE=*|GIT_INDEX_FILE=*|GIT_COMMON_DIR=*|GIT_OBJECT_DIRECTORY=*)
          ENVS="${ENVS}$(untilde_val "$tok" "${SEG_Q[$TOKI]:-}")
"; continue ;;
        *=*) continue ;;
        git|*/git) SEEN_GIT=1; continue ;;
        *) break ;;
      esac
    fi
    # A selector's VALUE is consumed before anything else. `git -C commit
    # commit` (a repo literally named `commit`) was read as the subcommand
    # arriving early, so the target was never applied and the scan ran on the
    # caller's repo. It also stops `git log -- git commit` from being taken for
    # a commit: `--` ends option parsing, so nothing after it is a subcommand.
    if [[ "$take_val" -eq 1 ]]; then
      take_val=0
      LOC_ARR[${#LOC_ARR[@]}]="$(untilde "$tok" "${SEG_Q[$TOKI]:-}")"
      continue
    fi
    if [[ "$skip_val" -eq 1 ]]; then skip_val=0; continue; fi
    [[ "$tok" == "--" ]] && break
    # Target selectors are the global options BETWEEN `git` and `commit`.
    # Position is load-bearing: `-C` is ALSO a `git commit` option (reuse a
    # message), so `git commit -C HEAD` has NO target selector — reading that
    # trailing `-C HEAD` as a directory made the scan run against a nonexistent
    # path and report clean.
    # The FIRST non-option token after `git` IS the subcommand — but only when
    # we can be sure it is not the VALUE of the option before it. `git
    # --shallow-file missing commit` stopped at `missing` and let the commit
    # through, because that global is not in the value-taking list. So: a
    # non-option token is the subcommand only if the token before it was `git`
    # itself or an option KNOWN to take no value. Otherwise it is ambiguous and
    # the walk keeps looking — over-blocking, the safe direction, and it still
    # lets `git log --grep commit` past because `log` follows `git` directly.
    case "$tok" in
      -*) case "$tok" in
            --no-pager|--paginate|-p|-P|--bare|--no-replace-objects|--literal-pathspecs|\
            --glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|\
            --no-lazy-fetch|--no-advice|--html-path|--man-path|--info-path|--version|--help)
              prev_opt_valueless=1 ;;
            *) prev_opt_valueless=0 ;;
          esac
          ;;
      commit) IS_COMMIT=1; break ;;
      *) if [ "${prev_opt_valueless:-1}" -eq 1 ]; then break; fi
         prev_opt_valueless=1 ;;   # consumed as the previous option's value
    esac
    # LOC_ARR is a WHITELIST of the globals that redirect WHICH repo/index git
    # uses. Collecting every pre-`commit` token instead dragged unrelated
    # globals' values in and broke the scan's own git command; anything that
    # cannot change the target is simply dropped.
    case "$tok" in
      -C|--git-dir|--work-tree|--namespace)
        LOC_ARR[${#LOC_ARR[@]}]="$tok"; take_val=1 ;;
      --git-dir=*|--work-tree=*|--namespace=*)
        LOC_ARR[${#LOC_ARR[@]}]="$(untilde_val "$tok" "${SEG_Q[$TOKI]:-}")" ;;
      -c|--config-env|--exec-path|--attr-source|--super-prefix) skip_val=1 ;;
      *) : ;;
    esac
  done
  SEG_TOKS=(); SEG_Q=()
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
done

# Scan clean (or degraded to the regex floor, which found nothing). This is a
# pure floor: no additionalContext, no reminder — those coding-specific soft
# advisories are swe's (hollow-test-check.sh). Silent success.
exit 0
