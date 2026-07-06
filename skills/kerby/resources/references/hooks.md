# Hooks — Automated Enforcement

Hooks are shell commands or LLM prompts that run automatically at specific lifecycle points. They provide **deterministic enforcement** of playbook rules — the agent can't skip them.

> **Note:** Hooks are currently supported by Claude Code. Other agents will ignore the hooks configuration in frontmatter but should still follow the playbook's written instructions.

---

## Active Hooks

kerby ships with these hooks:

> The coding enforcers (`.env` protection/read-warning, high-stakes routing,
> pre-commit check, quality-gate verification) are documented in the coding
> rulebook that declares them — e.g. the bundled `swe` rulebook's own
> `references/hooks.md`. This engine reference covers only the engine-owned
> SessionStart/knowledge hooks below.

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
2. **Reindex** the AUTO-INDEX block in `KNOWLEDGE.md` from the title (frontmatter) and first body line of each entry file. Idempotent — only writes if content actually changed. Internally calls `knowledge-reindex.sh --force`.
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

### SessionEnd → Checkpoint Verification

**Type:** Prompt hook (LLM evaluation)
**Strictness:** Soft-verify

When the session ends, a prompt hook verifies that:
1. All code is committed (no uncommitted changes)
2. `.kerby/STATUS.md` or `.kerby/memory.log` was updated during the session

If the checkpoint is missing, the agent is reminded. This is advisory — it flags the gap but doesn't prevent session exit.

---

## Customizing Hooks

### Runtime Toggles (env vars)

Non-security hooks respect a single env var for ad-hoc disabling during a session:

```bash
# Disable one hook
CODING_RULES_HOOK_DISABLED=session-start-context

# Disable several (comma-separated, no spaces)
CODING_RULES_HOOK_DISABLED=session-start-context,hollow-test-check
```

Hook names match the `# Name:` header in each script. Current names:

| Name | Disablable? |
|------|-------------|
| `session-start-context` | Yes |
| `context-bootstrap` | Yes |
| `knowledge-bootstrap` | Yes (or per-project: `agent-context.yaml: knowledge.enabled: false`) |
| `knowledge-reindex` | Yes (same per-project opt-out as `knowledge-bootstrap`) |
| `knowledge-lint` | Yes (same per-project opt-out as `knowledge-bootstrap`) |
| `hollow-test-check` | Yes — swe's soft hollow-test + commit reminder (v9.3). Honors the legacy alias `pre-commit-check` (its pre-v9.3 name inside base's script) |
| `warn-env-read` | Yes (soft `.env`-read reminder) |
| `route-high-stakes` | Yes (soft §3 high-stakes routing reminder) |
| `pre-commit-check` | No — the base floor's **secret scan** is never disablable (the `pre-commit-check` token is now only the legacy alias for `hollow-test-check` above, which is a different, self-contained script) |
| `protect-env` | No — security-critical, edit `.claude/settings.json` to remove |
| `protect-git` | No — data-loss-critical, edit `.claude/settings.json` to remove |

**Rule:** security-critical hooks cannot be disabled via env var. This is intentional. An env var is too easy to set accidentally (shell rc, CI config, `.envrc`) for a rule that blocks secret leaks. To bypass, make a deliberate config edit.

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
| Never commit secrets | Agent must self-check | Hard-blocked before commit happens |
| Never edit .env files | Agent must self-check | Hard-blocked before edit happens |
| Run quality gates | Agent must remember | Soft-verified when agent stops |
| Create checkpoints | Agent must remember | Soft-verified at session end |

Hooks turn "the agent should do X" into "X happens automatically." The playbook's written instructions remain the source of truth — hooks enforce the most critical rules deterministically.
