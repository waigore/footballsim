# UX VLM gate

Shared checker for PR and tier-2 visual QA. Rubrics SoT:
[UX — Visual rubrics](https://github.com/waigore/footballsim/wiki/ux-visual-rubrics).

## Files

| Path | Role |
|------|------|
| `rubrics.yaml` | Pass/fail criteria (mirrors wiki) |
| `screens.yaml` | Screen id → scripts + desktop `baseline_url` |
| `catalogue.py` | Load YAML; map paths; parse PR table |
| `check_screens.py` | Grade images via Cheaper Inference vision |
| `pr_gate.py` | PR: UI diff → screenshots → checker |

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
