# codex-review — opt-in Codex workflows for kerby

Wires the Codex CLI (an independent model line) into three workflows, under one
stance: **Codex advises, Claude decides.**

| Workflow | Prose | Mechanics |
|---|---|---|
| PR gate — review before `gh pr create`; P0/P1 block; 3-round cap; PASS/DENIED/HELD | `references/pr-workflow.md` | `hooks/codex-pr-gate.sh` (PreToolUse/Bash) + `scripts/codex-mark.sh` (sole marker writer) |
| Plan review — adversarial pass on complex plans, dissent disclosed | `references/plan-review.md` | none (behavioral, `warn`) |
| Rescue delegation — independent diagnosis before human escalation | `references/delegation.md` | `scripts/codex-run.sh` (bounds one headless attempt) |

Every headless Codex invocation — review, scoped re-review, rescue — runs through
`scripts/codex-run.sh`. It closes stdin, gives the runtime its own process group,
kills it at a ceiling derived from the observed-good `dur=` median, and reports
how it ended (0 clean · 4 killed at the ceiling · 5 runtime error). It bounds
*one attempt* and never retries: the delegation budget and the verdict grammar
stay with the prose and `codex-mark.sh` respectively.

The root body (`references/stance.md`) is a thin eager index: stance, on-disk
preflight, when-to-read pointers. The heavy references load on demand.

## Opt-in and install

`codex-review` declares no `[detect]` markers — it never auto-selects. Opt a repo
in explicitly:

```
kerby load codex-review      # adds to the selection (pin persists)
kerby install                # register the gate hook (Phase 2)
```

Until `kerby install` binds the hook, `pr-create-gate` is declared `hard` but
effectively behavioral — `kerby status` shows the degrade. `kerby pr-check`
reports preflight, marker/rounds/audit state, hook binding, and duplicate rules.

**Duplicate rules:** if the global or repo CLAUDE.md still carries the old codex
sections, the stance's adoption check (and `pr-check`) surfaces a
remove/proceed/stop menu. While duplicates coexist there is no mechanical winner —
identical copies waste tokens; drifted copies are ambiguous (CLAUDE.md nominally
outranks loaded prose). Migration is move-not-copy: delete the old copy.

**Per-check opt-out (contract 2): none.** User config remaps severities at the
gate level only (`block_on`/`hold_on`) — it cannot disable one check. A repo that
wants the PR gate but not plan review relies on plan review's complexity
self-gating (~zero cost on simple plans). `hold_on = []` would demote ALL
warn-severity checks — blunt; not recommended.

## State files (per-clone, in `$GIT_DIR`, never committed)

| File | Written by | Meaning |
|---|---|---|
| `codex-reviewed` | `scripts/codex-mark.sh` ONLY | marker: the reviewed HEAD sha |
| `codex-review.log` | `scripts/codex-run.sh` (fresh inode per attempt) | evidence codex-mark verifies |
| `codex-review-rounds` | `scripts/codex-mark.sh` | branch + round counter (cap 3) |
| `codex-review-audit.log` | `scripts/codex-mark.sh` | append-only PASS history; its `dur=` median sets the watchdog ceiling |
| `codex-run-attempts.log` | `scripts/codex-run.sh` | append-only history of killed/failed attempts — deliberately NOT the audit log, so these can never skew the `dur=` median |

## Bypass

`CODEX_GATE_BYPASS=1` **directly prefixing** the gh invocation, user-authorized
only (manifest `override = "authorized-scoped"`). The prefix form is the only
honored one: an embedded token (PR-body text) authorizes nothing, and one
authorized invocation never authorizes a second one in the same command.
Marker-less use is sanctioned only inside the step-4 fallback ladder (GitHub-side
review replacing the local one, or the disclosed last-rung degradation) when
local Codex is genuinely missing — or present but unable to produce a verdict
within the delegation budget (`references/delegation.md` § Bounded delegation).

## Known ceilings (deliberate)

