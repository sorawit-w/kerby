#!/bin/bash
# Hook: Hard-block destructive git commands (data-loss guardrail)
# Type: PreToolUse on Bash
# Name: protect-git
# Exit 2 = block action, stderr shown to agent as feedback
#
# Blocks:
#   - git push --force / -f         (allows --force-with-lease)
#   - git push to a protected branch (main, master, dev, develop, staging, trunk, release/*)
#   - git reset --hard
#   - git clean -f / -fd / --force
#   - git branch -D / --delete --force
#   - git checkout . / git restore . / git checkout -- . (wholesale local discard)
#   - git commit while ON a protected branch (workflow guard — see below)
#
# Allows targeted variants: `git checkout -- src/foo.ts`, `git restore --staged file`,
# `git push origin feature/foo`, `git clean -n` (dry run), etc.
#
# The destructive blocks above are NOT disablable via CODING_RULES_HOOK_DISABLED.
# Data-loss-critical hooks cannot be toggled off by an env var.
# To bypass for a one-off, run the command yourself in a terminal.
# To remove permanently, delete the hook entry from .claude/settings.json
# (requires a deliberate file edit, not an ambient variable).
#
# EXCEPTION — the commit-on-protected-branch check (section 7) is a WORKFLOW
# guard, not a data-loss block, so it HAS a scoped escape hatch:
# `CODING_RULES_ALLOW_PROTECTED_COMMIT=1` bypasses ONLY that check (the
# destructive blocks stay non-disablable). Use it inline, per-command:
#   CODING_RULES_ALLOW_PROTECTED_COMMIT=1 git commit …
# and only when the user has explicitly authorized committing to the protected
# branch. The hook detects this assignment IN THE COMMAND STRING and only when it
# directly prefixes the `git commit` (it runs before the command, so it can't read
# the child shell's env). An ambiently-exported var, or the token appearing
# elsewhere in the command, is deliberately NOT honored — both are self-bypasses.

set -u

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$CMD" ]]; then
  exit 0
fi

# Lowercase for case-insensitive matching.
LC=$(echo "$CMD" | tr '[:upper:]' '[:lower:]')

block() {
  echo "BLOCKED: $1" >&2
  echo "Reason: destructive git command — data loss is hard or impossible to undo." >&2
  echo "If you really need this, run it yourself in a terminal." >&2
  echo "See kerby guardrails (hooks/protect-git.sh)." >&2
  exit 2
}

# 1. Force push (but allow --force-with-lease, which checks remote state first).
if echo "$LC" | grep -qE '\bgit\b.*\bpush\b.*(--force\b|[[:space:]]-f\b|[[:space:]]-[a-z]*f[a-z]*\b)'; then
  if ! echo "$LC" | grep -qE -- '--force-with-lease'; then
    block "git push --force / -f"
  fi
fi

# 2. Push to a protected branch. Matches BOOTSTRAP.md branching list.
PROTECTED='(main|master|dev|develop|staging|trunk|release/[^[:space:]]+)'
if echo "$LC" | grep -qE "\bgit\b.*\bpush\b[^|;&]*\b${PROTECTED}\b"; then
  block "git push to a protected branch"
fi

# 3. Reset --hard
if echo "$LC" | grep -qE '\bgit\b.*\breset\b.*--hard\b'; then
  block "git reset --hard"
fi

# 4. Clean with force flag.
if echo "$LC" | grep -qE '\bgit\b.*\bclean\b.*(-[a-z]*f[a-z]*\b|--force\b)'; then
  block "git clean -f / --force"
fi

# 5. Branch -D / --delete --force
if echo "$LC" | grep -qE '\bgit\b.*\bbranch\b.*(-d[a-z]*[[:space:]]|-[a-z]*d[a-z]*[[:space:]]|--delete[[:space:]]+--force\b)'; then
  # Match -D (capital D) explicitly, since lowercased above. After tr, -D becomes -d.
  # Distinguish -d (safe delete) from -D (force delete). After lowercasing both look the same,
  # so re-check the original CMD for capital -D.
  if echo "$CMD" | grep -qE '\bgit\b.*\bbranch\b.*-D\b'; then
    block "git branch -D"
  fi
  if echo "$LC" | grep -qE '\bgit\b.*\bbranch\b.*--delete[[:space:]]+--force\b'; then
    block "git branch --delete --force"
  fi
fi

# 6. Wholesale local discard: checkout . / restore . / checkout -- .
# Matches when the pathspec is exactly "." (the whole working dir).
# Allows targeted pathspecs like `git checkout -- src/foo.ts`.
if echo "$LC" | grep -qE '\bgit\b.*\b(checkout|restore)\b([[:space:]]+--)?[[:space:]]+\.([[:space:]]|$)'; then
  block "git checkout . / git restore . (wholesale local discard)"
fi

# 7. Commit while ON a protected branch (WORKFLOW guard — escapable, unlike 1–6).
# This reads real repo state (the TARGET repo's current branch), not just the
# command string, and it parses the git invocation rather than scanning for a bare
# "commit" word — so `git log --grep=commit` (subcommand `log`) is NOT a commit,
# while `git -C path commit` / `git -c k=v commit` are.
#
# A PreToolUse hook fires BEFORE the command runs, so:
#   - the inline override `VAR=1 git commit` lives in the child shell we can't see;
#     we parse the assignment out of the command string instead (never an exported
#     ambient var — that's a session-wide self-bypass), and per-invocation: an
#     override on a LATER commit must not authorize an earlier bare one.
#   - we cannot predict the runtime branch of a compound command (a `switch -c`
#     may fail, its new branch may be protected, `;` runs the commit regardless),
#     so branch creation and the commit must be SEPARATE commands — no carve-out.
#
# Commit detection is STRUCTURAL, not a text match. It used to run a regex over
# the command string, which cannot model shell quoting: an escaped space, a line
# continuation, a quoted selector value, a heredoc body or a lone `&` each made
# the gate mis-read the command — some skipping the check, some blocking a
# command that creates no commit. The command is tokenized once and an exact
# `git` … `commit` token pair is the whole test. (Issue #48; the same rebuild
# base/hooks/pre-commit-check.sh got for issue #46.)
#
# The DESTRUCTIVE matchers above deliberately stay loose (`\bgit\b.*\bpush\b.*
# --force`): they over-block, which is the safe direction for a data-loss guard.
# This gate needs precision in BOTH directions — a miss is a commit on a
# protected branch, a false positive blocks legitimate work — so only it is
# rebuilt here.

