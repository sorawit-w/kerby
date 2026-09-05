<p align="center">
  <img src="https://raw.githubusercontent.com/sorawit-w/kerby/main/assets/kerby-li.png" alt="kerby — one author's operating system for agentic coding" width="100%"/>
</p>

# kerby

A Claude Code skill in two parts: a **domain-blind engine** (loads rulebooks, validates them, pins trust, registers guardrail hooks, renders verdicts) and **pluggable rulebooks** that carry the actual judgment. The engine has no opinions; the rulebooks are nothing but.

The bundled **`swe` rulebook** — the origin of the whole project, and what an unpinned load detects in a repo carrying a build manifest — loads **one specific person's** operating system for agentic coding: branching discipline, commit cadence, verification gates, sub-agent delegation triggers, ambiguity-before-cost rules, and a small amount of taste about how rules themselves should be written. Its workflows, commands (`prepare`, `audit`), and opinions are documented in [its own README](rulebooks/swe/README.md). Other rulebooks can be dropped in as folders, loaded from a path, or pulled from a GitHub repo — see [`docs/AUTHORING-RULEBOOKS.md`](../../docs/AUTHORING-RULEBOOKS.md).

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
- **Engine sub-commands** routed via the `args` parameter: `load` (default), `unload`, `reload`, `status`, `install`, `uninstall`, `rulebooks list|create`, `commands`, `hooks`, `check-updates`. Loaded rulebooks add their own commands — the `swe` rulebook provides `prepare` and `audit` ([its README](rulebooks/swe/README.md) documents them).
- **Per-project install** appends a single instruction line to your `CLAUDE.md` / `AGENTS.md` / `AI-CONTEXT.md` / `.cursorrules` so future sessions auto-invoke `kerby` at start. **Per-file confirmation required — never silent.**
- **Compaction-safe.** Long sessions can strip earlier context; `args: status` checks whether each selected rulebook's markers are still present (for the bundled `swe`, its BOOTSTRAP signatures; other rulebooks scan via their own manifest `[identity]`), `args: reload` re-injects them.

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
| `load` (default) | Select rulebooks (explicit arg — id, path, URL, or `owner/repo` → `.kerby/rulebooks.lock` pin → builtin-marker detection → ask the user; no silent default). **An explicit arg adds to the pinned selection — it never replaces it** (already selected = in-context refresh; removal is `unload`'s job). Reads **every selected rulebook's** eager prose — e.g. `rulebooks/swe/BOOTSTRAP.md` plus the base floor rules — via `Read` so it enters context as a tool result; announces one line per selected rulebook, plus `selection: <list>` when the pin changes; confirms to user. On an unpinned repo the first session may detect (one builtin's markers match) or ask (several match, or none), then writes the pin so later sessions load silently. External (`local`) rulebooks pass a one-time trust review with a hash pin first. |
| `unload <id>` | Drop one rulebook from the pinned selection (swap = `unload`, then `load`). Deletes no files, approvals, or hooks — a later `load` re-selects without a fresh trust prompt while the hash still matches. |
| `reload` | Same as `load`, refreshing every selected rulebook in context (the bundled `swe` confirms with its "BOOTSTRAP refreshed" line; other rulebooks via their own manifest `[identity]` or the generic template). Useful after Claude Code compacts the conversation. |
| `status` | Scan recent context for each selected rulebook's markers (for the bundled `swe`, its BOOTSTRAP signatures like `Prime Directive`; other rulebooks via their manifest `[identity]` phrases); report loaded / partially loaded / not loaded per rulebook, plus the rulebook panel — each check's declared vs. *effective* enforcement, with degrades and named gaps visible. |
| `hooks` | **Read-only.** Show what `install` would register — the Phase 2 candidate set, one row per enforcer with its tier, trigger, the checks it binds, and whether it is currently registered. Binding is reported against one named settings file (the project's `.claude/settings.local.json` by default; `--settings <path>` for another), because the same enforcer can be registered globally and absent locally. Orphaned registrations and missing scripts are listed too. Writes nothing. |
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

1. **Resolves the install root** and, from it, the relpath of each bundled hook script — the `PreToolUse` enforcers under `rulebooks/<rulebook>/hooks/` and the `SessionStart` services under `resources/hooks/` (the engine-services root). Discovery order is the locator in `SKILL.md` § Locating the bundled rule content — the harness-provided skill directory, then `${KERBY_DIR}`, then ask. It deliberately does **not** search for the install: a recursive glob let workspace content pick the trust root, and an enumerated path list can be neither authenticated nor kept complete.
2. **Asks where to register**:
   - `~/.claude/settings.json` (global — applies to every project)
   - `<project>/.claude/settings.local.json` (project, gitignored — your machine only) — **default**
   - `<project>/.claude/settings.json` (project, committed — teammates also inherit)
3. **Builds the hook entries** as `~/.claude/kerby/bin/hook <event> <relpath>` — a small launcher `install` copies to your user-local `~/.claude/kerby/bin/`, which resolves the install root at hook time from `~/.claude/kerby/install-root` (refreshed by every `kerby load`), so the registrations survive an install that moves — then shows them as a table and asks — `all`, `choose` (walk the declinable rows, each defaulting to yes), or `none`. How many entries there are depends on the selection and on what you decline, so no count is quoted here. The `Tier` column is derived from each check's `floor`/`severity` (`docs/rulebook-contract.md` § Hook tiers): `locked` rows are shown but never offered for decline; `recommended` and `optional` rows are. The `CHECKS IT BINDS` column lists each check the enforcer binds as `<id> (<kind>, <enforcement>)`, copied from the manifest — there is deliberately no prose description column, since `[[check]]` has no field to source one from. The `Resolved from` column is the install-relative directory each script lives in:

   | Tier | Event | Matcher | Script | Resolved from | What it does |
   |---|---|---|---|---|---|
   | `recommended` | `PreToolUse` | `"Edit\|Write"` | `protect-env.sh` | `rulebooks/swe/hooks/` | Hard-block edits to an existing credential file, and to any env-file name that aliases one (symlink / hard link) or is relative. Templates (`.env.example`/`.template`/`.sample`) and creating an absent env file stay allowed (security — not env-var disablable) |
   | `locked` | `PreToolUse` | `"Bash"` | `protect-git.sh` | `rulebooks/swe/hooks/` | Hard-block destructive git (`reset --hard`, `push --force` to protected branches, `clean -f`, etc.) — security, not env-var disablable |
   | `locked` | `PreToolUse` | `"Bash"` | `pre-commit-check.sh` | `rulebooks/base/hooks/` | The base floor's **pure secret scan** — hard-block on detected secrets in staged files. Base's own registration, offered under every selection since `base` merges under every rulebook; `locked`, so never offered for decline and never env-var disablable |
   | `optional` | `PreToolUse` | `"Bash"` | `hollow-test-check.sh` | `rulebooks/swe/hooks/` | swe's self-contained soft check (v9.3): flag hollow tests + remind to run the gates at commit — a *separate* `Bash` entry from base's scan, disablable via `CODING_RULES_HOOK_DISABLED=hollow-test-check` |
   | `optional` | `PreToolUse` | `"Read"` | `warn-env-read.sh` | `rulebooks/swe/hooks/` | Soft-remind when reading `.env` files (env-var disablable) |
   | `optional` | `PreToolUse` | `"Edit\|Write"` | `route-high-stakes.sh` | `rulebooks/swe/hooks/` | Remind when editing a §3 high-stakes path — advisory routing, not a block |
   | `optional` | `SessionStart` | `""` | `session-start-context.sh` | `resources/hooks/` | Inject `.kerby/STATUS.md` head + recent `.kerby/memory.log` so the agent resumes with state |
   | `optional` | `SessionStart` | `""` | `knowledge-bootstrap.sh` | `resources/hooks/` | Scaffold `.kerby/knowledge/KNOWLEDGE.md` if missing; reindex AUTO-INDEX block; flag entries older than 180 days |
   | `optional` | `SessionStart` | `""` | `context-bootstrap.sh` | `resources/hooks/` | Scaffold `CONTEXT.md` (project domain glossary) if missing; never overwrites |

   (`SKILL.md` is the source of truth for the full derivation — base-first dedup, with shim-following still supported for an *external* rulebook that shims into a shared script. As of v9.3 the bundled `swe` is self-contained: base's secret scan and swe's `hollow-test-check.sh` are **two distinct `Bash` entries**, not one shimmed registration. The table above is a `swe`-on-`base` install.)

4. **Shows the full diff** of the merged settings.json — additions *and* removals. If a removal would drop a `locked` or `recommended` protection, that is called out in its own block above the diff, so it cannot hide among routine changes. One final `Apply this diff? [y/n]` — separate from the per-hook choices above, and the last point at which nothing has been written yet. On `n`, nothing is.
5. **Re-runnable, and it can now delete.** Re-running skips already-managed entries the derivation still produces, and *removes* managed entries absent from the accepted set — a hook declined this run, one whose script is gone, or one whose `matcher`/`event` changed. **Removal is scoped to project settings files:** in global `~/.claude/settings.json` only dead-script entries are pruned, because another project's registration there is indistinguishable from a decline; a decline is reported instead, under `Declined, left registered`. Declines are not persisted, so a re-run re-asks every declinable row; answering `all` reproduces the previous full set exactly. `status` reports a leftover entry as `orphaned registration — re-run kerby install`.

`uninstall` mirrors symmetrically, removing only entries whose resolved path sits under a kerby hook root. Hand-written hook entries with the same script names but different paths are left alone.

### Disabling individual hooks at runtime

Once hooks are registered, a hook honors the `CODING_RULES_HOOK_DISABLED` env var (comma-separated, no spaces) **if and only if its tier is `optional`** — meaning the `[[check]]` declaring it sets `severity = "warn"` or `"info"`, or it is an engine service under `resources/hooks/`, which are all `optional`. A check with `floor = true` (`locked`) or `severity = "block"` (`recommended`) refuses the variable. To settle a specific hook, read those two fields in `rulebooks/*/rulebook.toml`; `resources/references/hooks.md` carries the full rule.

```bash
# Disable one hook for the current shell
export CODING_RULES_HOOK_DISABLED=session-start-context

# Disable several
export CODING_RULES_HOOK_DISABLED=session-start-context,hollow-test-check,knowledge-bootstrap
```

> **Note on the legacy `pre-commit-check` token:** before v9.3 the hollow-test soft check lived inside base's `pre-commit-check.sh` under that name. `hollow-test-check.sh` still honors the legacy `pre-commit-check` token, so an old disable setting keeps working — but it now disables only the **hollow-test soft check**, never the secret scan (which is non-disablable by design).

**To remove a `locked` or `recommended` hook**, edit your settings file and delete the entry — a deliberate config edit, never an ambient variable that can drift in from a shell rc, a CI config, or an `.envrc`. Declining a `recommended` hook when `install` walks the declinable rows is the other route, and leaves nothing behind to edit. A `locked` hook is never in that walk — the settings edit is its only route.

### Plugin-level activation is intentionally NOT supported

Hooks are never auto-registered at plugin install time. Specifically: the parent plugin's `plugin.json` carries no `hooks` field, and there is no `hooks/hooks.json` at the plugin root. This is by design — installing the plugin must never silently add guardrail hooks to your projects. Activation stays skill-scoped, opt-in via Phase 2 of `install`.

## What's inside

Two folders, two jobs — the v7 split made physical:

**`rulebooks/`** — the rules, as self-contained folders (copy one, get a governed domain):

- **`rulebooks/base/`** — the universal floor, merged under every rulebook: `secrets-staged` (+ its `pre-commit-check.sh` enforcer), `no-print-secret`, `untrusted-agent-artifacts`, `iron-law-claims`, `approval-for-irreversible`. Non-overridable.
- **`rulebooks/swe/`** — the software-engineering rulebook (auto-detected on a repo with a build manifest, v9.1): `BOOTSTRAP.md` (the root body: Prime Directive, routing, hard rules, reference index), `workflows/` (the five task-shape playbooks), `references/` (~26 long-tail topic guides), `hooks/` (the tool-boundary enforcers: `protect-env.sh`, `protect-git.sh`, `warn-env-read.sh`, `route-high-stakes.sh`, and its self-contained `hollow-test-check.sh` — v9.3, no longer a shim into base), `commands/` (`audit`, `prepare`), `templates/` + `scripts/` (incl. `check-plan-gate-parity.sh`, the swe plan-gate constant guard relocated here in v9.5.1) + `agent-context.schema.yaml` (the per-project `agent-context.yaml` contract and its validator).

**`resources/`** — engine machinery only, rulebook-agnostic:

- **`hooks/`** — the SessionStart services (`session-start-context.sh`, `knowledge-bootstrap.sh`, `context-bootstrap.sh`) plus knowledge tooling (`knowledge-reindex.sh`, `knowledge-lint.sh` — advisory `.kerby/knowledge/` integrity check; `--strict` to fail on findings).
- **`templates/`** — the state templates (`STATUS.md`, `KNOWLEDGE.md`, `CONTEXT.md`) the services scaffold into a project's `.kerby/`.
- **`scripts/validate-rulebook.py`** — the manifest/trust validator every `load` runs.
- **`references/`** — engine docs: `hooks.md` (registration + lifecycle) and `multi-tool.md` (Claude Code / Codex / Cursor wiring).

Rulebook-specific opinions (branching defaults, commit cadence, verification taste) and
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
