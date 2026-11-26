# UX VLM gate

Shared checker for PR and tier-2 visual QA. Rubrics SoT:
[UX — Visual rubrics](https://github.com/waigore/footballsim/wiki/ux-visual-rubrics).

## Files

| Path | Role |
|------|------|
| `rubrics.yaml` | Pass/fail criteria (mirrors wiki) |
| `screens.yaml` | Screen id → kind, required CTA, scripts, desktop `baseline_url` |
| `catalogue.py` | Load + validate YAML; map paths; parse PR table |
| `check_screens.py` | Grade images via Cheaper Inference vision; enforce CTA |
| `pr_gate.py` | PR: UI diff → screenshots → checker |

## Primary CTA per screen

`screens.yaml` declares a `kind` for every screen:

| Kind | CTA rule |
|------|----------|
| `flow` | **Must** declare `primary_cta` (`labels`, optional `side`). The gate fails when that exact label is not read in the shot, or sits on the wrong side. |
| `browse` | BACK (or an equally clear leave door) is an acceptable primary; no hard label check. |
| `overlay` | Live chrome over play; no CONTINUE mandate. |

```yaml
  - id: league-hub
    kind: flow
    primary_cta:
      labels: [CONTINUE]
      side: right
```

`catalogue.py` rejects a catalogue where a flow screen has no `primary_cta`, a
non-flow screen declares one, or a label/side is malformed — a flow screen can
never fall back to the old soft "obvious primary door" wording.

`check_screens.py` injects the screen's requirement into the VLM prompt, asks
the grader to report the label it read (`cta_label`) and where it sits
(`cta_side`), then fails the `cta` rubric when that read label does not match.

## Env

| Variable | Default |
|----------|---------|
| `CHEAPER_INFERENCE_API_KEY` | (required; alias `CHEAPERINFERENCE_API_KEY`) |
| `CHEAPER_INFERENCE_BASE_URL` | `https://api.cheaperinference.com/v1` |
| `CHEAPER_INFERENCE_MODEL` | `qwen3.5-flash` |

Thinking/reasoning is disabled on the chat request.

## Invoke

```bash
pip install -r tools/ux_vlm/requirements.txt

# Unit checks (catalogue + CTA map + grader wiring)
python tools/ux_vlm/test_catalogue.py

# PR mode (items from PR body, via pr_gate)
python tools/ux_vlm/pr_gate.py --base origin/main --pr-body @body.md

# Explicit items
python tools/ux_vlm/check_screens.py --mode items --items-json '[{"screen_id":"main-menu","image_url":"https://…"}]'

# Tier-2 full catalogue
python tools/ux_vlm/check_screens.py --mode catalogue --fail-file /tmp/ux_fail.json

# Wiring only
python tools/ux_vlm/check_screens.py --mode catalogue --dry-run
```

PR budget: ≤10 images, checker aimed at ≤1 min. Tier-2: full catalogue ≤10 min.
