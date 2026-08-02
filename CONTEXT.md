# Project Context

> Domain glossary and shared language for this project. Read this at session start. Use these terms in code, commit messages, and prose so humans and agents speak the same language.

## How to use this file

- **Read at session start.** The agent reads `CONTEXT.md` as part of project detection (BOOTSTRAP step 2).
- **Use the terms.** When a concept here has a name, use that name — not a description. *"Materialization cascade"* beats *"the problem when a lesson inside a section is made real."*
- **Propose additions, don't silently edit.** When new domain jargon emerges (a concept used 2+ times, a renamed entity, a new module that becomes vocabulary), surface it before writing.
- **Enduring vocabulary, not session state.** Session state lives in `.kerby/STATUS.md`; decisions and lessons in `.kerby/knowledge/`; this file is the glossary.

## Glossary

### Rulebook

A self-contained folder (`rulebook.toml` manifest + prose rules + hooks + commands) carrying a domain's actual judgment. The engine stays domain-blind — it loads, validates, and dispatches rulebooks without knowing what any of them govern. `skills/kerby/rulebooks/<id>/`

### GATE → WEIGH → VERDICT

The one motion the engine runs on every action: an action arrives at the gate, kerby weighs it against the evidence the loaded rulebook demands, then it passes or is BLOCKED. The engine doesn't know or care what the work is — only the rulebook does.

### Floor

The `base` rulebook's checks (`floor = true` in the manifest) — always merged first into any selection and non-overridable by any extending rulebook. Secrets-staged, untrusted-agent-artifacts, iron-law-claims, and approval-for-irreversible are the current floor rules.

### Selection

The pinned set of active rulebooks for a project, recorded in `.kerby/rulebooks.lock`'s `selected` array. Additive via `load <id>` — loading one rulebook never silently drops another already selected; removing is the explicit `unload <id>`.

## Module map

- `skills/kerby/resources/` — engine machinery: the validator, SessionStart state hooks, state templates
- `skills/kerby/rulebooks/base/` — universal floor rules, merged under every selection
- `skills/kerby/rulebooks/swe/` — the software-engineering rulebook (`BOOTSTRAP.md`, workflows, hooks, commands `audit`/`prepare`)
- `skills/kerby/rulebooks/skill-authoring/` — verification gate for repos that author agent skills
- `skills/kerby/rulebooks/codex-review/` — opt-in Codex-workflow rulebook (PR gate, plan review, delegation)
- `docs/` — `rulebook-contract.md` (the manifest schema authority) and `AUTHORING-RULEBOOKS.md`
- `scripts/` — repo-level dev tooling (`check-skill-compat.py`)

## Superseded terms

<!-- When a term is retired, mark it here with the replacement. Don't delete. -->
<!-- - **Old name** → **New name** — one-line reason. -->
