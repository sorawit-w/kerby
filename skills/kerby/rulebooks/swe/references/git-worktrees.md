# Git Worktrees — Isolated Parallel Branches

Worktrees give a branch its own physical directory within a single repository. In kerby they are the **escalation path, not the default** — the default is an in-place `git checkout -b` (BOOTSTRAP.md § Branching). This reference holds the tactics for when an escalation trigger applies.

---

## When to Use

| Situation | Use Worktree? | Reason |
|----------|---|---|
| Concurrent work on a *different branch* (parallel agents/sessions) | Yes | Necessity — git cannot check out two branches in one working tree |
| User or harness explicitly requests one | Yes | Explicit request; if the harness already runs you inside a worktree it provides, use that one — never nest a second |
| Uncommitted work elsewhere must survive untouched | Yes — announce first | Dirty-state preservation; announce and proceed |
| Feature/bugfix, solo serial — any size, any file count | No | The in-place default; task type and size are not triggers |
| Quick single-file tasks (`quick-task.md`) | No | Context switch overhead not justified |
| Sub-agent fan-out on one feature | No new worktrees | Sub-agents share the coordinator's working tree (`sub-agent-delegation.md`) |

See BOOTSTRAP.md § Branching for the escalation triggers — a worktree is never created silently; announce the trigger in one line before creating.

---

## Package Manager Detection

When an escalation trigger applies, check what a worktree costs on this stack — some managers duplicate dependencies per worktree, others share them globally.

| Lockfile | Manager | Worktree Cost |
|----------|---------|---|
| `bun.lockb` | Bun | duplication-safe ✓ |
| `pnpm-lock.yaml` | pnpm | duplication-safe ✓ |
| `.pnp.cjs` or `.pnp.js` | Yarn Berry PnP | duplication-safe ✓ |
| `yarn.lock` (no `.pnp`) | Yarn 1.x | duplication-safe ✓ |
| `deno.lock` | Deno | duplication-safe ✓ |
| `pyproject.toml` | Python | duplication-safe ✓ |
| `Cargo.toml` | Rust | duplication-safe ✓ |
| `go.mod` | Go | duplication-safe ✓ |
| `package-lock.json` | npm | expensive — duplicates `node_modules` (see note below) |
| (no lockfile) | (no install) | duplication-safe ✓ |

**npm cost note (never silent):** the in-place default already avoids `node_modules` duplication, so on most npm repos this note never fires. When a trigger *does* force a worktree on an npm repo (or one with `node_modules/ > 500MB` or >50 direct dependencies), create it and name the cost in the same one-line announcement — e.g. "creating worktree — trigger: concurrent branches; note: npm will duplicate node_modules." Cost never silently overrides a trigger, and no fallback happens without saying so.

---

## Creation

Create a new worktree with a clean branch:

```bash
git worktree add .worktrees/<branch-name> -b <type>/<description>
```

Example:

```bash
git worktree add .worktrees/feature-auth -b feature/auth
```

Then install and verify:

```bash
cd .worktrees/feature-auth
{package_manager} install    # bun install, pnpm install, etc.
{build_command} && {test_command}
```

The final `build && test` is a baseline verification — confirms the repo is clean before you start work. Pre-existing failures here are not your responsibility.

---

## Editor Workflow

After creation and install, open the worktree in your editor. Recommended approaches (do not mandate):

- **VS Code:** `code .worktrees/<name>`
- **Cursor:** `cursor .worktrees/<name>`
- **JetBrains (IntelliJ, PyCharm, Rust Rover):** File → Open → `.worktrees/<name>`
- **Current editor:** Refresh file tree and navigate — no new window required

The worktree behaves like a normal git repo directory. Editor choice is user preference.

---

## Cleanup & Lifecycle

After work is complete:

| Outcome | Action |
|---------|--------|
| Merged locally | `git worktree remove .worktrees/<name>` |
| PR opened | Keep worktree until PR merged; then `git worktree remove .worktrees/<name>` |
| Preserve for later | Keep worktree, note reason/branch in `.kerby/memory.log` |
| Explicit discard | `git worktree remove --force .worktrees/<name>` (requires intent) |

**Before discarding:** Verify with `git branch -v` that all work is pushed or committed to a safe location.

---

## Inspection & Status

List all active worktrees:

```bash
git worktree list
```

Output shows path, branch, commit SHA, and detach state. Use this to verify no stale or orphaned worktrees before concluding "repo is clean."

**Cross-worktree discipline:** `git status` in one worktree shows only that worktree's state. Always run `git worktree list` and spot-check each active worktree before concluding the repo is clean.

---

## Failure Modes & Recovery

| Issue | Recovery |
|-------|----------|
| "Worktree is locked" | `git worktree unlock .worktrees/<name>` |
| Directory deleted externally | `git worktree prune` (removes stale entries) |
| Branch already checked out in another worktree | Git prevents duplicate; use existing worktree instead |
| Orphaned worktree entries (`.git/worktrees/`) | `git worktree prune` cleans up dangling references |
| Long-path failures on Windows (260-char MAX_PATH) — builds/installs fail on deep `.worktrees/<branch>/node_modules/…` paths | `git config core.longpaths true` fixes git itself, **not** other tooling (MSBuild, node-gyp) that walks the same paths; keep branch names short; prefer the in-place default when no trigger forces isolation |

---

## Migration from In-Place Branches

If you're already on a traditional in-place branch when adopting worktrees:

- Finish the current branch normally (via existing checkout)
- Apply worktrees only to new branches going forward
- Do not retroactively convert old branches — it adds complexity and risk

---

## Prerequisites

Before creating your first worktree:

1. Ensure `.worktrees/` is in `.gitignore`
2. If not present, add it and commit:

```bash
echo ".worktrees/" >> .gitignore
git add .gitignore
git commit -m "chore: add .worktrees to gitignore"
```

Run this once per repo — it blocks accidental commits of worktree metadata.

---

Worktree tactical patterns adapted from obra/superpowers (MIT).
