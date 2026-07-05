# ENGINE-MAP — v5.8.0 rule corpus → v6 engine/rulebook destinations

> **Historical (v6-era).** Paths herein predate the v7 self-containment split and the
> v8 `.ai/`→`.kerby/` move; see `ENGINE-MAP-v2.md` for the v7 layout. Kept as the
> decision record of the v6 refactor.

Phase-0 artifact of the v6 pluggable-rulebooks refactor. Every rule/section in
the corpus gets a **destination**; silence is not a destination. Grounded at
commit `fbf6085` (v5.8.0).

Destinations:

- **core** — the domain-blind engine: skill orchestration (SKILL.md flows),
  loader/validator, lockfile, view providers, complexity grading + tier
  selection, PASS/HELD/DENIED vocabulary, error catalog, state preservation
  (`.ai/` machinery + SessionStart/maintenance hooks), templates/schema (D14).
- **base** — universal floor rulebook (`rulebooks/base/`): domain-blind checks
  every rulebook inherits (D9 floors live here).
- **code** — the coding rulebook (`rulebooks/code/`): coding checks and
  coding-methodology prose, declared **in place** (builtin may declare
  repo-relative paths, D6).
- **defer** — decision deliberately postponed; stays exactly where it is.

**Physical moves are capped** at the ~5 base prose extractions (handoff
ring-fence). Everything else is *declared in place*: destination describes
which component owns the rule in the target architecture, not a file move.

## How BOOTSTRAP keeps loading (the parity spine)

The manifest is the single authority for what a rulebook contains (D1). To keep
`kerby load` byte-identical in effect (§ 9 parity), the `code` rulebook
declares `BOOTSTRAP.md` itself as its eager root prose check, and declares the
references/workflows as on-demand prose (`token_cost` drives the ordering),
mirroring today's BOOTSTRAP → references progressive disclosure. BOOTSTRAP § 7's
index remains in the text (it is rule content telling the *agent* where detail
lives); the manifest is what tells the *engine* what exists. A mechanical
coverage check keeps the two from drifting (Phase 2 acceptance).

---

## 1. BOOTSTRAP.md (`skills/kerby/resources/BOOTSTRAP.md`, 321 lines)

| Section | Gist | Destination | Declared as | Notes |
|---|---|---|---|---|
| § 1 Prime Directive | clarity/safety/never-broken + priority order | code | in the `operating-rules` prose check (whole BOOTSTRAP body, eager, `token_cost=medium`) | Wording is repo-shaped ("repo broken"); a domain-blind restatement is a future base candidate, not a v1 extraction |
| § 1b Decision Ladder | 6-rung write-less-code ladder | code | ↑ same body | Coding-specific |
| § 2 Detect Project State | 9-artifact read sequence | core (text in place) | ↑ same body | Project-entry mechanics; reads `.ai/` state (engine tier) |
| § 2.5 Grade Before Route | complexity grade line, opt-out rules | core (text in place) | ↑ same body | Grading is engine per D14; ring-fence forbids changing it — text stays in BOOTSTRAP at v1 |
| § 3 Route to Workflow + high-stakes override | task-type routing table, high-stakes globs | code | ↑ same body; globs backed by `high-stakes-routing` check (partial) | Routing targets are domain facts (D14) |
| § 4 Plan Gate | plan threshold, ≥7 approval stop, Expected Outcomes | core (text in place) | ↑ same body | Gate mechanics; parity-checked constants (`check-plan-gate-parity.sh`) |
| § 4 Branching | protected branches, worktree gate | code | ↑ same body; backed by `protected-branch-commit` + `destructive-git` checks | |
| § 4 Commit Discipline | commit-per-piece, type required, memory.log format | code | ↑ same body | memory.log *format* is core state-preservation; the discipline is code |
| § 4 Verification | no claims without fresh evidence + gate command | code | ↑ same body; detail = `verification-before-completion` check | Domain-blind kernel extracted to base `iron-law-claims` |
| § 4 Diagnosis | evidence-before-fix, escape valve | code | ↑ same body | Generalizes debugging Iron Law; coding-shaped |
| § 4 Resource Cleanup | kill spawned processes, disclosed leave-running | code | ↑ same body | |
| § 4 Manual Verification Instructions | How-to-Verify block | code | ↑ same body | |
| § 4 Sub-Agent Delegation | 3+ files → delegate; blind lenses | code | ↑ same body | |
| § 4 Ambiguity-Before-Cost | ask before 5 costly actions | code | ↑ same body | Irreversible-git item overlaps base `approval-for-irreversible`; list itself is coding-specific |
| § 4 Output Discipline | no preamble/fluff | defer | ↑ same body | Future base candidate (domain-blind comms); over the ~5-extraction cap |
| § 4 Accuracy | never invent paths/values | defer | ↑ same body | Future base candidate; over the cap |
| § 4 Environment Safety | prod/non-prod side-effect matrix trigger | code | ↑ same body | |
| § 4 Guardrails (summary list) | secrets, deps, scope, untrusted artifacts, no merge | code | ↑ same body | Two bullets have base kernels (extracted: `no-print-secret`, `untrusted-agent-artifacts`) |
| § 4 Vendor-coupled files extension | match existing pattern in SDK-coupled files | code | ↑ same body | |
| § 5 When Stuck | escape-valve table | code | ↑ same body | |
| § 6 Before Context Fills | checkpoint procedure | core (text in place) | ↑ same body | State preservation |
| § 7 Reference Index | 26-entry topic → file table | core → superseded by manifest as *engine* authority | index text retained for the agent | Coverage check keeps manifest ↔ index in sync |

