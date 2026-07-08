# Plan review (Codex adversarial pass)

When drafting an implementation plan in Plan mode on a task, if the Codex plugin
is available (verify on disk per the stance preflight) **and the plan grades
complex or high-stakes** — under a loaded grading rulebook's complexity grade when
one is present; otherwise: irreversible ops, money, security surface, multi-repo,
or >~5 files — run `/codex:adversarial-review` on the draft plan before presenting
the final plan. Simple plans skip the adversarial pass silently. Triage each
finding: accept it (revise the plan) or reject it with reasoning — Codex advises,
Claude decides. One pass, no loop-until-Codex-approves: Codex sign-off is not the
termination condition; Claude's judgment is. All findings must be resolved before
the plan is presented, but resolved ≠ hidden — any material finding that was
rejected gets one line in the presented plan (what Codex flagged, why it was
rejected) so the user sees the dissent at approval time. Skip silently when the
plugin isn't installed.

**Invocation caveat:** `/codex:review` AND `/codex:adversarial-review` are
user-only commands (`disable-model-invocation` — most codex commands are; only
`rescue` and `setup` are model-invocable), so they do NOT appear in the agent's
Skill list and the agent cannot self-trigger them — in an autonomous/unattended
run, substitute `/codex:rescue --background` with a review / adversarial-review
brief (Codex advises, Claude decides — same stance); a human can run the named
commands directly. **Whenever this caveat bites** (the agent wants `/codex:review`
or `/codex:adversarial-review` but can't self-invoke), it also **offers the user
`/codex:setup --enable-review-gate`** — the plugin's built-in Stop-hook gate that
runs the review mechanically at stop-time, removing the agent from the loop
entirely. Offer once per repo per session, not on every occurrence; enabling is
the user's call, and the cost caveat to state when offering is single-sourced in
`references/delegation.md`. General rule: before asserting a `/codex` (or any
plugin) capability is "not installed," verify on disk (`find …/commands -name
'*.md'`) — the session skill list omits `disable-model-invocation` commands, so
absence-from-the-list ≠ not-installed.

**Cross-model role diversity (when to double up):** the default is a division of
labor, not two panels — Claude runs a role-composition pass (e.g. `team-composer`)
for role breadth; the Codex model line is spent on *grounding* (the
adversarial-review above, verifying against code/specs), which is where a second
model actually pays. Only for **greenfield / divergent** planning — no spec or
code to verify against — also run an independent Codex role-lens pass: hand it the
2–3 seats most likely to disagree (e.g. skeptical architect, security, domain
expert) and have it argue *against* the draft; Claude adjudicates (Codex advises,
Claude decides). Do NOT default to a second full role panel on Codex — the same
roles on a different engine buy a second narrative, not diverse grounding, at ~2×
planning cost. Non-negotiable whichever path: the trust-bearing step is a second
model checking the artifact, never the models discussing more.
