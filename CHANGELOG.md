# Changelog

All notable changes to `kerby` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versioning is semver.

## [5.1.0] — 2026-06-21

Mapped the **Security Lens** ([`validation.md`](skills/kerby/resources/references/validation.md)
§ Security Lens — Conditional Pass) to named, dated security standards and closed one
genuine coverage gap. The lens stays **conditional** and **`[behavioral]`** — it *targets*
these standards best-effort by agent judgment; nothing mechanically verifies conformance,
and no artifact may claim the code is "OWASP-compliant."

### Added
- **SSRF coverage** `[A10 · CWE-918]` — new trigger (*outbound requests to a user-influenced
  URL/host* — webhooks, unfurlers, fetchers, proxies, cloud metadata) plus a check item
  (allowlist destinations, block internal ranges + `169.254.169.254`, no redirect-following
  or DNS-rebinding into internal targets). This is the behavior-changing addition: the lens
  now fires on a surface the prior trigger list missed.
- **OWASP Top 10 (2021) + CWE tags** on every Security Lens check, plus `[A06 · CWE-1104]`
  on the dependency-review rule in [`guardrails.md`](skills/kerby/resources/references/guardrails.md)
  § Security Awareness. Tags are a dated citation, stamped against the 2021 list; `LLM01`
  references the separate OWASP Top 10 for LLM Applications.
- **A04 (Insecure design)** `[A04 · CWE-657]` and **A05 (Security misconfiguration)**
  `[A05 · CWE-16]` named as explicit check items. **A08** folded into the existing
  deserialization trigger as `[A08 · CWE-502/494]` rather than a duplicate bullet.
- **Non-certification honesty note** in the lens: targets the standards best-effort,
  `[behavioral]`, mapping is hand-maintained and not auto-tracked for drift.

### Notes
- **A09 (logging/monitoring) deliberately not named** — its "never log secrets" half is
  already the Secret-exposure check (`[A02 · CWE-200/532]`); its "log security events" half
  is ops scope-creep outside a coding lens.
- **`working-patterns.md` intentionally left untagged** — its platform-code security items
  are woven into prose, not a taggable list; tagging there spreads the citation-staleness
  liability for little gain.
- No tooling added (no SAST/CodeQL/SARIF); no change to `audit.md` or the `security` audit
  dimension; no third-party skill references.

## [5.0.0] — 2026-06-20

**Renamed the project from `cerby` to `kerby`.** The name now follows the Greek
**Kerberos** (Κέρβερος) — the hound at the gate — rather than the Latin *Cerberus*
the old name shortened. This is a breaking change: the plugin/skill install name
changed from `cerby` to `kerby`, so existing installs must reinstall under the new
name. Rules, hooks, workflows, and behavior are otherwise unchanged.

### Changed
- **Plugin identity** — `name`/`id`/`keywords`/URLs across `.claude-plugin/`,
  `.codex-plugin/`, and `.agents/plugins/` manifests now read `kerby`; repo URLs
  point to `github.com/sorawit-w/kerby`.
- **Skill** — `skills/cerby/` → `skills/kerby/`; SKILL.md `name: cerby` → `kerby`;
  all prose, references, hooks, templates, and the `.eval/triggers/` corpus updated.
- **Voice** — `VOICE.md` lore now derives the name from Greek *Kerberos* (Latin
  *Cerberus* noted as the later spelling).
- **Assets** — `assets/cerby-*.png` → `assets/kerby-*.png` (filenames + references).
  ⚠️ The bitmap artwork still renders the old wordmark and needs a redraw.

## [4.22.0] — 2026-06-20

Two `audit` runs over the same repo state diverged in layout — the HTML chrome was
already deterministic, but the Markdown **body** wasn't: §6 defined finding *fields*
without a layout, and §7 said "grouped by dimension, sorted by severity" without
pinning list-vs-table. Each run improvised the body. Fix: **pin the body structure**
and give the audit its **own render template** so the same findings always produce a
structurally identical report.

### Added
- **`skills/kerby/resources/templates/audit-report.html.template`** — a dedicated
  audit render template. Shares the generic `html-export.html.template` `:root` BASE-token
  contract (so `DESIGN.md` overrides through one surface) and adds the audit-only layer:
  coverage banner, `table.findings`, severity badges, confidence styling, `--measure: 52rem`,
  and **fixed** semantic `--sev-*` status tokens (a brand palette can't make "blocker"
  stop reading as danger).

