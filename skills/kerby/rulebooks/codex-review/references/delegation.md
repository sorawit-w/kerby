# Codex delegation (the rescue ladder)

When stuck — a retry budget exhausts, a debugging hypothesis cap hits, or two
consecutive fix attempts fail the same way — run `/codex:rescue` for an
independent diagnosis pass before escalating to the user. Prefer `--background`
for open-ended investigations (use `--effort high` for deep root-cause work) and
keep working meanwhile; check with `/codex:status` and fetch with `/codex:result`.
Codex advises; Claude decides — its diagnosis is a hypothesis to verify, not a fix
to apply blind. This is a rung before human escalation, not a replacement for it:
if the independent pass doesn't break the deadlock, escalate as usual.

## The stop-time review gate — offer wording and cost caveat (single source)

The stop-time review gate (`/codex:setup --enable-review-gate`) stays off by
default — enable per-repo only if the prose review workflows are observed being
skipped. Cost caveat (state it whenever offering the gate, from any workflow in
this rulebook): the Stop hook spawns a Codex task on **every** turn end — the
"skip non-edit turns" logic is inside the Codex prompt (instant ALLOW), not the
hook — so even chat-only turns pay one Codex round trip; 15-min timeout. Good for
build-heavy repos that ship PRs, wasteful for mostly-conversational sessions.
