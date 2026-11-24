# UX playtest issue bodies

Reuse labels and plain English from [`file-github-issue`](../../file-github-issue/SKILL.md).
Skip the interview and human confirm steps — the playtest already observed the problem.

## Bug / inconsistency

**Title:** `[Bug] <short UX symptom>`  
**Labels:** `todo`, `bug`

```markdown
## Summary
<1–2 sentences>

## Platform
- OS / build: desktop <Windows | macOS | Linux>
- How run: editor / desktop launch via tools/launch_game.sh
- Version / commit: <git SHA>

## Steps to reproduce
1. …
2. …

## Expected
<what should happen>

## Actual
<what happened>

## Evidence
- Playtest report: https://github.com/waigore/footballsim/wiki/evidence/ux-playtest-YYYYMMDD
- Finding: F<n> on that page

## Analysis
- Likely locus: <scene/script/area or “unknown”>
- Wiki alignment: <matches rules | conflicts | rules silent | N/A (pure UX)>
- Severity: <blocker | major | minor | polish>
- Notes: <repro confidence>

## Acceptance
- [ ] UX issue fixed or intentionally accepted
```

## Enhancement

**Title:** `[Feature] <short UX improvement>`  
**Labels:** `todo`, `enhancement`

```markdown
## Summary
<what should improve>

## Reason
<player friction seen in playtest>

## Evidence
- Playtest report: https://github.com/waigore/footballsim/wiki/evidence/ux-playtest-YYYYMMDD
- Finding: F<n> on that page

## Impact analysis
- Pillars touched: P1 / P5 (and others if clear)
- Wiki: <silent | already specified — link>
- Scope guess: <small | medium | large>
- Desktop + mobile: desktop observed; note if mobile likely affected
- Dependencies / risks: <…>

## Proposal
<concrete UX change>

## Acceptance
- [ ] Improvement playable on desktop (and mobile if in scope)
```
