# Record the Verdict

**Record every evaluator verdict durably — one line naming the verdict, the
date, and an identifier for the exact text that was evaluated.**

The evaluator gate says "fresh pass on the exact text shipped." That claim is
only checkable later if the pass was written down *with the text-state it
covered*. An unrecorded pass is a remembered pass, and memory does not survive
a session boundary.

## Which identifier — pick the one the home allows

The evaluated tree is usually uncommitted when the pass runs, so name an
identifier that exists at record time:

| Durable home | Identifier that works there |
|---|---|
| PR body | the branch HEAD commit SHA (recorded after the change is committed and pushed) |
| `.kerby/memory.log` | the committed SHA, once it exists |
| Commit message | **not** its own SHA (impossible) — use a content hash of the evaluated tree: `git hash-object` on the file, or `git stash create` for a dirty worktree |

One line. Shape:

```
skill-evaluator: clean (34/34) at 3f2c1ab — 2026-07-05
```

Name the actual verdict — `clean`, or the finding count if not clean — and the
identifier of the evaluated text. If the text changes after the recorded pass,
the record itself now shows the gate re-opened: the recorded identifier no
longer matches what shipped. That mismatch is the point — it makes staleness
visible instead of remembered.

*Provenance: evidence-format sweep of the kerby record (2026-07-05) — passes
were implied by workflow, never recorded with the evaluated identifier; the
v4.20.0 incident (`cb8f699`) is only reconstructible because the failure was
recorded.*
