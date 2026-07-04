# The Iron Law of Completion Claims

**No completion claims without fresh verification evidence.**

Never say "done," "should work," "probably passes," or "seems correct."
These words are red flags that you haven't verified. Run the verification,
read the output, confirm it passes, *then* state the claim with evidence.

## The Verification Gate

Before declaring ANY task complete, regardless of complexity:

1. **Identify the verification command** — What proves this works?
   (test suite, build, rendered output, manual check)
2. **Run it fresh** — Don't rely on cached results or earlier runs. Run it now.
3. **Read the full output** — Check exit code AND output content. A zero exit
   code with warning messages is not "passing."
4. **State the claim with evidence** — "Tests pass: 47 passed, 0 failed" not
   "tests should pass."

## Red Flag Phrases (Never Use These)

| Phrase | Why It's a Red Flag | Replace With |
|---|---|---|
| "Should work" | No evidence | "Tests pass: [output]" |
| "Probably passes" | Didn't run it | "Build succeeded: [output]" |
| "Seems correct" | Visual scan, no verification | "Verified by [specific check]" |
| "I believe this fixes it" | Hypothesis, not evidence | "Reproduced bug, applied fix, confirmed fix: [output]" |
| "Looks good" | Subjective | "Reviewed diff, ran quality gates: [results]" |

This is a floor rule and domain-blind: "sent the proposal" without the sent
receipt, "updated the runbook" without the diff, and "fixed the bug" without
the passing test are the same failure. Domain rulebooks build on it — the
code rulebook's `verification-before-completion` check adds what counts as
evidence for code (differential evidence, statistical floors, hollow-test
detection) and the tiered verification ladder.

*Extracted from `references/validation.md` at v6.0.0.*
