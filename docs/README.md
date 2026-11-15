# Docs

Index for product and process docs. Agent entry: [`../AGENTS.md`](../AGENTS.md).

Every Markdown file at the repo root and under `docs/` must stay **≤ 500 words** (fenced code excluded). Lint: `python tools/lint_docs_words.py` (CI job `docs-lint`).

## Product

| Doc | Purpose |
|-----|---------|
| [Simulation rules (wiki)](https://github.com/waigore/footballsim/wiki) | Mechanics source of truth |
| [requirements.md](requirements.md) | Pillars P1–P5 (`REQ-*`) |
| [rubric.md](rubric.md) | Evaluation gate (`RUB-*`) |
| [deferred.md](deferred.md) | Deferred gaps ranked by impact |

## Process

| Doc | Purpose |
|-----|---------|
| [pull-requests.md](pull-requests.md) | PR rules: `gh`, required checks, merge |
| [testing.md](testing.md) | Test + e2e budgets (≤5 min / ≤2 min) |
| [android-debug.md](android-debug.md) | Debug APK via PR into `android-debug` |
| [skills.md](skills.md) | Project skills; Cursor/OpenCode/Grok facades; Hermes via `.agents` |
