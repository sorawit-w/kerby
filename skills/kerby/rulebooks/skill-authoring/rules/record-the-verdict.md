# Record the Verdict

**Record every evaluator verdict durably — one line naming the verdict, the
date, and the SHA (or text-state) that was evaluated.**

The evaluator gate says "fresh pass on the exact text shipped." That claim
is only checkable later if the pass was written down *with the text-state it
covered*. An unrecorded pass is a remembered pass, and memory does not
survive a session boundary.

One line, in any durable home the change already touches:

- the PR body,
- the commit message, or
- `.kerby/memory.log` (when the repo keeps kerby project state).

Shape:

```
skill-evaluator: clean (34/34) at 3f2c1ab — 2026-07-05
```

Name the actual verdict — `clean`, or the finding count if not clean — and
the commit SHA of the evaluated tree. If the text changes after the recorded
pass, the record itself now shows the gate re-opened: the recorded SHA no
longer matches the shipped one. That mismatch is the point — it makes
staleness visible instead of remembered.

*Provenance: evidence-format sweep of the kerby record (2026-07-05) — passes
were implied by workflow, never recorded with the evaluated SHA; the v4.20.0
incident (`a386277`) is only reconstructible because the failure was recorded.*
