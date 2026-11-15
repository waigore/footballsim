# Testing

Unit/integration tests and headless e2e smoke. Two CI tiers; budgets are hard gates once `project.godot` exists. Until then, Godot CI jobs no-op.

## Tiers

| Tier | When | Command / gate | Budget |
|------|------|----------------|--------|
| **1 (PR)** | Code/test path PRs | Impacted suites + **80% patch** coverage; e2e smoke | tests **≤ 5 min**; smoke **≤ 2 min** |
| **2 (trunk)** | Every **8 hours** on `main` (+ manual) | Full suite (sharded when large); overall **80%** coverage | shard **≤ 20 min**; gate **≤ 10 min** |

Tier 1 is the merge gate (`tests` / `e2e-smoke`). Tier 2 does not block PRs; failures open a sticky `ci-tier2` issue the **fix-tests** agent closes.

## Bootstrap

No `project.godot` yet: `tests` / `build` / `e2e-smoke` / tier 2 pass as no-ops. Add `gd-tools.toml`, `tests/`, impact map, and `tools/e2e_smoke.gd` with the Godot scaffold; then wire real suite selection (`tools/select_impacted_tests.py`).

## E2E smoke (tier 1)

Smoke boots the app and exercises a short critical path. Deep rules stay in `tests/`. Budget **≤2 min**.

## Local (when project exists)

```bash
gd-tools test --coverage --timeout 240 --parallel 4
gd-tools coverage diff --patch --base origin/main --patch-fail-under 80
godot --headless --path . --script res://tools/e2e_smoke.gd
```

## Speed rules

- Prefer pure fixtures over full UI mounts.
- Cache shared state in `before_all`; one Godot boot per theme.
- Keep PR suites under 5 minutes; profile with `--durations`.

## Related

- PR checks: [`pull-requests.md`](pull-requests.md)
- Coverage / suite tooling: gd-tools when vendored
