#!/usr/bin/env python3
"""Derive FC card face stats and the positional overall from ability sub-stats.

`data/fc_ratings.json` holds the model: the ability sub-stat list, the classic
FC face weights, the per-position overall weight tables (sum 100), the slot
bias a position's overall carries, and the international-reputation bonus. The
game never guesses a face bar or an overall: both come from here, from the
sub-stat sheet the snapshot stores.

The GDScript twin `scripts/data/fc_ratings.gd` reads the same JSON, so the
snapshot tool and the shipped game cannot drift.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = ROOT / "data" / "fc_ratings.json"

SCALE_MAX = 99


def load_model(path: Path = MODEL_PATH) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def half_up(value: float) -> int:
    """Round half away from zero — the rounding a card is printed with."""
    return int(value + 0.5) if value >= 0 else -int(-value + 0.5)


def weighted(values: dict[str, int], weights: dict[str, int]) -> int:
    total = sum(int(values.get(key, 0)) * int(weight) for key, weight in weights.items())
    return half_up(total / 100.0)


def face_stats(sub: dict[str, int], model: dict | None = None) -> dict[str, int]:
    """The six outfield card bars, from the sub-stat sheet."""
    model = model or load_model()
    return {name: weighted(sub, weights) for name, weights in model["face"].items()}


def keeper_stats(sub: dict[str, int], model: dict | None = None) -> dict[str, int]:
    """The keeper card's five bars plus its speed.

    A keeper card prints the raw keeper sub-stats, not a blend, and its speed
    is the same pace formula an outfielder carries.
    """
    model = model or load_model()
    out = {bar: int(sub.get(key, 30)) for bar, key in model["keeper_face"]}
    out["spd"] = weighted(sub, model["face"][model["keeper_speed"]])
    return out


def position_for(role: str, model: dict | None = None) -> str:
    model = model or load_model()
    table = model["role_position"]
    return str(table.get(role, "CM"))


def overall(
    sub: dict[str, int],
    role: str,
    intl_rep: int = 1,
    model: dict | None = None,
) -> int:
    """The position's weighted overall, stepped by its slot bias and reputation."""
    model = model or load_model()
    position = position_for(role, model)
    spec = model["positions"][position]
    value = weighted(sub, spec["weights"]) + float(spec["slot_bias"])
    rule = model["intl_rep"]
    if int(intl_rep) >= int(rule["from"]):
        value += float(rule["bonus"])
    return max(1, min(SCALE_MAX, half_up(value)))


def clamped(sub: dict[str, int]) -> dict[str, int]:
    return {key: max(1, min(SCALE_MAX, int(value))) for key, value in sub.items()}


def synthesize(
    club_base: float,
    role: str,
    wobble: int = 0,
    model: dict | None = None,
) -> dict[str, int]:
    """Sub-stats for a player the sheet does not carry.

    The role profile is the sheet's own typical shape; the club's strength
    shifts the whole sheet up or down, and a deterministic wobble keeps two
    team-mates apart. The result then walks the same derive path as a scraped
    player, so no surface can tell them apart.
    """
    model = model or load_model()
    position = position_for(role, model)
    table = model["synthesis"]
    profile = table["roles"].get(position) or table["roles"]["CM"]
    delta = float(club_base) - float(table["base"])
    out = {}
    for key, value in profile.items():
        out[key] = int(round(float(value) + delta + wobble))
    return clamped(out)


def card_of(
    sub: dict[str, int],
    role: str,
    intl_rep: int = 1,
    model: dict | None = None,
) -> dict:
    """Everything a card prints, derived from one sub-stat sheet."""
    model = model or load_model()
    out = {
        "ovr": overall(sub, role, intl_rep, model),
        **face_stats(sub, model),
        "gk": keeper_stats(sub, model),
    }
    return out
