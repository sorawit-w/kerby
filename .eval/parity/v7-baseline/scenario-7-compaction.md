# v7-baseline — compaction caveat (v6.0.0 @ b161c32)

PARITY-CRITICAL: carries over word-for-word.

## Compaction caveat

Once `load` runs, BOOTSTRAP enters conversation context. Claude Code's compaction may strip or summarize that context during long sessions. **If the rules seem to stop applying, invoke with `args: reload`.** Running `args: status` is the safest way to verify whether the rules are still in context after compaction.
