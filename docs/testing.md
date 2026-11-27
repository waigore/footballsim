# Testing

Tests and headless e2e smoke; two tiers, hard budgets.

## Tiers

| Tier | When | Command / gate | Budget |
|------|------|----------------|--------|
| **1 (PR)** | Code/test path PRs | Impacted suites + **80% patch**; e2e smoke; UX VLM on UI paths | tests **≤5 min**; smoke **≤4 min**; ux-vlm **≤1 min**/10 |
| **2 (trunk)** | Every **8 hours** on `main` (+ manual) | Full suite; **90%**; Poisson census; catalogue UX VLM | shard **≤45 min**; UX **≤10 min** |

Tier 1 merge gate: `tests` / `e2e-smoke` / `ux-vlm`. Tier 2 is not a PR gate; sticky `ci-tier2`+`todo`.

## Impact map

Tier 1 selects suites via [`tests/impact_map.toml`](../tests/impact_map.toml) + `tools/select_impacted_tests.py`; unmapped in-scope paths fail. Tier 2 runs the full suite, `--check-complete`.

## E2E smoke (tier 1)

Two legs, one `e2e-smoke` job (**≤4 min**); each fails fast on its own budget.

- [`tools/e2e_smoke.gd`](../tools/e2e_smoke.gd) — one **sim-only** Manchester United v Manchester City
  match (seed **1000**) to full time: no pitch, HUD, team select or highlights. Any scoreline passes,
  **0-0 included**.
- [`tools/smoke/all_leagues.gd`](../tools/smoke/all_leagues.gd) — a generated season with **every seed
  competition** (seed **1200**), all fixtures Auto. Continues run to **≥21 calendar days** and past
  every league's opener; every fixture due in that window must be played in every selected league.
  Budget **≤120 s**.

Deep rules stay in `tests/`.

## Poisson-agreement census (tier 2)

`playtests/census` plays fixed-seed full matches (MCI v IPS, MCI v MCI) and hard-gates goal dispersion vs Poisson λ: **10% target** plus a two-sided **95% allowance** at the grid's n (`CensusLib.variance_tolerance`; ≈±67% at n=32), **≤120 s** per match (40–80 s on CI). `.github/workflows/census.yml` shards the grid; `test_census_aggregate.gd` pools and asserts. Tier 2 only; census edits run the poisson suite on PRs. Numbers: wiki poisson-model.

```bash
godot --headless --path . --import --quit
CENSUS_SHARDS=1 gd-tools test playtests/census/test_census_mci_bur.gd
CENSUS_SHARDS=1 gd-tools test playtests/census/test_census_mci_mci.gd
CENSUS_REQUIRE=1 gd-tools test playtests/census/test_census_aggregate.gd
```

## Local

```bash
python tools/select_impacted_tests.py --check-complete
python tools/select_impacted_tests.py --base origin/main --print-command
gd-tools test --coverage --timeout 240 --parallel 4 $(
  python tools/select_impacted_tests.py --base origin/main | grep -v '^ALL$' | grep -v '^NONE$'
)
gd-tools coverage diff --patch --base origin/main --patch-fail-under 80
godot --headless --path . --script res://tools/e2e_smoke.gd
godot --headless --path . --script res://tools/smoke/all_leagues.gd
```

## Coverage scope

Tier 2 measures shipped code: `scripts/`, `scenes/`, `ui/`, `autoload/`.

| Excluded | Why |
|----------|-----|
| `tools/` | Dev probes; nothing a player runs (`gd-tools.toml` `coverage.exclude`) |
| `scripts/view/pitch_view.gd`, league sheet paint | Rendered-frame paint; the suite is headless (`# gd-tools: no cover`). League layout stays measured |

gd-tools instrumentation rules:

- A `match` arm with a statement body must use block form (`"ST":` then an indented `return` on its own line). Inline arms (`"ST": return 1.0`) cannot be tracked and the file drops out of the plan.
- A ternary inside a `:=` declaration must carry an explicit type (`var x: float = a if c else b`); the tracker wrapper hides the inferred type.

`gd-tools coverage show --min 90` lists files it could not instrument.

## Speed rules

- Prefer pure fixtures over full UI mounts.
- Cache shared state in `before_all`; one Godot boot per theme.
- Reuse models: the Poisson gate builds one `PoissonModel` per fixture, not per season (`PoissonCalibration.models_for`).
- Point save/cache dirs at `TestScratch`: every checkout shares one Godot user dir, so fixed names let
  concurrent runs delete each other's SQLite.
- Keep PR suites under 5 minutes; profile with `--durations`.

## Related

- PR checks: [`pull-requests.md`](pull-requests.md)
- Coverage / suite tooling: gd-tools
