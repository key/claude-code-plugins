---
name: review-adr
description: Review an ADR with the context-free adr-reviewer agent (layout, frontmatter, writing rules)
---

# ADR Review Dispatch

Thin frontend for the `adr-reviewer` agent. Determine the review target, launch the agent with a
clean context, and relay its report. Do not review the document yourself in the main context —
the value of this review is that the reviewer has no knowledge of the conversation that produced
the ADR (author bias, and "only makes sense if you were in the room" detection).

## Workflow

1. **Determine the target ADR file(s)**
   - If the user gave path(s) or an ADR number, use them.
   - Else check `git diff --name-only` (and staged/branch diff) for changed files under the ADR
     directory (`docs/adr/` or `decisions/`).
   - Else ask the user which ADR to review.
2. **Launch the `adr-reviewer` agent** with the resolved file path(s). Pass only paths — no
   summary of the conversation, no authoring intent. Context isolation is the point.
3. **Relay the report faithfully**: findings with severity and fixes, plus the verdict. Do not
   soften, filter, or pre-resolve findings.
4. **Apply fixes only on the user's instruction**, then use the layout and writing rules of the
   `manage-adr` skill for the edits. Offer a re-review after non-trivial fixes.
