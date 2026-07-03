# Parity replay — Realized outcomes after the v6 loader integration

Recorded 2026-07-03 at commit `6654f23` (post-Phase-3 SKILL.md), against the
Expected side in `../baseline/`. Realized evidence is recorded as-observed
and never edited to match the prediction (Iron Law extension). Verdicts are
judged on **material intent**.

| Scenario | Verdict | Evidence |
|---|---|---|
| 1 — `kerby load` (no args) | **match** | New load step 3 reads BOOTSTRAP.md in full via the Read tool as the code rulebook's root body (`operating-rules`); step 4 keeps the baseline's verbatim confirmation; step 6 keeps the readiness nudge conditions and silence rules unchanged. Differences are exactly the two the baseline permits: the one-line D19 announcement and the announced first-load `rulebooks.lock` pin write. |
| 2 — `kerby status` | **match** | Steps 1–3 keep the signature-scan method and both verbatim verdict lines; the rulebook panel is the additive step 4 the baseline permits. |
| 3 — mechanical gates | **match** | Re-run at `6654f23`: knowledge-lint 8 PASS, pre-commit-check 24 PASS, protect-git 50 PASS, route-high-stakes 74 PASS, session-start-context 7 PASS, warn-env-read 8 PASS — identical counts to baseline; `check-skill-compat.py` and `check-plan-gate-parity.sh` both exit 0. Hook semantics untouched (the rulebook split declares them as checks; no hook script changed). |

Scenario 1/2 realization note: `load`/`status` are agent-followed prose flows
with no runnable surface outside a live session, so the Realized side is a
dry-run walk of the revised SKILL.md against each baseline step (the
baseline's own recording method), plus the mechanical suite for everything
hook-backed. The live-session confirmation is the wrap-up scratch-repo
verification (handoff § 10).

Trust-flow mechanics verified mechanically in `scripts/validate-rulebook.test.sh`:
hash covers declared bodies (a 1-char tamper changes it → re-validation +
re-prompt path), `--hash` refuses invalid rulebooks (fail-closed), E11 lint
warns on injection patterns shown in the trust prompt.