### Changed
- **`references/audit.md` §6** — a finding is now a `<tr>` in a raw-HTML `table.findings`
  with a fixed five-column order, not a Markdown bullet list. The raw-HTML scaffolding is
  the only trusted markup; cell *content* is entity-escaped + wrapped in a literal
  `<code>` element (Markdown backtick spans are inert inside the passed-through block —
  §8 step 2's backtick rule governs Markdown body text, not cell content).
- **`references/audit.md` §7** — the report skeleton is pinned to one exact top-to-bottom
  order (title → banner → summary → per-dimension tables → footer). Dimension sections
  follow the §10 stable-map order and same-severity rows tie-break by Location, so the
  ordering is *total* (no filesystem/git-discovery drift between runs). The banner is
  emitted as raw HTML. Zero-findings renders the banner + "No violations among the
  statically-checkable rules in scope" — never a bare ✓.
- **`references/audit.md` §8** — the render now wraps in `audit-report.html.template`. The
  untrusted-input escaping + self-check obligations are unchanged.
- **`references/html-export.md`** — the "one sanctioned exception" note now says the audit
  reuses the fill-and-override *machinery* and token contract via its **own** template, not
  the generic one. Docs stay honest.

### Notes
- MINOR (additive, user-visible output-format change). Determinism is the acceptance bar:
  same findings + same corpus → structurally identical report. No new checks, no hook
  changes, `BOOTSTRAP.md` untouched.

## [4.21.2] — 2026-06-19

A `team-composer` audit asked whether the agent-skills v5.2.0 "library-conventions"
layer (authority tiers / supply-chain / co-load regression gate / state-passing)
should be ported into kerby. Finding: **kerby already implements it, often as the
origin** — tiers are mechanically hook-enforced (stronger than a review annotation),
provenance lives in `NOTICE` + dated inline citations, eval grading is delegated to
`skill-evaluator`, and the harness/control-loop vocabulary is in the root `CLAUDE.md`.
The one genuinely-novel agent-skills mechanism — the cross-skill co-load regression
gate — is N/A for a single skill. So nothing was ported; one fixture was added.

### Added
- **`.eval/triggers/kerby.json`** — a committed trigger-eval boundary corpus
  (should-fire / should-not-fire / neighbor-steal) protecting kerby's sharp
  "do NOT invoke on general coding tasks" boundary, including the load-bearing case
  that a general "security review of my repo" must NOT fire (kerby `audit` is
  conformance-to-kerby, not a general bug/security review). The fixture is labeled
  data the skill owns, not a runner: triggering-accuracy runs are `skill-creator`'s
  `run_eval` job (NOT `skill-evaluator`, which audits rule adherence), and no gate
  auto-runs it — it is a manual regression checklist for description edits.
- **`skills/kerby/CLAUDE.md`** — a short note recording why the conventions layer is
  not ported and why a trigger fixture coexists with "ships no eval harness."

### Changed
- **`.gitignore`** — un-ignored `.eval/triggers/` only (`.eval/*` + `!.eval/triggers/`)
  so the boundary corpus is committed while the rest of `.eval/` stays local scratch.

### Notes
- Backwards-compatible (PATCH). No rule text or `SKILL.md` description changed, so no
  `skill-evaluator` gate fired. Fixture + docs only; no eval harness shipped.

## [4.21.1] — 2026-06-17

### Fixed
- **`prepare` now degrades cleanly on a repo with no git history.** `adopt-existing.md`
  issued the `git log` decision-scan and `git branch --show-current` as unconditional
  steps with no fallback, leaving the no-git case undefined — an agent could stall or
  `git init` unprompted (a repo-state change the ring-fence forbids). It now populates the
  code-derived artifacts only, skips the git-history knowledge scan, records the branch as
  `n/a (no git)`, and never `git init`s — mirroring `audit`'s existing no-git stance.
  Surfaced by a `skill-evaluator` absent-state audit.

## [4.21.0] — 2026-06-17

First release under the **`kerby`** name. The skill was extracted from
[`sorawit-w/agent-skills`](https://github.com/sorawit-w/agent-skills) — where it shipped
as `coding-rules` through v4.21.0 — into this standalone repo, with full commit history
preserved (`git log`). The version number is continuous with the `coding-rules` line; the
rename is the only change in this release.

### Changed
- **Renamed `coding-rules` → `kerby`** everywhere: skill `name`, trigger phrases, the
  `/kerby` invocation, the `KERBY_DIR` env var, hook-path signatures, glob discovery, and
  all prose. `coding-rules` is no longer recognized — invoke `kerby` (or `/kerby`).
- **Standalone packaging.** Own plugin manifests (Claude Code, Codex, Cowork), own
  `check-skill-compat.py`, vendored harness-engineering vocabulary in the repo-root
  `CLAUDE.md`. Sibling skills it used to be bundled with (`sub-agent-coordinator`,
  `team-composer`, `i18n`, `tech-stack-recommendations`, `brand-workshop`) are now
  optional external pointers to `sorawit-w/agent-skills` with graceful fallback.

### Notes
- Prior per-version history (v4.0–v4.21.0 under the `coding-rules` name) lives in the
  preserved git history and in the `sorawit-w/agent-skills` CHANGELOG.
- **Breaking:** anyone invoking `/coding-rules` must switch to `/kerby`. There is no
  back-compat alias by design — `kerby` is a clean-identity repo.
