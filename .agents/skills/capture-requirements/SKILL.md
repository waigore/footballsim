---
name: capture-requirements
description: |-
  Interactively capture a Footballsim feature requirement from the product
  owner across functional, non-functional (game/sim budgets), UX,
  architectural, and algorithmic/schematic dimensions; flag gaps; confirm
  the pack; then file a container issue plus related sub-issues via
  file-github-issue (todo+enhancement or question by ambiguity). Wiki
  follow-up is the default expectation for new features (still confirm).
  Use proactively when a feature request is large, multi-system, or
  ambiguous; when the user asks to capture/spec/elicit requirements; or
  when light file-github-issue intake is not enough. Prefer
  file-github-issue alone for small clear one-shot asks.

  Examples:
    - "add a transfer window" → deep interview → pack → confirm → container+subs
    - vague multi-screen feature → agent routes here instead of light filing
    - "capture requirements for X" → this skill end-to-end
---

# Capture requirements

One **feature theme** per run with the **product owner in chat**. Deliverable:
confirmed requirement pack + GitHub **container issue** and **sub-issues**
(or one issue if a single shippable slice). Do **not** implement, open a PR,
or edit the wiki here.

Filing mechanics → [`file-github-issue`](../file-github-issue/SKILL.md).
Ambiguous design proposals awaiting accept → may file `question` (then
[`clarify-github-issue`](../clarify-github-issue/SKILL.md)).

## Sources

| Source | Role |
|--------|------|
| Owner chat | Intent; confirm pack + wiki note |
| [Wiki Simulation rules](https://github.com/waigore/footballsim/wiki) | Alignment / silence / conflict |
| [`docs/requirements.md`](../../../docs/requirements.md) | Pillars / REQ-* |
| [`docs/rubric.md`](../../../docs/rubric.md) | RUB-* when useful |
| [`AGENTS.md`](../../../AGENTS.md) | Layout / sim-vs-UI conventions |
| Codebase (skim) | Propose components/sequences; flag conflicts |
| [`references/requirement-pack.md`](references/requirement-pack.md) | Capture shape shown to owner |
| [`references/container-template.md`](references/container-template.md) | Parent issue body |
| [`references/filing.md`](references/filing.md) | Split + sub-issue link |
| Feature/bug templates | Via file-github-issue `references/` |
| [`../_shared/plain-english.md`](../_shared/plain-english.md) | Human-facing wording |

**Not this skill:** bugs → file-github-issue. Wiki-only ambiguity hunt →
elucidate-design. Implementing `todo` → resolve-issue.

## Route: this vs file-github-issue

| Signal | Skill |
|--------|-------|
| Small, clear, one behavior | [`file-github-issue`](../file-github-issue/SKILL.md) |
| Multi-system, UX+sim, schema, budgets, or fuzzy scope | **This skill** |
| Unsure on a **feature** | Prefer **this skill** |

Agent decides. Do not double-file the same ask.

## Dimensions (preferred order)

Each point should mostly engender the next. Prefer this order; **judgement**
on depth and sequencing (skip ahead or loop back when the owner jumps).

1. **Functional** — required behavior
2. **Non-functional** — game/sim budgets (tick/frame cost, UI responsiveness,
   save/load, desktop+mobile playability)—not service SLAs
3. **UX** — how behavior shows in UI; how critical streamlined UX is
4. **Architectural** — components, who talks to whom, sequences, where data
   lives; **capture owner intent**, **propose** sequences from the codebase,
   **flag** conflicts with existing architecture
5. **Algorithmic / schematic** — formulas, calculations, data schema

Unaffected dimension → short **“not affected”** remark; do not invent detail.
Gaps or inconsistencies → flag and clarify with the owner before filing.

## Labels (after capture)

| Ambiguity | Labels |
|-----------|--------|
| Low — ready to implement | `todo` + `enhancement` (file-github-issue) |
| High — design still open | `question` only (clarify later) |

Same label set on container and its subs unless a sub is clearly wiki-design-only
(`question`) while others are ready (`todo`+`enhancement`)—prefer one mode for
the whole set when practical.

Ensure labels exist (same `gh label create` pattern as file-github-issue /
elucidate-design).

## Workflow

```text
- [ ] 1. Intake + route
- [ ] 2. Duplicate search → confirm if matches
- [ ] 3. Interview (dimensions; flag gaps)
- [ ] 4. Draft pack (+ proposed architecture)
- [ ] 5. Owner confirm (required)
- [ ] 6. Wiki gate (default expect follow-up for new features)
- [ ] 7. Choose labels by ambiguity
- [ ] 8. File container + subs via file-github-issue patterns → link → stop
```

### 1. Intake + route

Take the feature ask. If light → hand off to file-github-issue and stop.
Else continue here. Ask only for missing functional seed if the ask is empty.

### 2. Duplicate search

Same as file-github-issue: search open issues; if plausible matches, **stop and
confirm** (skip / comment / file anyway). Do not file until they choose.

### 3. Interview

Walk dimensions with judgement. Prefer cascade; probe only what matters.
When proposing architecture, skim relevant `scripts/`, `scenes/`, `autoload/`
enough to name real modules—no deep refactor research.

### 4. Draft pack

Build the pack from [`references/requirement-pack.md`](references/requirement-pack.md).
Include open questions and conflict flags.

### 5. Owner confirm (required)

Show the pack in chat. Get explicit OK (and answers to remaining blockers)
**before** creating issues. Unlike file-github-issue, do **not** submit without
this confirm.

### 6. Wiki gate

For **new** features/requirements, wiki follow-up is the **default expectation**
(rules silent or need extension). Still **confirm** with the owner before noting
it. If they decline, omit `## Wiki follow-up` but still file. Conflicts with
written rules: call out and confirm note / later elucidate. Do not edit the wiki.

### 7–8. File

Follow [`references/filing.md`](references/filing.md):

- **≥2 workstreams** → container + sub-issues; link with `addSubIssue`
- **1 shippable slice** → one issue via file-github-issue (no empty container)
- Reuse file-github-issue templates, plain English, and submit commands
- Reply with all URLs; stop

## Rules

- Owner confirm before any `gh issue create` from this skill.
- Propose architecture; never invent “decided” schema/formulas the owner did not accept.
- Plain English above any `## For agents` block.
- Prefer `gh`; label every filed issue.
- No implementation, no PR, no wiki edits in this skill.
