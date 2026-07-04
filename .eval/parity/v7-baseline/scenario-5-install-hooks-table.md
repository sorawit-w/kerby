# v7-baseline — install Phase 2 hook set (v6.0.0 @ b161c32)

v7 derives this set from manifests; the derived (event, matcher, filename)
tuple-SET must equal this table exactly (paths re-rooted per map; dedup per V14).

### Phase 2 — Claude Code lifecycle hooks (optional)

After Phase 1 completes, ask once:

> Also register `kerby`' Claude Code lifecycle hooks (`PreToolUse` / `SessionStart`)? These give deterministic enforcement on top of the rules — `protect-env`, `protect-git`, and `pre-commit-check` block destructive actions, `warn-env-read` soft-reminds on `.env` reads, and `route-high-stakes` reminds when you edit a §3 high-stakes path; the SessionStart trio (`session-start-context`, `knowledge-bootstrap`, `context-bootstrap`) injects prior project state and scaffolds `.ai/knowledge/` + `CONTEXT.md`. Read `resources/references/hooks.md` first if you haven't. [y/n]

If `n`, end the install — Phase 2 is skipped, the skill is still fully usable. (Registration is the executable trust opt-in: the rulebook's `hard`/`partial` checks stay declared either way, but their *effective* enforcement degrades to behavioral until their enforcers are registered — `status` shows the difference.)

If `y`:

1. **Resolve the absolute path** to the bundled hooks directory. First match wins:
   1. The parent of the BOOTSTRAP.md location resolved at `load` time, plus `/hooks` (e.g., `<install-root>/resources/hooks`).
   2. `Glob` pattern `**/skills/kerby/resources/hooks` — first match.
   3. `${KERBY_DIR}/resources/hooks` if the env var is set.
   4. If all fail, ask the user for the path.

2. **Pick the settings file**. Ask:

   > Where should hooks be registered?
   >   1. `~/.claude/settings.json` (global — every project you work on)
   >   2. `<project>/.claude/settings.local.json` (this project, your machine only — gitignored)
   >   3. `<project>/.claude/settings.json` (this project, committed — teammates also inherit)
   > Choose 1, 2, or 3. **Default: 2** (lowest blast radius, easiest to revert).

3. **Read or create the settings file.** If missing, create with `{}`. Read existing JSON. **If the JSON is malformed, STOP** and ask the user to fix it before re-running — never overwrite a file we couldn't parse.

4. **Build the hook entries** with absolute paths to the resolved hook scripts. The exact set, in this order:

   | Event | Matcher | Script |
   |---|---|---|
   | `PreToolUse` | `"Edit\|Write"` | `<hooks-dir>/protect-env.sh` |
   | `PreToolUse` | `"Read"` | `<hooks-dir>/warn-env-read.sh` |
   | `PreToolUse` | `"Bash"` | `<hooks-dir>/protect-git.sh` |
   | `PreToolUse` | `"Bash"` | `<hooks-dir>/pre-commit-check.sh` |
   | `PreToolUse` | `"Edit\|Write"` | `<hooks-dir>/route-high-stakes.sh` |
   | `SessionStart` | `""` | `<hooks-dir>/session-start-context.sh` |
   | `SessionStart` | `""` | `<hooks-dir>/knowledge-bootstrap.sh` |
   | `SessionStart` | `""` | `<hooks-dir>/context-bootstrap.sh` |

   Each entry uses the standard Claude Code hook shape:

   ```json
   {
     "matcher": "<matcher>",
     "hooks": [
       { "type": "command", "command": "<absolute-path-to-script>" }
     ]
   }
   ```

5. **Detect already-managed entries.** A hook entry is *kerby-managed* iff its `command` ends in one of the eight script filenames above AND its path contains `/skills/kerby/resources/hooks/`. Skip already-present entries — Phase 2 is idempotent.

6. **Show the full diff** — print a unified diff of what will be added to the chosen settings file. Include the resolved absolute paths so the user can verify them.

7. **Single final confirmation** — `Apply this diff? [y/n]`. On `n`, abort cleanly without modifying the file. On `y`, write the merged JSON back, preserving any unrelated keys exactly.

8. **Summarize Phase 2**:

   > Phase 2: registered `<N>` hook entries in `<settings-path>`. Already-present: `<list>`. Skipped (user declined): `<list>`.

### Phase 2 edge cases

- **User has hand-written hook entries pointing at the same script paths.** Treat them as already-installed; do not add a duplicate.
- **User has unrelated `hooks` content in the same settings file.** Preserve it exactly. We only touch our own entries inside `hooks.PreToolUse[*]` and `hooks.SessionStart[*]`.
- **`pre-commit-check.sh` overlap with a git-side `.git/hooks/post-commit` install of `knowledge-reindex.sh`.** They are independent — the former is a Claude Code PreToolUse hook on `Bash`, the latter is a git-side post-commit hook documented separately in `references/hooks.md`. Phase 2 only registers the Claude Code lifecycle hooks; the git-side post-commit hook stays a manual, opt-in install per the doc.

### Idempotency and re-runs

`install` is safe to re-run. Phase 1 reports already-installed vendor files as `already installed` and skips. Phase 2 detects already-managed hook entries by their absolute-path signature and skips. No duplicates introduced by re-running.

---
