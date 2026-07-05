# code — the coding rulebook

kerby's first domain rulebook and the silent default for `kerby load`. Clarity over
cleverness, safety over speed, never leave the repo broken — and nothing unproven
passes the gate. Extends `base` (the universal floor rides along automatically).

Self-contained: everything this rulebook *declares* lives in this folder. Copy the
folder, get the rules — the receiving kerby will still ask its user for approval
before loading it, exactly as it should. The one host dependency is the floor:
`code` extends `base`, so its `hollow-test-heuristic` enforcer reuses the floor's
`pre-commit-check.sh` rather than shipping a private copy of the non-disablable
secret scan. The floor always rides along from the host install — `kerby install`
binds that check to the host `base` script, and if a relocated copy can't reach a
floor, the soft check degrades to behavioral (the secret-scan floor itself is
never affected — `base` registers it directly).

## Layout

| Path | What it is |
|---|---|
| `rulebook.toml` | the manifest — the single authority for what this rulebook contains |
| `BOOTSTRAP.md` | the root body: prime directive, decision ladder, routing, hard rules, reference index |
| `references/` | the long-tail topic guides BOOTSTRAP's index loads on demand |
| `workflows/` | the five task-shape playbooks (new-project, adopt-existing, feature, bugfix, quick-task) |
| `hooks/` | tool-boundary enforcers (destructive-git, `.env` protection, high-stakes routing, …) + tests |
| `commands/` | the bodies of this rulebook's user-invocable commands |
| `templates/`, `scripts/`, `assets/` | agent-context schema/template + validator, audit/html templates, workflow diagrams |

## Checks

Eleven checks: five hook-backed (`destructive-git` — floor, `protected-branch-commit`,
`protect-env`, `env-read-warning`, `high-stakes-routing`, `hollow-test-heuristic`) and
five prose gates (`operating-rules` = BOOTSTRAP, `quality-gate-tiers`,
`verification-before-completion`, `security-lens`, `guardrails-scope-security`).
Declared enforcement is honest: `kerby status` shows what is mechanically bound
versus behavioral, per check.

## Commands

| Command | What it does |
|---|---|
| `kerby audit` (or `kerby code audit`) | read-only static conformance audit of the project against this corpus; report under `.kerby/audits/` |
| `kerby prepare` (or `kerby code prepare`) | onboard an existing repo — populate kerby's context artifacts from code + git history, diff-and-confirm on every write |

## Provenance

The original kerby corpus (v1–v5 as a monolithic playbook), split engine-from-rules
in v6.0.0, physically self-contained in v7.0.0. Contract: `docs/rulebook-contract.md`.
