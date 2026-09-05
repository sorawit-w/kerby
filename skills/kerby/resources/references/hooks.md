# Hooks — Automated Enforcement

Hooks are shell commands or LLM prompts that run automatically at specific lifecycle points. They provide **deterministic enforcement** of playbook rules — the agent can't skip them.

> **Note:** Hooks are currently supported by Claude Code. Other agents mostly ignore the hooks configuration and should still follow the playbook's written instructions — with one exception worth knowing about: Copilot CLI on Windows reads `.claude/settings.json` and tries to run the hooks through PowerShell, which cannot execute a `.sh`. See `resources/references/multi-tool.md` § GitHub Copilot.

---

## Active Hooks

kerby ships with these hooks:

> The coding enforcers (`.env` protection/read-warning, high-stakes routing,
> pre-commit secret scan) are documented in the coding
> rulebook that declares them — e.g. the bundled `swe` rulebook's own
> `references/hooks.md`. This engine reference covers only the engine-owned
> SessionStart/knowledge hooks below.

### The launcher — how a registration finds its script

Since 9.27.0 `kerby install` does not write an install-owned script's absolute
path into `settings.json` (an approved external rulebook's enforcer keeps its
absolute path — it lives outside the install). It writes
`"<home>/.claude/kerby/bin/hook" <event> <relpath>` (`<home>` expanded — a
quoted `~` would not be): a
small POSIX `sh` launcher (shipped as `resources/scripts/hook-launcher.sh`,
copied to your user-local `~/.claude/kerby/bin/` by `install`) plus the
script's path relative to the install root. At hook time the launcher reads
the root from `~/.claude/kerby/install-root` — one line that every `kerby load`
refreshes from the copy it actually loaded — and from nothing else: a project
settings file can set env vars for its hooks, so `KERBY_DIR` is deliberately not
consulted here. It runs the script as a child with stdin untouched (a child, not
`exec`, so a script whose interpreter is missing becomes a visible fail-open
instead of a silent exit 127). Move the install, run any session
once, and every hook follows.

**It fails open, visibly.** If the pointer is missing or the script is not
there, the launcher exits 0 and says so on the channel the event reads: an
`additionalContext` line for `PreToolUse`, a plain line for `SessionStart`,
stderr for the git hook. An absolute path that stopped resolving used to fail
silently for weeks — nine dead entries and a pre-commit scan that never ran —
which is the failure this replaces. `kerby status` reports the launcher and
pointer state; the SessionStart heartbeat (the first line of every session in which that
hook is registered and enabled) does too.

### SessionStart → Context Injection

**Script:** `hooks/session-start-context.sh`
**Strictness:** Informational (no blocking)

Runs at the start of every session. Injects:
- Reminder of the 9-step workflow
- Contents of `.kerby/STATUS.md` (if it exists) — so the agent knows where the previous session left off
- Last entries from `.kerby/memory.log` (if it exists) — recent decisions and context

This replaces the need for the agent to "remember" to read project state — it's surfaced automatically.

---

### SessionStart → Knowledge Bootstrap

**Script:** `hooks/knowledge-bootstrap.sh`
**Strictness:** Informational (no blocking)

Runs at the start of every session. Three jobs:

1. **Scaffold** `.kerby/knowledge/KNOWLEDGE.md` from `templates/KNOWLEDGE.md.template` if the directory is missing. One-time, idempotent.
2. **Reindex** the AUTO-INDEX block in `KNOWLEDGE.md` from the title (frontmatter) and first body paragraph of each entry file. Idempotent — only writes if content actually changed. Internally calls `knowledge-reindex.sh --force`.
3. **Stale scan** — scans entry files for `updated:` (or `created:` as fallback) and prints any older than 180 days, so the agent can flag them rather than treating them as authoritative.

Why reindex on session start instead of post-commit? `KNOWLEDGE.md` is read by agents at the start of each session — that's the only moment freshness matters. Aligning regen with the read avoids per-project git-hook installation entirely. (For the case where the agent writes a new entry mid-session, see "Mid-session updates" below.)

Opt-out per project via `agent-context.yaml`:

```yaml
knowledge:
  enabled: false
```

Defaults to enabled when the section is missing. Override the staleness window with `CODING_RULES_KNOWLEDGE_STALE_DAYS=90`.

