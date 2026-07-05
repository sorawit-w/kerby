# The Evaluator Gate on Final Text

**No skill change ships without a fresh pass from the `skill-evaluator` skill (or the equivalent split-role skill audit this repo designates) against the exact text being shipped.**

A pass is evidence about one specific text-state. Any edit after the pass —
a "small fix," a merge, a rewording — re-opens the gate: the pass is stale
and the changed text is unverified. Verify the final text, not a draft of it.

A clean score is **evidence, not proof**. A 34/34 adherence pass has shipped
with two real bugs (a read-only-claim-vs-edit contradiction and a
markdown-escape-ordering flaw) that only an independent review caught —
adherence auditing cannot see internal contradictions. Treat a green number
as one gate cleared, never as ship authorization by itself.

## Scope — which changes re-open the gate

| Change | Gate |
|---|---|
| Pure typo / formatting that alters no directive | Exempt |
| New, removed, or reworded directive, prohibition, threshold, or trigger | Re-opens the gate |
| Skill `description` (triggering surface) changed | Re-opens the gate — and if the repo ships a trigger/boundary fixture (should-fire / should-not-fire corpus), re-check it too; it is a manual checklist, nothing runs it automatically |

This rulebook governs the **host repo's** skills. Edits to kerby's own rules
are governed by kerby's repo docs (`skills/kerby/CLAUDE.md`), which set a
strictly higher bar.

*Provenance: v4.20.0 incident (kerby commit `a386277`); v4.0.2 external-absorb
audit (`7b8b34a`); the un-run trigger-fixture record in `skills/kerby/CLAUDE.md`.*
