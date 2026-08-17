---
name: manage-adr
description: Author, update, and supersede Architecture Decision Records with the canonical layout and writing rules
---

# ADR Authoring

Author ADRs (Architecture Decision Records) following the canonical layout and writing rules below.
Use this skill for creating a new ADR, revising an unmerged ADR, changing status, or superseding an
existing ADR. After authoring, recommend a review by the `adr-reviewer` agent (context-free check).

## Request types

| Request | Action |
|---|---|
| Record a new design decision | New ADR (next section) |
| Change status (accept / reject / deprecate) | Edit `status` and `date` in frontmatter only |
| Replace an existing ADR | New ADR + set the old one's `status` to `superseded by ADR-NNNN` |
| Partial replacement | New ADR + keep the old status; state the replaced scope in both bodies |

## Creating a new ADR

### 1. Locate the ADR directory and number

- Use the repository's existing ADR directory (`docs/adr/` or `decisions/`). If none exists, ask
  the user before creating one (default proposal: `docs/adr/`).
- Number = max existing number + 1, zero-padded to 4 digits. Never reuse numbers.
- Filename: `NNNN-<english-kebab-slug>.md`. The filename is the single source of the ADR id.

### 2. Frontmatter ([MADR](https://adr.github.io/madr/)-compatible + tags)

```yaml
---
status: proposed
date: 2026-01-01
decision-makers: [key]
tags: [testing, ci]
---
```

- `status`: `proposed | rejected | accepted | deprecated | superseded by ADR-NNNN`
  (lowercase; supersession is expressed as a status value, not a separate field)
- `date`: last-updated date (`YYYY-MM-DD`). Update on every content or status change.
- `decision-makers`: list of people involved in the decision.
- `tags`: search keywords (project-local extension to MADR).
- Do NOT add `id`, `title`, `related`, `supersedes`, or `superseded-by` fields. The id lives in the
  filename, the title lives in the H1, and relations live in body links / the status value.
- Initial status: `proposed` while under discussion; `accepted` when the user states the decision
  is already made.

### 3. Body layout (headings in the repository's documentation language; shown here in Japanese)

```markdown
# ADR-NNNN: <短いタイトル>

## 概要
## 背景
## 決定内容
## 採用する利点
## 受け入れるトレードオフ
## 候補案と却下理由
### <候補名>          <- one subsection per candidate, NOT a bullet list
## 見直し条件
```

- The H1 number must match the filename number.
- 利点/トレードオフ come right after 決定内容 (they describe the adopted decision); 候補案 comes
  after them so rejected-option details do not mix with the adopted one.
- Each 候補案 subsection: 1-2 sentences describing the candidate, then the rejection reason.
- Omit a section only when it is truly empty; do not invent content to fill it.

## Writing rules

### What to write

1. **概要 (mandatory, first)**: bullet list of WHAT this ADR defines + one-line purpose. A reader
   must not need to read to the end to learn the subject.
2. **背景**: WHY this ADR became necessary (what was unclear or inconsistently judged). Motivating
   measurements/evidence: minimal, and dated (`YYYY-MM-DD 時点`).
3. **決定内容**: policies, principles, scope contracts (e.g. "what will NOT be reduced"), and
   technology selections (record the license and its compatibility when adopting a dependency).
4. **候補案と却下理由**: subsection form as above.
5. **受け入れるトレードオフ**: be honest, including "there is no way to notice X when it breaks".
6. **見直し条件**: triggers for revisiting the decision.
7. References to other ADRs: file-name links like `[ADR-0003](0003-db-strategy.md)`, never a bare
   number.
8. Scope: the whole repository by default. If narrowed, state the reason AND the release condition
   together.

### What NOT to write

1. **Concrete gate values** (thresholds etc.): write the derivation rule and a pointer to the
   primary source (implementation/config file) instead.
2. **Implementation details / how-to**: env var names, task names, hook wiring, per-key config
   explanations, token registration steps.
3. **Enumerations that go stale**: file names, function names, lists of covered targets
   (interfaces etc.) used to narrow scope.
4. **Issue / PR numbers**: references flow one way, Issue -> ADR, never ADR -> Issue.
5. **Incidental discoveries or postponed items**: a made decision goes to the ADR that owns the
   topic; an open question goes to an issue.
6. **Schedules / timing**: ordering *rationale* is fine ("migrate after tests are expanded,
   so migration and threshold-setting happen once"), dates and phase numbers are not.
7. **Work logs / self-justification**: "confirmed by exhaustive grep", "the old version was X so
   we upgrade" and similar narration.
8. **Metric targets framed as goals**: quantitative metrics (coverage etc.) are an *observation of
   results*; do not present raising a number as the purpose of a decision.

## After writing

1. Run the repository's markdown linter on the file if available.
2. Update the ADR index (`README.md` in the ADR directory) if one exists.
3. Show the file path to the user.
4. Recommend a context-free review: launch the `adr-reviewer` agent with the file path.
