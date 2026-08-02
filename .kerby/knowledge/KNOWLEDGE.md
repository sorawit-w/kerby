# Knowledge Base Index

Project knowledge — architecture decisions, domain context, conventions, and lessons learned.
Read this index to find relevant context before planning or implementing.

## Entries

<!-- AUTO-INDEX:START -->
<!-- Hand-edited: knowledge-reindex.sh's mechanical extraction truncates mid-sentence
     and can split a code-span across the 120-char cut, breaking markdown. Re-check
     these lines by hand after any --force reindex rather than trusting the script. -->
- [Why the engine was split from rulebook content](decision-engine-rulebook-split.md) — v6/v7 split into an engine + self-contained rulebooks (confidence: high)
- [Why the coding rulebook was renamed code → swe](decision-code-to-swe-rename.md) — v9.0.0 rename frees `code` as an unreserved id (confidence: high)
- [Why the engine stopped keying behavior on rulebook names](decision-engine-independence-zoning.md) — v9.4–9.5 decoupling via the `[identity]` contract table (confidence: high)
<!-- AUTO-INDEX:END -->
