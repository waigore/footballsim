#!/usr/bin/env python3
"""Grade UI screenshots against UX visual rubrics via Cheaper Inference vision.

Modes:
  --mode items     Grade explicit {screen_id, image_url} list (PR gate)
  --mode catalogue Grade every catalogue baseline_url (tier-2)

Env:
  CHEAPER_INFERENCE_API_KEY   (or CHEAPERINFERENCE_API_KEY)
  CHEAPER_INFERENCE_BASE_URL  default https://api.cheaperinference.com/v1
  CHEAPER_INFERENCE_MODEL     default qwen3.5-flash
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from catalogue import (  # noqa: E402
    DEFAULT_RUBRICS,
    DEFAULT_SCREENS,
    cta_labels,
    cta_requirement,
    cta_side,
    label_seen,
    load_catalogue,
    screen_by_id,
)


def _ssl_context() -> ssl.SSLContext:
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except Exception:  # noqa: BLE001 — fall back to system CAs
        return ssl.create_default_context()

DEFAULT_BASE_URL = "https://api.cheaperinference.com/v1"
DEFAULT_MODEL = "qwen3.5-flash"
MAX_PR_IMAGES = 11
# Six rubric rows with short reasons fit under 400; busy screens (match-hud)
# still truncate there and fall through to "unparseable verdict".
DEFAULT_MAX_TOKENS = 1024
GRADE_RETRIES = 2


def _api_key() -> str:
    key = (
        os.environ.get("CHEAPER_INFERENCE_API_KEY")
        or os.environ.get("CHEAPERINFERENCE_API_KEY")
        or ""
    ).strip()
    if not key:
        raise SystemExit(
            "Missing CHEAPER_INFERENCE_API_KEY (or CHEAPERINFERENCE_API_KEY)."
        )
    return key


def _base_url() -> str:
    return (
        os.environ.get("CHEAPER_INFERENCE_BASE_URL") or DEFAULT_BASE_URL
    ).rstrip("/")


def _model() -> str:
    return os.environ.get("CHEAPER_INFERENCE_MODEL") or DEFAULT_MODEL


def _download(url: str, timeout: float = 20.0) -> tuple[bytes, str]:
    req = urllib.request.Request(url, headers={"User-Agent": "footballsim-ux-vlm"})
    with urllib.request.urlopen(req, timeout=timeout, context=_ssl_context()) as resp:
        data = resp.read()
        ctype = (resp.headers.get("Content-Type") or "image/png").split(";")[0]
    if not data:
        raise RuntimeError(f"empty image at {url}")
    return data, ctype


def _data_url(data: bytes, ctype: str) -> str:
    b64 = base64.standard_b64encode(data).decode("ascii")
    return f"data:{ctype};base64,{b64}"


def re_strip_fence(text: str) -> str:
    lines = text.strip().splitlines()
    if lines and lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].startswith("```"):
        lines = lines[:-1]
    return "\n".join(lines).strip()


def _chat(
    messages: list[dict[str, Any]],
    timeout: float = 45.0,
    *,
    max_tokens: int = DEFAULT_MAX_TOKENS,
) -> str:
    payload: dict[str, Any] = {
        "model": _model(),
        "messages": messages,
        "temperature": 0,
        "max_tokens": max_tokens,
        # Thinking / reasoning off for Flash-class graders.
        "reasoning": {"effort": "none"},
        "enable_thinking": False,
    }
    body = json.dumps(payload).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {_api_key()}",
        "Content-Type": "application/json",
        "User-Agent": "footballsim-ux-vlm",
    }

    def _post(data: bytes) -> dict[str, Any]:
        req = urllib.request.Request(
            f"{_base_url()}/chat/completions",
            data=data,
            headers=headers,
            method="POST",
        )
        with urllib.request.urlopen(
            req, timeout=timeout, context=_ssl_context()
        ) as resp:
            return json.loads(resp.read().decode("utf-8"))

    try:
        raw = _post(body)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        if exc.code == 400 and (
            "reasoning" in detail
            or "thinking" in detail
            or "enable_thinking" in detail
        ):
            payload.pop("reasoning", None)
            payload.pop("enable_thinking", None)
            raw = _post(json.dumps(payload).encode("utf-8"))
        else:
            raise RuntimeError(f"VLM HTTP {exc.code}: {detail}") from exc

    choices = raw.get("choices") or []
    if not choices:
        raise RuntimeError(f"VLM empty choices: {raw!r}")
    message = choices[0].get("message") or {}
    content = message.get("content") or ""
    if isinstance(content, list):
        content = "".join(
            part.get("text", "") if isinstance(part, dict) else str(part)
            for part in content
        )
    return str(content).strip()


def _verdict_of(obj: Any) -> tuple[bool, str] | None:
    """One verdict object → (pass, reason), or None when it is not a verdict."""
    if not isinstance(obj, dict):
        return None
    if "pass" not in obj and "passed" not in obj:
        return None
    passed = bool(obj.get("pass", obj.get("passed", False)))
    reason = str(obj.get("reason") or obj.get("explanation") or "").strip()
    return passed, reason or ("pass" if passed else "fail")


def _aggregate(results: list[Any]) -> tuple[bool, str]:
    """A results array passes only when every row passes."""
    verdicts = [v for v in (_verdict_of(row) for row in results) if v is not None]
    if not verdicts:
        return False, "unparseable verdict: empty results"
    failed = [reason for passed, reason in verdicts if not passed]
    if failed:
        return False, failed[0]
    return True, verdicts[0][1]


def _parse_verdict(text: str) -> tuple[bool, str]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re_strip_fence(cleaned)
    for opener, closer in (("{", "}"), ("[", "]")):
        start = cleaned.find(opener)
        end = cleaned.rfind(closer)
        if start < 0 or end <= start:
            continue
        try:
            parsed = json.loads(cleaned[start : end + 1])
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, list):
            return _aggregate(parsed)
        if isinstance(parsed, dict):
            if isinstance(parsed.get("results"), list):
                return _aggregate(parsed["results"])
            verdict = _verdict_of(parsed)
            if verdict is not None:
                return verdict
            for value in parsed.values():
                if isinstance(value, list):
                    return _aggregate(value)
    upper = cleaned.upper()
    if upper.startswith("PASS") or "\nPASS" in upper:
        return True, cleaned[:240]
    if upper.startswith("FAIL") or "\nFAIL" in upper:
        return False, cleaned[:240]
    return False, f"unparseable verdict: {cleaned[:240]}"


_CTA_REPORT = (
    'In the cta rubric row, also report "cta_label": the exact label text of the '
    'primary action you can read (empty string if none), and "cta_side": '
    '"left", "center", or "right" for where that control sits.'
)


def build_prompt(
    rubrics: list[dict[str, Any]], screen: dict[str, Any] | None = None
) -> str:
    """Grader prompt: shared rubrics plus this screen's required primary CTA."""
    rubric_block = "\n".join(f"- {r['id']}: {r['prompt']}" for r in rubrics)
    parts = [
        "You are a strict UI visual QA grader for a football simulation game.",
        "Judge ONLY what is visible in the screenshot against each rubric.",
        "Reply with ONE JSON object only, no markdown, shape:",
        '{"results":[{"rubric_id":"...","pass":true,"reason":"..."}, ...]}',
        "Include every rubric id below. Be conservative: fail on clear defects.",
        "Keep each reason under 20 words so the JSON stays complete.",
    ]
    if screen is not None:
        parts.append(f"Screen requirement:\n{cta_requirement(screen)}")
        if cta_labels(screen):
            parts.append(_CTA_REPORT)
    parts.append(f"Rubrics:\n{rubric_block}")
    return "\n\n".join(parts)


