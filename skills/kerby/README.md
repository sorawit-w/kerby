<p align="center">
  <img src="https://raw.githubusercontent.com/sorawit-w/kerby/main/assets/kerby-li.png" alt="kerby — one author's operating system for agentic coding" width="100%"/>
</p>

# kerby

A Claude Code skill in two parts: a **domain-blind engine** (loads rulebooks, validates them, pins trust, registers guardrail hooks, renders verdicts) and **pluggable rulebooks** that carry the actual judgment. The engine has no opinions; the rulebooks are nothing but.

The bundled **`swe` rulebook** — the default, and the origin of the whole project — loads **one specific person's** operating system for agentic coding: branching discipline, commit cadence, verification gates, sub-agent delegation triggers, ambiguity-before-cost rules, and a small amount of taste about how rules themselves should be written. Its workflows, commands (`prepare`, `audit`), and opinions are documented in [its own README](rulebooks/swe/README.md). Other rulebooks can be dropped in as folders, loaded from a path, or pulled from a GitHub repo — see [`docs/AUTHORING-RULEBOOKS.md`](../../docs/AUTHORING-RULEBOOKS.md).

> ⚠️ **Read this before installing.** The `swe` rulebook is **deliberately, aggressively opinionated** — one author's personal taste, not a "best-practice" guide or a neutral default. Read [its README](rulebooks/swe/README.md) and `rulebooks/swe/BOOTSTRAP.md` end-to-end before adopting; fork, edit, or skip rules that don't fit your taste.

## Companion skills

Skills you'll likely want alongside `kerby` — all ship in this same marketplace. Brief overview here; deeper integration notes in [Cross-skill integration](#cross-skill-integration) below.

