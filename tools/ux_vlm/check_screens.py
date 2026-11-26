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
MAX_PR_IMAGES = 10


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


def _chat(messages: list[dict[str, Any]], timeout: float = 45.0) -> str:
    payload: dict[str, Any] = {
        "model": _model(),
        "messages": messages,
        "temperature": 0,
        "max_tokens": 400,
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


def _parse_verdict(text: str) -> tuple[bool, str]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re_strip_fence(cleaned)
    try:
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start >= 0 and end > start:
            obj = json.loads(cleaned[start : end + 1])
            passed = bool(obj.get("pass", obj.get("passed", False)))
            reason = str(obj.get("reason") or obj.get("explanation") or "").strip()
            return passed, reason or ("pass" if passed else "fail")
    except json.JSONDecodeError:
        pass
    upper = cleaned.upper()
    if upper.startswith("PASS") or "\nPASS" in upper:
        return True, cleaned[:240]
    if upper.startswith("FAIL") or "\nFAIL" in upper:
        return False, cleaned[:240]
    return False, f"unparseable verdict: {cleaned[:240]}"


def grade_image(
    image_url: str,
    rubrics: list[dict[str, Any]],
    *,
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
    rubric_block = "\n".join(f"- {r['id']}: {r['prompt']}" for r in rubrics)
    prompt = (
        "You are a strict UI visual QA grader for a football simulation game.\n"
        "Judge ONLY what is visible in the screenshot against each rubric.\n"
        "Reply with ONE JSON object only, no markdown, shape:\n"
        '{"results":[{"rubric_id":"...","pass":true,"reason":"..."}, ...]}\n'
        "Include every rubric id below. Be conservative: fail on clear defects.\n\n"
        f"Rubrics:\n{rubric_block}"
    )
    content = _chat(
        [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": vision_url}},
                ],
            }
        ]
    )
    cleaned = content.strip()
    if cleaned.startswith("```"):
        cleaned = re_strip_fence(cleaned)
    try:
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        obj = json.loads(cleaned[start : end + 1])
        rows = obj.get("results") or []
        by_id = {str(r.get("rubric_id")): r for r in rows if isinstance(r, dict)}
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
    except (json.JSONDecodeError, ValueError, TypeError):
        passed, reason = _parse_verdict(content)
        for rubric in rubrics:
            results.append(
                {"rubric_id": rubric["id"], "pass": passed, "reason": reason}
            )
    return results


def _grade_one(
    item: dict[str, str],
    rubrics: list[dict[str, Any]],
    screens: list[dict[str, Any]],
    *,
    dry_run: bool,
) -> dict[str, Any]:
    sid = item["screen_id"]
    url = item["image_url"]
    screen = screen_by_id(screens, sid) or {"id": sid, "scripts": []}
    try:
        results = grade_image(url, rubrics, dry_run=dry_run)
        return {
            "screen_id": sid,
            "image_url": url,
            "scripts": list(screen.get("scripts") or []),
            "results": results,
            "error": None,
        }
    except Exception as exc:  # noqa: BLE001 — surface to CI
        return {
            "screen_id": sid,
            "image_url": url,
            "scripts": list(screen.get("scripts") or []),
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