def _reason_affirms_label(labels: list[str], reason: str) -> bool:
    """True when free text says the button reads/says a required label."""
    for label in labels:
        escaped = re.escape(label)
        if re.search(
            rf"(?:reads?|says|labelled|labeled)\s+['\"]?{escaped}['\"]?",
            reason,
            re.I,
        ):
            return True
        if re.search(
            rf"['\"]?{escaped}['\"]?\s+is\s+present",
            reason,
            re.I,
        ):
            return True
    return False


def enforce_cta(
    screen: dict[str, Any] | None, results: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Fail the cta rubric when the grader never read the screen's named door.

    The prompt asks for the label; this makes the requirement hard rather than
    trusting a model that is happy to call any door "the obvious primary".
    When the model returns pass=false but still names the required door in
    cta_label or affirms it in the reason text, trust that read — models often
    contradict themselves while describing the correct button.
    """
    labels = cta_labels(screen or {})
    if not labels:
        return results
    side = cta_side(screen or {})
    wanted = " or ".join(f"'{label}'" for label in labels)
    out: list[dict[str, Any]] = []
    for result in results:
        if result.get("rubric_id") != "cta":
            out.append(result)
            continue
        read = str(result.get("cta_label") or "").strip()
        reason = str(result.get("reason") or "")
        probe = read or reason
        label_ok = any(label_seen(label, probe) for label in labels)
        seen_side = str(result.get("cta_side") or "").strip().lower()
        side_ok = not side or not seen_side or seen_side == side
        if result.get("pass"):
            if not label_ok:
                failed = dict(result)
                failed["pass"] = False
                failed["reason"] = (
                    f"required primary CTA {wanted} is not readable "
                    f"(grader read: {read or 'nothing'})"
                )
                out.append(failed)
                continue
            if not side_ok:
                failed = dict(result)
                failed["pass"] = False
                failed["reason"] = (
                    f"required primary CTA {wanted} must sit on the {side}; "
                    f"the grader placed it on the {seen_side}"
                )
                out.append(failed)
                continue
            out.append(result)
            continue
        affirmed = (bool(read) and label_ok) or _reason_affirms_label(labels, reason)
        if affirmed and side_ok:
            salvaged = dict(result)
            salvaged["pass"] = True
            salvaged["reason"] = (
                f"grader affirmed {wanted}; ignoring contradictory fail reason"
            )
            out.append(salvaged)
            continue
        out.append(result)
    return out


def grade_image(
    image_url: str,
    rubrics: list[dict[str, Any]],
    *,
    screen: dict[str, Any] | None = None,
    dry_run: bool = False,
) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    if dry_run:
        for rubric in rubrics:
            results.append(
                {"rubric_id": rubric["id"], "pass": True, "reason": "dry-run"}
            )
        return results

    # Prefer HTTPS URLs (wiki raw) so the provider fetches the image — faster
    # and stays under the request body size cap. Fall back to data URLs for
    # local file paths.
    if image_url.startswith("https://") or image_url.startswith("http://"):
        vision_url = image_url
    else:
        path = Path(image_url)
        data = path.read_bytes()
        suffix = path.suffix.lower()
        ctype = {
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".webp": "image/webp",
            ".gif": "image/gif",
        }.get(suffix, "image/png")
        vision_url = _data_url(data, ctype)
    prompt = build_prompt(rubrics, screen)
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {"url": vision_url}},
            ],
        }
    ]
    last_content = ""
    for attempt in range(GRADE_RETRIES):
        content = _chat(messages)
        last_content = content
        cleaned = content.strip()
        if cleaned.startswith("```"):
            cleaned = re_strip_fence(cleaned)
        try:
            start = cleaned.find("{")
            end = cleaned.rfind("}")
            obj = json.loads(cleaned[start : end + 1])
            rows = obj.get("results") or []
            by_id = {
                str(r.get("rubric_id")): r for r in rows if isinstance(r, dict)
            }
            results = []
            for rubric in rubrics:
                rid = str(rubric["id"])
                row = by_id.get(rid)
                if not row:
                    results.append(
                        {
                            "rubric_id": rid,
                            "pass": False,
                            "reason": "missing rubric result from model",
                        }
                    )
                    continue
                results.append(
                    {
                        "rubric_id": rid,
                        "pass": bool(row.get("pass", row.get("passed", False))),
                        "reason": str(row.get("reason") or "").strip() or "n/a",
                    }
                )
                if rid == "cta":
                    label = row.get("cta_label")
                    if label is None:
                        label = obj.get("cta_label")
                    side = row.get("cta_side") or obj.get("cta_side")
                    if label is not None:
                        results[-1]["cta_label"] = str(label).strip()
                    if side is not None:
                        results[-1]["cta_side"] = str(side).strip().lower()
            return enforce_cta(screen, results)
        except (json.JSONDecodeError, ValueError, TypeError, IndexError):
            # Truncated JSON (token cap) — retry once before FAIL-closed.
            if attempt + 1 < GRADE_RETRIES:
                continue
    results = []
    passed, reason = _parse_verdict(last_content)
    for rubric in rubrics:
        results.append(
            {"rubric_id": rubric["id"], "pass": passed, "reason": reason}
        )
    return enforce_cta(screen, results)


def _grade_one(
    item: dict[str, str],
    rubrics: list[dict[str, Any]],
    screens: list[dict[str, Any]],
    *,
    dry_run: bool,
) -> dict[str, Any]:
    sid = item["screen_id"]
    url = item["image_url"]
    screen = screen_by_id(screens, sid)
    try:
        results = grade_image(url, rubrics, screen=screen, dry_run=dry_run)
        return {
            "screen_id": sid,
            "image_url": url,
            "scripts": list((screen or {}).get("scripts") or []),
            "results": results,
            "error": None,
        }
    except Exception as exc:  # noqa: BLE001 — surface to CI
        return {
            "screen_id": sid,
            "image_url": url,
            "scripts": list((screen or {}).get("scripts") or []),
            "results": [],
            "error": str(exc),
        }


def run_items(
    items: list[dict[str, str]],
    rubrics: list[dict[str, Any]],
    screens: list[dict[str, Any]],
    *,
    dry_run: bool = False,
    fail_file: Path | None = None,
    workers: int = 5,
) -> int:
    if len(items) > MAX_PR_IMAGES:
        print(
            f"ERROR: {len(items)} images exceeds max {MAX_PR_IMAGES}; split the PR.",
            file=sys.stderr,
        )
        return 1

    failures: list[dict[str, Any]] = []
    workers = max(1, min(workers, len(items) or 1))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [
            pool.submit(_grade_one, item, rubrics, screens, dry_run=dry_run)
            for item in items
        ]
        for fut in as_completed(futures):
            row = fut.result()
            sid = row["screen_id"]
            print(f"== grading {sid} ==")
            print(f"   image: {row['image_url']}")
            if row["error"]:
                print(f"FAIL {sid}: grader error: {row['error']}", file=sys.stderr)
                failures.append(
                    {
                        "screen_id": sid,
                        "scripts": row["scripts"],
                        "error": row["error"],
                    }
                )
                continue
            screen_failed = False
            for result in row["results"]:
                status = "PASS" if result["pass"] else "FAIL"
                print(f"   {status} {result['rubric_id']}: {result['reason']}")
                if not result["pass"]:
                    screen_failed = True
            if screen_failed:
                failures.append(
                    {
                        "screen_id": sid,
                        "scripts": row["scripts"],
                        "results": row["results"],
                    }
                )

    if fail_file is not None:
        fail_file.write_text(json.dumps(failures, indent=2) + "\n", encoding="utf-8")

    if failures:
        print("\nFailed screens:", file=sys.stderr)
        for fail in failures:
            sid = fail["screen_id"]
            scripts = ", ".join(fail.get("scripts") or []) or "(no scripts)"
            print(f"  - {sid} ← {scripts}", file=sys.stderr)
        return 1

    print("All screens passed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=("items", "catalogue"),
        default="items",
        help="items: --items-json list; catalogue: all baseline_url entries",
    )
    parser.add_argument(
        "--items-json",
        help='JSON list of {"screen_id","image_url"} (or path / @path)',
    )
    parser.add_argument("--rubrics", type=Path, default=DEFAULT_RUBRICS)
    parser.add_argument("--screens", type=Path, default=DEFAULT_SCREENS)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Skip VLM calls; treat rubrics as pass (wiring test)",
    )
    parser.add_argument(
        "--fail-file",
        type=Path,
        help="Write JSON failure report (screen ids + scripts)",
    )
    args = parser.parse_args()

    rubrics, screens, _shared = load_catalogue(args.rubrics, args.screens)

    if args.mode == "catalogue":
        items = [
            {"screen_id": str(s["id"]), "image_url": str(s["baseline_url"])}
            for s in screens
        ]
    else:
        if not args.items_json:
            print("--items-json required for --mode items", file=sys.stderr)
            return 2
        raw = args.items_json
        path_candidate = Path(raw[1:] if raw.startswith("@") else raw)
        if raw.startswith("@") or (path_candidate.exists() and not raw.strip().startswith("[")):
            payload = json.loads(path_candidate.read_text(encoding="utf-8"))
        else:
            payload = json.loads(raw)
        if not isinstance(payload, list):
            print("--items-json must be a JSON list", file=sys.stderr)
            return 2
        items = [
            {"screen_id": str(i["screen_id"]), "image_url": str(i["image_url"])}
            for i in payload
        ]

    started = time.monotonic()
    code = run_items(
        items,
        rubrics,
        screens,
        dry_run=args.dry_run,
        fail_file=args.fail_file,
    )
    elapsed = time.monotonic() - started
    print(f"Elapsed: {elapsed:.1f}s for {len(items)} image(s)")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
