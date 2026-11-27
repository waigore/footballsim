# Pull requests

Base rules for opening and landing PRs (humans and agents).

**Tooling:** [`gh`](https://cli.github.com/) for all GitHub PR ops.  
**Gate docs:** map rules changes to [`requirements.md`](requirements.md) / [`rubric.md`](rubric.md).

## Principles

1. **Small and focused** — one concern; stack PRs over mixed refactors + features.
2. **Use `gh`** — create, inspect, merge via CLI.
3. **Respect checks** — required status checks are the merge gate; never bypass or force-merge.
4. **Prefer auto-merge** — enable squash auto-merge when ready; let GitHub land when green.

## Required checks (main)

**Protect main** requires these (strict: branch up to date with `main`):

| Check | Workflow | Meaning |
|-------|----------|---------|
| `tests` | [CI](../.github/workflows/ci.yml) | Tier 1: impacted suites + 80% patch; no-op if no code / no project; `main` push skips |
| `build` | [CI](../.github/workflows/ci.yml) | Headless import/compile; else no-op |
| `e2e-smoke` | [CI](../.github/workflows/ci.yml) | Needs `build`; smoke when present; else no-op |
| `docs-lint` | [CI](../.github/workflows/ci.yml) | Docs ≤ 500 words — always |
| `arch-lint` | [CI](../.github/workflows/ci.yml) | P3 + static P1 (2D/icons/hover) — always |
| `skills-isolation` | [CI](../.github/workflows/ci.yml) | PR-only: fail if code **and** skills both change |
| `ai-bench-report` | [CI](../.github/workflows/ci.yml) | PR AI paths: hills report ≥ baseline; else no-op |
| `ux-vlm` | [CI](../.github/workflows/ci.yml) | UI paths: desktop wiki shots in body; VLM rubrics; no-op if no UI |

Code paths: `scenes/`, `scripts/`, `ui/`, `autoload/`, `tests/`, `addons/`, `project.godot`, `icon.svg` (+ `tools/e2e_smoke.gd`, `tools/smoke/**`). Skills: `.agents/skills/`, `.cursor/skills/`, `.opencode/skill/`, `.grok/skills/`. Docs-only / skills-only OK.

**UI paths (`ux-vlm`):** `scenes/`, `ui/`, `scripts/ui/`, `assets/ui/`, `fonts/`. On change, one desktop wiki URL per affected screen (max 10):

```markdown
## UX screenshots
| screen | url |
|--------|-----|
| league-hub | https://raw.githubusercontent.com/wiki/waigore/footballsim/evidence/images/… |
```

Missing links or VLM fail → fail (no sticky). Rubrics: [wiki](https://github.com/waigore/footballsim/wiki/ux-visual-rubrics); YAML `tools/ux_vlm/`.

**Tier 2** ([ci-tier2](../.github/workflows/tier2.yml)): every **8h** — full suite + 90% + catalogue UX VLM. Not a PR check. Sticky `ci-tier2`+`todo` → fix-tests.

Budgets ([testing.md](testing.md)): `tests` ≤5 min; smoke ≤4 min; `ux-vlm` ≤1 min/10. Squash only; delete branches; auto-merge on.

### Respecting checks

- Confirm with `gh pr checks` / `gh pr view --json statusCheckRollup,mergeStateStatus`.
- Do not merge while required checks fail, pend, or skip incompletely.
- Do not use `--admin`, overrides, or rule disablement for a red PR.
- Fix forward on the PR branch; don’t close/reopen to clear failures.
- Keep the branch current with `main` under strict status policy.

## Workflow with `gh`

**Before:** up-to-date `main`; branch `feat/…` / `fix/…` / `docs/…`; run tests + docs/arch lints when relevant; clean `git status`.

**Create:**

```bash
git push -u origin HEAD
gh pr create --title "…" --body "$(cat <<'EOF'
## Summary
- …

## Test plan
- [ ] …

EOF
)"
```

Prefer draft until reviewable. Title/body say **why**; cite `REQ-*`/`RUB-*` when relevant.

**While open:** `gh pr checks` · `gh pr view` · `gh pr comment`. Push fixes; avoid force-push unless rewriting a private draft.

**Merge:** prefer squash auto-merge ([Automerge](../.github/workflows/automerge.yml)):

```bash
gh pr merge --squash --auto --delete-branch
```

Never merge to `main` outside a PR that satisfied the ruleset checks.

## Quick checklist

- [ ] Maps to a pillar (`P1`–`P5`) or is docs/tooling-only
- [ ] Opened/updated with `gh`
- [ ] Checks green (`skills-isolation`, `ai-bench-report`, `ux-vlm` as needed)
- [ ] Branch current with `main`; squash / `--auto` — no bypass