# --- BEGIN SHARED SHELL TOKENIZER ------------------------------------------
# KEEP BYTE-IDENTICAL to rulebooks/base/hooks/pre-commit-check.sh's copy of this block.
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

tokenize "$CMD"
HAS_GIT=0
_i=0
while [ "$_i" -lt "${#TOKENS[@]}" ]; do
  if ! is_sep "$_i"; then
    case "${TOKENS[$_i]}" in git|*/git) HAS_GIT=1; break ;; esac
  fi
  _i=$((_i+1))
done

if [ "$HAS_GIT" -eq 1 ]; then
  # Resolve the branch each commit would ACTUALLY land on, then block on the
  # first protected one. Walk the token stream, cutting a segment at each
  # separator token:
  #   - a `cd <path>` segment updates the effective directory for later BARE
  #     commits, replayed in a subshell with literal args — NEVER eval, so a
  #     path cannot smuggle in a command.
  #   - a commit segment resolves its own target: an explicit -C/--git-dir on
  #     THAT invocation wins (a -C on a different sub-command must not leak in),
  #     else the accumulated cd chain, else cwd.
  # EVERY commit is checked, not just the first. Residuals are shared with
  # pre-commit-check.sh and listed in references/threat-model.md.
  CDLIST=""
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

    if [ "${SEG_TOKS[0]}" = "cd" ]; then
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

    SEEN_GIT=0; IS_COMMIT=0; OVERRIDE=0; skip_val=0; take_val=0; redir_val=0
    prev_opt_valueless=1
    LOC_ARR=()
    TOKI=-1
    for tok in ${SEG_TOKS[@]+"${SEG_TOKS[@]}"}; do
      TOKI=$((TOKI+1))
      if [[ "$SEEN_GIT" -eq 0 ]]; then
        if [ "$redir_val" -eq 1 ]; then redir_val=0; continue; fi
        case "$tok" in
          [0-9]*'>'*|[0-9]*'<'*|'>'*|'<'*|'&>'*)
            case "$tok" in *[!0-9\<\>\&]*) : ;; *) redir_val=1 ;; esac
            continue ;;
        esac
        case "$tok" in
          # The override is read STRUCTURALLY: an assignment leading THIS
          # invocation. A sed strip over the raw string could be fooled by the
          # same token inside a message or a different segment, and it is a
          # self-bypass switch, so precision matters more here than anywhere.
          CODING_RULES_ALLOW_PROTECTED_COMMIT=1) OVERRIDE=1; continue ;;
          *=*) continue ;;
          git|*/git) SEEN_GIT=1; continue ;;
          *) break ;;
        esac
      fi
      if [[ "$take_val" -eq 1 ]]; then
        take_val=0; LOC_ARR[${#LOC_ARR[@]}]="$(untilde "$tok" "${SEG_Q[$TOKI]:-}")"; continue
      fi
      if [[ "$skip_val" -eq 1 ]]; then skip_val=0; continue; fi
      [[ "$tok" == "--" ]] && break
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
           prev_opt_valueless=1 ;;
      esac
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
    # Per-invocation: an override on a LATER commit must not authorize an
    # earlier bare one, so it is evaluated inside the segment, not globally.
    [[ "$OVERRIDE" -eq 1 ]] && continue

    CURRENT=$(
      while IFS= read -r _d; do [ -n "$_d" ] && { cd "$_d" 2>/dev/null || exit 0; }; done <<< "$CDLIST"
      git ${LOC_ARR[@]+"${LOC_ARR[@]}"} branch --show-current 2>/dev/null
    )
    HAS_HEAD=$(
      while IFS= read -r _d; do [ -n "$_d" ] && { cd "$_d" 2>/dev/null || { echo 0; exit 0; }; }; done <<< "$CDLIST"
      git ${LOC_ARR[@]+"${LOC_ARR[@]}"} rev-parse --verify -q HEAD >/dev/null 2>&1 && echo 1 || echo 0
    )
    # Allow when there's nothing to commit onto yet or no branch:
    #   - empty CURRENT = detached HEAD / not a repo
    #   - HEAD does not resolve = initial commit (unborn branch still reports a name)
    if [[ -n "$CURRENT" && "$HAS_HEAD" == "1" ]] && echo "$CURRENT" | grep -qE "^${PROTECTED}$"; then
      echo "BLOCKED: git commit on protected branch '$CURRENT'." >&2
      echo "Create a feature branch first: git checkout -b feat/<short-description>" >&2
      echo "(or git switch -c fix/<...>), then stage and commit there." >&2
      echo "Workflow guard, not data loss. To commit here intentionally — and only" >&2
      echo "if the user authorized it — set the override inline for this command:" >&2
      echo "  CODING_RULES_ALLOW_PROTECTED_COMMIT=1 git commit ..." >&2
      echo "See kerby guardrails (hooks/protect-git.sh)." >&2
      exit 2
    fi
  done
fi

exit 0
