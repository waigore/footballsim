#!/usr/bin/env python3
"""Build, refresh and ship the Premier League seed snapshot.

The snapshot is `data/pl_snapshot.json` (readable source of truth) and the game
loads the SQLite copy `data/pl_seed.sqlite` it produces. Rebuild the database
after every snapshot edit; bump `db_version` so the game replaces its cache.

Usage:
    python tools/pl_snapshot.py fetch --source espn --season 2025
    python tools/pl_snapshot.py build
    python tools/pl_snapshot.py verify

`fetch` refreshes only league data (table, fixtures, player season/career
figures) from one source. Player ratings are the game's own dataset and are
never overwritten by a league refresh: ESPN does not publish them.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import ssl
import sys
import time
import unicodedata
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "data" / "pl_snapshot.json"
SEED_DB = ROOT / "data" / "pl_seed.sqlite"

SCHEMA_VERSION = 1
SOURCE_ESPN = "espn"
ESPN_SITE = "https://site.api.espn.com/apis/site/v2/sports"
ESPN_CORE = "https://sports.core.api.espn.com/v2"
LEAGUE = "eng.1"

PLAYER_ATTRS = ("ovr", "pac", "sho", "pas", "dri", "def", "phy")
GK_ATTRS = ("div", "han", "kic", "ref", "spd")
## ESPN abbreviates the Manchester clubs differently from the shipped seed.
ESPN_ALIASES = {"MAN": "MUN", "MNC": "MCI"}
STYLE_KEYS = (
    "possession",
    "tempo",
    "press",
    "line",
    "width",
    "directness",
    "crossing",
    "aggression",
)

SCHEMA = """
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE competition (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, short_name TEXT NOT NULL,
    season_label TEXT NOT NULL
);
CREATE TABLE club (
    id TEXT PRIMARY KEY, competition_id TEXT NOT NULL, name TEXT NOT NULL,
    short TEXT NOT NULL, abbr TEXT NOT NULL, nickname TEXT NOT NULL,
    manager TEXT NOT NULL, stadium TEXT NOT NULL, city TEXT NOT NULL,
    capacity INTEGER NOT NULL, formation TEXT NOT NULL,
    color TEXT NOT NULL, color_dark TEXT NOT NULL, color_light TEXT NOT NULL,
    shorts TEXT NOT NULL, gk_color TEXT NOT NULL, text_color TEXT NOT NULL,
    style_possession REAL, style_tempo REAL, style_press REAL, style_line REAL,
    style_width REAL, style_directness REAL, style_crossing REAL,
    style_aggression REAL
);
CREATE TABLE player (
    id TEXT PRIMARY KEY, club_id TEXT NOT NULL, name TEXT NOT NULL,
    number INTEGER NOT NULL, role TEXT NOT NULL, pos TEXT NOT NULL,
    ovr INTEGER NOT NULL, pac INTEGER NOT NULL, sho INTEGER NOT NULL,
    pas INTEGER NOT NULL, dri INTEGER NOT NULL, def INTEGER NOT NULL,
    phy INTEGER NOT NULL, height INTEGER NOT NULL,
    gk_div INTEGER, gk_han INTEGER, gk_kic INTEGER, gk_ref INTEGER, gk_spd INTEGER,
    squad TEXT NOT NULL, ord INTEGER NOT NULL, espn_id TEXT, age INTEGER,
    nationality TEXT, date_of_birth TEXT
);
CREATE TABLE table_row (
    club_id TEXT PRIMARY KEY, position INTEGER NOT NULL, played INTEGER NOT NULL,
    won INTEGER NOT NULL, drawn INTEGER NOT NULL, lost INTEGER NOT NULL,
    gf INTEGER NOT NULL, ga INTEGER NOT NULL, points INTEGER NOT NULL
);
CREATE TABLE fixture (
    id TEXT PRIMARY KEY, competition_id TEXT NOT NULL, matchday INTEGER NOT NULL,
    kickoff TEXT NOT NULL, home_club_id TEXT NOT NULL, away_club_id TEXT NOT NULL,
    home_goals INTEGER NOT NULL, away_goals INTEGER NOT NULL, played INTEGER NOT NULL
);
CREATE TABLE season_stat (
    player_id TEXT PRIMARY KEY, season_label TEXT NOT NULL,
    matches INTEGER NOT NULL, starts INTEGER NOT NULL, minutes INTEGER NOT NULL,
    goals INTEGER NOT NULL, assists INTEGER NOT NULL,
    yellow INTEGER NOT NULL, red INTEGER NOT NULL
);
CREATE TABLE career_stat (
    player_id TEXT PRIMARY KEY, matches INTEGER NOT NULL, goals INTEGER NOT NULL,
    assists INTEGER NOT NULL
);
CREATE TABLE sim_player_stat (
    player_id TEXT PRIMARY KEY, apps INTEGER NOT NULL DEFAULT 0,
    minutes INTEGER NOT NULL DEFAULT 0, goals INTEGER NOT NULL DEFAULT 0,
    assists INTEGER NOT NULL DEFAULT 0, shots INTEGER NOT NULL DEFAULT 0,
    passes INTEGER NOT NULL DEFAULT 0, passes_ok INTEGER NOT NULL DEFAULT 0,
    tackles INTEGER NOT NULL DEFAULT 0, saves INTEGER NOT NULL DEFAULT 0,
    yellow INTEGER NOT NULL DEFAULT 0, red INTEGER NOT NULL DEFAULT 0,
    rating_sum REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT ''
);
CREATE TABLE sim_club_stat (
    club_id TEXT PRIMARY KEY, played INTEGER NOT NULL DEFAULT 0,
    won INTEGER NOT NULL DEFAULT 0, drawn INTEGER NOT NULL DEFAULT 0,
    lost INTEGER NOT NULL DEFAULT 0, gf INTEGER NOT NULL DEFAULT 0,
    ga INTEGER NOT NULL DEFAULT 0, points INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT ''
);
CREATE INDEX player_club_idx ON player (club_id);
CREATE INDEX fixture_home_idx ON fixture (home_club_id);
CREATE INDEX fixture_away_idx ON fixture (away_club_id);
"""

# ------------------------------------------------------------------ helpers --


def slug(text: str) -> str:
    norm = unicodedata.normalize("NFKD", text)
    ascii_text = norm.encode("ascii", "ignore").decode("ascii")
    out = "".join(c if c.isalnum() else "-" for c in ascii_text.lower())
    return "-".join(part for part in out.split("-") if part)


def surname_key(name: str) -> str:
    """Match key: last word of a name, accent- and punctuation-free."""
    words = [w for w in name.replace(".", " ").split() if w]
    return slug(words[-1]) if words else slug(name)


def initial_key(name: str) -> str:
    words = [w for w in name.replace(".", " ").split() if w]
    return words[0][0].lower() if len(words) > 1 else ""


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def get_json(url: str, tries: int = 4) -> dict:
    context = ssl.create_default_context()
    try:  # macOS framework Pythons often ship without a system CA bundle.
        import certifi

        context = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        pass
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "footballsim-seed/1.0"})
            with urllib.request.urlopen(req, timeout=30, context=context) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            if attempt == tries - 1:
                raise SystemExit(f"fetch failed: {url}: {exc}") from exc
            time.sleep(1.5 * (attempt + 1))
    return {}


# -------------------------------------------------------------------- fetch --


def fetch_table(season: int, snapshot: dict) -> dict[str, str]:
    """Fill table rows; return ESPN team id -> club id."""
    data = get_json(f"https://site.api.espn.com/apis/v2/sports/soccer/{LEAGUE}/standings?season={season}")
    entries = data["children"][0]["standings"]["entries"]
    by_abbr = {c["abbr"].upper(): c["id"] for c in snapshot["clubs"]}
    by_name = {slug(c["name"]): c["id"] for c in snapshot["clubs"]}
    rows: dict[str, dict] = {}
    espn_ids: dict[str, str] = {}
    for entry in entries:
        abbr = entry["team"]["abbreviation"].upper()
        club_id = by_abbr.get(ESPN_ALIASES.get(abbr, abbr))
        if club_id is None:
            club_id = by_name.get(slug(entry["team"].get("displayName", "")))
        if club_id is None:
            continue
        espn_ids[str(entry["team"]["id"])] = club_id
        stats = {s["name"]: s.get("value") for s in entry["stats"] if s.get("value") is not None}
        rows[club_id] = {
            "club_id": club_id,
            "position": int(stats.get("rank", 0)),
            "played": int(stats.get("gamesPlayed", 0)),
            "won": int(stats.get("wins", 0)),
            "drawn": int(stats.get("ties", 0)),
            "lost": int(stats.get("losses", 0)),
            "gf": int(stats.get("pointsFor", 0)),
            "ga": int(stats.get("pointsAgainst", 0)),
            "points": int(stats.get("points", 0)),
        }
    snapshot["table"] = sorted(rows.values(), key=lambda r: r["position"])
    return espn_ids


def fetch_fixtures(season: int, espn_ids: dict[str, str]) -> list[dict]:
    by_espn = espn_ids
    events: dict[str, dict] = {}
    for year in (season, season + 1):
        data = get_json(f"{ESPN_SITE}/soccer/{LEAGUE}/scoreboard?dates={year}&limit=1000")
        for event in data.get("events", []):
            if int(event.get("season", {}).get("year", 0)) != season:
                continue
            events[event["id"]] = event
    fixtures: list[dict] = []
    for event in sorted(events.values(), key=lambda e: e["date"]):
        comp = event["competitions"][0]
        sides = {c["homeAway"]: c for c in comp["competitors"]}
        home = by_espn.get(str(sides["home"]["team"]["id"]))
        away = by_espn.get(str(sides["away"]["team"]["id"]))
        if home is None or away is None:
            continue
        played = bool(comp["status"]["type"].get("completed")) or comp["status"]["type"]["name"] in (
            "STATUS_FULL_TIME",
            "STATUS_FINAL",
        )
        fixtures.append(
            {
                "id": f"espn-{event['id']}",
                "matchday": int(event.get("week", {}).get("number", 0) or 0),
                "kickoff": str(event["date"])[:10],
                "home": home,
                "away": away,
                "home_goals": int(sides["home"].get("score", 0) or 0) if played else 0,
                "away_goals": int(sides["away"].get("score", 0) or 0) if played else 0,
                "played": 1 if played else 0,
            }
        )
    return fixtures


def _leader_ids(season: int) -> dict[str, str]:
    """ESPN athlete id -> club abbreviation for the goals/assists leaders."""
    data = get_json(f"{ESPN_CORE}/sports/soccer/leagues/{LEAGUE}/seasons/{season}/types/1/leaders")
    out: dict[str, str] = {}
    for cat in data.get("categories", []):
        if cat["name"] not in ("goalsLeaders", "assistsLeaders"):
            continue
        for leader in cat.get("leaders", []):
            ref = leader["athlete"]["$ref"].split("/athletes/")[-1].split("?")[0]
            out[ref] = ""
    return out


def _stat_map(payload: dict) -> dict[str, float]:
    out: dict[str, float] = {}
    for cat in payload.get("splits", {}).get("categories", []):
        for stat in cat.get("stats", []):
            try:
                out[stat["name"]] = float(stat.get("value", 0) or 0)
            except (TypeError, ValueError):
                continue
    return out


def _player_stats(athlete_id: str, season: int) -> dict:
    season_stats = _stat_map(
        get_json(
            f"{ESPN_CORE}/sports/soccer/leagues/{LEAGUE}/seasons/{season}/types/1/athletes/{athlete_id}/statistics/0"
        )
    )
    career = _stat_map(get_json(f"{ESPN_CORE}/sports/soccer/leagues/{LEAGUE}/athletes/{athlete_id}/statistics/0"))
    return {
        "season": {
            "matches": int(season_stats.get("appearances", 0)),
            "starts": int(season_stats.get("starts", 0)),
            "minutes": int(season_stats.get("minutes", 0)),
            "goals": int(season_stats.get("totalGoals", season_stats.get("goals", 0))),
            "assists": int(season_stats.get("goalAssists", 0)),
            "yellow": int(season_stats.get("yellowCards", 0)),
            "red": int(season_stats.get("redCards", 0)),
        },
        "career": {
            "matches": int(career.get("appearances", 0)),
            "goals": int(career.get("totalGoals", career.get("goals", 0))),
            "assists": int(career.get("goalAssists", 0)),
        },
    }


def fetch_players(season: int, snapshot: dict, espn_ids: dict[str, str]) -> None:
    """Match shard players to ESPN rosters, then pull identity and figures."""

    def roster(club_id: str, espn_team: str) -> tuple[str, list]:
        data = get_json(f"{ESPN_SITE}/soccer/{LEAGUE}/teams/{espn_team}/roster?season={season}")
        return club_id, data.get("athletes", [])

    rosters: dict[str, list] = {}
    with ThreadPoolExecutor(max_workers=6) as pool:
        jobs = [pool.submit(roster, club, team) for team, club in espn_ids.items()]
        for job in jobs:
            club_id, athletes = job.result()
            rosters[club_id] = athletes

    season_stats: list[dict] = []
    career_stats: list[dict] = []
    matched: list[tuple[dict, str]] = []
    for club in snapshot["clubs"]:
        athletes = rosters.get(club["id"], [])
        for player in club["players"]:
            key = (surname_key(player["name"]), initial_key(player["name"]))
            for athlete in athletes:
                if (surname_key(athlete.get("shortName", "")), initial_key(athlete.get("shortName", ""))) != key:
                    continue
                player["espn_id"] = str(athlete["id"])
                player["age"] = int(athlete.get("age", 0) or 0)
                player["nationality"] = str(athlete.get("citizenship") or "")
                player["date_of_birth"] = str(athlete.get("dateOfBirth", ""))[:10]
                matched.append((player, str(athlete["id"])))
                break

    def pull(item: tuple[dict, str]) -> tuple[dict, dict]:
        player, athlete_id = item
        return player, _player_stats(athlete_id, season)

    with ThreadPoolExecutor(max_workers=6) as pool:
        for player, stats in pool.map(pull, matched):
            s = stats["season"]
            if s["matches"] > 0:
                season_stats.append({"player_id": player["id"], "season_label": snapshot["season_label"], **s})
            c = stats["career"]
            if c["matches"] > 0:
                career_stats.append({"player_id": player["id"], **c})

    snapshot["season_stats"] = sorted(season_stats, key=lambda r: (-r["goals"], -r["assists"], r["player_id"]))
    snapshot["career"] = career_stats


def cmd_fetch(args: argparse.Namespace) -> int:
    if args.source != SOURCE_ESPN:
        raise SystemExit("only --source espn is implemented; do not mix sources in one run")
    snapshot = load(args.snapshot)
    snapshot["source"] = "ESPN"
    snapshot["snapshot_date"] = args.date or time.strftime("%Y-%m-%d", time.gmtime())
    snapshot["season_label"] = f"{args.season}-{str(args.season + 1)[2:]}"
    espn_ids = fetch_table(args.season, snapshot)
    if len(espn_ids) < 20:
        raise SystemExit(f"ESPN standings covered {len(espn_ids)} clubs; expected 20")
    snapshot["fixtures"] = fetch_fixtures(args.season, espn_ids)
    fetch_players(args.season, snapshot, espn_ids)
    snapshot["db_version"] = int(snapshot.get("db_version", 1)) + (1 if args.bump_version else 0)
    save(args.snapshot, snapshot)
    print(
        f"snapshot {snapshot['season_label']}: {len(snapshot['table'])} table rows, "
        f"{len(snapshot['fixtures'])} fixtures, {len(snapshot['season_stats'])} season stat lines, "
        f"db_version {snapshot['db_version']}"
    )
    return 0


# -------------------------------------------------------------------- build --


def build_db(snapshot: dict) -> dict:
    meta = {
        "schema_version": str(SCHEMA_VERSION),
        "db_version": str(snapshot["db_version"]),
        "season_label": snapshot["season_label"],
        "snapshot_date": snapshot["snapshot_date"],
        "source": snapshot["source"],
        "ratings_source": snapshot.get("ratings_source", ""),
        "league_name": snapshot["competition"]["name"],
        "referee": snapshot.get("referee", ""),
    }
    SEED_DB.unlink(missing_ok=True)
    con = sqlite3.connect(SEED_DB)
    con.executescript(SCHEMA)
    con.executemany("INSERT INTO metadata VALUES (?, ?)", meta.items())
    comp = snapshot["competition"]
    con.execute(
        "INSERT INTO competition VALUES (?, ?, ?, ?)",
        (comp["id"], comp["name"], comp["short_name"], snapshot["season_label"]),
    )
    for club in snapshot["clubs"]:
        style = club.get("style", {})
        con.execute(
            "INSERT INTO club VALUES (" + ",".join("?" * 25) + ")",
            (
                club["id"], comp["id"], club["name"], club["short"], club["abbr"],
                club.get("nickname", ""), club.get("manager", ""), club["stadium"],
                club["city"], int(club["capacity"]), club["formation"],
                club["color"], club["color_dark"], club["color_light"],
                club["shorts"], club["gk_color"], club["text"],
                *[float(style.get(k, 0.5)) for k in STYLE_KEYS],
            ),
        )
        for ord, p in enumerate(club["players"]):
            gk = p.get("gk") or {}
            con.execute(
                "INSERT INTO player VALUES (" + ",".join("?" * 25) + ")",
                (
                    p["id"], club["id"], p["name"], int(p["number"]), p["role"], p["pos"],
                    *[int(p[a]) for a in PLAYER_ATTRS], int(p.get("height", 180)),
                    *[int(gk.get(a, 30)) if gk else None for a in GK_ATTRS],
                    p["squad"], ord, p.get("espn_id"), int(p.get("age", 0) or 0),
                    p.get("nationality", ""), p.get("date_of_birth", ""),
                ),
            )
    for row in snapshot.get("table", []):
        con.execute(
            "INSERT INTO table_row VALUES (?,?,?,?,?,?,?,?,?)",
            (row["club_id"], row["position"], row["played"], row["won"], row["drawn"],
             row["lost"], row["gf"], row["ga"], row["points"]),
        )
    for fx in snapshot.get("fixtures", []):
        con.execute(
            "INSERT INTO fixture VALUES (?,?,?,?,?,?,?,?,?)",
            (fx["id"], comp["id"], fx["matchday"], fx["kickoff"], fx["home"], fx["away"],
             fx["home_goals"], fx["away_goals"], fx["played"]),
        )
    for s in snapshot.get("season_stats", []):
        con.execute(
            "INSERT INTO season_stat VALUES (?,?,?,?,?,?,?,?,?)",
            (s["player_id"], s["season_label"], s["matches"], s["starts"], s["minutes"],
             s["goals"], s["assists"], s["yellow"], s["red"]),
        )
    for c in snapshot.get("career", []):
        con.execute(
            "INSERT INTO career_stat VALUES (?,?,?,?)",
            (c["player_id"], c["matches"], c["goals"], c["assists"]),
        )
    con.commit()
    clubs = con.execute("SELECT COUNT(*) FROM club").fetchone()[0]
    players = con.execute("SELECT COUNT(*) FROM player").fetchone()[0]
    con.close()
    return {"clubs": clubs, "players": players, "bytes": SEED_DB.stat().st_size}


def cmd_build(args: argparse.Namespace) -> int:
    snapshot = load(args.snapshot)
    summary = build_db(snapshot)
    print(
        f"seed {SEED_DB.relative_to(ROOT)}: {summary['clubs']} clubs, "
        f"{summary['players']} players, {summary['bytes']} bytes, db_version {snapshot['db_version']}"
    )
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    snapshot = load(args.snapshot)
    problems: list[str] = []
    if SEED_DB.exists():
        con = sqlite3.connect(SEED_DB)
        meta = dict(con.execute("SELECT key, value FROM metadata").fetchall())
        clubs = con.execute("SELECT COUNT(*) FROM club").fetchone()[0]
        players = con.execute("SELECT COUNT(*) FROM player").fetchone()[0]
        starters = con.execute("SELECT COUNT(*) FROM player WHERE squad='starter'").fetchone()[0]
        con.close()
        if meta.get("db_version") != str(snapshot["db_version"]):
            problems.append("seed db_version does not match the snapshot; run build")
        if clubs != len(snapshot["clubs"]):
            problems.append("club count differs from the snapshot")
        if starters != 11 * len(snapshot["clubs"]):
            problems.append("every club must ship eleven starters")
        print(f"seed: {clubs} clubs, {players} players, starters {starters}, metadata {meta}")
    else:
        problems.append(f"missing {SEED_DB.relative_to(ROOT)}; run build")
    for club in snapshot["clubs"]:
        ids = [p["id"] for p in club["players"]]
        if len(ids) != len(set(ids)):
            problems.append(f"{club['id']}: duplicate player ids")
        if sum(1 for p in club["players"] if p["squad"] == "starter") != 11:
            problems.append(f"{club['id']}: needs eleven starters")
    if problems:
        print("\n".join(f"FAIL {p}" for p in problems), file=sys.stderr)
        return 1
    print("verify: OK")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, default=SNAPSHOT)
    sub = parser.add_subparsers(dest="cmd", required=True)
    fetch = sub.add_parser("fetch", help="refresh league data from one source")
    fetch.add_argument("--source", default=SOURCE_ESPN)
    fetch.add_argument("--season", type=int, default=2025)
    fetch.add_argument("--date", default="")
    fetch.add_argument("--bump-version", action="store_true")
    fetch.set_defaults(func=cmd_fetch)
    build = sub.add_parser("build", help="write data/pl_seed.sqlite from the snapshot")
    build.set_defaults(func=cmd_build)
    verify = sub.add_parser("verify", help="check the shipped seed against the snapshot")
    verify.set_defaults(func=cmd_verify)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
