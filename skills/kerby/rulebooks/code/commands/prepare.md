## `prepare`

Onboard an **existing repo** into kerby — populate (and refresh) the artifacts BOOTSTRAP's `detect_project` step reads (`agent-context.yaml`, `CONTEXT.md`, `.ai/knowledge/`, `.ai/STATUS.md`, `.ai/memory.log`) from the repo's real code and git history. This is the existing-code counterpart to `new-project.md` (greenfield) and to the resume flow in `references/project-entry.md` (read-and-continue).

1. Resolve the install root the same way `load` does (Glob `**/skills/kerby/SKILL.md`, else `${KERBY_DIR}`, else ask). The workflow file lives at `<install-root>/rulebooks/code/workflows/adopt-existing.md`.
2. **Read `rulebooks/code/workflows/adopt-existing.md` in full** with the `Read` tool, then follow it. It carries the procedure: tiered population by inferability, diff-and-confirm on every write, and per-tier refresh rules that never clobber human-curated content.
3. The workflow modifies user files — but **only ever behind a per-artifact diff-and-confirm**, exactly like `install`. Never write any artifact silently. Honor the out-of-scope ring-fence in the workflow (no quality gates, no tooling install — including SAST provisioning, which is an audit-time `--sast` concern, not onboarding — no `ROADMAP.md`, no commits/merge, no secret contents).

`prepare` is safe to re-run: per the workflow's refresh rules it re-derives only agent-owned content and is a diffs-only near-no-op on an already-onboarded repo.

**Forcing the knowledge pass.** The `.ai/knowledge/` decision/lesson pass runs automatically only on first onboarding (empty `.ai/knowledge/`); once entries exist it is opt-in. To force it without the opt-in prompt, pass a knowledge-force signal with `prepare` — `args: prepare:knowledge`, `args: prepare --knowledge`, or natural language ("force the knowledge pass", "prepare and draft knowledge candidates"). The workflow runs the pass regardless of existing entries. Forcing only controls whether the pass runs — drafts are still `confidence: low`, still per-entry diff-and-confirm, and `confidence: high` entries stay frozen.

Edge case:
- **No git repo** → populate the code-derived artifacts only (`agent-context.yaml`, `CONTEXT.md`, `.ai/memory.log` stub); skip the git-history knowledge scan and record the branch as `n/a (no git)`; never `git init` to satisfy a step. Detail: `adopt-existing.md` § Core principles.
