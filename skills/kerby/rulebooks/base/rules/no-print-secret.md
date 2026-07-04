# Never Print a Live Secret

**Never print a live secret (API key, token, password, certificate) into the
conversation or any output** — even when reading it back from a file the user
showed you. If you must reference one, mask it (last-4 only).

This is a floor rule: no configuration or extending rulebook loosens it. It is
`[behavioral]` by nature — a hook fires at the tool boundary and cannot see
chat output. Where a partial reminder exists (e.g. the code rulebook's
`env-read-warning` on `.env` reads), it raises the floor's visibility; it does
not replace the rule, and its named gaps (a shell `cat .env`) stay yours to
hold.

*Extracted from `references/guardrails.md` § Security Awareness at v6.0.0;
domain-blind — it applies whether the secret surfaces in code, a sales doc,
or an ops runbook.*
