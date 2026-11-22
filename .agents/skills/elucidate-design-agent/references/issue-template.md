# Question issue template (elucidate design)

**Title:** plain English, e.g. `Clarify <theme>: <short ambiguity>`

**Labels:** `question` only

```markdown
## Summary
<1–2 sentences: what is unclear and why it matters to the player>

## Ambiguity
<what is unclear, contradictory, or missing — cite wiki pages/sections in plain words>

## Proposed design
<precise rule or AI behavior a product owner can accept or reject>

## Why this reading
<player-facing rationale; prefer clarity and agency. Keep short.>

## Required work (after accept)
- [ ] Add Design Record page(s) and prepend Design Records index + Design Changelog (follow design-record shape)
- [ ] Update wiki Simulation rules / AI pages listed below so they match the accepted design
- [ ] Wiki pages to edit: <page titles>
- [ ] Code / tests: <systems to change, or “none — wiki only”>
- [ ] Player-visible check: <one sentence acceptance>

## For agents
- Theme: <one theme>
- Pillars: P5 (and others if touched)
- REQ / RUB (if known): <ids or none>
- Design-record shape: `.agents/skills/elucidate-design-agent/references/design-record.md`
- Wiki update: `.agents/skills/elucidate-design-agent/references/wiki-update.md`
- Related open issues checked: <none or #N…>
```

Do not allocate a live `DR-…` ID in the proposal (resolver allocates on accept/implement). Describe the intended record title/theme only if helpful.