The `KNOWLEDGE.md` written by this hook contains `<!-- AUTO-INDEX:START -->` / `<!-- AUTO-INDEX:END -->` markers — only the lines between those markers are rewritten. Custom intro text or extra sections elsewhere in the file are preserved. If markers are missing, the hook prints a warning and skips index regen.

**Mid-session updates.** When an agent writes a new knowledge entry during a session (after the code rulebook's proposal-then-approval knowledge flow), it should run `bash "${KERBY_DIR}/resources/hooks/knowledge-reindex.sh" --force` to refresh the index immediately rather than waiting for the next session. The script is safe to call ad-hoc — idempotent and side-effect-free if nothing changed.

---

### SessionStart → Context Bootstrap

**Script:** `hooks/context-bootstrap.sh`
**Strictness:** Informational (no blocking)

Runs at the start of every session. If `CONTEXT.md` is missing at project root, scaffolds it from `templates/CONTEXT.md.template`. Never overwrites an existing `CONTEXT.md` — human-curated content is treated as authoritative.

`CONTEXT.md` is the project's enduring domain glossary (see `references/domain-glossary.md`). It's read at session start as part of BOOTSTRAP step 2 and used in code, plans, and prose to keep terminology consistent.

Opt-out per project via `agent-context.yaml`:

```yaml
context:
  enabled: false
```

Defaults to enabled when the section is missing.

---

### git pre-commit → Secret Scan (Optional, offered by `install`)

**Script:** the declaring check's own enforcer, run as `<enforcer> --git-hook`
**Strictness:** Blocking (aborts the commit)
**Trigger:** git's native `pre-commit` hook (not Claude Code lifecycle)

**This is the same scanner as the `PreToolUse` secret check, through a different door.**
Not a duplicate and not a replacement — they see different things:

| | PreToolUse hook | git `pre-commit` hook |
|---|---|---|
| Runs | before the Bash command | during the commit |
| Decides from | the command **text** | the **real index** git is committing |
| Sees `git add x && git commit` | **no** — nothing is staged yet | yes |
| Sees `git -C "$VAR" commit`, aliases, wrappers | **no** — they resolve at runtime | yes |
| Sees `git commit --no-verify` | yes | **no** — git skips its hooks |

That last row is why both are kept. Deleting either one opens a hole the other does not cover.

**Neither is guaranteed present, and they fail to be present for different reasons.** That
is the availability argument, and it is separate from the coverage argument above: even if
one caught strictly more than the other, it still would not be a replacement.

| | Not enforcing when |
|---|---|
| PreToolUse hook | Phase 2 was never accepted here, or its entry was later removed from the settings file |
| git hook | Phase 3 was never accepted here; or this is a fresh clone (git hooks are never cloned); or `core.hooksPath` sends git to a *different* hooks dir, so the file kerby wrote is not the one git runs; or the hook file is not executable, in which case git skips it entirely; or its scanner is not executable, in which case the hook runs and its own guard exits 0 |

Two things that table is careful *not* to say. **Declining a whole phase does not remove
anything** — saying no to Phase 2 or Phase 3 outright leaves whatever is installed exactly
where it is. Declining an *individual* hook inside Phase 2 is different, and does remove
it: since kerby 9.24.0 the Phase 2 walk offers each declinable hook separately, and a
decline that lands on an already-registered entry prunes it, so the answer takes effect
instead of being silently ignored (project-scoped settings files only — a globally
registered hook is shared with other projects and is reported rather than removed). Bulk
removal is still `uninstall`'s job. And **`core.hooksPath` shadows rather
than disables**: git still runs hooks, just from elsewhere, so a husky user can wire the
scanner into their own `.husky/pre-commit` by hand. kerby will not do that for them.

If you wire it in yourself, that file stays yours: kerby reads and writes only the repo's
default hooks dir, never the one `core.hooksPath` points at, so `uninstall` will not touch
your `.husky/pre-commit` even if you pasted kerby's template into it verbatim.

The list is the common cases, not a proof of exhaustiveness. `kerby status` reports what
**kerby** has bound; it does not survey every hook in the repo, so it can say "kerby is
not enforcing here" while some other tool's hook is running fine.

Unlike the post-commit reindex below, this one is **offered by `install`** (Phase 3) rather
than pasted by hand — a security floor earns an installer; a convenience reindex does not.
It is per-clone: git hooks are never cloned, so teammates are not covered by your install.

Behaviour worth knowing:

- **Index-only.** It scans `git diff --cached`, not the working tree. Git writes a temporary
  index and points `GIT_INDEX_FILE` at it *before* running the hook, so `--cached` sees
  exactly what will be committed — for `-a`, `-i`, a pathspec and `--only` alike. A dirty
  tracked file the commit does not include will **not** block it.
- **Fails open if the scanner is gone.** If kerby's install moves, the hook warns and exits
  0 rather than aborting every commit with 127.
- **Says so when it degrades.** With no `betterleaks`/`gitleaks` on `PATH` it prints one
  line and falls back to the built-in regex floor. This matters more here than in the
  PreToolUse path: a GUI git client runs hooks with a launchd `PATH` of
  `/usr/bin:/bin:/usr/sbin:/sbin`, where an installed scanner is invisible.
- **`core.hooksPath` sends git elsewhere.** If that config is set to a *different* dir than
  the repo's default (husky does; set to the default dir itself it changes nothing), git
  runs hooks from there instead, so a file kerby wrote would sit dormant. `install` refuses rather than write one; `uninstall` and `status` still
  look at the **default** dir, so a hook that went dormant when the config was added later
  is still found and removable. None of this means nothing is enforcing — a hook wired
  into the configured dir by hand runs perfectly well; kerby simply reports only on its
  own. (The default dir is resolved from git, never assumed to be `.git/hooks` — in a
  worktree or submodule it is not.)

Remove it with `kerby uninstall`. It removes any hook carrying kerby's `kerby-managed:`
marker — including one an older kerby wrote, or one written against an install root that
has since moved. A hook without that marker is someone else's and is never touched.

---

### git post-commit → Knowledge Reindex (Optional)

**Script:** `hooks/knowledge-reindex.sh`
**Strictness:** Informational (no blocking)
**Trigger:** git's native `post-commit` hook (not Claude Code lifecycle)

**This hook is optional.** The SessionStart bootstrap above already keeps `KNOWLEDGE.md` fresh at the only moment it matters (session start). Wire post-commit only if you want index updates to land in the same commit as the entry changes that triggered them — useful for cleaner git history or shared-team conventions, unnecessary for solo workflows.

The script has two modes:

- **Default (no args)** — git-gated. Only regenerates if the just-made commit touched a `.kerby/knowledge/*.md` file other than `KNOWLEDGE.md`. Requires being in a git work tree. This is what the post-commit hook below uses.
- **`--force`** — Always regenerates, no git checks. This is what `knowledge-bootstrap.sh` calls internally, and what the agent should call after writing a new entry mid-session.

Either way:

- **Initial commits work.** Uses `git diff-tree --root` so the very first commit triggers an index build.
- **Idempotent.** If regeneration produces no actual change, the file isn't touched (keeps `git status` clean).
- **The regenerated `KNOWLEDGE.md` is left UNSTAGED.** Auto-amending the commit was deliberately rejected — it would mutate history under your feet.
- **Marker-safe.** If `<!-- AUTO-INDEX:START -->` / `<!-- AUTO-INDEX:END -->` markers are missing, the script prints a one-line warning and exits without touching the file.
- **Same opt-out** as `knowledge-bootstrap` — `agent-context.yaml: knowledge.enabled: false` skips it.

To wire it as a per-project post-commit hook (one-paste, from the project's git root):

```bash
mkdir -p .git/hooks
cat > .git/hooks/post-commit <<EOF
#!/bin/bash
# Wired by kerby. Add other post-commit logic above or below.
"\${KERBY_DIR:-\$HOME/dev/kerby}/resources/hooks/knowledge-reindex.sh"
EOF
chmod +x .git/hooks/post-commit
```

If your project already has a `post-commit` hook, append the script call to it instead of overwriting.

---

### Manual / git post-commit → Knowledge Integrity (Optional)

**Script:** `hooks/knowledge-lint.sh`
**Strictness:** Advisory (exit 0; `--strict` exits non-zero)
**Trigger:** Manual invocation, or git's native `post-commit` hook (not Claude Code lifecycle)

Two zero-dependency mechanical checks over `.kerby/knowledge/` entries:

1. **Broken `related:` target** — an entry's `related:` frontmatter names a file that isn't in `.kerby/knowledge/`. Fires only when a link is declared, so effectively no false positives.
2. **Supersede-without-pointer** — an entry has a `## Superseded` section whose body names no replacement entry (no `.md` token).

**Advisory by default** — prints findings, always exits 0. Pass `--strict` to exit 1 on any finding (for a git pre-push or CI gate). Deliberately **not** a SessionStart hook: integrity drifts slowly and shouldn't be re-checked every session. There is **no orphan check** — `related:` is optional, so "no inbound link" is a curation opinion, not a correctness error; that's a semantic-lint concern for a richer knowledge tool (e.g. OpenKB, referenced by the bundled `swe` rulebook), not this engine floor's.

Same opt-out as the other knowledge hooks — `agent-context.yaml: knowledge.enabled: false`, or `CODING_RULES_HOOK_DISABLED=knowledge-lint`. Run it directly any time (`bash "${KERBY_DIR}/resources/hooks/knowledge-lint.sh"`), or append the call to a project `post-commit` hook the same way as `knowledge-reindex.sh` above. Self-tested by `hooks/knowledge-lint.test.sh`.

---

### No SessionEnd hook — checkpointing is not verified mechanically

**Nothing verifies that a checkpoint happened.** kerby registers exactly two events —
`PreToolUse` and `SessionStart` (see the `install` derivation) — and no manifest declares
any other. Earlier revisions of this file described a `SessionEnd` prompt hook that
"verifies all code is committed" and that `.kerby/STATUS.md` or `.kerby/memory.log` was
updated; no such hook was ever shipped, so the claim is removed rather than softened.

Committing before the session ends and updating the checkpoint files
(swe's `references/context-management.md`) are **behavioral** — held by the rules, not by a hook.

---

## Windows

**Claude Code runs hooks through Git Bash on Windows**, so kerby registers exactly what it
registers everywhere else — the launcher line, `~/.claude/kerby/bin/hook <event> <relpath>` — and it works unchanged (the launcher is POSIX `sh`, and Git Bash runs it). The
hook schema's `shell` defaults to `bash`, falling back to `powershell` only when Git Bash
is not installed.

Claude Code itself treats Git for Windows as optional — without it, it falls back to
PowerShell and keeps working. **kerby's hooks do not have that fallback**: a `.sh` handed
to PowerShell does not run. So what is optional for Claude Code is required for these
hooks to enforce anything. If Claude Code does not find it — a custom install location,
or a `PATH` that Git's installer never touched — point it there explicitly:

```json
{ "env": { "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe" } }
```

Point it at the `bash.exe` itself, not the folder containing it.

**Other harnesses reading the same settings file may not honor that contract.** Copilot CLI
reads `.claude/settings.json` too, and runs each hook in whatever shell the CLI itself is
in — on Windows, PowerShell, which cannot execute a `.sh`, so the script does not run.
That is a mismatch in the harness, not in what kerby wrote, and the remedy is on that
side: `disableAllHooks: true` in `.github/copilot/settings.local.json` stops Copilot
attempting them while leaving the same registrations working for Claude Code. It silences
every hook in that repository, not only kerby's. `multi-tool.md` § GitHub Copilot has the
detail and the caveats.

---

## Customizing Hooks

### Runtime Toggles (env vars)

Some hooks respect a single env var for ad-hoc disabling during a session — which ones is a tier question, not a security judgement (see the rule below; `codex-pr-gate` is not security-critical and still refuses it):

```bash
# Disable one hook
CODING_RULES_HOOK_DISABLED=session-start-context

# Disable several (comma-separated, no spaces)
CODING_RULES_HOOK_DISABLED=session-start-context,hollow-test-check
```

Hook names match the `# Name:` header in each script.

**The rule — a hook honors `CODING_RULES_HOOK_DISABLED` if and only if its tier is `optional`.** A hook's tier comes from the `[[check]]` that declares its `enforcer`, in the rulebook manifests installed alongside this file (`rulebooks/*/rulebook.toml`):

| Tier | The declaring check says | Honors the variable? |
|---|---|---|
| `locked` | `floor = true` | No |
| `recommended` | `severity = "block"`, no `floor` | No |
| `optional` | `severity = "warn"` or `"info"` | **Yes** |

Two rules finish it. Engine services under `resources/hooks/` declare no check at all and are every one `optional`. And where a single script backs several checks, the strictest tier wins — a script sharing an enforcer with a `floor` check is `locked` too, even if its other check is not.

**No inventory lives here, deliberately.** The hook set has relocated four times (the v9.0 `code` → `swe` rename, v9.3 moving `hollow-test-check` out of base, v9.16 adding `git_hook`), and each move left the hand-written table that used to sit here further behind — it had omitted `codex-pr-gate` entirely. Any list reintroduced here would start drifting the same day. To settle a specific hook, read the two fields in its manifest; that answer is current by construction.

Two notes the rule does not carry:

- `hollow-test-check` also honors the legacy token `pre-commit-check` — its pre-v9.3 name, from when this logic lived inside base's script. Anyone who disabled it under the old name keeps working.
- `knowledge-bootstrap`, `knowledge-reindex` and `knowledge-lint` additionally take a per-project opt-out: `agent-context.yaml` → `knowledge.enabled: false`. `context-bootstrap` takes `context.enabled: false`. Unlike the env var, these are committed, so they travel to teammates.

**Why `recommended` refuses the variable even though `install` will offer to decline it.** Declining at install is a deliberate act at a prompt, with a diff and a confirmation. An env var is ambient — it drifts in from a shell rc, a CI config, or an `.envrc` that direnv wrote in the very directory holding the `.env`. A protection should not switch off through state you forgot you set. To remove a `recommended` or `locked` hook permanently, make a deliberate `.claude/settings.json` edit.

`CODING_RULES_HOOK_PROFILE` is reserved for future use (named presets like `minimal` / `strict`). Not wired yet — use the disable list.

### Disabling Hooks (permanent)

If a hook is causing issues in your project, you can:
- Remove or modify the hooks in the skill's frontmatter
- Override with project-level settings in `.claude/settings.json`

### Adding Your Own Hooks

You can extend kerby's hooks by adding to your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "if": "Bash(rm -rf*)",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'BLOCKED: Destructive command detected.' >&2 && exit 2"
          }
        ]
      }
    ]
  }
}
```

### Hook Strictness Levels

| Exit Code | Behavior | Use For |
|-----------|----------|---------|
| `0` | Success — to add context for the agent, print JSON `{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"…"}}` on **stdout**. Plain (non-JSON) stdout and **stderr are NOT surfaced to the agent on exit 0** — a reminder written to stderr+exit 0 is silently dropped. | Reminders, soft warnings |
| `2` | Blocking error — action prevented, **stderr shown** to the agent | Security violations, hard rules |
| Other | Non-blocking error — logged, action proceeds | Diagnostics, optional checks |

> **Gotcha (cost us two hooks):** on exit 0 the only channel the agent reads is JSON-on-stdout (`additionalContext`). A non-blocking advisory must use that — *not* `echo … >&2`. stderr reaches the agent only on the exit-2 block path. For an advisory that must not block, emit `additionalContext` and set **no** `permissionDecision` (a `permissionDecision` of `allow`/`deny` would auto-approve or block the call).

---

## How Hooks Map to the Playbook

| Playbook Rule | Enforcement Without Hooks | Enforcement With Hooks |
|--------------|--------------------------|----------------------|
| Read project state first | Agent must remember | SessionStart injects state automatically |
| Bootstrap `.kerby/knowledge/` on first use | Agent must remember (often forgets) | SessionStart scaffolds + flags stale entries |
| Keep `KNOWLEDGE.md` index in sync with entries | Agent must remember on every entry change | SessionStart reindexes; agent calls `knowledge-reindex.sh --force` for mid-session updates |
| Never commit secrets | Agent must self-check | Already-staged secrets hard-blocked, for the forms a static pass can resolve — **but `git add x && git commit`, wrappers and aliases are not seen**, so the agent must still self-check (see `threat-model.md`) |
| Never overwrite an existing `.env` | Agent must self-check | Hard-blocked before the edit happens — Edit/Write only, so a shell redirect still needs self-check (templates and creating an absent env file stay allowed) |
| Run quality gates | Agent must remember | **Still must remember** — no hook verifies this; swe's post-commit reminder is advisory and disablable |
| Create checkpoints | Agent must remember | **Still must remember** — no hook verifies this |

Hooks turn "the agent should do X" into "X happens automatically." The playbook's written instructions remain the source of truth — hooks enforce the most critical rules deterministically.
