# PR workflow (Codex-gated)

When opening a PR (base = the repo's default branch):

1. **Review before the PR.** If local Codex (`/codex:review`) is available, run it
   against the branch diff (`--base <default-branch> --scope branch`) and loop
   review → fix → re-review per the **Review loop (bounded)** rule below.
   `/codex:review` is user-only (`disable-model-invocation`) — the agent runs the
   same engine headless instead: `node <codex-plugin>/scripts/codex-companion.mjs
   review "--wait --base <default-branch> --scope branch" < /dev/null` via
   background Bash with an explicit timeout (default timeout SIGTERMs), or
   substitutes `/codex:rescue` with a review brief. Every attempt is bounded per
   `references/delegation.md` § Bounded delegation — a budget exhausted with no
   verdict activates the step-4 fallback. When this caveat bites, also offer the user the plugin's
   stop-time review gate once per repo per session — the cost caveat and mechanics
   are single-sourced in `references/delegation.md`. "Not in my Skill list" is NOT
   "no local Codex" — verify on disk first (see `references/stance.md` preflight);
   the fallback in step 4 is only for a plugin that is genuinely missing or
   broken, or one that exhausted the delegation budget with no verdict.
   **Review loop (bounded).** Every review brief must carry the severity rubric and
   the verdict contract: "Tag each finding P0 (security / data-loss / correctness
   blocker), P1 (likely bug or broken contract), P2 (should-fix), P3 (nit). End the
   review with one final line: `CODEX_VERDICT: P0=<n> P1=<n> P2=<n> P3=<n>`, counting
   OPEN findings." If the invocation path can't carry a custom brief, use the
   rescue-with-brief substitute. Only open P0/P1 block: fix them, then run a SCOPED
   re-review ("verify these fixes + scan the fix diff" — never a fresh full-branch
   pass). P2/P3: fix in the same pass if trivial, otherwise log (issue or
   ponytail-debt) — they never trigger a re-review. Hard cap: 3 rounds —
   `scripts/codex-mark.sh` (below) counts rounds per branch and enforces it. Cap hit
   with open P0/P1 → HELD: stop, escalate to the user, no merge, no marker. Severity
   is Codex's call; Claude may downgrade a finding only with a one-line reason
   recorded in the PR body. "Clean review" throughout this section means: no open
   P0/P1 within the cap.
   **PR gate (mechanical):** this rulebook's PreToolUse hook
   (`hooks/codex-pr-gate.sh`, registered by `kerby install`) blocks `gh pr create`
   unless a marker records a clean Codex review of the current HEAD. The marker is
   written ONLY by this rulebook's `scripts/codex-mark.sh` — never by hand;
   hand-writing it is gate-dodging. Tee every review's output to
   `$(git rev-parse --git-dir)/codex-review.log`, then run `scripts/codex-mark.sh`
   (resolve it relative to this rulebook's root — the folder this file was loaded
   from): it verifies a clean `CODEX_VERDICT` (P0=0 P1=0) against a log newer than
   HEAD, enforces the round cap (PASS / DENIED / HELD), writes the marker, appends
   to the audit log, and prints the PR-note line used in step 3. Any new commit
   stales the marker (re-review, re-mark). Deliberate bypass (user-approved only):
   prefix the gh invocation with `CODEX_GATE_BYPASS=1` — the prefix form is the only
   honored one; the token embedded elsewhere in the command authorizes nothing, and
   one authorized invocation never authorizes another in the same command. The gate
   verifies the repo at the session cwd, so run `gh pr create` as a standalone
   command — combining it with `cd`/`pushd`/`-C`, or retargeting it with
   `gh -R`/`--repo`, is refused (would check, or create the PR against, the wrong
   repo). Known ceiling: the gate string-matches on a broad token sequence (`gh` … `pr`
… `create`/`new`, any option form between, not crossing a command separator),
so it catches every gh invocation syntax but also over-blocks a matching string
in quoted prose (safe direction); the raw REST path (`gh api …/pulls`) and
user-defined `gh alias` shortcuts are not resolved (documented deliberate-bypass
ceiling). The **final** review must run
   against the exact tree you push — fix churn on the branch is throwaway (the
   squash-merge collapses it), but nothing may change after that last clean review.
2. **Open the PR**, then merge with `--squash --delete-branch` (squash keeps one
   commit per PR; `--delete-branch` because a repo may have `deleteBranchOnMerge`
   off).
3. **Local Codex clean → merge immediately**, pasting the PR-note line printed by
   `scripts/codex-mark.sh` into the PR body: `Codex-reviewed locally at <sha> ·
   rounds=<n> · P0/P1=0 · P2/P3 logged=<n>` — `<sha>` is the branch HEAD you
   reviewed and pushed. (Squash-merge changes the commit SHA on the default branch
   but not the content, so the note stays verifiable as "reviewed tree == PR head
   tree".)
4. **Fallback — no local Codex verdict** (plugin/CLI genuinely missing or broken
   per the stance preflight, NOT merely absent from the Skill list — **or present
   but unable to produce a verdict within the delegation budget**, per
   `references/delegation.md` § Bounded delegation): the mechanical
   PR gate will still block `gh pr create` with no marker — this is the one
   sanctioned marker-less use of `CODEX_GATE_BYPASS=1`, because the GitHub-side
   review below replaces the local one; never bypass when local Codex works.
   Sanctioned ≠ pre-authorized: the bypass still needs the user's per-PR
   approval (the gate rule's "user-approved only" applies on every rung). Open
   the PR (with the bypass), trigger a GitHub-side `@codex review` (include the
   P0–P3 rubric in the mention comment), and poll. **Address every P0/P1 comment
   before merging** — fix it (a fix is a new push → new review cycle) or push back
   with reasoning. P2/P3 comments get a reply plus a log entry (issue or
   ponytail-debt) and count as addressed. Never merge with an open, unaddressed
   P0/P1. Merge only on a green light **against the current head**: an approval /
   👍 reaction dated after the latest push, or — once all comments are addressed —
   the silence cap after ≥1 completed review of HEAD (never when Codex never
   reviewed HEAD at all). **Cadence:** poll ~every **150 s**; if Codex isn't
   reviewing by the first poll, re-mention `@codex review`; each reply that
   addresses a comment resets the timer; merge at the silence cap — the **4th poll,
   ~10 min** after that reply. A clean signal (👍, or a completed no-findings review
   of HEAD) short-circuits the cap and merges immediately.
   **Last rung — no GitHub remote, or GitHub Codex also unavailable:** the agent
   verifies the diff itself against green regression tests, then asks the user for
   fresh per-PR `CODEX_GATE_BYPASS=1` authorization, disclosing in the PR body
   that no independent Codex review occurred. Self-review is NOT a substitute for
   the review — it is a disclosed degradation, taken only after both Codex venues
   have failed (or the GitHub venue doesn't exist for this repo).

Enforcement note: the review-before-PR half IS mechanically gated (the PR gate in
step 1, registered per repo by `kerby install`), and the clean-verdict attestation
is mechanical too (`scripts/codex-mark.sh` — ceiling: it trusts the teed log;
forging one is possible but deliberate, and `$GIT_DIR/codex-review-audit.log` keeps
the history visible). The merge rules (steps 2–4) remain instruction only — they
shape behavior but don't block a bad merge; a repo wanting a hard merge gate needs
its own hook.
