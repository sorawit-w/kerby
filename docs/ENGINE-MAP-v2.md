# ENGINE-MAP v2 — the kerby v7 engine/rulebook file split

> **Historical (v7-era).** Paths and migration machinery described here reflect the
> v7.0.0 split; the stubs/shims and lockfile fallback it documents were removed in
> v8.0.0. Kept as the decision record of the split.

The executable companion to the v7.0.0 plan. Method: every file under `skills/kerby/`
gets exactly one destination, decided by the *"would a sales rulebook want it?"* test.
Target layout: `skills/kerby/resources/` = engine only; `skills/kerby/rulebooks/{base,swe}/`
= self-contained content. **A file whose destination this map does not determine is a
BLOCKED condition, never a judgment call.**

Destinations: `engine` (stays under `resources/`) · `base` / `swe` (move into
`rulebooks/<id>/…`) · `root` (skill root, unchanged) · `excluded` (not moved, not shipped).

## File-by-file table

| # | Current path (under `skills/kerby/`) | Destination | New path (under `skills/kerby/`) |
|---|---|---|---|
| 1 | `SKILL.md` | root | — |
| 2 | `README.md` | root | — |
| 3 | `CLAUDE.md` | root | — |
| 4 | `assets/bugfix-loop.svg` | swe | `rulebooks/swe/assets/bugfix-loop.svg` |
| 5 | `assets/feature-loop.svg` | swe | `rulebooks/swe/assets/feature-loop.svg` |
| 6 | `assets/workflow-routing.svg` | swe | `rulebooks/swe/assets/workflow-routing.svg` |
| 7 | `resources/BOOTSTRAP.md` | swe | `rulebooks/swe/BOOTSTRAP.md` |
| 8 | `resources/agent-context.schema.yaml` | swe | `rulebooks/swe/agent-context.schema.yaml` |
| 9 | `resources/.impeccable/hook.cache.json` | excluded | generated cache → `.gitignore` |
| 10 | `resources/hooks/.impeccable/hook.cache.json` | excluded | generated cache → `.gitignore` |
| 11 | `resources/hooks/context-bootstrap.sh` | engine | — |
| 12 | `resources/hooks/knowledge-bootstrap.sh` | engine | — |
| 13 | `resources/hooks/knowledge-lint.sh` | engine | — |
| 14 | `resources/hooks/knowledge-lint.test.sh` | engine | — |
| 15 | `resources/hooks/knowledge-reindex.sh` | engine | — |
| 16 | `resources/hooks/pre-commit-check.sh` | **base** (V14) | `rulebooks/base/hooks/pre-commit-check.sh` |
| 17 | `resources/hooks/pre-commit-check.test.sh` | **base** (V14) | `rulebooks/base/hooks/pre-commit-check.test.sh` |
| 18 | `resources/hooks/protect-env.sh` | swe | `rulebooks/swe/hooks/protect-env.sh` |
| 19 | `resources/hooks/protect-git.sh` | swe | `rulebooks/swe/hooks/protect-git.sh` |
| 20 | `resources/hooks/protect-git.test.sh` | swe | `rulebooks/swe/hooks/protect-git.test.sh` |
| 21 | `resources/hooks/route-high-stakes.sh` | swe | `rulebooks/swe/hooks/route-high-stakes.sh` |
| 22 | `resources/hooks/route-high-stakes.test.sh` | swe | `rulebooks/swe/hooks/route-high-stakes.test.sh` |
| 23 | `resources/hooks/session-start-context.sh` | engine | — |
| 24 | `resources/hooks/session-start-context.test.sh` | engine | — |
| 25 | `resources/hooks/warn-env-read.sh` | swe | `rulebooks/swe/hooks/warn-env-read.sh` |
| 26 | `resources/hooks/warn-env-read.test.sh` | swe | `rulebooks/swe/hooks/warn-env-read.test.sh` |
| 27 | `resources/references/audit.md` | swe | `rulebooks/swe/references/audit.md` |
| 28 | `resources/references/communication.md` | swe | `rulebooks/swe/references/communication.md` |
| 29 | `resources/references/context-management.md` | swe | `rulebooks/swe/references/context-management.md` (v7 correction: cited only by swe's BOOTSTRAP/refs) |
| 30 | `resources/references/debugging.md` | swe | `rulebooks/swe/references/debugging.md` |
| 31 | `resources/references/design-md.md` | swe | `rulebooks/swe/references/design-md.md` |
| 32 | `resources/references/domain-glossary.md` | swe | `rulebooks/swe/references/domain-glossary.md` |
| 33 | `resources/references/environment-safety.md` | swe | `rulebooks/swe/references/environment-safety.md` |
| 34 | `resources/references/error-handling.md` | swe | `rulebooks/swe/references/error-handling.md` |
| 35 | `resources/references/external-resources.md` | swe | `rulebooks/swe/references/external-resources.md` |
| 36 | `resources/references/git-worktrees.md` | swe | `rulebooks/swe/references/git-worktrees.md` |
| 37 | `resources/references/guardrails.md` | swe | `rulebooks/swe/references/guardrails.md` |
| 38 | `resources/references/hooks.md` | **split** | engine keeps + `rulebooks/swe/references/hooks.md` (section list below) |
| 39 | `resources/references/html-export.md` | swe | `rulebooks/swe/references/html-export.md` |
| 40 | `resources/references/implementation-planning.md` | swe | `rulebooks/swe/references/implementation-planning.md` |
| 41 | `resources/references/knowledge-management.md` | swe | `rulebooks/swe/references/knowledge-management.md` (v7 correction: 8 swe cites vs 1 engine, de-deep-linked) |
| 42 | `resources/references/multi-tool.md` | engine | — |
| 43 | `resources/references/project-entry.md` | swe | `rulebooks/swe/references/project-entry.md` |
| 44 | `resources/references/quality-gates.md` | swe | `rulebooks/swe/references/quality-gates.md` |
| 45 | `resources/references/recommendations.md` | swe | `rulebooks/swe/references/recommendations.md` |
| 46 | `resources/references/roadmap.md` | swe | `rulebooks/swe/references/roadmap.md` |
| 47 | `resources/references/safety-mindset.md` | swe | `rulebooks/swe/references/safety-mindset.md` |
| 48 | `resources/references/sast-normalization.md` | swe | `rulebooks/swe/references/sast-normalization.md` |
| 49 | `resources/references/sast-provisioning.md` | swe | `rulebooks/swe/references/sast-provisioning.md` |
| 50 | `resources/references/sub-agent-delegation.md` | swe | `rulebooks/swe/references/sub-agent-delegation.md` |
| 51 | `resources/references/threat-model.md` | swe | `rulebooks/swe/references/threat-model.md` |
| 52 | `resources/references/validation.md` | swe | `rulebooks/swe/references/validation.md` |
| 53 | `resources/references/vendor-adapters.md` | swe | `rulebooks/swe/references/vendor-adapters.md` |
| 54 | `resources/references/working-patterns.md` | swe | `rulebooks/swe/references/working-patterns.md` |
| 55 | `resources/rulebooks/base/rulebook.toml` | base | `rulebooks/base/rulebook.toml` |
| 56 | `resources/rulebooks/base/rules/approval-for-irreversible.md` | base | `rulebooks/base/rules/approval-for-irreversible.md` |
| 57 | `resources/rulebooks/base/rules/iron-law-claims.md` | base | `rulebooks/base/rules/iron-law-claims.md` |
| 58 | `resources/rulebooks/base/rules/no-print-secret.md` | base | `rulebooks/base/rules/no-print-secret.md` |
| 59 | `resources/rulebooks/base/rules/untrusted-agent-artifacts.md` | base | `rulebooks/base/rules/untrusted-agent-artifacts.md` |
| 60 | `resources/rulebooks/swe/rulebook.toml` | swe | `rulebooks/swe/rulebook.toml` |
| 61 | `resources/scripts/validate-agent-context.ts` | swe | `rulebooks/swe/scripts/validate-agent-context.ts` |
| 62 | `resources/scripts/validate-rulebook.py` | engine | — |
| 63 | `resources/templates/CONTEXT.md.template` | engine | — |
| 64 | `resources/templates/KNOWLEDGE.md.template` | engine | — |
| 65 | `resources/templates/STATUS.md.template` | engine | — |
| 66 | `resources/templates/agent-context.yaml.template` | swe | `rulebooks/swe/templates/agent-context.yaml.template` |
| 67 | `resources/templates/audit-report.html.template` | swe | `rulebooks/swe/templates/audit-report.html.template` |
| 68 | `resources/templates/html-export.html.template` | swe | `rulebooks/swe/templates/html-export.html.template` |
| 69 | `resources/workflows/adopt-existing.md` | swe | `rulebooks/swe/workflows/adopt-existing.md` |
| 70 | `resources/workflows/bugfix.md` | swe | `rulebooks/swe/workflows/bugfix.md` |
| 71 | `resources/workflows/feature.md` | swe | `rulebooks/swe/workflows/feature.md` |
| 72 | `resources/workflows/new-project.md` | swe | `rulebooks/swe/workflows/new-project.md` |
| 73 | `resources/workflows/quick-task.md` | swe | `rulebooks/swe/workflows/quick-task.md` |

New files created in Phase B (not moves): `rulebooks/swe/commands/audit.md` +
`rulebooks/swe/commands/prepare.md` (wording-preserving relocation of SKILL.md's two
sections — content-diff-verified, not rename-verified, since the source is a file
*section*). New in Phase D: `rulebooks/{base,code}/README.md` (new prose). New in
Phase A: the 2-line exec shim `rulebooks/swe/hooks/pre-commit-check.sh` (V14) and the
5 old-path enforcer shims + pointer stubs (see Migration).

## hooks.md section split (move-only; every line lands verbatim in exactly one file)

Source: `resources/references/hooks.md` (284 lines). The ONLY non-moved lines permitted:
one new title heading + one pointer line at the top of the swe-side file, and a pointer
line where sections left the engine file.

| Section (heading) | Destination |
|---|---|
| `# Hooks — Automated Enforcement` (title + intro, incl. multi-tool note) | engine |
| `## Active Hooks` (header) | engine (swe file gets its own new title line) |
| `### SessionStart → Context Injection` | engine |
| `### SessionStart → Knowledge Bootstrap` | engine |
| `### SessionStart → Context Bootstrap` | engine |
| `### PreToolUse → .env File Protection` | swe |
| `### PreToolUse → .env Read Warning` | swe |
| `### PreToolUse → High-Stakes Path Routing` | swe |
| `### PreToolUse → Pre-Commit Check` | code (documents the base-owned enforcer from the coding session's perspective; script itself lives in `base/hooks/` per V14) |
| `### git post-commit → Knowledge Reindex (Optional)` | engine |
| `### Manual / git post-commit → Knowledge Integrity (Optional)` | engine |
| `### Stop → Quality Gate Verification` | code (quality gates are coding-lane) |
| `### SessionEnd → Checkpoint Verification` | engine (checkpointing = state preservation; the "code committed" line is incidental) |
| `## Customizing Hooks` (all subsections: runtime toggles, disabling, adding your own, strictness levels) | engine |
| `## How Hooks Map to the Playbook` | engine (system-level philosophy table) |

## Migration: stubs + shims (v7-only machinery — removed in v8.0.0)

| Class | Mechanism |
|---|---|
| Moved `.md` files (BOOTSTRAP, 24 references, 5 workflows) | One-line pointer stub at each old path: `Moved to <new path> in v7.0.0; this stub is removed in v8.` |
| The 5 registered enforcer hooks (`protect-env`, `warn-env-read`, `protect-git`, `pre-commit-check`, `route-high-stakes`) | 2-line `exec` shim at the old `resources/hooks/<name>.sh` path → new location (`rulebooks/swe/hooks/` ×4, `rulebooks/base/hooks/` ×1). Without these, existing installs' registered absolute paths dangle and enforcement silently dies. |
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
| Flow-internal mechanics prose (Phase A) | path re-roots (`resources/rulebooks/`→`rulebooks/`, hooks-dir table, workflow/audit doc pointers, locator rewrite) + the contract-2 corrections the reorg makes mandatory (`--origin builtin` no longer grants special resolution; detection signature gains the legacy-shim root). **User-facing verbatim strings — confirmations, announcement format, TOFU prompt block, compaction caveat — are NOT covered by this row and must stay byte-identical** (verified: scenarios 3 & 7 IDENTICAL at Phase A replay; prompt/announcement blocks untouched in 1/2/4/5/6). |
| Rulebook id (v9.0.0 rename) | everywhere the baseline prints `code@1.0.0` / id `code` / `kerby code <cmd>`, the live output prints `swe@2.0.0` / `swe` / `kerby swe <cmd>` — id/version substitution only; the surrounding verbatim strings (confirmations, announcement format, TOFU prompt block) are otherwise unchanged |
| Pin migration (v9.0.0) | + one-line announcement `pin migrated: builtin 'code' → 'swe' (renamed in v9.0.0)` preceding a pinned load of a pre-v9 lockfile |
| `status` panel (v9.0.0) | + `registered script missing — re-run kerby install` row for a settings entry under a kerby-managed root whose script no longer exists (the state a pre-v9 hook install leaves after the rename) |
| Selection source grammar (v9.1.0) | announcement gains `detected` / `chosen`, loses `default`; the first-time-default hint is replaced by a `(matched: <marker>; …)` hint on `detected` |
| Ask-fallback flow (v9.1.0) | new surface — an unpinned load with a multi-match or no-match presents the builtin list and asks; spec-tested, not parity-tested (mirrors the "New commands" row) |

Replay rule: byte-match everything except these enumerated deltas. A mismatch outside
the table = stop, classify, BLOCKED if unexplained — never "explain away".

## Locked decisions (V1–V16)

See the v7 plan (mirrored in the PR description). Summary index: V1 layout · V2 command
model · V3 audit/prepare re-home · V4 install derivation · V5 base listed as floor ·
V6 interactive create · V7 eval scoping · V8 contract 2 · V9 stubs/shims · V10 trust
unchanged · V11 behavior parity · V12 remote sources · V13 lockfile → `.kerby/` ·
V14 shared-enforcer ownership · V15 load replace/`+`/unload + cold dispatch ·
V16 reserved names + dispatch precedence.
