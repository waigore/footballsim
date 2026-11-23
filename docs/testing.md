# Testing

Unit/integration tests and headless e2e smoke. Two CI tiers; budgets are hard gates.

## Tiers

| Tier | When | Command / gate | Budget |
|------|------|----------------|--------|
| **1 (PR)** | Code/test path PRs | Impacted suites + **80% patch** coverage; e2e smoke | tests **≤ 5 min**; smoke **≤ 4 min** |
| **2 (trunk)** | Every **8 hours** on `main` (+ manual) | Full suite (sharded when large); overall **80%** coverage; Poisson census | shard **≤ 45 min**; gate **≤ 10 min** |

Tier 1 is the merge gate (`tests` / `e2e-smoke`). Tier 2 does not block PRs; failures open a sticky `ci-tier2` issue the **fix-tests** agent closes.

## Impact map

Tier 1 selects suites via [`tests/impact_map.toml`](../tests/impact_map.toml) + `tools/select_impacted_tests.py`. Unmapped in-scope paths fail. Tier 2 runs the full suite and `--check-complete`.

## E2E smoke (tier 1)

Smoke proves the sim alone can play a match. [`tools/e2e_smoke.gd`](../tools/e2e_smoke.gd) builds one
**sim-only** Manchester United v Manchester City match (seed **1000**), plays both halves to full
time, prints the score and exits — no pitch, HUD, team select or highlights. Any scoreline passes,
**0-0 included**. Deep rules stay in `tests/`. Budget **≤4 min**; the script exits as soon as full
time (or added time) is reached and fails fast if the match stalls.

## Poisson-agreement census (tier 2)

`playtests/census` plays full physics matches on fixed seed grids for the anchors (MCI v BUR, MCI v MCI) and hard-gates two things: goal variance vs the Poisson λ (`|var − λ|/λ ≤ 10%`, both sides) and a **≤ 60 s** wall-clock budget per match (a 60 Hz GDScript tick bottoms out near 30 s; tighten with a native hot loop later). Tier-2 only — the impact map sends census edits to the fast poisson suite on PRs. Grid size, seeds and the latest measured numbers live on the wiki poisson-model page.

## Local

```bash
python tools/select_impacted_tests.py --check-complete
python tools/select_impacted_tests.py --base origin/main --print-command
gd-tools test --coverage --timeout 240 --parallel 4 $(
  python tools/select_impacted_tests.py --base origin/main | grep -v '^ALL$' | grep -v '^NONE$'
)
gd-tools coverage diff --patch --base origin/main --patch-fail-under 80
godot --headless --path . --script res://tools/e2e_smoke.gd
```

## Coverage scope

Tier 2 measures **shipped game code**: `scripts/`, `scenes/`, `ui/`, `autoload/`.

| Excluded | Why |
|----------|-----|
| `tools/` | Dev probes, reporting scripts, old suite copies — nothing a player runs (`gd-tools.toml` `coverage.exclude`) |
| `scripts/view/pitch_view.gd` | Stadium painting: only runs when a frame renders, and the suite is headless (`# gd-tools: no cover`) |

Two gd-tools instrumentation rules shape the source:

- A `match` arm with a statement body must use block form (`"ST":` then an indented `return` on its own line). Inline arms (`"ST": return 1.0`) cannot be tracked and the file drops out of the plan.
- A ternary inside a `:=` declaration must carry an explicit type (`var x: float = a if c else b`); the tracker wrapper hides the inferred type.

Check the plan locally with `gd-tools coverage show --min 80`; it reports files it could not instrument.

## Speed rules

- Prefer pure fixtures over full UI mounts.
- Cache shared state in `before_all`; one Godot boot per theme.
- Keep PR suites under 5 minutes; profile with `--durations`.

## Related

- PR checks: [`pull-requests.md`](pull-requests.md)
- Coverage / suite tooling: gd-tools when vendored
