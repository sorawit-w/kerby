# Approval Before Irreversible Actions

**Before any destructive, hard-to-undo, or externally-visible action, get
explicit human approval.** If you're certain the action is needed, ask the
human to run it themselves — certainty is not authorization.

What counts (any one qualifies):

- **Destructive** — deletes or overwrites work that cannot be mechanically
  recovered (force-pushes, hard resets, dropping data, overwriting a
  human-authored file).
- **Hard to undo** — reversible in principle but expensive in practice
  (rewriting shared history, bulk renames across a live system, schema
  changes).
- **Externally visible** — leaves the workspace: sending email/messages,
  publishing, live payments, calling partner production APIs, anything a
  third party can observe before the human reviews it. Crossing from a
  non-production context into production is always in this class.

A scoped, user-authorized escape hatch on a specific guard (e.g. an explicit
"yes, commit to that branch" honored via a documented override) is
authorization; inferring permission from silence, or from approval given in a
different context, is not.

This is a floor rule: no configuration or extending rulebook loosens it.
Domain rulebooks name their domain's instances and back the reachable ones
with hard enforcers — the code rulebook's `destructive-git` (no escape hatch)
and `protected-branch-commit` (authorized-scoped override) are the canonical
pair.

*Generalized at v6.0.0 from `references/guardrails.md` § Destructive Git
Commands ("ask the developer to run it themselves"), BOOTSTRAP § 4
Ambiguity-Before-Cost (irreversible git operations), and the env-crossing
human-validation rule in `references/environment-safety.md` — those keep
their domain-specific mechanics; this is the universal floor beneath them.*
