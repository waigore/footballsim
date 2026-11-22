# Design record + changelog shapes

Used by [`resolve-issue-agent`](../../resolve-issue-agent/SKILL.md) when an accepted design issue requires records. Elucidate only **requires** this work on the issue; it does not allocate IDs or write wiki pages.

Wiki SoT: [Design Records](https://github.com/waigore/footballsim/wiki/design-records), [Design Changelog](https://github.com/waigore/footballsim/wiki/design-changelog).

Human-facing wiki text: plain English ([`../../_shared/plain-english.md`](../../_shared/plain-english.md)). Keep requirement IDs in a short agents note on the record if needed.

## Allocate an ID

1. Use **UTC** date `YYYYMMDD`.
2. List existing `DR-YYYYMMDD-*` / `dr-YYYYMMDD-*` pages for that day.
3. Next `NN` = max existing + 1, zero-padded to **2** digits (`01`…`99`). If ≥100 that day, use 3 digits.
4. ID = `DR-YYYYMMDD-NN`. Page slug = `dr-YYYYMMDD-NN`.

IDs sort chronologically as plain text. Never reuse or renumber.

## New record page (`dr-YYYYMMDD-NN.md`)

```markdown
# DR-YYYYMMDD-NN — Short title

| Field | Value |
|-------|-------|
| **Status** | accepted |
| **Date** | YYYY-MM-DD (UTC) |
| **Theme** | <one theme> |
| **Supersedes** | none |
| **Issue** | #<N> |

## Sources

- Unclear: <page / section in plain words> …
- Checked, already clear / not resolving this: <page> …

## Ambiguity

<what was unclear, contradictory, or missing>

## Change

<precise rule or AI behavior>

## Reasoning

Why this reading helps the player (agency / clarity). Other product pillars: <brief or none>.

## Impact

- Wiki: <pages edited>
- Code: <systems / none>
- Player-visible: <one sentence>

## For agents

- REQ / RUB (if any): …
- GitHub issue: #N
```

## Index + changelog

On `design-records.md`, **prepend** a table row (newest first).

On `design-changelog.md`, **prepend**:

```markdown
## DR-YYYYMMDD-NN — Short title
- **Change:** one sentence (plain English)
- **Impact:** wiki pages + systems touched
- **Record:** [DR-YYYYMMDD-NN](dr-YYYYMMDD-NN)
```

Remove the `_(No entries yet.)_` / `_(none yet)_` placeholders on first real entry.