| Skill | Use it for |
|---|---|
| [`team-composer`](https://github.com/sorawit-w/agent-skills/tree/main/skills/team-composer) | Multi-role discussion *before* coding — "monolith vs services?", "which DB?", "is this refactor worth it?" Surfaces trade-offs the rules can't. |
| [`sub-agent-coordinator`](https://github.com/sorawit-w/agent-skills/tree/main/skills/sub-agent-coordinator) | Coordination patterns *during* execution — fan-out, pipeline, specialist routing, briefing templates. The natural sibling to BOOTSTRAP's `sub-agent-delegation` reference. |
| [`wear-the-hat`](https://github.com/sorawit-w/agent-skills/tree/main/skills/wear-the-hat) | When you want one specific lens applied to a task without convening a full panel — `@security_specialist` on auth code, `@dataviz_engineer` on a chart, `@accessibility_specialist` on a UI. Single-role embodiment. |
| [`skill-evaluator`](https://github.com/sorawit-w/agent-skills/tree/main/skills/skill-evaluator) | Auditing rule changes via split-context review — never grade rules in the same agent that wrote them. |
| [`tech-stack-recommendations`](https://github.com/sorawit-w/agent-skills/tree/main/skills/tech-stack-recommendations) | Picking a runtime / framework / database / hosting target on a new project or migration. Pairs with `workflows/new-project.md`. |

None are required — `kerby` works on its own. They sharpen the edges where it deliberately stays thin (multi-role planning, sub-agent coordination, rule evaluation, stack selection).

## What it does

- **Loads the selected rulebook's root body** (for `swe`, `rulebooks/swe/BOOTSTRAP.md`) into the current session via the `Read` tool, so the rules enter conversation context as a tool result (not a paraphrase).
- **Engine sub-commands** routed via the `args` parameter: `load` (default), `unload`, `reload`, `status`, `install`, `uninstall`, `rulebooks list|create`. Loaded rulebooks add their own commands — the `swe` rulebook provides `prepare` and `audit` ([its README](rulebooks/swe/README.md) documents them).
- **Per-project install** appends a single instruction line to your `CLAUDE.md` / `AGENTS.md` / `AI-CONTEXT.md` / `.cursorrules` so future sessions auto-invoke `kerby` at start. **Per-file confirmation required — never silent.**
- **Compaction-safe.** Long sessions can strip earlier context; `args: status` checks whether BOOTSTRAP markers are still present, `args: reload` re-injects them.

## What it doesn't do

- **Auto-trigger on general coding tasks.** This is opt-in only — the user must explicitly mention `kerby`, `/kerby`, or ask to load/install/check it. The rules are a meta-system, not a fix for individual bugs.
- **Modify your code.** The rules govern *how* the agent works; they don't ship code edits.
- **Silently change vendor files.** `install` and `uninstall` ask per-file before touching `CLAUDE.md` etc. If you say no, nothing happens.
- **Replace your judgment.** Every rule has a stated reason; if the reason doesn't apply to your project, the rule shouldn't either.
- **Pretend to be evaluated.** Rule changes route to a separate skill ([`skill-evaluator`](https://github.com/sorawit-w/agent-skills/tree/main/skills/skill-evaluator)) for a split-context audit. Inline grading by the same agent that wrote the rule is exactly what the evaluator is designed to avoid.

## When to use it

- You're working with Claude Code, Codex, Cursor, or another agent and you want a **shared frame** the agent will follow without you re-typing it every session.
- You've already fork-and-edited the rules so they reflect *your* taste — and want them to load reliably across sessions in a project.
- You want a **compaction-safe loader**: even if a long session strips earlier context, a one-line reload restores the rules.
- You want per-project install hygiene that touches one line in your vendor agent-instruction file and stops there.

## When not to use it

- **You haven't read `rulebooks/swe/BOOTSTRAP.md`.** Loading rules you haven't read defeats the purpose. The cost is paid in tokens on every session; the value is paid out only when the rules match your judgment.
- **The rules conflict with your team's conventions.** Branching and commit discipline rules are not universal. If your team batches commits or works on `main`, this skill will fight you. Fork and adapt.
- **You want a neutral, "best-practice" preamble.** This isn't that. Try a more general guide instead.
- **You're trying to fix a specific bug.** The skill governs how tasks are done — it doesn't *do* the task. Use a debugging skill (e.g., [`engineering:debug`](https://github.com/anthropics/skills) or [`anthropic-skills:diagnose`](https://github.com/anthropics/skills)) for that.

## Sub-commands

The skill is invoked via `Skill` tool with `args: <sub-command>`. Defaults to `load` if `args` is empty.

| Sub-command | What it does |
|---|---|
| `load` (default) | Select rulebooks (explicit arg — id, path, URL, or `owner/repo` → `.kerby/rulebooks.lock` pin → default `swe`), announce it in one line, then read its eager prose — `rulebooks/swe/BOOTSTRAP.md` plus the base floor rules — via `Read` so it enters context as a tool result, confirm to user. External (`local`) rulebooks pass a one-time trust review with a hash pin first. |
| `reload` | Same as `load`, but with a "BOOTSTRAP refreshed" confirmation. Useful after Claude Code compacts the conversation. |
| `status` | Scan recent context for BOOTSTRAP signatures (e.g., `Prime Directive`, `<hard_rules>`, distinctive headers); report loaded / not loaded, plus the rulebook panel — each check's declared vs. *effective* enforcement, with degrades and named gaps visible. |
| `install` | **Phase 1** — append the session-start instruction to your vendor agent-instruction files (`CLAUDE.md` / `AGENTS.md` / `AI-CONTEXT.md` / `.cursorrules`), per-file confirmation. **Phase 2 (optional)** — register `kerby`' Claude Code lifecycle hooks (`PreToolUse` + `SessionStart`) in your chosen settings file. Both phases are independently skippable; both show a diff and require explicit confirmation. |
| `uninstall` | Mirror — Phase 1 removes the install line from vendor files; Phase 2 removes kerby-managed hook entries from your chosen settings file. Both phases optional, both confirmed. |
| `kerby swe prepare` *(rulebook command)* | Onboard an existing repo — populate kerby's context artifacts from code + git history, diff-and-confirm on every write. Full docs in the [swe README](rulebooks/swe/README.md#commands). |
| `kerby swe audit` *(rulebook command)* | Read-only static conformance audit → HTML report under `.kerby/audits/`. Full docs in the [swe README](rulebooks/swe/README.md#commands). |

`install` and `uninstall` are idempotent — re-running is safe. Rulebook commands are declared by each rulebook's manifest and dispatched by the engine; the bare form (`/kerby audit`) works while exactly one loaded rulebook provides that command (inference).

### How to invoke

Slash command (recommended — unambiguous):

```bash
/kerby               # default sub-command: load
/kerby load          # explicit
/kerby reload        # after compaction
/kerby status        # check whether rules are still loaded
/kerby install       # persistent per-project setup
/kerby uninstall     # mirror — both phases
/kerby swe prepare  # onboard an existing repo (populate context)
/kerby swe prepare:knowledge  # prepare + force the .kerby/knowledge candidate pass
/kerby swe audit    # conformance audit → HTML report (incremental)
/kerby swe audit --full security  # whole-repo, security dimension only
```

If no other installed plugin defines a `kerby` skill, the short form `/kerby` also resolves. The namespaced form is always unambiguous and recommended. Rulebook commands (`prepare`, `audit` — provided by the `swe` rulebook) are shown in their qualified `kerby <rulebook> <command>` form; the bare form (`/kerby audit`) also works while exactly one loaded rulebook provides that command (inference).

Or in natural language — Claude will route correctly:

- "load kerby"
- "install kerby in this project"
- "are kerby still loaded?"
- "reload kerby — they seem to have stopped applying"
- "uninstall kerby"
- "onboard this repo into kerby" / "make this repo kerby-ready" / "prepare this repo"
- "prepare this repo and force the knowledge pass" (forces the opt-in `.kerby/knowledge/` candidate pass)
- "audit this repo against kerby" / "run a kerby conformance audit" / "audit the security dimension"

### `load` vs `install` — they're independent

The two most-used sub-commands have different lifetimes. Worth understanding before you reach for either.

- **`load`** reads `BOOTSTRAP.md` into the **current session's** context. The rules are active now and only now — when the session ends or context is compacted, they're gone.
- **`install`** appends one instruction line to your project's vendor agent-instruction files (and, optionally, registers hooks) so **future sessions** auto-invoke `load` at session start. It does NOT touch the current session's BOOTSTRAP state.

Neither command requires the other. Typical patterns:

```bash
# One-off in this session only — no persistence
/kerby load

# Persistent setup for future sessions — no immediate effect on this session
/kerby install

# First time in a project: persist AND activate now
/kerby install
/kerby load
```

**Subtle gotcha:** right after running `install` for the first time, BOOTSTRAP is **not** yet active in the current session — `install` only edited a file, it didn't load anything. Either run `load` manually in the same turn, or start a fresh session (where the install line in `CLAUDE.md` etc. will auto-fire `load`).

After `install` is applied to a project, every future session in that project auto-loads via the install line — you shouldn't need to type anything. Exceptions:

- **Mid-session compaction** stripped BOOTSTRAP → `/kerby reload` (or run `status` first to confirm).
- **You want to verify** the rules are still active → `/kerby status`.

## What `install` actually does — two independent phases

This is the most surface-area part of the skill, so the contract is laid out explicitly:

### Phase 1 — vendor agent-instruction files (one-line append)

For each detected file (`CLAUDE.md`, `AGENTS.md`, `AI-CONTEXT.md`, `.cursorrules`), the skill asks per-file before appending:

```
At session start, invoke the `kerby` skill (args: load) to load kerby guardrails into context.
```

Skipping a file leaves it untouched. Already-installed files are detected and skipped silently. No other content is modified.

### Phase 2 — Claude Code lifecycle hooks (settings.json registration, optional)

After Phase 1 completes, the skill asks once whether to register hooks. **Not required** — Phase 2 can be skipped entirely, and the skill still works (BOOTSTRAP load + reload + status are independent of hooks).

If accepted, the skill:

1. **Resolves the absolute paths** to the bundled hook scripts — the `PreToolUse` enforcers under `<install-root>/rulebooks/<rulebook>/hooks/` and the `SessionStart` services under `<install-root>/resources/hooks/` (the engine-services root). Discovery order: BOOTSTRAP-relative path (from `load`) → Glob match → `${KERBY_DIR}` env var → ask the user.
2. **Asks where to register**:
   - `~/.claude/settings.json` (global — applies to every project)
   - `<project>/.claude/settings.local.json` (project, gitignored — your machine only) — **default**
   - `<project>/.claude/settings.json` (project, committed — teammates also inherit)
3. **Builds eight hook entries** with absolute paths to the resolved scripts (the `Resolved from` column is the install-relative directory each script lives in):

   | Event | Matcher | Script | Resolved from | What it does |
   |---|---|---|---|---|
   | `PreToolUse` | `"Edit\|Write"` | `protect-env.sh` | `rulebooks/swe/hooks/` | Hard-block edits to `.env` files (security — not env-var disablable) |
   | `PreToolUse` | `"Bash"` | `protect-git.sh` | `rulebooks/swe/hooks/` | Hard-block destructive git (`reset --hard`, `push --force` to protected branches, `clean -f`, etc.) — security, not env-var disablable |
   | `PreToolUse` | `"Bash"` | `pre-commit-check.sh` | `rulebooks/base/hooks/` | Soft-warn on missing quality gates before `git commit`; hard-block on detected secrets in staged files (the floor scan; `swe` binds it via a confined shim — one registration) |
   | `PreToolUse` | `"Read"` | `warn-env-read.sh` | `rulebooks/swe/hooks/` | Soft-remind when reading `.env` files (env-var disablable) |
   | `PreToolUse` | `"Edit\|Write"` | `route-high-stakes.sh` | `rulebooks/swe/hooks/` | Remind when editing a §3 high-stakes path — advisory routing, not a block |
   | `SessionStart` | `""` | `session-start-context.sh` | `resources/hooks/` | Inject `.kerby/STATUS.md` head + recent `.kerby/memory.log` so the agent resumes with state |
   | `SessionStart` | `""` | `knowledge-bootstrap.sh` | `resources/hooks/` | Scaffold `.kerby/knowledge/KNOWLEDGE.md` if missing; reindex AUTO-INDEX block; flag entries older than 180 days |
   | `SessionStart` | `""` | `context-bootstrap.sh` | `resources/hooks/` | Scaffold `CONTEXT.md` (project domain glossary) if missing; never overwrites |

   (`SKILL.md` is the source of truth for the full derivation — base-first dedup, shim-following to the resolved target. The table above is the default `swe`-on-`base` install.)

4. **Shows the full diff** of the merged settings.json. Single y/n confirmation. On `n`, nothing is written.
5. **Idempotent** — re-running detects already-managed entries by their absolute-path signature (any script whose resolved path sits under a kerby hook root — `<install-root>/rulebooks/*/hooks/` or `<install-root>/resources/hooks/`) and skips them.

`uninstall` mirrors symmetrically, removing only entries whose resolved path sits under a kerby hook root. Hand-written hook entries with the same script names but different paths are left alone.

### Disabling individual hooks at runtime

Once hooks are registered, three soft hooks (non-security) can be temporarily disabled via the `CODING_RULES_HOOK_DISABLED` env var (comma-separated, no spaces):

```bash
# Disable one hook for the current shell
export CODING_RULES_HOOK_DISABLED=session-start-context

# Disable several
export CODING_RULES_HOOK_DISABLED=session-start-context,pre-commit-check,knowledge-bootstrap
```

Disablable: `session-start-context`, `knowledge-bootstrap`, `context-bootstrap`, `pre-commit-check` (soft reminder only — secret scan still runs).
**Not disablable** (security / data-loss critical): `protect-env`, `protect-git`. To bypass these, edit your settings file and remove the entry — a deliberate config edit, not an ambient variable.

### Plugin-level activation is intentionally NOT supported

Hooks are never auto-registered at plugin install time. Specifically: the parent plugin's `plugin.json` carries no `hooks` field, and there is no `hooks/hooks.json` at the plugin root. This is by design — installing the plugin must never silently add guardrail hooks to your projects. Activation stays skill-scoped, opt-in via Phase 2 of `install`.

## What's inside

Two folders, two jobs — the v7 split made physical:

**`rulebooks/`** — the rules, as self-contained folders (copy one, get a governed domain):

- **`rulebooks/base/`** — the universal floor, merged under every rulebook: `secrets-staged` (+ its `pre-commit-check.sh` enforcer), `no-print-secret`, `untrusted-agent-artifacts`, `iron-law-claims`, `approval-for-irreversible`. Non-overridable.
- **`rulebooks/swe/`** — the software-engineering rulebook and silent default: `BOOTSTRAP.md` (the root body: Prime Directive, routing, hard rules, reference index), `workflows/` (the five task-shape playbooks), `references/` (~26 long-tail topic guides), `hooks/` (the tool-boundary enforcers: `protect-env.sh`, `protect-git.sh`, `warn-env-read.sh`, `route-high-stakes.sh`, + the confinement shim into base's pre-commit check), `commands/` (`audit`, `prepare`), `templates/` + `scripts/` + `agent-context.schema.yaml` (the per-project `agent-context.yaml` contract and its validator).

**`resources/`** — engine machinery only, rulebook-agnostic:

- **`hooks/`** — the SessionStart services (`session-start-context.sh`, `knowledge-bootstrap.sh`, `context-bootstrap.sh`) plus knowledge tooling (`knowledge-reindex.sh`, `knowledge-lint.sh` — advisory `.kerby/knowledge/` integrity check; `--strict` to fail on findings).
- **`templates/`** — the state templates (`STATUS.md`, `KNOWLEDGE.md`, `CONTEXT.md`) the services scaffold into a project's `.kerby/`.
- **`scripts/validate-rulebook.py`** — the manifest/trust validator every `load` runs.
- **`references/`** — engine docs: `hooks.md` (registration + lifecycle) and `multi-tool.md` (Claude Code / Codex / Cursor wiring).

Rulebook-specific opinions (worktree-default, commit cadence, verification taste) and
the rule-editing guide live with the rulebook — see the
[swe README](rulebooks/swe/README.md#a-note-on-opinionation).

## Install

This skill is distributed via the [`sorawit-w/kerby`](https://github.com/sorawit-w/kerby) plugin marketplace. From Claude Code or Cowork:

```
/plugin marketplace add sorawit-w/kerby
/plugin install kerby@kerby
```

Once the plugin is installed, the skill is available system-wide. Then, in any project where you want the rules to auto-load on session start:

```
> Use the kerby skill with args: install
```

The skill will detect your vendor agent-instruction files and ask per-file before adding the one-line invocation.

## Cross-skill integration

| Skill | Relationship |
|---|---|
| [`skill-evaluator`](https://github.com/sorawit-w/agent-skills/tree/main/skills/skill-evaluator) | Use for evaluating rule changes — never inline-grade in the same agent that wrote the rule. The skill's own `CLAUDE.md` enforces this. |
| `superpowers:*` *(if installed)* | Some superpowers skills overlap with the BOOTSTRAP rules (TDD, brainstorming, verification-before-completion). User instructions and explicit invocations win — see Phase 0.5 in `team-composer`'s docs for a pattern. |
| Project-local `CLAUDE.md` / `AGENTS.md` | Per the BOOTSTRAP priority order (User > Project config > Agent context > Playbook), the project's own instructions always win over rules in this skill. |

## Status

Extracted and renamed from `coding-rules` ([sorawit-w/agent-skills](https://github.com/sorawit-w/agent-skills)), full git history preserved — see [CHANGELOG.md](https://github.com/sorawit-w/kerby/blob/main/CHANGELOG.md) for the current release. The rules have been used and refined over time but the skill packaging in this marketplace is new. **Treat as alpha** — feedback on the loader behavior welcome via [issues](https://github.com/sorawit-w/kerby/issues). Rule-content feedback should generally take the shape of *fork-and-edit*, not feature-request.

## Contributions

Not accepting external contributions to the rule content — these are personal taste, and "everyone's opinion in one BOOTSTRAP.md" is not the goal. Bug reports on the loader (path resolution, install/uninstall edge cases) are welcome.

Feel free to fork.

## License

MIT — see the [LICENSE](https://github.com/sorawit-w/kerby/blob/main/LICENSE) file at the repo root.
