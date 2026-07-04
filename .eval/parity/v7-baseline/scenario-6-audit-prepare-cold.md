# v7-baseline — audit + prepare invocation surface, captured COLD (v6.0.0 @ b161c32)

Cold = today's standalone invocation with nothing loaded (there is no load step).
Permitted v7 delta ONLY: + selection announcement + load confirmation PRECEDING
this output (cold dispatch); the command behavior itself byte-matches.

## `prepare`

Onboard an **existing repo** into kerby — populate (and refresh) the artifacts BOOTSTRAP's `detect_project` step reads (`agent-context.yaml`, `CONTEXT.md`, `.ai/knowledge/`, `.ai/STATUS.md`, `.ai/memory.log`) from the repo's real code and git history. This is the existing-code counterpart to `new-project.md` (greenfield) and to the resume flow in `references/project-entry.md` (read-and-continue).

1. Resolve the bundled rule-content root the same way `load` resolves `BOOTSTRAP.md` (Glob `**/skills/kerby/resources/BOOTSTRAP.md`, else `${KERBY_DIR}/resources/BOOTSTRAP.md`, else ask). The workflow file is its sibling at `<install-root>/resources/workflows/adopt-existing.md`.
2. **Read `resources/workflows/adopt-existing.md` in full** with the `Read` tool, then follow it. It carries the procedure: tiered population by inferability, diff-and-confirm on every write, and per-tier refresh rules that never clobber human-curated content.
3. The workflow modifies user files — but **only ever behind a per-artifact diff-and-confirm**, exactly like `install`. Never write any artifact silently. Honor the out-of-scope ring-fence in the workflow (no quality gates, no tooling install — including SAST provisioning, which is an audit-time `--sast` concern, not onboarding — no `ROADMAP.md`, no commits/merge, no secret contents).

`prepare` is safe to re-run: per the workflow's refresh rules it re-derives only agent-owned content and is a diffs-only near-no-op on an already-onboarded repo.

**Forcing the knowledge pass.** The `.ai/knowledge/` decision/lesson pass runs automatically only on first onboarding (empty `.ai/knowledge/`); once entries exist it is opt-in. To force it without the opt-in prompt, pass a knowledge-force signal with `prepare` — `args: prepare:knowledge`, `args: prepare --knowledge`, or natural language ("force the knowledge pass", "prepare and draft knowledge candidates"). The workflow runs the pass regardless of existing entries. Forcing only controls whether the pass runs — drafts are still `confidence: low`, still per-entry diff-and-confirm, and `confidence: high` entries stay frozen.

Edge case:
- **No git repo** → populate the code-derived artifacts only (`agent-context.yaml`, `CONTEXT.md`, `.ai/memory.log` stub); skip the git-history knowledge scan and record the branch as `n/a (no git)`; never `git init` to satisfy a step. Detail: `adopt-existing.md` § Core principles.

---

---

## `audit`

Run a **static conformance audit** of the current project against the kerby corpus and write a self-contained HTML report. **Read `resources/references/audit.md` in full and follow it** — it holds the untrusted-input doctrine, the auditability classifier, the checks, scoping, and the report contract. The audit is **read-only**: it never edits code, commits, or merges. It is NOT a bug/security review (`/code-review`) and NOT a SKILL.md audit (`skill-evaluator`).

Invocation via the args parameter: `audit [--full] [--sast] [<dimension> ...]` (dimensions: `security` `quality` `data` `git-hygiene` `docs`; omitted = all). `--sast` is **opt-in** (off by default): it adds deterministic code-static security checks — semgrep (OWASP/CWE) + a pinned dependency-advisory scan — to the `security` dimension. Default-on is deferred to Phase 2, gated on the byte-identity check in `references/sast-normalization.md`; `--no-sast` is reserved for when that flip lands.

1. **Preflight (`audit.md` § 2).** If the repo root is a skill-authoring surface, do NOT run — say *"This looks like a skill-authoring repo — run `skill-evaluator` instead; `audit` is for real coding projects"* and stop (overridable if the user re-runs). A monorepo with a real app proceeds, excluding `skills/**` + `.claude-plugin/**`.
2. **Resolve scope.** Default incremental (changes since `.ai/audits/.last-audit`); `--full` sweeps the repo. Positional dimensions filter which checks run; an unknown/ambiguous dimension → list the available ones and ask, don't guess.
3. **Read the live corpus, classify, check.** Walk `BOOTSTRAP.md` + its references; classify each rule auditable/partial/process-only; run the auditable + partial checks in the two bands (mechanical=`observed`, inference=`inferred`). When `--sast` is passed **and the `security` dimension is in scope** (dimensions omitted = all, which includes security), also resolve the project's pinned SAST toolchain from `agent-context.yaml` `stack.tools.sast` and provision it if needed (`references/sast-provisioning.md`; network at setup only, into the git-ignored `.ai/sast/` cache — not repo source, so step 5's *No source files changed* still holds). If the toolchain or advisory snapshot can't be provisioned, the SAST/deps checks are **`not-run`** (banner + a `notrun` callout in the security section) — never silent, never folded into the checked count, and the audit still completes. If `--sast` is passed but `security` is **not** in scope (e.g. `audit --sast quality`), `--sast` is a **no-op**: do not provision, scan, or write the cache — note in the completion message that `--sast` was ignored because `security` wasn't in scope.
4. **Write the report.** `.ai/audits/audit-<dims>-<mode>-<YYYYMMDD-HHMMSS>.md`, render to `.html` (degrade to md-only if no converter), with the three-way coverage banner. If `.ai/audits/` isn't git-excluded, **recommend** the `.gitignore` line in the completion message — do NOT edit `.gitignore` yourself (the audit is read-only).
5. Confirm: *"**Audit complete.** Checked `<C>`, partial `<P>`, process-only `<Q>`. Report: `<path>`. No source files changed."* (plus the `.gitignore` tip if applicable)

Edge cases:
- **No git repo** → audit the working tree only (file-level checks); skip history-based checks (commit-type, schema-migration) and say so in the banner.
- **Empty incremental scope, valid baseline** → report *"no changes since last audit"*, not an empty findings list.
- **`--sast` requested but toolchain/snapshot unresolvable** → SAST + deps reported `not-run` (banner + `notrun` callout); the security section must not read as a clean pass; the audit does not error.
- **First `--sast` run on a baseline that didn't cover SAST** (`.last-audit` is pre-`--sast` or `sast:no`) → force `--full` (`audit.md` §9); the SAST/dependency checks have no valid incremental baseline, so a delta-only scan would miss pre-existing findings.

---