## 2. Gate-bearing references (read in full)

### references/guardrails.md (109 lines)

| Section | Destination | Declared as | Notes |
|---|---|---|---|
| Enforcement legend (`[enforced-when-installed]`/`[enforced-partial]`/`[behavioral]`) | core | contract vocabulary (D3 `enforcement = hard/partial/behavioral` + degrade rule) | Text stays; the contract formalizes it |
| What NOT to Do table | code | `guardrails-scope-security` prose check (`block`, high) | |
| Destructive Git Commands | code | `destructive-git` check, `kind=code`, enforcer `hooks/protect-git.sh`, `floor=true` | No escape hatch — data loss |
| Commit-on-protected-branch + escape hatch | code | `protected-branch-commit` check, `override="authorized-scoped"` (`CODING_RULES_ALLOW_PROTECTED_COMMIT=1`) | The D9 non-floor exemplar |
| Scope Discipline | code | within `guardrails-scope-security` | Future base candidate; over the cap |
| Security Awareness — never commit secrets | **base** | `secrets-staged`, `kind=data`, runner `gitleaks` (betterleaks/gitleaks else regex floor), enforcer `hooks/pre-commit-check.sh`, `needs=[staged_content]`, `floor=true` | Hook + rule pair |
| Security Awareness — never print a live secret | **base** (EXTRACT → `rulebooks/base/rules/no-print-secret.md`) | `no-print-secret`, prose, behavioral, `block`, `floor=true`, low | Hook can't see chat output; partial reminder via `env-read-warning` stays code |
| Security Awareness — exposed-cred patterns, env vars, dep review | code | within `guardrails-scope-security` | Patterns are code-shaped |
| Config vs. Secrets Boundary | code | within `guardrails-scope-security` | |
| Agent-Authored Artifacts as Untrusted Input | **base** (EXTRACT → `rulebooks/base/rules/untrusted-agent-artifacts.md`) | `untrusted-agent-artifacts`, prose, behavioral, `block`, `floor=true`, medium | The D7/D8 mitigation itself; domain-blind (any lane ingests agent output) |
| Documentation Updates | code | within `guardrails-scope-security` | |

### references/validation.md (153 lines)

| Section | Destination | Declared as | Notes |
|---|---|---|---|
| Iron Law + Red Flag Phrases + Verification Gate (4 steps) | **base** (EXTRACT kernel → `rulebooks/base/rules/iron-law-claims.md`) | `iron-law-claims`, prose, behavioral, `block`, `floor=true`, medium | Domain-blind: "no completion claims without fresh evidence" holds for a sales doc or an ops runbook |
| Iron Law extension (Expected/Realized outcomes) | code | `verification-before-completion` prose check (`block`, high) | Coupled to the plan gate (core) and feature.md § 7 |
| What Counts as Evidence (body-diff, n≥10, hollow tests) | code | ↑ same check; hollow-test statics backed by `hollow-test-heuristic` (partial, warn) | |
| Verification by Complexity (tiers, QA sub-agent) | code | ↑ same check | |
| Security Lens — Conditional Pass | code | `security-lens` prose check (`block`, high); findings `basis=targeted`, never "certified" (D16) | |
| Manual Verification Instructions / see-your-output | code | ↑ within `verification-before-completion` | |

### references/quality-gates.md (104 lines)

