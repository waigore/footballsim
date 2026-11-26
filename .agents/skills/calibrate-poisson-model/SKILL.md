---
name: calibrate-poisson-model
description: |-
  Run the Poisson calibration loop with the repo's own tools: audit λ, sample
  seasons against the last-10 PL scoring envelope, accept a candidate only when
  the scoring bands **and** the pre-tune home/draw/away mix both pass, then land
  the constants with tests. Use when AUTO seasons overscore or blow out, when a
  scoreline question is really a λ question, or when the envelope data or the
  model constants need a change.
---

# Calibrate the Poisson model

One loop, one candidate, one gate. The model's λ is fitted to football, not to the
physics engine, and the gate is a command — not an opinion.

## Rules

- **Owner constraint outranks the bands.** Keep the sampled **home / draw / away**
  mix within the gate's drift tolerance of the frozen pre-tune baseline. Dampen
  scorelines and extreme blowouts only; never "fix" scoring by reshaping 1X2.
- **Prefer baselines and elasticity** over ρ. Touch `rho` only when draws drift
  outside tolerance *after* the score dampening — and say so in the PR.
- **One source for the envelope.** `data/pl_scoring_envelope.json` is the SoT for
  the bands and the pre-tune baseline. Do not hand-tune a band to make a candidate
  pass; if the real-world data changes, re-collect it and say which seasons.
- **The physics engine is not part of this loop.** It is calibrated toward λ, in a
  separate pass with its own census budget. Note the follow-up; never "fix" the
  miss by moving engine constants here.
- **Skills ship separately.** `skills-isolation` fails a PR that touches game/test
  code *and* skill trees. The constants/tests PR and this skill's PR are two PRs.
- **No new abstraction for the loop.** Reuse `tools/poisson_calibration.gd`
  (sampler + gates) and `tools/poisson_calibrate.gd` (the report).

## Workflow

1. **Baseline.** On a fresh branch from `main`, run the report unmodified and keep
   the output. The envelope file already carries the frozen pre-tune mix; the run
   tells you where the current model actually sits.

   ```bash
   godot --headless --path . --script res://tools/poisson_calibrate.gd
   ```

2. **Read the failures.** The report has two halves: a λ audit for fixed pairings
   and the sampled seasons. A failure is one of:
   - *Goals, champion GF or blowout band* → lower `home_xg` / `away_xg` together,
     then `attack_elasticity` / `defence_elasticity` if margins are still wide.
   - *Draw share above the drift gate* → the score dampening lifted draws; raise
     `rho` (it currently trims 0-0 / 1-1). Keep the change small — a few
     hundredths — and re-read all three shares, not just draws.
   - *Home/away share outside the gate while draws pass* → the candidate changed
     the venue split; prefer symmetric baselines over asymmetric ones.

3. **Sweep without editing code.** Overrides read the same calibration table the
   model uses; each run is ~0.6 s at the default 20 seasons.

   ```bash
   godot --headless --path . --script res://tools/poisson_calibrate.gd -- \
     20 7000 home_xg=1.35 away_xg=1.16 attack_elasticity=0.98 \
     defence_elasticity=0.98 rho=0.08
   ```

   Vary one family at a time (totals → elasticity → ρ) and keep the candidate that
   has margin on every band, not one that just scrapes a single seed.

4. **Prove stability.** Re-run at a second seed and at 10/40 seasons. A candidate
   that only passes at seed 7000 is a coincidence:

   ```bash
   godot --headless --path . --script res://tools/poisson_calibrate.gd -- 20 12345 <overrides>
   ```

5. **Land the winner.** Only now edit `scripts/sim/poisson_model.gd` — the
   constants and `DEFAULT_CALIBRATION` together — and update the RHO comment if
   its direction changed. Update `tests/test_poisson_model.gd` expectations, and
   keep `test_calibration_sits_inside_the_pl_scoring_envelope` as the gate.

6. **Test and lint.**

   ```bash
   HOME=/tmp/gdhome gd-tools test tests/test_poisson_model.gd
   python tools/lint_docs_words.py
   python tools/lint_arch.py
   ```

   If the run touched an engine comment, run that engine's suites too
   (`python tools/select_impacted_tests.py --base origin/main --print-command`).

7. **PR.** Constants + tests + envelope/tool changes in one PR that cites the
   issue; quote the before/after table from the report. Note the physics census
   follow-up. Skill changes go in a separate skills-only PR.

8. **Wiki.** Update `poisson-model`: the formula numbers, the ratings table, the
   ρ direction and the envelope table. A design decision (new SoT, changed ρ sign)
   needs a Design Record; the existing one is DR-20261125-19.

## Reading the report

- `λ` line — expected goals per game from the chance model; sampled goals sit
  slightly above it because sampling is discrete.
- `λ audit` — the pairings the wiki table quotes; copy these numbers into the page.
- Bands — pass means inside the ten real seasons' range, not "close enough".
- Drift rows — absolute difference against the frozen pre-tune mix, in points.

## Output

A candidate that passes all gates at more than one seed, landed as a small PR
(constants + tests + envelope), a wiki page that quotes the same numbers, and an
explicit note that the engine's census follows separately.
