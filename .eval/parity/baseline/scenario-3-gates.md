# Scenario 3 — mechanical gate outcomes, v5.8.0

Recorded as-observed on 2026-07-03 at `fbf6085` (macOS, bash, python 3.14.2).

## Hook test suites (`skills/kerby/resources/hooks/*.test.sh`)

| Suite | Result | Assertions |
|---|---|---|
| `knowledge-lint.test.sh` | exit 0 — all pass | 8 PASS |
| `pre-commit-check.test.sh` | exit 0 — all pass | 24 PASS |
| `protect-git.test.sh` | exit 0 — all pass | 50 PASS |
| `route-high-stakes.test.sh` | exit 0 — all pass | 74 PASS |
| `session-start-context.test.sh` | exit 0 — all pass | 7 PASS |
| `warn-env-read.test.sh` | exit 0 — all pass | 8 PASS |

(`protect-env.sh`, `context-bootstrap.sh`, `knowledge-bootstrap.sh`,
`knowledge-reindex.sh` have no dedicated `*.test.sh` at v5.8.0.)

Representative gate outcome (destructive-git): `protect-git.test.sh` blocks all
BLOCK-array commands with exit 2 (incl. `git push --force`, `git reset --hard`,
commit-on-protected-branch) and allows all ALLOW-array safe variants with
exit 0 — 50/50 assertions.

## Repo check scripts

| Check | Result |
|---|---|
| `python3 scripts/check-skill-compat.py` | exit 0 — `ok skills/kerby/SKILL.md`; version parity all manifests at 5.8.0 |
| `bash scripts/check-plan-gate-parity.sh` | exit 0 — plan_threshold default 4 across 5 files; approval point 7 across 4 files; invariant 4 ≤ 7 |

## What v6 must preserve (material intent)

- Every suite above still exits 0 with the same (or higher) assertion counts.
- Hook semantics unchanged — the rulebook split reframes hooks as declared
  checks (D13) but must not alter what they block/allow.
- Both repo scripts stay green (version parity moves to 6.0.0 in Phase 4).