| Section | Destination | Declared as | Notes |
|---|---|---|---|
| Gate Tiers (Quick/Standard/Full) + tier choice + at-commit rule | code | `quality-gate-tiers` prose check (`block`, medium); `{build,lint,test}_command` become the manifest `[commands]` table (D14) | |
| Formatter Scope (touched-files-only) | code | ↑ same check | |
| When Gates Fail (→ error-handling.md) | code | pointer; retry budgets stay in `error-handling.md` | |

### Base extraction #5 — approval-for-irreversible

`rulebooks/base/rules/approval-for-irreversible.md` generalizes the
destructive-command discipline (guardrails.md § Destructive Git: "ask the
developer to run it themselves"), the irreversible-git item of BOOTSTRAP § 4
Ambiguity-Before-Cost, and the env-crossing human-validation rule
(environment-safety / safety-mindset § cost-of-error) into one domain-blind
floor: **before any destructive, hard-to-undo, or externally-visible action,
get explicit human approval**. Prose, behavioral, `block`, `floor=true`, low.

## 3. Hooks (`skills/kerby/resources/hooks/`, 10 scripts)

| Hook | Destination | Declared as | Notes |
|---|---|---|---|
| `protect-git.sh` | code | enforcer of `destructive-git` (floor) AND `protected-branch-commit` (override) — one script, two checks | `needs=[branch]` / `[branch, install_state]` |
| `protect-env.sh` | code | enforcer of `protect-env` (`hard`, block) | No test file at v5.8.0 (observed) |
| `pre-commit-check.sh` | split | enforcer of base `secrets-staged` (hard, floor) AND code `hollow-test-heuristic` (partial, warn, gap named) | Same script backs a base check and a code check — allowed; enforcer is a path, not an identity |
| `warn-env-read.sh` | code | enforcer of `env-read-warning` (partial, warn, gap: "Bash cat .env not caught") | |
| `route-high-stakes.sh` | code | enforcer of `high-stakes-routing` (partial, warn, gap: prose-only traffic-shaping category) | |
| `session-start-context.sh` | **core** | not a check — state preservation (injects `.ai/STATUS.md` + memory.log with `DATA>` framing) | Registered by `install` as engine machinery, exactly as today |
| `knowledge-bootstrap.sh` | **core** | not a check — scaffolds/reindexes `.ai/knowledge/` | ↑ |
| `context-bootstrap.sh` | **core** | not a check — scaffolds `CONTEXT.md` | ↑ |
| `knowledge-reindex.sh` | **core** | manual git-side maintenance utility | ↑ |
| `knowledge-lint.sh` | **core** | advisory `.ai/knowledge/` integrity lint | Candidate future `data` check (`needs=[repo_tree]`); defer |

D13 note: `install` Phase 2 remains the executable trust opt-in; what changes
in Phase 3 is only that `status` computes *effective* enforcement from the
registration state (D3/D4) instead of prose assertions.

## 4. Engine surface (all → core)

| Artifact | Notes |
|---|---|
| `SKILL.md` sub-command flows (`load`/`reload`/`status`/`install`/`uninstall`/`prepare`/`audit`) | `load`/`reload`/`status` rewritten in Phase 3 to run through manifests; the rest untouched |
| `scripts/check-skill-compat.py`, `scripts/check-plan-gate-parity.sh` | unchanged; new validator ships in the skill bundle at `resources/scripts/validate-rulebook.py` (repo `scripts/` does not travel with the plugin), tested by repo-level `scripts/validate-rulebook.test.sh` |
| `templates/*` (6), `agent-context.schema.yaml`, `scripts/validate-agent-context.ts` | project-scaffolding machinery |
| `.ai/` conventions (memory.log, STATUS.md, knowledge/, BLOCKERS.md) | state preservation |
| `assets/*.svg`, README, CLAUDE.md, VOICE.md | docs/meta |
| **NEW:** `rulebooks.lock` (JSON, consuming-project root) | D17 pin + hash entries; §6 of the handoff |

## 5. Hardcoded-filename inventory (the coupling D1 removes)

Where the v5.8.0 load path (engine, not rule text) names rule files:

| Location | Coupling | v6 resolution |
|---|---|---|
| SKILL.md:24–30 | BOOTSTRAP.md locator (Glob / `KERBY_DIR` / ask) + "all other resource paths follow the same prefix" | Locator stays (finds the *skill*); what to read comes from the manifest |
| SKILL.md:64–65 (`load` step 1–2) | reads `resources/BOOTSTRAP.md` by name | manifest-driven: eager prose of the selected rulebook |
| SKILL.md:98 (`status`) | BOOTSTRAP signature phrases | kept (context detection) + rulebook panel added |
| SKILL.md:113–114 (`prepare`) | `workflows/adopt-existing.md` by name | untouched at v1 (prepare is core flow; its workflow is core-owned) |
| SKILL.md:177, 199–210, 223, 279, 295 (`install`/`uninstall`) | eight hook filenames + `/skills/kerby/resources/hooks/` signature | untouched at v1 — install registers *enforcers*; Phase 3 reads registration state for degrade. Deriving the hook list from manifests is a v6.x follow-up, noted in the authoring guide |
| SKILL.md:303–305 (`audit`) | `references/audit.md`, sast files | untouched (audit is core flow) |
| SKILL.md:40–50 (harness table) | quality-gates/validation/hook paths in prose | pointer updates only |
| BOOTSTRAP § 2/§ 4/§ 7 | ~30 `references/*.md` citations | rule content, not engine coupling — stays; mirrored by manifest (coverage-checked) |
| `route-high-stakes.sh` + test | resolves BOOTSTRAP § 3 globs for parity | unchanged (check-internal parity, a feature) |

## 6. Handoff-assumption resolutions

1. **Python ≥ 3.11** — confirmed: python3 is 3.14.2 here; `tomllib` imports.
   Documented as a requirement of `validate-rulebook.py` only (existing
   scripts stay version-agnostic).
2. **No external consumers of `resources/references/*` paths** — in-repo grep
   confirms citations only in prose docs (root README/CLAUDE.md/CHANGELOG,
   skill README/CLAUDE.md/SKILL.md, workflows, 2 hook comments). Vendor plugin
   manifests (`.claude-plugin/*`, `.codex-plugin/*`, `.agents/plugins/*`)
   reference only `./skills/kerby` — **no structural adapter changes needed**.
3. **Vendor adapters pointer-updates only** — confirmed (see 2).
4. **`.eval/` fixture home** — confirmed with one repo fact: `.eval/*` is
   gitignored except a whitelist; added `!.eval/rulebooks/` and
   `!.eval/parity/` beside the `!.eval/triggers/` precedent.

## 7. Locked-decision conflicts found

None. One design gap in the handoff's draft manifests (they never declare
BOOTSTRAP.md, which would leave the engine guessing its way to the primary
rule body) — resolved *within* the locked decisions by declaring BOOTSTRAP as
the code rulebook's eager root prose check (see "parity spine" above). The
draft manifests also under-count the corpus (26 indexed references + 5
workflows vs. the drafts' 4 prose checks); § 8 lists the full declared set.

## 8. Remaining references & workflows

Two axes per file: **owner** (which component the content belongs to in the
target architecture) and **declared by manifest at v1** (yes = a `[[check]]`
in a rulebook.toml; no = reached exactly as today, via BOOTSTRAP § 7 / § 3 —
rule content pointing at rule content, which is not engine coupling). The
handoff's prose-granularity note applies: whole-file declaration is the v1
unit; per-section split is ring-fenced out.

| File (lines) | Owner | Declared at v1 | Notes |
|---|---|---|---|
| `working-patterns.md` (379) | code | no | Straddles heavily. Future base candidates flagged: Task Approach 1–8, Anti-Rationalization, Pushback Protocol, Source-Driven Claims, Think-in-Code. Complexity-routing section is core-owned text in place |
| `debugging.md` (104) | code | no | Iron Law origin ("no fixes without root cause"); coding-shaped (breakpoints, tests). Domain-blind kernel already lands in base via `iron-law-claims` |
| `error-handling.md` (283) | code | no | Retry budgets (build 5 / test 3 / lint 5 → BLOCKED). Never-Leave-Broken is a future base candidate. `.ai/BLOCKERS.md` format is core state |
| `communication.md` (182) | code | no | Conventional commits, PR shape. memory.log / STATUS.md / knowledge formats inside it are core state-preservation specs |
| `git-worktrees.md` (149) | code | no | Worktree tactics; gate itself lives in BOOTSTRAP § 4 |
| `environment-safety.md` (61) | code | no | Core rule + detection are near-domain-blind (future base candidate); the 9-category matrix is code |
| `sub-agent-delegation.md` (170) | code | no | Delegation methodology; tier/model pinning mechanics are core-owned text in place |
| `vendor-adapters.md` (243) | code | no | Ports-and-adapters doctrine + Existing-Code Rule |
| `implementation-planning.md` (403) | code | no | Multi-session planning; plan-approval mechanics are core-owned text in place |
| `design-md.md` (106) | code | no | DESIGN.md authority for UI work |
| `roadmap.md` (162) | code | no | ROADMAP.md shape + update discipline |
| `threat-model.md` (50) | core | no | The honest enforcement map — the D3/D4 legend's source; Phase 3 `status` supersedes its *runtime* role, the doc stays as design rationale |
| `audit.md` (218) | core | no | `audit` sub-command spec. Its § 1 untrusted-input doctrine duplicates the base `untrusted-agent-artifacts` kernel — pointer, not second copy, when base body is written |
| `hooks.md` (285) | core | no | Hook registration/lifecycle/customization — engine machinery documentation |
| `multi-tool.md` (171) | core | no | Vendor-file sync, sub-agent model pinning — engine |
| `project-entry.md` (307) | core | no | Project state detection + entry flows — engine |
| `context-management.md` (95) | core | no | Session lifecycle/checkpointing — state preservation |
| `knowledge-management.md` (252) | core | no | `.ai/knowledge/` machinery + curation discipline |
| `domain-glossary.md` (54) | core | no | CONTEXT.md lifecycle (context-bootstrap hook) |
| `html-export.md` (76) | core | no | Deterministic export pipeline |
| `sast-normalization.md` (61), `sast-provisioning.md` (92) | core | no | Audit `--sast` machinery |
| `external-resources.md` (127), `recommendations.md` (145) | defer | no | Registry/suggestion catalog — not rules |
| `safety-mindset.md` (200) | defer | no | Decision filters are strong future-base candidates (Taste Test, Reversibility Matrix); over the v1 extraction cap |
| `workflows/*.md` (5 files, 651) | code | no | Task-shape playbooks, routed by BOOTSTRAP § 3 (rule content). `feature.md` § 3 grading ladder + § 7 outcome routing are core-owned text in place (ring-fenced: no edits beyond load-flow pointers) |

## 9. The v1 declared set (what Phase 2 actually writes)

**`rulebooks/base/rulebook.toml`** — 5 checks (handoff § 5.1 confirmed):
`secrets-staged` (data, hard via `pre-commit-check.sh`, floor),
`no-print-secret`, `untrusted-agent-artifacts`, `iron-law-claims`,
`approval-for-irreversible` (prose, behavioral, floor; bodies extracted to
`rulebooks/base/rules/*.md`).

**`rulebooks/code/rulebook.toml`** — handoff § 5.2 **plus one addition**:

| Check | kind | enforcement | Source |
|---|---|---|---|
| `operating-rules` (**added**) | prose (eager, medium) | behavioral | `BOOTSTRAP.md` declared in place — the parity spine (§ 7 above) |
| `destructive-git` | code | hard (`protect-git.sh`), floor | guardrails § Destructive Git |
| `protected-branch-commit` | code | hard (`protect-git.sh`), override `authorized-scoped` | guardrails § protected-branch |
| `protect-env` | code | hard (`protect-env.sh`) | guardrails table |
| `env-read-warning` | code | partial (`warn-env-read.sh`), gap named | guardrails § Security Awareness |
| `high-stakes-routing` | code | partial (`route-high-stakes.sh`), gap named | BOOTSTRAP § 3 override |
| `hollow-test-heuristic` | code | partial (`pre-commit-check.sh`), gap named | validation § What Counts as Evidence |
| `quality-gate-tiers` | prose (block, medium) | behavioral | `references/quality-gates.md` in place |
| `verification-before-completion` | prose (block, high) | behavioral | `references/validation.md` in place |
| `security-lens` | prose (block, high) | behavioral | `references/validation.md` in place (deduped by path) |
| `guardrails-scope-security` | prose (block, high) | behavioral | `references/guardrails.md` in place |

Plus `[commands]` (`{build,lint,test}_command`) and `[gate]` per the handoff.

## 10. Future-base backlog (flagged, NOT extracted at v1)

Domain-blind candidates surfaced by the full-corpus pass, all over the ~5
extraction cap: Output Discipline, Accuracy (BOOTSTRAP § 4); Scope Discipline
(guardrails); Anti-Rationalization, Pushback Protocol, Task Approach,
Source-Driven Claims (working-patterns); Never-Leave-Broken (error-handling);
safety-mindset decision filters; environment-safety core rule. Each is a
one-manifest-edit addition once the base rulebook exists — which is the point
of the refactor.
