# ENGINE-MAP v2 — the kerby v7 engine/rulebook file split

The executable companion to the v7.0.0 plan. Method: every file under `skills/kerby/`
gets exactly one destination, decided by the *"would a sales rulebook want it?"* test.
Target layout: `skills/kerby/resources/` = engine only; `skills/kerby/rulebooks/{base,code}/`
= self-contained content. **A file whose destination this map does not determine is a
BLOCKED condition, never a judgment call.**

Destinations: `engine` (stays under `resources/`) · `base` / `code` (move into
`rulebooks/<id>/…`) · `root` (skill root, unchanged) · `excluded` (not moved, not shipped).

## File-by-file table

| # | Current path (under `skills/kerby/`) | Destination | New path (under `skills/kerby/`) |
|---|---|---|---|
| 1 | `SKILL.md` | root | — |
| 2 | `README.md` | root | — |
| 3 | `CLAUDE.md` | root | — |
| 4 | `assets/bugfix-loop.svg` | code | `rulebooks/code/assets/bugfix-loop.svg` |
| 5 | `assets/feature-loop.svg` | code | `rulebooks/code/assets/feature-loop.svg` |
| 6 | `assets/workflow-routing.svg` | code | `rulebooks/code/assets/workflow-routing.svg` |
| 7 | `resources/BOOTSTRAP.md` | code | `rulebooks/code/BOOTSTRAP.md` |
| 8 | `resources/agent-context.schema.yaml` | code | `rulebooks/code/agent-context.schema.yaml` |
| 9 | `resources/.impeccable/hook.cache.json` | excluded | generated cache → `.gitignore` |
| 10 | `resources/hooks/.impeccable/hook.cache.json` | excluded | generated cache → `.gitignore` |
| 11 | `resources/hooks/context-bootstrap.sh` | engine | — |
| 12 | `resources/hooks/knowledge-bootstrap.sh` | engine | — |
| 13 | `resources/hooks/knowledge-lint.sh` | engine | — |
| 14 | `resources/hooks/knowledge-lint.test.sh` | engine | — |
| 15 | `resources/hooks/knowledge-reindex.sh` | engine | — |
| 16 | `resources/hooks/pre-commit-check.sh` | **base** (V14) | `rulebooks/base/hooks/pre-commit-check.sh` |
| 17 | `resources/hooks/pre-commit-check.test.sh` | **base** (V14) | `rulebooks/base/hooks/pre-commit-check.test.sh` |
| 18 | `resources/hooks/protect-env.sh` | code | `rulebooks/code/hooks/protect-env.sh` |
| 19 | `resources/hooks/protect-git.sh` | code | `rulebooks/code/hooks/protect-git.sh` |
| 20 | `resources/hooks/protect-git.test.sh` | code | `rulebooks/code/hooks/protect-git.test.sh` |
| 21 | `resources/hooks/route-high-stakes.sh` | code | `rulebooks/code/hooks/route-high-stakes.sh` |
| 22 | `resources/hooks/route-high-stakes.test.sh` | code | `rulebooks/code/hooks/route-high-stakes.test.sh` |
| 23 | `resources/hooks/session-start-context.sh` | engine | — |
| 24 | `resources/hooks/session-start-context.test.sh` | engine | — |
| 25 | `resources/hooks/warn-env-read.sh` | code | `rulebooks/code/hooks/warn-env-read.sh` |
| 26 | `resources/hooks/warn-env-read.test.sh` | code | `rulebooks/code/hooks/warn-env-read.test.sh` |
| 27 | `resources/references/audit.md` | code | `rulebooks/code/references/audit.md` |
| 28 | `resources/references/communication.md` | code | `rulebooks/code/references/communication.md` |
| 29 | `resources/references/context-management.md` | engine | — |
| 30 | `resources/references/debugging.md` | code | `rulebooks/code/references/debugging.md` |
| 31 | `resources/references/design-md.md` | code | `rulebooks/code/references/design-md.md` |
| 32 | `resources/references/domain-glossary.md` | code | `rulebooks/code/references/domain-glossary.md` |
| 33 | `resources/references/environment-safety.md` | code | `rulebooks/code/references/environment-safety.md` |
| 34 | `resources/references/error-handling.md` | code | `rulebooks/code/references/error-handling.md` |
| 35 | `resources/references/external-resources.md` | code | `rulebooks/code/references/external-resources.md` |
| 36 | `resources/references/git-worktrees.md` | code | `rulebooks/code/references/git-worktrees.md` |
| 37 | `resources/references/guardrails.md` | code | `rulebooks/code/references/guardrails.md` |
| 38 | `resources/references/hooks.md` | **split** | engine keeps + `rulebooks/code/references/hooks.md` (section list below) |
| 39 | `resources/references/html-export.md` | code | `rulebooks/code/references/html-export.md` |
| 40 | `resources/references/implementation-planning.md` | code | `rulebooks/code/references/implementation-planning.md` |
| 41 | `resources/references/knowledge-management.md` | engine | — |
| 42 | `resources/references/multi-tool.md` | engine | — |
| 43 | `resources/references/project-entry.md` | code | `rulebooks/code/references/project-entry.md` |
| 44 | `resources/references/quality-gates.md` | code | `rulebooks/code/references/quality-gates.md` |
| 45 | `resources/references/recommendations.md` | code | `rulebooks/code/references/recommendations.md` |
| 46 | `resources/references/roadmap.md` | code | `rulebooks/code/references/roadmap.md` |
| 47 | `resources/references/safety-mindset.md` | code | `rulebooks/code/references/safety-mindset.md` |
| 48 | `resources/references/sast-normalization.md` | code | `rulebooks/code/references/sast-normalization.md` |
| 49 | `resources/references/sast-provisioning.md` | code | `rulebooks/code/references/sast-provisioning.md` |
| 50 | `resources/references/sub-agent-delegation.md` | code | `rulebooks/code/references/sub-agent-delegation.md` |
| 51 | `resources/references/threat-model.md` | code | `rulebooks/code/references/threat-model.md` |
| 52 | `resources/references/validation.md` | code | `rulebooks/code/references/validation.md` |
| 53 | `resources/references/vendor-adapters.md` | code | `rulebooks/code/references/vendor-adapters.md` |
| 54 | `resources/references/working-patterns.md` | code | `rulebooks/code/references/working-patterns.md` |
| 55 | `resources/rulebooks/base/rulebook.toml` | base | `rulebooks/base/rulebook.toml` |
| 56 | `resources/rulebooks/base/rules/approval-for-irreversible.md` | base | `rulebooks/base/rules/approval-for-irreversible.md` |
| 57 | `resources/rulebooks/base/rules/iron-law-claims.md` | base | `rulebooks/base/rules/iron-law-claims.md` |
| 58 | `resources/rulebooks/base/rules/no-print-secret.md` | base | `rulebooks/base/rules/no-print-secret.md` |
| 59 | `resources/rulebooks/base/rules/untrusted-agent-artifacts.md` | base | `rulebooks/base/rules/untrusted-agent-artifacts.md` |
| 60 | `resources/rulebooks/code/rulebook.toml` | code | `rulebooks/code/rulebook.toml` |
| 61 | `resources/scripts/validate-agent-context.ts` | code | `rulebooks/code/scripts/validate-agent-context.ts` |
| 62 | `resources/scripts/validate-rulebook.py` | engine | — |
| 63 | `resources/templates/CONTEXT.md.template` | engine | — |
| 64 | `resources/templates/KNOWLEDGE.md.template` | engine | — |
| 65 | `resources/templates/STATUS.md.template` | engine | — |
| 66 | `resources/templates/agent-context.yaml.template` | code | `rulebooks/code/templates/agent-context.yaml.template` |
| 67 | `resources/templates/audit-report.html.template` | code | `rulebooks/code/templates/audit-report.html.template` |
| 68 | `resources/templates/html-export.html.template` | code | `rulebooks/code/templates/html-export.html.template` |
| 69 | `resources/workflows/adopt-existing.md` | code | `rulebooks/code/workflows/adopt-existing.md` |
| 70 | `resources/workflows/bugfix.md` | code | `rulebooks/code/workflows/bugfix.md` |
| 71 | `resources/workflows/feature.md` | code | `rulebooks/code/workflows/feature.md` |
| 72 | `resources/workflows/new-project.md` | code | `rulebooks/code/workflows/new-project.md` |
| 73 | `resources/workflows/quick-task.md` | code | `rulebooks/code/workflows/quick-task.md` |

