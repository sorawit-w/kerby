# v7 parity baseline — Expected side (Iron Law)

Captured **as-observed** from `skills/kerby/SKILL.md` at v6.0.0 (`b161c32`), before any
v7 change. Each scenario file quotes the authoritative text verbatim via mechanical
extraction (no paraphrase). After each v7 phase, replay the same extraction against the
post-change SKILL.md and diff: **byte-match required except the enumerated deltas in
`docs/ENGINE-MAP-v2.md` § Expected parity deltas.** A mismatch outside that table is a
stop-and-classify, BLOCKED if unexplained — never edited to match.

| File | Surface | Parity class |
|---|---|---|
| scenario-1 | selection order, pin, announcement line | whitelist deltas only |
| scenario-2 | trust flow + TOFU prompt | + commands/source lines only |
| scenario-3 | load flow, verbatim confirmations, readiness nudge | builtin-code wording verbatim |
| scenario-4 | status verdict + rulebook panel | + `Loaded rulebooks:` only |
| scenario-5 | install Phase 2 hook set | (event, matcher, filename) tuple-set equality |
| scenario-6 | audit + prepare invocation surface (captured cold) | + cold-dispatch preamble only |
| scenario-7 | compaction caveat | word-for-word |

The v6 baseline (`.eval/parity/baseline/`) is a frozen historical capture — do not edit.