- **String-match gate, not a shell parser.** The matcher is a broad token
  sequence — `gh` … `pr` … `create`/`new` in order, any options in any form
  between, not crossing a `;`/`&`/`|` separator. This catches every gh
  invocation syntax by design (attached `-Rowner/repo`, `-R=owner/repo`, spaced
  `-R owner/repo`, `--repo=`, the `new` alias, arbitrary global flags) rather
  than enumerating option shapes — four review rounds each found a shape an
  enumerating regex missed, so the gate stopped enumerating. The trade is
  over-blocking in the safe direction: a `gh pr create`-shaped string inside
  quoted prose, or a `-C `/`-R`/`--repo`/`GH_REPO=` token anywhere in a compound
  command, triggers a (re)fusal — the gate already asks you to run the command
  standalone, so rerun it plain or bypass. Deliberate-only escape hatches it does
  **not** try to catch (shaped like intent, not accident): the raw REST path
  (`gh api repos/{o}/{r}/pulls -X POST …`), a user-defined `gh alias`, or a shell
  line-continuation split. These are the `CODEX_GATE_BYPASS` category by another
  name — an accepted ceiling, not a hole to plug.
- **codex-mark trusts the transcript.** Forging a log is deliberate deception,
  not drift; `$GIT_DIR/codex-review-audit.log` keeps history visible.
- **The ceiling is the only bound — no early kill.** codex-run cannot tell a
  wedged runtime from a thinking one, and does not pretend to: both go quiet.
  The block-point line Codex was once matched on is printed at *startup* on
  every redirected-stdin run and appears verbatim in `references/delegation.md`,
  so it fires on healthy transcripts; macOS `ps %cpu` is a lifetime average and
  cannot report instantaneous idleness. A build that killed on line-plus-silence
  truncated a healthy 107 KB review at 38s — that is worse than the unbounded
  wait it replaced. Cost of the honest version: a genuine wedge burns the full
  ceiling instead of ~6s. Exit code 3 is left unused rather than recycled.
- **codex-run bounds one attempt, not the budget.** It never retries. The
  2-attempt delegation budget stays with the prose in
  `references/delegation.md`, because budget consumption is defined by verdict
  *parseability* — codex-mark's grammar, which must not be forked into a
  second script.
- **jq required for the gate hook.** Missing jq degrades to an announced ALLOW —
  the notice rides `additionalContext` JSON on stdout (the channel the agent
  reads on a PreToolUse exit 0; stderr there is invisible to the model). Install
  jq to restore enforcement.
- **Ambient GH_REPO is invisible.** An in-command `GH_REPO=other/repo gh pr
  create` is refused (wrong-repo), but an already-`export`ed `GH_REPO` can't be
  seen by a PreToolUse hook — same ambient-var blindness as swe's protect-git.
- **Plan review has no mechanical backstop.** The eager stance's trigger line is
  the only prompt; if rules seem to stop applying mid-session (compaction), run
  `kerby reload`.
- **`accepts = ["git_change"]`** scopes the subject model to the mechanical gate;
  the plan-review/delegation prose is behavioral and not subject-scoped.

## Provenance

Ported 2026-07-07 from the maintainer's global CLAUDE.md (v3) and
`~/.claude/hooks/{codex-pr-gate.sh,codex-mark.sh}` — the complete port: nothing
codex-coupled remains global after migration. Hook hardened over the global
original: whitespace-tolerant detection, per-invocation strip-then-residual
bypass, explicit no-jq degrade. codex-mark hardened: all four `CODEX_VERDICT`
counts required (fail-closed on a partial line).

`scripts/codex-run.sh` added 2026-08-03 (0.3.0) — no upstream original. Written
against a reproduced failure: a 23.7-hour attempt (`dur=85344s`) recorded in this
repo's own audit log beside 2-minute reviews, caused by an invocation shape that
could not be bounded (`… | tee log &` makes `$!` the *tee* pid) on a platform with
no `timeout(1)`.
