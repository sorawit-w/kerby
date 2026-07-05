# The Evaluator Gate on Final Text

**No skill change ships *as verified* without a fresh pass from the
`skill-evaluator` skill (or the equivalent split-role skill audit this repo
designates) against the exact text being shipped.** The only way past a
missing or failing pass is the explicit, labeled degrade path in
[[degrade-loudly]] — never a silent one.

**"Ship" means** the change reaching the repo's default branch, or any
publish/release step — whichever comes first. Work-in-progress commits on a
feature branch are not shipping; the gate is due before the change merges or
publishes, against the exact text that will land.

**"Skill change" means** an edit to any file the skill loads as instructions —
`SKILL.md` and the reference/prompt files it pulls into context — not incidental
assets (images, fixtures the skill doesn't load as rules).

A pass is evidence about one specific text-state. Any edit after the pass — a
"small fix," a merge, a rewording — re-opens the gate: the pass is stale and
the changed text is unverified. Verify the final text, not a draft of it.

A clean score is **necessary, not sufficient**. It clears the adherence gate;
it is not by itself ship authorization — a 34/34 pass has shipped with two real
bugs (a read-only-claim-vs-edit contradiction and a markdown-escape-ordering
flaw) that only an independent review caught, because adherence auditing cannot
see internal contradictions. Whatever other review gates the repo runs (an
independent-model review, a human sign-off) still apply on top of a green
number.

## Scope — which changes re-open the gate

| Change | Gate |
|---|---|
| Pure typo / formatting that alters no directive | Exempt |
| New, removed, or reworded directive, prohibition, threshold, or trigger | Re-opens the gate |
| Any byte change to the skill `description` (triggering surface) | Re-opens the gate — this row wins over the typo exemption even for a typo fix inside `description`; and if the repo ships a trigger/boundary fixture (should-fire / should-not-fire corpus), re-check it too, since nothing runs it automatically |

The exemption is self-certified, so **when in doubt, the gate is open** — a
diff that could be read as a reworded directive is not "formatting cleanup."

The **designated equivalent** (when a repo names one instead of
`skill-evaluator`) lives in a versioned repo file, not a chat message, so every
session sees the same designation. This rulebook governs the **host repo's**
skills; edits to kerby's own rules are governed by kerby's repo docs
(`skills/kerby/CLAUDE.md`), which set a strictly higher bar.

*Provenance: the v4.20.0 clean-pass-with-real-bugs incident (kerby commit
`cb8f699`, documented by the v4.20.1 follow-up `a386277`); the v4.0.2
external-absorb audit (`7b8b34a`); the un-run trigger-fixture record in
`skills/kerby/CLAUDE.md`.*