New files created in Phase B (not moves): `rulebooks/code/commands/audit.md` +
`rulebooks/code/commands/prepare.md` (wording-preserving relocation of SKILL.md's two
sections — content-diff-verified, not rename-verified, since the source is a file
*section*). New in Phase D: `rulebooks/{base,code}/README.md` (new prose). New in
Phase A: the 2-line exec shim `rulebooks/code/hooks/pre-commit-check.sh` (V14) and the
5 old-path enforcer shims + pointer stubs (see Migration).

## hooks.md section split (move-only; every line lands verbatim in exactly one file)

Source: `resources/references/hooks.md` (284 lines). The ONLY non-moved lines permitted:
one new title heading + one pointer line at the top of the code-side file, and a pointer
line where sections left the engine file.

| Section (heading) | Destination |
|---|---|
| `# Hooks — Automated Enforcement` (title + intro, incl. multi-tool note) | engine |
| `## Active Hooks` (header) | engine (code file gets its own new title line) |
| `### SessionStart → Context Injection` | engine |
| `### SessionStart → Knowledge Bootstrap` | engine |
| `### SessionStart → Context Bootstrap` | engine |
| `### PreToolUse → .env File Protection` | code |
| `### PreToolUse → .env Read Warning` | code |
| `### PreToolUse → High-Stakes Path Routing` | code |
| `### PreToolUse → Pre-Commit Check` | code (documents the base-owned enforcer from the coding session's perspective; script itself lives in `base/hooks/` per V14) |
| `### git post-commit → Knowledge Reindex (Optional)` | engine |
| `### Manual / git post-commit → Knowledge Integrity (Optional)` | engine |
| `### Stop → Quality Gate Verification` | code (quality gates are coding-lane) |
| `### SessionEnd → Checkpoint Verification` | engine (checkpointing = state preservation; the "code committed" line is incidental) |
| `## Customizing Hooks` (all subsections: runtime toggles, disabling, adding your own, strictness levels) | engine |
| `## How Hooks Map to the Playbook` | engine (system-level philosophy table) |

## Migration: stubs + shims (removal at v8)

| Class | Mechanism |
|---|---|
| Moved `.md` files (BOOTSTRAP, 24 references, 5 workflows) | One-line pointer stub at each old path: `Moved to <new path> in v7.0.0; this stub is removed in v8.` |
| The 5 registered enforcer hooks (`protect-env`, `warn-env-read`, `protect-git`, `pre-commit-check`, `route-high-stakes`) | 2-line `exec` shim at the old `resources/hooks/<name>.sh` path → new location (`rulebooks/code/hooks/` ×4, `rulebooks/base/hooks/` ×1). Without these, existing installs' registered absolute paths dangle and enforcement silently dies. |
| Registered-entry re-point | `install` + `status` detect kerby-managed entries pointing at old `resources/hooks/` enforcer paths and offer a one-confirm re-point to the new locations. |
| Root `rulebooks.lock` | Read as fallback for one major version; auto-migrated to `.kerby/rulebooks.lock` on next pin write (V13). |

## Expected parity deltas (the ONLY permitted differences vs. `.eval/parity/v7-baseline/`)

| Surface | Permitted delta |
|---|---|
| TOFU prompt | + `Commands it provides: …` line; + `Source: <url>` line (remote only) |
| `status` | + `Loaded rulebooks:` header line |
| Announcement | one line per selected rulebook (multi-load only; single-rulebook line unchanged) |
| `install` summary | per-rulebook grouping wording; entry *set* identical per V14 dedup |
| Lockfile path mentions | `.kerby/rulebooks.lock` (+ one-line migration announcement, V13) |
| Cold dispatch (`audit`/`prepare`, nothing loaded) | + selection announcement + load confirmation *preceding* the baseline output; command output itself byte-matches (baseline captures these cold) |
| New commands (`rulebooks`, `unload`, `load +`) | no baseline exists — spec-tested, not parity-tested |

Replay rule: byte-match everything except these enumerated deltas. A mismatch outside
the table = stop, classify, BLOCKED if unexplained — never "explain away".

## Locked decisions (V1–V16)

See the v7 plan (mirrored in the PR description). Summary index: V1 layout · V2 command
model · V3 audit/prepare re-home · V4 install derivation · V5 base listed as floor ·
V6 interactive create · V7 eval scoping · V8 contract 2 · V9 stubs/shims · V10 trust
unchanged · V11 behavior parity · V12 remote sources · V13 lockfile → `.kerby/` ·
V14 shared-enforcer ownership · V15 load replace/`+`/unload + cold dispatch ·
V16 reserved names + dispatch precedence.
