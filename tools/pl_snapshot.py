#!/usr/bin/env python3
"""Build, refresh and ship the multi-competition football seed snapshot.

The snapshot is `data/pl_snapshot.json` (readable source of truth) and the game
loads the SQLite copy `data/pl_seed.sqlite` it produces. Rebuild the database
after every snapshot edit; bump `db_version` so the game replaces its cache.

The seed holds more than one competition: the Premier League, La Liga, the
Bundesliga and the English pyramid share one database, one season window and one
set of stable ids. A club's id is `{FIFA country}-{abbr}{N}` (for example
`ENG-MUN1`) and a player's id is a UUID: both are minted once and kept, so a
promotion, a relegation or a roster refresh never rewrites an identity.
Abbreviations stay display-only.

Usage:
    python tools/pl_snapshot.py seed --competition LL --season 2026
    python tools/pl_snapshot.py fetch --source espn --season 2026 --competition all
    python tools/pl_snapshot.py remap
    python tools/pl_snapshot.py build
    python tools/pl_snapshot.py verify

`seed` creates a competition's clubs and squads from ESPN rosters the first
time a league ships: real clubs, real squads, and the game's own role-based
ratings (ESPN publishes no ratings). `fetch` refreshes only league data (table,
fixtures, player identity and season/career figures) from one source; ratings
are never overwritten by a league refresh.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sqlite3
import ssl
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import sys as _sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cup_seed_data import (  # noqa: E402
    CUPS, NAME_POOLS, NORTH_CITIES, PL_EUROPE, PRIORS, SPANISH_NORTH,
    CI_PRELIMINARY, CI_SEEDS, ENGLISH_STUBS, GERMAN_STUBS, SPANISH_STUBS,
    ITALIAN_STUBS,
)
from uefa_seed_data import (  # noqa: E402
    ACCESS as UEFA_ACCESS, ASSOCIATION_LEAGUE as UEFA_ASSOCIATION_LEAGUE,
    ASSOCIATIONS, CLUB_ALIASES as UEFA_ALIASES, COMPETITIONS as UEFA_COMPETITIONS,
    ENTRANTS as UEFA_ENTRANTS, STUB_NAMES, STUBS as UEFA_STUBS, TIER as UEFA_TIER,
)

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / "tools") not in _sys.path:
    _sys.path.insert(0, str(ROOT / "tools"))

import fc_ratings  # noqa: E402  — the shared derive module

SNAPSHOT = ROOT / "data" / "pl_snapshot.json"
SEED_DB = ROOT / "data" / "pl_seed.sqlite"

SCHEMA_VERSION = 3
SOURCE_ESPN = "espn"
SOURCE_SOFIFA = "sofifa"
RATINGS_SHEET = ROOT / "data" / "fc_sheet.csv"
ESPN_SITE = "https://site.api.espn.com/apis/site/v2/sports"
ESPN_CORE = "https://sports.core.api.espn.com/v2"

## FIFA alpha-3 codes for the associations the seed ships.
FIFA_COUNTRY = {"England": "ENG", "Wales": "WAL", "Spain": "ESP", "Germany": "GER",
                "Italy": "ITA", "Andorra": "AND"}
## Clubs that play in the English pyramid but belong to another association.
## The id carries the club's own country, never its competition's.
COUNTRY_BY_CLUB = {
    ("CH", "CAR"): "Wales",
    ("CH", "SWA"): "Wales",
    ("CH", "WXM"): "Wales",
    ("L2", "NEW"): "Wales",
    ("LL2", "AND"): "Andorra",
}
## A reserve side ships the senior club's abbreviation: the season refuses it a
## promotion place, and the seed is the only thing that knows a filial by.
RESERVE_OF = {
    "LL2": {"CEL": "CEL", "RSO2": "RSO"},
}
CLUB_ID_RE = re.compile(r"^([A-Z]{3})-([A-Z0-9]{2,5})([1-9][0-9]*)$")
PLAYER_ID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
## Every player id is a UUID drawn from this namespace, so a re-seed of the same
## ESPN athlete mints the same id without ever embedding a club.
PLAYER_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "https://github.com/waigore/footballsim/player")

## One row per shipped competition.
COMPETITIONS = {
    "PL": {
        "espn": "eng.1",
        "name": "Premier League",
        "short_name": "PREMIER LEAGUE",
        "country": "England",
        "rules": {
            "win_points": 3, "draw_points": 1, "relegation_places": 3,
            "ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 38,
            "season_start": "2026-08-15", "season_end": "2027-05-23",
            "weekend_bias": 0.85, "midweek_matchdays": 5,
        },
    },
    "LL": {
        "espn": "esp.1",
        "name": "La Liga",
        "short_name": "LA LIGA",
        "country": "Spain",
        "rules": {
            # Spain runs the same 20-club, 38-matchday shape as England. The
            # band counts are La Liga's own: 1-4 UCL, 5th UEL and 6th UECL (the
            # Copa del Rey winner takes a UEL place into the same band), three
            # relegated. Fewer midweek rounds than England: Spain plays more
            # weekend-only rounds, so four rounds move midweek.
            "win_points": 3, "draw_points": 1, "relegation_places": 3,
            "ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 38,
            "season_start": "2026-08-15", "season_end": "2027-05-23",
            "weekend_bias": 0.88, "midweek_matchdays": 4,
        },
    },
    "LL2": {
        "espn": "esp.2",
        "name": "La Liga 2",
        "short_name": "LA LIGA 2",
        "country": "Spain",
        "strength": (74.0, 64.0),
        "capacity": (24000, 4000),
        "rules": {
            # Segunda's 22-club, 42-matchday shape and its own end of season:
            # two automatic promotions, a four-team bracket for a third, four
            # RELEGATED labels with nowhere to go (Primera Federación is out of
            # scope) and no European places. The bracket is
            # `segunda_four_two_leg` (wiki DR-20261128-33); reserve sides are
            # barred from the promotion places by the seed's `reserve_of`.
            "win_points": 3, "draw_points": 1, "clubs": 22, "matchdays": 42,
            "promotion_places": 2, "promotion_playoff_places": 4,
            "relegation_places": 4, "playoff_format": "segunda_four_two_leg",
            "ucl_places": 0, "uel_places": 0, "uecl_places": 0,
            "season_start": "2026-08-14", "season_end": "2027-06-06",
            "weekend_bias": 0.85, "midweek_matchdays": 6,
        },
    },
    "BL": {
        "espn": "ger.1",
        "name": "Bundesliga",
        "short_name": "BUNDESLIGA",
        "country": "Germany",
        "rules": {
            # The Bundesliga's 18-club, 34-matchday shape. Without a domestic
            # cup in the save, 1-4 go to the Champions League, 5th to the
            # Europa League and 6th to the Conference League. 17th and 18th are
            # relegated, 16th plays the Relegation against 2.BL's third
            # (container #237; the graph itself is #240).
            "win_points": 3, "draw_points": 1, "clubs": 18,
            "relegation_places": 2, "relegation_playoff_places": 1,
            "ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 34,
            "season_start": "2026-08-28", "season_end": "2027-05-22",
            "weekend_bias": 0.88, "midweek_matchdays": 4,
        },
    },
    "BL2": {
        "espn": "ger.2",
        "name": "2. Bundesliga",
        "short_name": "2. BUNDESLIGA",
        "country": "Germany",
        "rules": {
            # 18 clubs, 34 matchdays. 1st and 2nd go up, 3rd plays the
            # Relegation against the Bundesliga's 16th; 17th and 18th are
            # relegated. No European bands: the 2.BL podium reads promotion or
            # RELEGATED only (container #237; the graph itself is #240).
            "win_points": 3, "draw_points": 1, "clubs": 18,
            "promotion_places": 2, "promotion_playoff_places": 1,
            "relegation_places": 2, "relegation_playoff_places": 1,
            "ucl_places": 0, "uel_places": 0, "uecl_places": 0, "matchdays": 34,
            "season_start": "2026-08-07", "season_end": "2027-05-23",
            "weekend_bias": 0.88, "midweek_matchdays": 4,
        },
    },
    # The English pyramid below the Premier League (#258/#259). Each tier is a
    # 24-club, 46-matchday double round robin; the promotion picture is the
    # 2026/27 one: a tier's top places go up automatically and its next places
    # play the mini-tournament that decides the last promotion, while the
    # tier above sends its bottom places down. `promotion_playoff_places` is the
    # size of that bracket (the band the table paints), and the bracket itself
    # is named by `playoff_format` in LeagueRules' compiled templates.
    #
    # `strength` is the squad band the seed hands a tier (top of the league to
    # the bottom): the pyramid descends, so a promoted side is the weakest club
    # in the division above rather than an equal. `capacity` is the ground-size
    # band used where ESPN publishes no attendance figure.
    "CH": {
        "espn": "eng.2",
        "name": "Championship",
        "short_name": "CHAMPIONSHIP",
        "country": "England",
        "strength": (78.0, 68.0),
        "capacity": (33000, 12000),
        "rules": {
            # 1-2 up, 3-8 into the six-team play-offs for one place; 22-24 down.
            "win_points": 3, "draw_points": 1, "clubs": 24, "matchdays": 46,
            "promotion_places": 2, "promotion_playoff_places": 6,
            "relegation_places": 3,
            "ucl_places": 0, "uel_places": 0, "uecl_places": 0,
            "season_start": "2026-08-07", "season_end": "2027-05-10",
            "weekend_bias": 0.85, "midweek_matchdays": 8,
        },
    },
    "L1": {
        "espn": "eng.3",
        "name": "League One",
        "short_name": "LEAGUE ONE",
        "country": "England",
        "strength": (72.0, 63.0),
        "capacity": (28000, 9000),
        "rules": {
            # 1-2 up, 3-6 into the four-team play-offs; 21-24 down.
            "win_points": 3, "draw_points": 1, "clubs": 24, "matchdays": 46,
            "promotion_places": 2, "promotion_playoff_places": 4,
            "relegation_places": 4,
            "ucl_places": 0, "uel_places": 0, "uecl_places": 0,
            "season_start": "2026-08-07", "season_end": "2027-05-10",
            "weekend_bias": 0.85, "midweek_matchdays": 8,
        },
    },
    "L2": {
        "espn": "eng.4",
        "name": "League Two",
        "short_name": "LEAGUE TWO",
        "country": "England",
        "strength": (68.0, 59.0),
        "capacity": (20000, 6000),
        "rules": {
            # 1-3 up, 4-7 into the four-team play-offs; 23-24 down.
            "win_points": 3, "draw_points": 1, "clubs": 24, "matchdays": 46,
            "promotion_places": 3, "promotion_playoff_places": 4,
            "relegation_places": 2,
            "ucl_places": 0, "uel_places": 0, "uecl_places": 0,
            "season_start": "2026-08-07", "season_end": "2027-05-10",
            "weekend_bias": 0.85, "midweek_matchdays": 8,
        },
    },
    "NL": {
        "espn": "eng.5",
        "name": "National League",
        "short_name": "NATIONAL LEAGUE",
        "country": "England",
        "strength": (64.0, 55.0),
        "capacity": (12000, 3000),
        "rules": {
            # 1 up, 2-7 into the National League's own one-leg ladder for one
            # place; 21-24 read RELEGATED with nowhere further to go (no
            # National League North/South in the save).
            "win_points": 3, "draw_points": 1, "clubs": 24, "matchdays": 46,
            "promotion_places": 1, "promotion_playoff_places": 6,
            "relegation_places": 4,
            "ucl_places": 0, "uel_places": 0, "uecl_places": 0,
            "season_start": "2026-08-08", "season_end": "2027-05-02",
            "weekend_bias": 0.85, "midweek_matchdays": 8,
        },
    },
    # The Italian pair (#420): Serie A on top of Serie B, 20 clubs and 38
    # matchdays each. Serie A's bands are 4 / 1 / 1 Europe with three direct
    # relegation places. Serie B sends two up automatically and runs its own
    # six-team bracket for a third (3rd-8th, skipped when 3rd is more than 14
    # points clear of 4th), drops 18th-20th and plays 16th against 17th over two
    # legs for one more RELEGATED label. Italian ids carry `SA-` / `SB-`.
    "SA": {
        "espn": "ita.1",
        "name": "Serie A",
        "short_name": "SERIE A",
        "country": "Italy",
        "strength": (84.0, 73.0),
        "capacity": (76000, 11000),
        "rules": {
            "win_points": 3, "draw_points": 1, "clubs": 20, "matchdays": 38,
            "relegation_places": 3,
            "ucl_places": 4, "uel_places": 1, "uecl_places": 1,
            "season_start": "2026-08-22", "season_end": "2027-05-23",
            "weekend_bias": 0.88, "midweek_matchdays": 5,
        },
    },
    "SB": {
        "espn": "ita.2",
        "name": "Serie B",
        "short_name": "SERIE B",
        "country": "Italy",
        "strength": (74.0, 64.0),
        "capacity": (36000, 5000),
        "rules": {
            "win_points": 3, "draw_points": 1, "clubs": 20, "matchdays": 38,
            "promotion_places": 2, "promotion_playoff_places": 6,
            "promotion_skip_gap": 14, "playoff_format": "serie_b_six",
            "relegation_places": 3, "playout_places": 2,
            "ucl_places": 0, "uel_places": 0, "uecl_places": 0,
            "season_start": "2026-08-22", "season_end": "2027-05-09",
            "weekend_bias": 0.85, "midweek_matchdays": 6,
        },
    },
}

## The club count a competition ships, used by seed/fetch/verify instead of a
## single 20-club assumption.
CLUB_COUNTS = {cid: int(spec["rules"].get("clubs", 20)) for cid, spec in COMPETITIONS.items()}


PLAYER_ATTRS = ("ovr", "pac", "sho", "pas", "dri", "def", "phy")
GK_ATTRS = ("div", "han", "kic", "ref", "spd")
## Every ability sub-stat a card is derived from, in the sheet's own names.
SUB_STATS = (
    "acceleration", "sprint_speed", "agility", "balance", "reactions",
    "ball_control", "dribbling", "composure", "crossing", "curve",
    "fk_accuracy", "finishing", "heading_accuracy", "long_shots",
    "long_passing", "short_passing", "shot_power", "volleys", "aggression",
    "interceptions", "positioning", "vision", "penalties", "jumping",
    "stamina", "strength", "marking_awareness", "standing_tackle",
    "sliding_tackle", "gk_diving", "gk_handling", "gk_kicking",
    "gk_positioning", "gk_reflexes",
)
## The card extras the snapshot stores beside the sub-stats.
CARD_EXTRAS = (
    "potential", "weak_foot", "skill_moves", "work_rate", "play_styles",
    "traits", "international_reputation",
)
## The sheet's column for each sub-stat; one sheet, every competition.
SHEET_COLUMNS = {
    "acceleration": "movement_acceleration",
    "sprint_speed": "movement_sprint_speed",
    "agility": "movement_agility",
    "balance": "movement_balance",
    "reactions": "movement_reactions",
    "ball_control": "skill_ball_control",
    "dribbling": "skill_dribbling",
    "composure": "mentality_composure",
    "crossing": "attacking_crossing",
    "curve": "skill_curve",
    "fk_accuracy": "skill_fk_accuracy",
    "finishing": "attacking_finishing",
    "heading_accuracy": "attacking_heading_accuracy",
    "long_shots": "power_long_shots",
    "long_passing": "skill_long_passing",
    "short_passing": "attacking_short_passing",
    "shot_power": "power_shot_power",
    "volleys": "attacking_volleys",
    "aggression": "mentality_aggression",
    "interceptions": "mentality_interceptions",
    "positioning": "mentality_positioning",
    "vision": "mentality_vision",
    "penalties": "mentality_penalties",
    "jumping": "power_jumping",
    "stamina": "power_stamina",
    "strength": "power_strength",
    "marking_awareness": "defending_marking_awareness",
    "standing_tackle": "defending_standing_tackle",
    "sliding_tackle": "defending_sliding_tackle",
    "gk_diving": "goalkeeping_diving",
    "gk_handling": "goalkeeping_handling",
    "gk_kicking": "goalkeeping_kicking",
    "gk_positioning": "goalkeeping_positioning",
    "gk_reflexes": "goalkeeping_reflexes",
}
## A club name in the shipped seed against the name the ratings sheet carries.
CLUB_ALIASES = {
    "Fulham": "Fulham FC",
    "Barcelona": "FC Barcelona",
    "Real Betis": "Real Betis Balompié",
    "Sevilla": "Sevilla FC",
    "Alavés": "Deportivo Alavés",
    "Espanyol": "RCD Espanyol",
    "Deportivo": "RC Deportivo de La Coruña",
    "Osasuna": "CA Osasuna",
    "Celta Vigo": "RC Celta",
    "Levante": "Levante UD",
    "Valencia": "Valencia CF",
    "Getafe": "Getafe CF",
    "Elche": "Elche CF",
    "Málaga": "Málaga CF",
    "Villarreal": "Villarreal CF",
    "Racing Santander": "Racing Santander",
    "Bayern Munich": "FC Bayern München",
    "Mainz": "1. FSV Mainz 05",
    "FC Cologne": "1. FC Köln",
    "Schalke 04": "FC Schalke 04",
    "Hertha Berlin": "Hertha BSC",
    "St. Pauli": "FC St. Pauli",
    "Millwall": "Millwall FC",
    "Reading": "Reading FC",
    "Blackpool": "Blackpool FC",
    "Bayer Leverkusen": "Bayer 04 Leverkusen",
    "Werder Bremen": "SV Werder Bremen",
    "TSG Hoffenheim": "TSG 1899 Hoffenheim",
    "Hamburg SV": "Hamburger SV",
    "Kaiserslautern": "1. FC Kaiserslautern",
    "Arminia Bielefeld": "DSC Arminia Bielefeld",
    "VfL Bochum": "VfL Bochum 1848",
    "VfL Osnabruck": "VfL Osnabrück",
    "Energie Cottbus": "FC Energie Cottbus",
}
## The line a role plays on. A keeper never matches an outfield sheet row, and
## a defender never takes a striker's profile, however close the birthday.
ROLE_LINES = {
    "GK": "GK",
    "RB": "DEF", "LB": "DEF", "RCB": "DEF", "LCB": "DEF", "CB": "DEF",
    "RWB": "DEF", "LWB": "DEF",
    "CDM": "MID", "RDM": "MID", "LDM": "MID", "CM": "MID", "RM": "MID",
    "LM": "MID",
    "CAM": "FWD", "RW": "FWD", "LW": "FWD", "ST": "FWD", "CF": "FWD",
}
POSITION_LINES = {
    "GK": "GK",
    "RB": "DEF", "LB": "DEF", "CB": "DEF", "RWB": "DEF", "LWB": "DEF",
    "CDM": "MID", "CM": "MID", "RM": "MID", "LM": "MID", "CAM": "MID",
    "RW": "FWD", "LW": "FWD", "ST": "FWD", "CF": "FWD",
}
## A defender is matched only against defenders, a keeper only against a
## keeper; a midfielder and a forward may swap, because the sheet lists a
## winger at LM and a 10 at CM.
LINE_COMPATIBLE = {
    "GK": {"GK"},
    "DEF": {"DEF"},
    "MID": {"MID", "FWD"},
    "FWD": {"FWD", "MID"},
}


## The cover the ratings gate holds the top leagues to, measured on the XI:
## a club's XI is what the sim fields and what most card surfaces open on. The
## whole-squad cover is reported beside it, never gated: a September card sheet
## trails a season's academy call-ups, and a synthesized kid is the honest answer
## for a player the sheet has never carried.
RATINGS_GATE = {"PL": 0.95, "LL": 0.90, "BL": 0.90}


def line_of(role: str) -> str:
    return ROLE_LINES.get(role, "MID")


def compatible(role: str, positions: list[str]) -> bool:
    """Whether a sheet row's positions can be read as this player's role."""
    if not positions:
        return False
    allowed = LINE_COMPATIBLE.get(line_of(role), {"MID"})
    for position in positions:
        if POSITION_LINES.get(position, "MID") in allowed:
            return True
    return False


## ESPN abbreviates some clubs differently from the shipped seed. One map per
## competition, so Bayern's ESPN MUN never collides with Manchester United.
ESPN_ALIASES = {"MAN": "MUN", "MNC": "MCI"}
ALIASES_BY_COMP = {
    "PL": {"MAN": "MUN", "MNC": "MCI"},
    "BL": {"MUN": "FCB"},
}
## Two clubs in one competition can share an ESPN abbreviation (the National
## League ships Harrogate Town and Hartlepool United as `HAR`). The shipped code
## is keyed by ESPN team id there, so the pair cannot collide inside the tier.
ABBR_BY_ESPN_ID = {
    "NL": {"19262": "HGT", "323": "HPL"},
}
STYLE_KEYS = (
    "possession", "tempo", "press", "line", "width", "directness", "crossing",
    "aggression",
)
## The eleven roles every shipped squad fields, in formation order.
ROLE_ORDER = ("GK", "RB", "RCB", "LCB", "LB", "RDM", "LDM", "RW", "CAM", "LW", "ST")
## ESPN's coarse roster positions (G/D/M/F) map into the slot they fill.
GROUP_ROLES = {
    "G": ["GK"],
    "D": ["RB", "RCB", "LCB", "LB"],
    "M": ["RDM", "LDM", "RW", "CAM", "LW"],
    "F": ["ST", "RW", "LW"],
}
## La Liga's touchline names for the shipped window, in the seed's
## initial-and-surname style. ESPN publishes squads but no coach, and the
## briefing prints a manager line, so the snapshot carries the game's own set.
MANAGERS = {
    "BAR": "H. Flick", "RMA": "X. Alonso", "ATM": "D. Simeone",
    "BET": "M. Pellegrini", "RSO": "S. Francisco", "SEV": "M. Almeyda",
    "RAC": "J. Alberto", "ATH": "E. Valverde", "ALA": "E. Coudet",
    "VIL": "Marcelino", "ESP": "M. González", "DEP": "I. Idiakez",
    "OSA": "J. Arrasate", "CEL": "C. Giráldez", "LEV": "J. Calleja",
    "RAY": "I. Pérez", "VAL": "C. Corberán", "GET": "J. Bordalás",
    "ELC": "E. Sarabia", "MCF": "S. Pellicer",
}
## Managers for the German pair, in the seed's initial-and-surname style, from
## the 2026-27 Bundesliga and 2. Bundesliga personnel tables. ESPN's roster
## `coach` field is stale for the shipped window, so the snapshot keeps its own.
GERMAN_MANAGERS = {
    "BL": {
        "FCA": "M. Baum", "FCU": "M. Lustrinelli", "SVW": "D. Thioune",
        "DOR": "N. Kovač", "ELV": "V. Wagner", "SGE": "A. Hütter",
        "SCF": "J. Schuster", "HSV": "M. Polzin", "TSG": "C. Ilzer",
        "KOE": "R. Wagner", "RBL": "M. Demichelis", "B04": "C. Martínez",
        "M05": "U. Fischer", "BMG": "A. Blessin", "FCB": "V. Kompany",
        "SCP": "R. Kettemann", "S04": "M. Muslić", "VFB": "S. Hoeneß",
    },
    "BL2": {
        "BSC": "S. Leitl", "DSC": "O. Kirch", "BOC": "U. Rösler",
        "EBS": "L. Kornetka", "COT": "C. Wollitz", "SVD": "F. Kohfeldt",
        "SGD": "T. Stamm", "SGF": "H. Vogel", "H96": "S. Wagner",
        "HDH": "F. Schmidt", "FCK": "T. Lieberknecht", "KSC": "M. Senft",
        "KSV": "M. Kniat", "FCM": "P. Sander", "FCN": "M. Klose",
        "OSN": "T. Schultz", "STP": "M. Rapp", "WOB": "T. Strobl",
    },
}
## Real German grounds, in the same shape as the Spanish venues above.

VENUES = {
    "BAR": ("Spotify Camp Nou", "Barcelona", 99354),
    "RMA": ("Santiago Bernabéu", "Madrid", 83186),
    "ATM": ("Riyadh Air Metropolitano", "Madrid", 70460),
    "BET": ("Benito Villamarín", "Seville", 60721),
    "RSO": ("Reale Arena", "San Sebastián", 39500),
    "SEV": ("Ramón Sánchez-Pizjuán", "Seville", 43883),
    "RAC": ("El Sardinero", "Santander", 22222),
    "ATH": ("San Mamés", "Bilbao", 53289),
    "ALA": ("Mendizorroza", "Vitoria-Gasteiz", 19840),
    "VIL": ("Estadio de la Cerámica", "Villarreal", 23500),
    "ESP": ("RCDE Stadium", "Barcelona", 40000),
    "DEP": ("Riazor", "A Coruña", 32660),
    "OSA": ("El Sadar", "Pamplona", 23576),
    "CEL": ("Balaídos", "Vigo", 29000),
    "LEV": ("Ciutat de València", "Valencia", 26354),
    "RAY": ("Estadio de Vallecas", "Madrid", 14708),
    "VAL": ("Mestalla", "Valencia", 49430),
    "GET": ("Coliseum", "Getafe", 16972),
    "ELC": ("Martínez Valero", "Elche", 31388),
    "MCF": ("La Rosaleda", "Málaga", 30044),
    # Bundesliga
    "FCA": ("WWK Arena", "Augsburg", 30660),
    "FCU": ("Stadion An der Alten Försterei", "Berlin", 22012),
    "SVW": ("Weserstadion", "Bremen", 42100),
    "DOR": ("Signal Iduna Park", "Dortmund", 81365),
    "ELV": ("Waldstadion an der Kaiserlinde", "Spiesen-Elversberg", 10000),
    "SGE": ("Deutsche Bank Park", "Frankfurt", 59500),
    "SCF": ("Europa-Park Stadion", "Freiburg im Breisgau", 34700),
    "HSV": ("Volksparkstadion", "Hamburg", 57000),
    "TSG": ("PreZero Arena", "Sinsheim", 30150),
    "KOE": ("RheinEnergieStadion", "Cologne", 49698),
    "RBL": ("Red Bull Arena", "Leipzig", 47800),
    "B04": ("BayArena", "Leverkusen", 30210),
    "M05": ("MEWA Arena", "Mainz", 33305),
    "BMG": ("Borussia-Park", "Mönchengladbach", 54057),
    "FCB": ("Allianz Arena", "Munich", 75000),
    "SCP": ("Home Deluxe Arena", "Paderborn", 15000),
    "S04": ("Veltins-Arena", "Gelsenkirchen", 62271),
    "VFB": ("MHPArena", "Stuttgart", 60058),
    # 2. Bundesliga
    "BSC": ("Olympiastadion", "Berlin", 74649),
    "DSC": ("Schüco-Arena", "Bielefeld", 27332),
    "BOC": ("Vonovia Ruhrstadion", "Bochum", 26000),
    "EBS": ("Eintracht-Stadion", "Braunschweig", 23325),
    "COT": ("LEAG Energie Stadion", "Cottbus", 22528),
    "SVD": ("Merck-Stadion am Böllenfalltor", "Darmstadt", 17650),
    "SGD": ("Rudolf-Harbig-Stadion", "Dresden", 32249),
    "SGF": ("Sportpark Ronhof Thomas Sommer", "Fürth", 16626),
    "H96": ("Heinz von Heiden Arena", "Hanover", 49000),
    "HDH": ("Voith-Arena", "Heidenheim", 15000),
    "FCK": ("Fritz-Walter-Stadion", "Kaiserslautern", 49327),
    "KSC": ("BBBank Wildpark", "Karlsruhe", 34302),
    "KSV": ("Holstein-Stadion", "Kiel", 15034),
    "FCM": ("Avnet Arena", "Magdeburg", 30098),
    "FCN": ("Max-Morlock-Stadion", "Nuremberg", 49923),
    "OSN": ("Stadion an der Bremer Brücke", "Osnabrück", 15741),
    "STP": ("Millerntor-Stadion", "Hamburg", 29546),
    "WOB": ("Volkswagen Arena", "Wolfsburg", 30000),
}

## Grounds for a competition whose abbreviations are shared with another tier
## (Serie B ships Carrarese as `CAR`, the English pyramid already ships Cardiff
## and Carlisle under the same code). These win over `VENUES` for their own
## competition and never leak into a re-seed of another league.
VENUES_BY_COMP = {
    "SA": {
        "LAZ": ("Stadio Olimpico", "Rome", 70634),
        "ROMA": ("Stadio Olimpico", "Rome", 70634),
        "INT": ("San Siro", "Milan", 75923),
        "MIL": ("San Siro", "Milan", 75923),
        "COMO": ("Stadio Giuseppe Sinigaglia", "Como", 13602),
        "JUV": ("Allianz Stadium", "Turin", 41507),
        "FRO": ("Stadio Benito Stirpe", "Frosinone", 16227),
        "BOL": ("Stadio Renato Dall'Ara", "Bologna", 36462),
        "NAP": ("Stadio Diego Armando Maradona", "Naples", 54726),
        "GEN": ("Stadio Luigi Ferraris", "Genoa", 36599),
        "CAG": ("Unipol Domus", "Cagliari", 16416),
        "ATA": ("Gewiss Stadium", "Bergamo", 24950),
        "TOR": ("Stadio Olimpico Grande Torino", "Turin", 27958),
        "MON": ("U-Power Stadium", "Monza", 17102),
        "LEC": ("Stadio Via del Mare", "Lecce", 31533),
        "FIO": ("Stadio Artemio Franchi", "Florence", 43147),
        "PAR": ("Stadio Ennio Tardini", "Parma", 22359),
        "SAS": ("Mapei Stadium", "Reggio Emilia", 21525),
        "VEN": ("Stadio Pier Luigi Penzo", "Venice", 11150),
        "UDI": ("Bluenergy Stadium", "Udine", 25144),
    },
    "SB": {
        "PAL": ("Stadio Renzo Barbera", "Palermo", 36365),
        "MOD": ("Stadio Alberto Braglia", "Modena", 21151),
        "AVE": ("Stadio Partenio-Lombardi", "Avellino", 26000),
        "MAN": ("Stadio Danilo Martelli", "Mantua", 12500),
        "ASC": ("Stadio Cino e Lillo Del Duca", "Ascoli Piceno", 12461),
        "CES": ("Orogel Stadium Dino Manuzzi", "Cesena", 23940),
        "PIS": ("Arena Garibaldi", "Pisa", 25000),
        "BEN": ("Stadio Ciro Vigorito", "Benevento", 16867),
        "SUD": ("Stadio Druso", "Bolzano", 5500),
        "SAM": ("Stadio Luigi Ferraris", "Genoa", 36599),
        "VER": ("Stadio Marcantonio Bentegodi", "Verona", 39211),
        "PAD": ("Stadio Euganeo", "Padua", 32420),
        "CAR": ("Stadio dei Marmi", "Carrara", 10000),
        "CRE": ("Stadio Giovanni Zini", "Cremona", 20641),
        "ENT": ("Stadio Comunale", "Chiavari", 5500),
        "JVS": ("Stadio Romeo Menti", "Castellammare di Stabia", 7642),
        "CAT": ("Stadio Nicola Ceravolo", "Catanzaro", 14650),
        "ARE": ("Stadio Città di Arezzo", "Arezzo", 13128),
        "VIC": ("Stadio Romeo Menti", "Vicenza", 12000),
        "EMP": ("Stadio Carlo Castellani", "Empoli", 16284),
    },
    "LL2": {
        "ALM": ("Estadio de los Juegos Mediterráneos", "Almería", 15000),
        "CAS": ("Estadio de Castalia", "Castellón", 15500),
        "GIR": ("Estadi Montilivi", "Girona", 14624),
        "GRA": ("Estadio Nuevo Los Cármenes", "Granada", 19336),
        "BUR": ("Estadio Municipal de El Plantío", "Burgos", 12200),
        "MLL": ("Estadi Mallorca Son Moix", "Palma", 23142),
        "EIB": ("Estadio Municipal de Ipurua", "Eibar", 8164),
        "COR": ("Estadio El Arcángel", "Córdoba", 21822),
        "LPA": ("Estadio de Gran Canaria", "Las Palmas", 32400),
        "RSG": ("Estadio El Molinón", "Gijón", 30000),
        "OVI": ("Estadio Carlos Tartiere", "Oviedo", 30500),
        "CDS": ("Estadi de la Nova Creu Alta", "Sabadell", 11981),
        "VLL": ("Estadio José Zorrilla", "Valladolid", 27618),
        "TEN": ("Estadio Heliodoro Rodríguez López", "Santa Cruz de Tenerife", 22824),
        "LEG": ("Estadio Municipal de Butarque", "Leganés", 12450),
        "ELD": ("Estadio Nuevo Pepico Amat", "Elda", 4036),
        "CAD": ("Estadio Nuevo Mirandilla", "Cádiz", 20724),
        "CEL": ("Estadio Municipal de Barreiro", "Vigo", 1170),
        "RSO2": ("Instalaciones de Zubieta", "San Sebastián", 1000),
        "ALB": ("Estadio Carlos Belmonte", "Albacete", 17000),
        "AND": ("Estadi Nacional", "Andorra la Vella", 3306),
        "CEU": ("Estadio Municipal Alfonso Murube", "Ceuta", 6500),
    },
}

SCHEMA = """
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE competition (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, short_name TEXT NOT NULL,
    season_label TEXT NOT NULL, country TEXT NOT NULL DEFAULT '',
    rules TEXT NOT NULL DEFAULT '{}'
);
CREATE TABLE club (
    id TEXT PRIMARY KEY, competition_id TEXT NOT NULL,
    country TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL,
    short TEXT NOT NULL, abbr TEXT NOT NULL, nickname TEXT NOT NULL,
    manager TEXT NOT NULL, stadium TEXT NOT NULL, city TEXT NOT NULL,
    capacity INTEGER NOT NULL, formation TEXT NOT NULL,
    color TEXT NOT NULL, color_dark TEXT NOT NULL, color_light TEXT NOT NULL,
    shorts TEXT NOT NULL, gk_color TEXT NOT NULL, text_color TEXT NOT NULL,
    style_possession REAL, style_tempo REAL, style_press REAL, style_line REAL,
    style_width REAL, style_directness REAL, style_crossing REAL,
    style_aggression REAL,
    stub INTEGER NOT NULL DEFAULT 0, tier INTEGER NOT NULL DEFAULT 0,
    region TEXT NOT NULL DEFAULT '', reserve_of TEXT NOT NULL DEFAULT ''
);
CREATE TABLE competition_member (
    competition_id TEXT NOT NULL, member_kind TEXT NOT NULL,
    member_id TEXT NOT NULL, role TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (competition_id, member_kind, member_id)
);
CREATE TABLE player (
    id TEXT PRIMARY KEY, club_id TEXT NOT NULL, name TEXT NOT NULL,
    number INTEGER NOT NULL, role TEXT NOT NULL, pos TEXT NOT NULL,
    ovr INTEGER NOT NULL, pac INTEGER NOT NULL, sho INTEGER NOT NULL,
    pas INTEGER NOT NULL, dri INTEGER NOT NULL, def INTEGER NOT NULL,
    phy INTEGER NOT NULL, height INTEGER NOT NULL,
    gk_div INTEGER, gk_han INTEGER, gk_kic INTEGER, gk_ref INTEGER, gk_spd INTEGER,
    squad TEXT NOT NULL, ord INTEGER NOT NULL, espn_id TEXT, age INTEGER,
    nationality TEXT, date_of_birth TEXT,
    subs TEXT NOT NULL DEFAULT '{}', extras TEXT NOT NULL DEFAULT '{}',
    ratings_matched INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE table_row (
    club_id TEXT PRIMARY KEY, competition_id TEXT NOT NULL,
    position INTEGER NOT NULL, played INTEGER NOT NULL,
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
CREATE INDEX fixture_comp_idx ON fixture (competition_id);
CREATE INDEX table_comp_idx ON table_row (competition_id);
CREATE INDEX member_comp_idx ON competition_member (competition_id);
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
    data = json.loads(path.read_text(encoding="utf-8"))
    return upgrade(data)


def save(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def upgrade(data: dict) -> dict:
    """Lift a single-competition snapshot into the multi-competition shape."""
    if isinstance(data.get("competitions"), list):
        for club in data.get("clubs", []):
            club.setdefault("competition_id", "PL")
        for row in data.get("table", []):
            row.setdefault("competition_id", "PL")
        for fx in data.get("fixtures", []):
            fx.setdefault("competition_id", "PL")
        return data
    primary = data.get("competition") or {
        "id": "PL", "name": "Premier League", "short_name": "PREMIER LEAGUE",
    }
    cid = str(primary.get("id", "PL"))
    spec = COMPETITIONS.get(cid, COMPETITIONS["PL"])
    data["competitions"] = [{
        "id": cid, "name": primary.get("name", spec["name"]),
        "short_name": primary.get("short_name", spec["short_name"]),
        "country": spec["country"], "espn": spec["espn"], "rules": spec["rules"],
    }]
    data.pop("competition", None)
    for club in data.get("clubs", []):
        club.setdefault("competition_id", cid)
    for row in data.get("table", []):
        row.setdefault("competition_id", cid)
    for fx in data.get("fixtures", []):
        fx.setdefault("competition_id", cid)
    data["schema_version"] = SCHEMA_VERSION
    return data


def spec_for(competition_id: str) -> dict:
    if competition_id in CUPS:
        return CUPS[competition_id]
    if competition_id in UEFA_COMPETITIONS:
        return UEFA_COMPETITIONS[competition_id]
    if competition_id not in COMPETITIONS:
        raise SystemExit(f"unknown competition {competition_id}; known: "
                         + ", ".join(list(COMPETITIONS) + list(CUPS) + list(UEFA_COMPETITIONS)))
    return COMPETITIONS[competition_id]


def club_id_for(competition_id: str, abbr: str, taken: set[str],
                country: str = "") -> str:
    """Mint a club's permanent id: `{FIFA country}-{abbr}{N}`.

    `N` starts at 1 for every (country, abbr) pair and only moves on when the
    pair is already in use, so two Barnets in two countries never collide.
    `country` names a UEFA stub's own association; a domestic club reads its
    competition's country instead.
    """
    stem = f"{club_country(competition_id, abbr, country)}-{abbr}"
    n = 1
    while f"{stem}{n}" in taken:
        n += 1
    return f"{stem}{n}"


def club_country(competition_id: str, abbr: str, declared: str = "") -> str:
    if competition_id in UEFA_COMPETITIONS:
        if len(declared) == 3 and declared.isupper():
            return declared
        return FIFA_COUNTRY.get(declared, "ENG")
    default = str(spec_for(competition_id)["country"])
    name = str(COUNTRY_BY_CLUB.get((competition_id, abbr), default))
    return FIFA_COUNTRY.get(name, "ENG")


def player_id_for(espn_id: str, club_name: str, player_name: str, taken: set[str]) -> str:
    """Mint a player's UUID: keyed on the ESPN athlete, never on the club.

    The seed can list the same athlete under two clubs (a stale roster), so a
    taken key falls back to the club it was first seen at. Assigned once and
    stored in the snapshot; a refresh keeps whatever id the player already has.
    """
    key = f"espn:{espn_id}" if espn_id else f"name:{club_name}|{player_name}"
    player = str(uuid.uuid5(PLAYER_NAMESPACE, key))
    if player in taken:
        player = str(uuid.uuid5(PLAYER_NAMESPACE, f"{key}|{club_name}"))
    n = 2
    while player in taken:
        player = str(uuid.uuid5(PLAYER_NAMESPACE, f"{key}|{club_name}#{n}"))
        n += 1
    return player


def shippable_abbr(competition_id: str, abbr: str, espn_id: str = "") -> str:
    """The abbreviation the seed ships for a competition's ESPN team.

    An ESPN team id wins over the abbreviation, so a tier that ships two clubs
    under one short code can still name both (see ABBR_BY_ESPN_ID).
    """
    by_id = ABBR_BY_ESPN_ID.get(competition_id, {}).get(str(espn_id))
    if by_id:
        return by_id
    up = str(abbr).upper()
    return ALIASES_BY_COMP.get(competition_id, ESPN_ALIASES).get(up, up)


def comp_clubs(snapshot: dict, competition_id: str) -> list[dict]:
    return [c for c in snapshot.get("clubs", []) if str(c.get("competition_id", "PL")) == competition_id]


def get_json(url: str, tries: int = 4, missing_ok: bool = False) -> dict:
    """GET a JSON payload; a 404 is an empty payload when `missing_ok`.

    ESPN has no statistics resource for an athlete who has not featured, so a
    mid-season refresh must read "no line" rather than fail the whole run.
    """
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
        except urllib.error.HTTPError as exc:
            if missing_ok and exc.code == 404:
                return {}
            if attempt == tries - 1:
                raise SystemExit(f"fetch failed: {url}: {exc}") from exc
            time.sleep(1.5 * (attempt + 1))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            if attempt == tries - 1:
                raise SystemExit(f"fetch failed: {url}: {exc}") from exc
            time.sleep(1.5 * (attempt + 1))
    return {}


# -------------------------------------------------------------------- fetch --


def fetch_table(competition_id: str, season: int, snapshot: dict) -> dict[str, str]:
    """Fill table rows; return ESPN team id -> club id."""
    league = spec_for(competition_id)["espn"]
    data = get_json(f"https://site.api.espn.com/apis/v2/sports/soccer/{league}/standings?season={season}")
    entries = data["children"][0]["standings"]["entries"]
    clubs = comp_clubs(snapshot, competition_id)
    by_abbr = {c["abbr"].upper(): c["id"] for c in clubs}
    by_name = {slug(c["name"]): c["id"] for c in clubs}
    rows: dict[str, dict] = {}
    espn_ids: dict[str, str] = {}
    for entry in entries:
        abbr = entry["team"]["abbreviation"].upper()
        club_id = by_abbr.get(shippable_abbr(competition_id, abbr, entry["team"].get("id", "")))
        if club_id is None:
            club_id = by_name.get(slug(entry["team"].get("displayName", "")))
        if club_id is None:
            continue
        espn_ids[str(entry["team"]["id"])] = club_id
        stats = {s["name"]: s.get("value") for s in entry["stats"] if s.get("value") is not None}
        rows[club_id] = {
            "club_id": club_id, "competition_id": competition_id,
            "position": int(stats.get("rank", 0)),
            "played": int(stats.get("gamesPlayed", 0)),
            "won": int(stats.get("wins", 0)),
            "drawn": int(stats.get("ties", 0)),
            "lost": int(stats.get("losses", 0)),
            "gf": int(stats.get("pointsFor", 0)),
            "ga": int(stats.get("pointsAgainst", 0)),
            "points": int(stats.get("points", 0)),
        }
    others = [r for r in snapshot.get("table", []) if str(r.get("competition_id", "PL")) != competition_id]
    snapshot["table"] = others + sorted(rows.values(), key=lambda r: r["position"])
    return espn_ids


def fetch_fixtures(competition_id: str, season: int, espn_ids: dict[str, str]) -> list[dict]:
    league = spec_for(competition_id)["espn"]
    prefix = slug(competition_id)
    events: dict[str, dict] = {}
    for year in (season, season + 1):
        data = get_json(f"{ESPN_SITE}/soccer/{league}/scoreboard?dates={year}&limit=1000")
        for event in data.get("events", []):
            if int(event.get("season", {}).get("year", 0)) != season:
                continue
            events[event["id"]] = event
    fixtures: list[dict] = []
    for event in sorted(events.values(), key=lambda e: e["date"]):
        comp = event["competitions"][0]
        sides = {c["homeAway"]: c for c in comp["competitors"]}
        home = espn_ids.get(str(sides["home"]["team"]["id"]))
        away = espn_ids.get(str(sides["away"]["team"]["id"]))
        if home is None or away is None:
            continue
        played = bool(comp["status"]["type"].get("completed")) or comp["status"]["type"]["name"] in (
            "STATUS_FULL_TIME",
            "STATUS_FINAL",
        )
        fixtures.append(
            {
                "id": f"{prefix}-espn-{event['id']}",
                "competition_id": competition_id,
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


def _stat_map(payload: dict) -> dict[str, float]:
    out: dict[str, float] = {}
    for cat in payload.get("splits", {}).get("categories", []):
        for stat in cat.get("stats", []):
            try:
                out[stat["name"]] = float(stat.get("value", 0) or 0)
            except (TypeError, ValueError):
                continue
    return out


def _player_stats(competition_id: str, athlete_id: str, season: int) -> dict:
    league = spec_for(competition_id)["espn"]
    season_stats = _stat_map(
        get_json(
            f"{ESPN_CORE}/sports/soccer/leagues/{league}/seasons/{season}/types/1/athletes/{athlete_id}/statistics/0",
            missing_ok=True,
        )
    )
    career = _stat_map(
        get_json(
            f"{ESPN_CORE}/sports/soccer/leagues/{league}/athletes/{athlete_id}/statistics/0",
            missing_ok=True,
        )
    )
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
            # ESPN's career payload carries goals but no assists; -1 means
            # "not in the snapshot" so the page prints a dash, never a fake 0.
            "goals": int(career.get("totalGoals", career.get("goals", -1))),
            "assists": int(career.get("goalAssists", -1)),
        },
    }


def fetch_players(competition_id: str, season: int, snapshot: dict, espn_ids: dict[str, str]) -> None:
    """Match shard players to ESPN rosters, then pull identity and figures."""
    league = spec_for(competition_id)["espn"]

    def roster(club_id: str, espn_team: str) -> tuple[str, list]:
        data = get_json(f"{ESPN_SITE}/soccer/{league}/teams/{espn_team}/roster?season={season}")
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
    for club in comp_clubs(snapshot, competition_id):
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
        return player, _player_stats(competition_id, athlete_id, season)

    with ThreadPoolExecutor(max_workers=6) as pool:
        for player, stats in pool.map(pull, matched):
            s = stats["season"]
            if s["matches"] > 0:
                season_stats.append({
                    "player_id": player["id"], "competition_id": competition_id,
                    "season_label": snapshot["season_label"], **s,
                })
            c = stats["career"]
            if c["matches"] > 0:
                career_stats.append({"player_id": player["id"], **c})

    others = [r for r in snapshot.get("season_stats", [])
              if str(r.get("competition_id", "PL")) != competition_id]
    snapshot["season_stats"] = others + sorted(
        season_stats, key=lambda r: (-r["goals"], -r["assists"], r["player_id"]))
    kept = {str(c["player_id"]) for c in career_stats}
    snapshot["career"] = [c for c in snapshot.get("career", []) if str(c["player_id"]) not in kept] + career_stats


# --------------------------------------------------------------------- seed --


def _rgb(hex_text: str) -> tuple[int, int, int]:
    text = (hex_text or "888888").strip().lstrip("#")
    if len(text) != 6:
        text = "888888"
    return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)


def _hex(rgb: tuple[float, float, float]) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(v))) for v in rgb)


def _shade(hex_text: str, factor: float) -> str:
    r, g, b = _rgb(hex_text)
    return _hex((r * factor, g * factor, b * factor))


def _ink(hex_text: str) -> str:
    r, g, b = _rgb(hex_text)
    return "#121212" if (0.299 * r + 0.587 * g + 0.114 * b) > 150 else "#ffffff"


def _jitter(text: str, span: int) -> int:
    digest = hashlib.sha1(text.encode("utf-8")).digest()
    return int(digest[0]) % (span * 2 + 1) - span


def _clamp(value: float, low: int = 35, high: int = 93) -> int:
    return max(low, min(high, int(round(value))))


def _wobble(text: str) -> int:
    return _jitter(text, 3)


## The card bar a face name prints under: pace -> PAC, and so on.
FACE_KEYS = {
    "pace": "pac", "shooting": "sho", "passing": "pas",
    "dribbling": "dri", "defending": "def", "physic": "phy",
}


def _card_from_subs(subs: dict[str, int], role: str, intl_rep: int = 1) -> dict:
    """The card a sub-stat sheet prints: overall, face bars and keeper bars."""
    card = fc_ratings.card_of(subs, role, intl_rep)
    out = {"ovr": card["ovr"], "gk": card["gk"]}
    for face, key in FACE_KEYS.items():
        out[key] = card.get(face, 0)
    return out


def _attributes(club_base: float, role: str, name: str) -> dict:
    """A card for a player the sheet does not carry.

    The sub-stat sheet is synthesized from the role profile and the club's
    strength, then walked through the same derive path a scraped player takes,
    so no surface can tell the two apart.
    """
    subs = fc_ratings.synthesize(club_base, role, _wobble(name))
    return _card_from_subs(subs, role)


def _role_for(group: str, counts: dict[str, int]) -> str:
    """The role in this player's line that the squad has fewest of."""
    options = GROUP_ROLES.get(group, ["CAM"])
    return min(options, key=lambda role: (counts.get(role, 0), ROLE_ORDER.index(role)))


def _ground(competition_id: str, season: int, team: dict, abbr: str,
            rank: int, size: int) -> tuple[str, str, int]:
    """The ground a seeded club ships: name, city and capacity.

    A hand-authored VENUES entry wins; otherwise ESPN's own venue for the season
    supplies the name and the city, and the capacity comes from the
    competition's band (ESPN publishes none for these leagues), stepped by
    league place and nudged per club so no two grounds read alike. A club ESPN
    knows no venue for keeps a synthetic name — the seed fills the gap rather
    than dropping the club.
    """
    if abbr in VENUES_BY_COMP.get(competition_id, {}):
        return VENUES_BY_COMP[competition_id][abbr]
    if abbr in VENUES:
        return VENUES[abbr]
    city = str(team.get("location", ""))
    spec = spec_for(competition_id)
    try:
        detail = get_json(
            f"{ESPN_CORE}/sports/soccer/leagues/{spec['espn']}/seasons/{season}"
            f"/teams/{team['id']}",
            missing_ok=True,
        )
    except SystemExit:
        detail = {}
    venue = detail.get("venue") or {}
    ground = str(venue.get("fullName") or "")
    city = str((venue.get("address") or {}).get("city") or city)
    if ground == "":
        ground = f"{team.get('location', team['displayName'])} Stadium"
    high, low = spec.get("capacity", (25000, 25000))
    span = float(high) - float(low)
    stepped = float(high) - float(rank - 1) * (span / float(max(size - 1, 1)))
    capacity = int(round(stepped / 500.0) * 500) + _jitter(abbr + competition_id, 1) * 500
    return ground, city, max(2000, min(int(high), capacity))


def seed_competition(competition_id: str, season: int, snapshot: dict) -> None:
    """Create a competition's clubs and squads from ESPN rosters."""
    spec = spec_for(competition_id)
    league = spec["espn"]
    data = get_json(f"https://site.api.espn.com/apis/v2/sports/soccer/{league}/standings?season={season}")
    entries = data["children"][0]["standings"]["entries"]
    size = max(len(entries), 2)
    rank_of = {}
    for entry in entries:
        stats = {s["name"]: s.get("value") for s in entry["stats"] if s.get("value") is not None}
        rank_of[str(entry["team"]["id"])] = int(stats.get("rank", size))
    # Ids are minted before the roster fan-out: a club keeps the id it already
    # has, and new clubs are numbered in club-name order so a rebuild of the
    # same league mints the same suffixes.
    taken = {str(c["id"]) for c in snapshot.get("clubs", [])
             if str(c.get("competition_id", "PL")) != competition_id}
    prior = {str(c.get("abbr", "")): str(c["id"]) for c in snapshot.get("clubs", [])
             if str(c.get("competition_id", "PL")) == competition_id
             and CLUB_ID_RE.match(str(c.get("id", "")))}
    club_of: dict[str, dict] = {}
    for entry in sorted(entries, key=lambda e: str(e["team"].get("displayName", ""))):
        team = entry["team"]
        abbr = shippable_abbr(competition_id, team["abbreviation"], team.get("id", ""))
        club_id = prior.get(abbr) or club_id_for(competition_id, abbr, taken)
        taken.add(club_id)
        club_of[str(team["id"])] = {"id": club_id, "abbr": abbr}

    def build(entry: dict) -> dict:
        team = entry["team"]
        club_id = club_of[str(team["id"])]["id"]
        abbr = club_of[str(team["id"])]["abbr"]
        meta = get_json(f"{ESPN_SITE}/soccer/{league}/teams/{team['id']}").get("team", {})
        roster = get_json(
            f"{ESPN_SITE}/soccer/{league}/teams/{team['id']}/roster?season={season}"
        ).get("athletes", [])
        color = _hex(_rgb(meta.get("color", team.get("color", "888888"))))
        rank = rank_of.get(str(team["id"]), size)
        # Club strength runs from the top of the competition's own band down to
        # its bottom: the same 84-to-71 stretch the hand-authored squads occupy
        # for a league that names no band, and a down-stepping band for the
        # pyramid's lower tiers so a promoted side is the weakest club above.
        high, low = spec.get("strength", (84.0, 71.0))
        club_base = float(high) - float(rank - 1) * ((float(high) - float(low)) / float(size - 1))
        ground, city, capacity = _ground(competition_id, season, team, abbr, rank, size)
        players: list[dict] = []
        role_counts: dict[str, int] = {}
        for athlete in roster:
            name = str(athlete.get("shortName") or athlete.get("displayName") or "")
            if name == "":
                continue
            group = str((athlete.get("position") or {}).get("abbreviation", "M"))
            role = _role_for(group, role_counts)
            role_counts[role] = role_counts.get(role, 0) + 1
            attrs = _attributes(club_base, role, name + club_id)
            height = athlete.get("height")
            cm = int(round(float(height) * 2.54)) if height else 180
            player = {
                "id": "", "name": name,
                "number": int(str(athlete.get("jersey") or 0).replace("'", "") or 0) or len(players) + 1,
                "role": role, "pos": role,
                **{k: attrs[k] for k in PLAYER_ATTRS},
                "height": max(160, min(210, cm)),
                "squad": "starter" if len(players) < 11 else "bench",
                "espn_id": str(athlete.get("id", "")),
                "age": int(athlete.get("age", 0) or 0),
                "nationality": str(athlete.get("citizenship") or ""),
                "date_of_birth": str(athlete.get("dateOfBirth", ""))[:10],
            }
            if role == "GK":
                player["gk"] = attrs["gk"]
            players.append(player)
        # ESPN lists keepers first; pick one body per formation slot so the XI
        # really covers all eleven roles, then order the sheet by line.
        rank_role = {role: i for i, role in enumerate(ROLE_ORDER)}
        used: set[int] = set()
        for role in ROLE_ORDER:
            pool = [i for i, p in enumerate(players) if p["role"] == role and i not in used]
            if pool:
                used.add(max(pool, key=lambda i: players[i]["ovr"]))
            elif len(used) < 11:
                rest = [i for i in range(len(players)) if i not in used]
                if rest:
                    used.add(max(rest, key=lambda i: players[i]["ovr"]))
        for i, player in enumerate(players):
            player["squad"] = "starter" if i in used else "bench"
        players.sort(key=lambda p: (
            0 if p["squad"] == "starter" else 1,
            rank_role.get(p["role"], 99), -p["ovr"]))
        # A shirt list, not the whole roster: the XI plus fifteen cover every
        # line, and an ESPN roster of 34 leaves room for the bench.
        players = players[:26]
        strength = float(rank)
        profile = 1.0 - (strength - 1.0) / float(size - 1)
        style = {
            "possession": round(0.44 + 0.24 * profile, 2),
            "tempo": round(0.48 + 0.12 * profile, 2),
            "press": round(0.46 + 0.24 * profile, 2),
            "line": round(0.50 + 0.14 * profile, 2),
            "width": 0.58, "directness": round(0.62 - 0.16 * profile, 2),
            "crossing": 0.52, "aggression": round(0.48 + 0.10 * (1.0 - profile), 2),
        }
        return {
            "id": club_id, "competition_id": competition_id,
            "country": club_country(competition_id, abbr),
            "name": team["displayName"], "short": team.get("shortDisplayName", team["displayName"]),
            "abbr": abbr, "nickname": meta.get("nickname", ""),
            "manager": GERMAN_MANAGERS.get(competition_id, {}).get(abbr)
            or (MANAGERS.get(abbr, "") if competition_id == "LL" else "")
            # ESPN publishes no current coach for the tiers below the top
            # flights (its roster coach list is a club's history, not a
            # touchline today), so the seed ships a role, never an invented
            # name: the briefing reads THE MANAGER until the source carries one.
            or "The Manager",
            "stadium": ground, "city": city, "capacity": int(capacity),
            "formation": "4-2-3-1", "color": color,
            "color_dark": _shade(color, 0.65), "color_light": _shade(color, 1.35),
            "shorts": "#ffffff", "gk_color": "#1a1a1a", "text": _ink(color),
            "style": style, "players": players,
            "reserve_of": "",
        }

    with ThreadPoolExecutor(max_workers=4) as pool:
        seeded = list(pool.map(build, entries))
    kept = [c for c in snapshot.get("clubs", [])
            if str(c.get("competition_id", "PL")) != competition_id]
    # Player ids are minted after the roster fan-out, in club-name order, so
    # every athlete gets one UUID for the whole snapshot.
    taken_players = {str(p["id"]) for c in kept for p in c.get("players", [])
                     if PLAYER_ID_RE.match(str(p.get("id", "")))}
    for club in sorted(seeded, key=lambda c: str(c["name"])):
        for player in club["players"]:
            player["id"] = player_id_for(
                str(player.get("espn_id", "")), str(club["name"]),
                str(player["name"]), taken_players)
            taken_players.add(player["id"])
    snapshot["clubs"] = kept + seeded
    for club in seeded:
        club["reserve_of"] = reserve_senior(snapshot, competition_id, str(club["abbr"]),
                                            str(club["id"]))


def reserve_senior(snapshot: dict, competition_id: str, abbr: str, club_id: str) -> str:
    """The senior club a reserve side belongs to, or '' when it is a senior side.

    The seed is the only surface that knows a filial: the season reads the flag
    and never guesses one from a name. The senior sits in the tier above, so a
    club of the same competition that happens to print the same abbreviation is
    not it.
    """
    want = RESERVE_OF.get(competition_id, {}).get(abbr, "")
    if not want:
        return ""
    same = [c for c in snapshot.get("clubs", [])
            if str(c.get("abbr", "")) == want and str(c.get("id", "")) != club_id
            and not int(c.get("stub", 0))]
    above = [c for c in same if str(c.get("competition_id", "")) != competition_id]
    for club in above or same:
        return str(club["id"])
    return ""


STUB_ROLES = [
    ("GK", "GK"), ("RB", "RB"), ("RCB", "CB"), ("LCB", "CB"), ("LB", "LB"),
    ("RDM", "CDM"), ("LDM", "CDM"), ("RW", "RW"), ("CAM", "CAM"), ("LW", "LW"),
    ("ST", "ST"), ("GK", "GK"), ("RCB", "CB"), ("LB", "LB"), ("RDM", "CDM"),
    ("RW", "RW"), ("LW", "LW"), ("ST", "ST"),
]

STUB_COLORS = [
    "#1f4e79", "#7a1f1f", "#1d5c3a", "#5b3a86", "#8a5a00", "#0f5f6e",
    "#4a4a4a", "#7a2f5a", "#2f5d1f", "#63391f", "#1f3f7a", "#6e1f3f",
]


## The band each cup stub's squad was authored at, keyed by the stub's own tier.
## `cup_seed_data` carries the same ladder per club; this is the fallback a club
## with no entry still needs.
STUB_TIER_BASE = {3: 65.0, 4: 60.0, 5: 57.0, 6: 55.0}


def _stub_club(cup_id: str, country: str, name: str, abbr: str, city: str,
               tier: int, region: str, band: int, pool: dict | None = None) -> dict:
    digest = hashlib.sha1(name.encode("utf-8")).hexdigest()
    h = int(digest[:8], 16)
    color = STUB_COLORS[h % len(STUB_COLORS)]
    ground = {"England": "Park", "Germany": "Stadion", "Spain": "Municipal",
              "Italy": "Stadio"}.get(country, "Stadium")
    style = {k: round(0.5 + _jitter(name + k, 12) / 100.0, 2) for k in STYLE_KEYS}
    return {
        "id": f"STUB-{name}",
        "name": name, "short": city, "abbr": abbr, "nickname": "", "manager": "",
        "stadium": f"{city} {ground}", "city": city,
        "capacity": 2500 + (h % 12) * 500, "formation": "4-4-2",
        "color": color, "color_dark": _shade(color, 0.62), "color_light": _shade(color, 1.35),
        "shorts": "#ffffff", "gk_color": "#1a1a1a", "text": _ink(color),
        "style": style,
        "players": _stub_squad(country, name, band, pool),
        "competition_id": cup_id, "country": country,
        "stub": 1, "tier": tier, "region": region,
    }


def _stub_squad(country: str, club_name: str, band: int,
                pool: dict | None = None) -> list[dict]:
    pool = pool or NAME_POOLS[country]
    players: list[dict] = []
    used: set[str] = set()
    for i, (role, pos) in enumerate(STUB_ROLES):
        first = pool["first"][(i * 5 + len(club_name)) % len(pool["first"])]
        last_index = (i * 7 + len(club_name)) % len(pool["last"])
        player_name = f"{first} {pool['last'][last_index]}"
        step = 1
        while player_name in used:
            last_index = (last_index + 1) % len(pool["last"])
            player_name = f"{first} {pool['last'][last_index]}"
            step += 1
            if step > len(pool["last"]):
                player_name = f"{first} {pool['last'][last_index]}-{i}"
        used.add(player_name)
        base = band + (1.5 if i < 11 else -3.0)
        subs = fc_ratings.synthesize(base, role, _wobble(player_name + club_name))
        attrs = _card_from_subs(subs, role)
        players.append({
            "id": f"{club_name}-{i + 1}-{player_name}",
            "name": player_name, "number": i + 1, "role": role, "pos": pos,
            "height": 172 + _jitter(club_name + player_name, 8),
            "squad": "starter" if i < 11 else "bench",
            "age": 19 + (int(hashlib.sha1(f"{club_name}{player_name}".encode()).hexdigest()[:4], 16) % 16),
            "nationality": country, "date_of_birth": "",
            "subs": subs, "club_base": float(base),
            "extras": {
                "potential": 0, "weak_foot": 0, "skill_moves": 0, "work_rate": "",
                "play_styles": "", "traits": "", "international_reputation": 1,
            },
            "ratings_matched": 0,
            **attrs,
        })
    return players


def _stub_rows() -> list[tuple[str, str, list]]:
    return [
        ("England", "FAC", ENGLISH_STUBS),
        ("Germany", "DFBP", GERMAN_STUBS),
        ("Spain", "CDR", SPANISH_STUBS),
        ("Italy", "CI", ITALIAN_STUBS),
    ]


def _club_index(snapshot: dict) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for club in snapshot["clubs"]:
        name = str(club["name"])
        if name in out and str(out[name].get("competition_id", "")) != str(club.get("competition_id", "")):
            out[name] = club
            continue
        out.setdefault(name, club)
        out[name] = club
    return out


def _entry_members(snapshot: dict) -> list[dict]:
    """The cup entry list: one row per (cup, club), role = the round it enters."""
    by_name = _club_index(snapshot)
    by_comp: dict[str, list[dict]] = {}
    for club in snapshot["clubs"]:
        by_comp.setdefault(str(club.get("competition_id", "")), []).append(club)
    members: list[dict] = []

    def add(cup_id: str, club: dict, role: str) -> None:
        members.append({"competition_id": cup_id, "member_id": str(club["id"]), "role": role})

    def club_of(competition_id: str, name: str) -> dict:
        for candidate in by_comp.get(competition_id, []):
            if str(candidate["name"]) == name:
                return candidate
        if name in by_name:
            return by_name[name]
        raise SystemExit(f"cup entrant {name} is not in the {competition_id} pool")

    for cid in ("L1", "L2", "NL"):
        for club_row in by_comp.get(cid, []):
            add("FAC", club_row, "R1")
    for cid in ("PL", "CH"):
        for club_row in by_comp.get(cid, []):
            add("FAC", club_row, "R3")
    for club_row in by_comp.get("FAC", []):
        add("FAC", club_row, "R1")

    table = {str(r["club_id"]): int(r["position"]) for r in snapshot.get("table", [])
             if str(r.get("competition_id", "")) == "L2"}
    for club_row in by_comp.get("L2", []):
        add("EFLC", club_row, "PR" if table.get(str(club_row["id"]), 99) >= 21 else "R1")
    for cid in ("L1", "CH"):
        for club_row in by_comp.get(cid, []):
            add("EFLC", club_row, "R1")
    for club_row in by_comp.get("PL", []):
        add("EFLC", club_row, "R3" if str(club_row["name"]) in PL_EUROPE else "R2")

    supercopa = set(PRIORS["SCE"]["entrants"])
    for club_row in by_comp.get("LL", []):
        add("CDR", club_row, "R32" if str(club_row["name"]) in supercopa else "R1")
    for club_row in by_comp.get("CDR", []):
        add("CDR", club_row, "PR" if int(club_row.get("tier", 4)) >= 5 else "R1")

    for cid in ("BL", "BL2"):
        for club_row in by_comp.get(cid, []):
            add("DFBP", club_row, "R1")
    for club_row in by_comp.get("DFBP", []):
        add("DFBP", club_row, "R1")

    ci_preliminary = set(CI_PRELIMINARY)
    ci_seeded = set(CI_SEEDS)
    for club_row in by_comp.get("SB", []):
        add("CI", club_row, "PR" if str(club_row["name"]) in ci_preliminary else "R1")
    for club_row in by_comp.get("SA", []):
        add("CI", club_row, "R16" if str(club_row["name"]) in ci_seeded else "R1")
    for club_row in by_comp.get("CI", []):
        add("CI", club_row, "PR")

    for name in PRIORS["CS"]["entrants"]:
        add("CS", club_of("PL", name), "F")
    for name in PRIORS["DFLS"]["entrants"]:
        add("DFLS", club_of("BL", name), "F")
    for name in PRIORS["SCE"]["entrants"]:
        add("SCE", club_of("LL", name), "SF")
    for name in PRIORS["SCI"]["entrants"]:
        add("SCI", club_of("SA", name), "F")
    return members


def seed_cups(snapshot: dict) -> dict:
    """Add the cup catalogue, its stubs, entry membership and priors."""
    for cid, spec in CUPS.items():
        row = {
            "id": cid, "name": spec["name"], "short_name": spec["short_name"],
            "country": spec["country"], "espn": "",
            "rules": dict(spec["rules"], kind=spec["kind"]),
        }
        existing = next((c for c in snapshot["competitions"] if str(c["id"]) == cid), None)
        if existing is None:
            snapshot["competitions"].append(row)
        else:
            existing.update(row)

    for club in snapshot["clubs"]:
        if int(club.get("stub", 0)):
            continue
        cid = str(club.get("competition_id", ""))
        city = str(club.get("city", ""))
        if cid in ("PL", "CH", "L1", "L2", "NL"):
            club["region"] = "north" if city in NORTH_CITIES else "south"
            if str(club.get("name", "")) == "Barnsley":
                club["region"] = "north"
        elif cid in ("LL", "LL2"):
            club["region"] = "north" if city in SPANISH_NORTH else "south"

    ## Drop only the cup catalogue's own stale stubs: a stub owned by another
    ## seed command (the UEFA entry lists) is not the cups' business.
    wanted = {row[0] for _, _, rows in _stub_rows() for row in rows}
    snapshot["clubs"] = [
        c for c in snapshot["clubs"]
        if not (int(c.get("stub", 0)) == 1
                and str(c.get("competition_id", "")) in CUPS
                and str(c["name"]) not in wanted)
    ]
    present = {str(c["name"]) for c in snapshot["clubs"]}
    for country, cup_id, rows in _stub_rows():
        for name, abbr, city, tier, region, band in rows:
            if name in present:
                continue
            snapshot["clubs"].append(_stub_club(cup_id, country, name, abbr, city, tier, region, band))
            present.add(name)

    ## The domestic pools are rebuilt from scratch; every other membership
    ## (the UEFA entry lists) belongs to its own seed command and is kept.
    kept = [m for m in snapshot.get("members", [])
            if str(m.get("competition_id", "")) not in CUPS]
    snapshot["members"] = kept + _entry_members(snapshot)
    snapshot["season_label"] = snapshot.get("season_label", "2026-27")
    return snapshot


def _pin_supercopa(snapshot: dict) -> None:
    by_name = _club_index(snapshot)
    for comp in snapshot["competitions"]:
        if str(comp["id"]) != "SCE":
            continue
        pairs = [[str(by_name[name]["id"]) for name in pair] for pair in PRIORS["SCE"]["semi_finals"]]
        comp["rules"]["semi_finals"] = pairs


def cmd_seed_cups(args: argparse.Namespace) -> int:
    snapshot = load(args.snapshot)
    snapshot = upgrade(snapshot)
    seed_cups(snapshot)
    snapshot = remap_ids(snapshot)
    _pin_supercopa(snapshot)
    snapshot["db_version"] = int(snapshot.get("db_version", 1)) + (1 if args.bump_version else 0)
    snapshot["schema_version"] = SCHEMA_VERSION
    save(args.snapshot, snapshot)
    for cid in CUPS:
        roles: dict[str, int] = {}
        for row in snapshot["members"]:
            if row["competition_id"] == cid:
                roles[row["role"]] = roles.get(row["role"], 0) + 1
        print(f"{cid}: {sum(roles.values())} entrants {roles}")
    return 0


def _uefa_stub_club(competition_id: str, iso: str, name: str, abbr: str, city: str,
                    band: int) -> dict:
    """A continental entrant's identity: no licensed squad, a playable band."""
    club = _stub_club(competition_id, "England", name, abbr, city, 1, "", band,
                      pool=STUB_NAMES)
    club["id"] = f"STUB-{name}"
    club["competition_id"] = competition_id
    club["country"] = iso
    club["stadium"] = f"{city} Stadium"
    club["capacity"] = 8000 + (int(hashlib.sha1(name.encode()).hexdigest()[:4], 16) % 24) * 1000
    for player in club["players"]:
        player["nationality"] = iso
    return club


def _uefa_members(snapshot: dict) -> list[dict]:
    """One row per (competition, club) with role = the round the club enters."""
    by_name: dict[str, dict] = {}
    for club in snapshot["clubs"]:
        by_name.setdefault(str(club.get("name", "")), club)
    members: list[dict] = []
    problems: list[str] = []
    for cid, rounds in UEFA_ENTRANTS.items():
        for round_id, entrants in rounds.items():
            for iso, name in entrants:
                key = UEFA_ALIASES.get(name, name)
                club = by_name.get(key)
                if club is None:
                    problems.append(f"{cid} {round_id}: {iso} {name} has no club")
                    continue
                members.append({"competition_id": cid, "member_id": str(club["id"]),
                                "role": round_id})
    if problems:
        raise SystemExit("UEFA entrants unresolved:\n  " + "\n  ".join(problems[:20]))
    return members


def _uefa_bands(snapshot: dict) -> dict[str, int]:
    """Mint every continental entrant's frozen coefficient band, once.

    The band is the pot the seed would have put the club in: the top nine
    entrants are band 1, the next nine band 2, the next nine band 3, and the rest
    band 4. The draw never reads squad strength again: a club keeps this band
    across seasons, and a later entrant inherits its association's median band
    when it has none of its own.
    """
    by_id = {str(club["id"]): club for club in snapshot["clubs"]}
    bands: dict[str, int] = {}
    for cid in UEFA_COMPETITIONS:
        entrants = sorted({str(row["member_id"]) for row in snapshot["members"]
                           if str(row["competition_id"]) == cid})
        ranked: list[tuple[float, str, str]] = []
        for club_id in entrants:
            club = by_id.get(club_id)
            if club is None:
                continue
            ovr = [float(p.get("ovr", 0)) for p in club.get("players", [])
                   if p.get("squad") == "starter"]
            strength = sum(ovr) / max(len(ovr), 1)
            ranked.append((strength, str(club.get("name", "")), club_id))
        ranked.sort(key=lambda row: (-row[0], row[1]))
        for index, (_, _, club_id) in enumerate(ranked):
            bands.setdefault(club_id, min(4, 1 + index // 9))
    return bands


def _uefa_access_rules(snapshot: dict) -> None:
    """Freeze the access-list shape and the pot bands into each competition's rules."""
    by_id = {str(club["id"]): club for club in snapshot["clubs"]}
    bands = _uefa_bands(snapshot)
    for cid in UEFA_COMPETITIONS:
        comp = next((c for c in snapshot["competitions"] if str(c["id"]) == cid), None)
        if comp is None:
            continue
        shape: dict[str, dict[str, int]] = {}
        for row in snapshot["members"]:
            if str(row["competition_id"]) != cid:
                continue
            club = by_id.get(str(row["member_id"]), {})
            iso = str(club.get("country", ""))
            if iso == "":
                continue
            counted = shape.setdefault(iso, {})
            role = str(row.get("role", ""))
            counted[role] = counted.get(role, 0) + 1
        shaped: dict[str, dict[str, list]] = {}
        for iso, access in UEFA_ACCESS.items():
            for round_id, slots in access.get(cid, {}).items():
                got = int(shape.get(iso, {}).get(round_id, 0))
                if got != len(slots):
                    raise SystemExit(
                        f"{cid} {iso} {round_id}: the entry list holds {got} places, "
                        f"the access list names {len(slots)}")
            shaped[iso] = access[cid]
        comp["rules"]["shape"] = shape
        comp["rules"]["access"] = shaped
        comp["rules"]["pot_bands"] = dict(bands)
        comp["rules"]["leagues"] = dict(UEFA_ASSOCIATION_LEAGUE)


def seed_uefa(snapshot: dict) -> dict:
    """Add the three continental competitions, their stubs and entry membership."""
    for cid, spec in UEFA_COMPETITIONS.items():
        row = {
            "id": cid, "name": spec["name"], "short_name": spec["short_name"],
            "country": spec["country"], "espn": "",
            "rules": dict(spec["rules"], kind=spec["kind"]),
        }
        existing = next((c for c in snapshot["competitions"] if str(c["id"]) == cid), None)
        if existing is None:
            snapshot["competitions"].append(row)
        else:
            existing.update(row)
    wanted = {name: (abbr, city, band, iso) for name, abbr, city, band, iso in UEFA_STUBS}
    entry_of: dict[str, str] = {}
    for cid, rounds in UEFA_ENTRANTS.items():
        for entrants in rounds.values():
            for _, name in entrants:
                entry_of.setdefault(name, cid)
    by_name = {str(c.get("name", "")): c for c in snapshot["clubs"]}
    for name, (abbr, city, band, iso) in wanted.items():
        existing = by_name.get(name)
        if existing is not None and int(existing.get("stub", 0)) == 0:
            continue
        cid = entry_of.get(name, "UCL")
        club = _uefa_stub_club(cid, iso, name, abbr, city, band)
        if existing is not None:
            snapshot["clubs"].remove(existing)
        snapshot["clubs"].append(club)
        by_name[name] = club
    kept = [m for m in snapshot.get("members", [])
            if str(m.get("competition_id", "")) not in UEFA_COMPETITIONS]
    snapshot["members"] = kept + _uefa_members(snapshot)
    return snapshot


def cmd_seed_uefa(args: argparse.Namespace) -> int:
    snapshot = load(args.snapshot)
    snapshot = upgrade(snapshot)
    seed_uefa(snapshot)
    snapshot = remap_ids(snapshot)
    _uefa_access_rules(snapshot)
    snapshot["db_version"] = int(snapshot.get("db_version", 1)) + (1 if args.bump_version else 0)
    snapshot["schema_version"] = SCHEMA_VERSION
    save(args.snapshot, snapshot)
    for cid in UEFA_COMPETITIONS:
        roles: dict[str, int] = {}
        for row in snapshot["members"]:
            if row["competition_id"] == cid:
                roles[row["role"]] = roles.get(row["role"], 0) + 1
        print(f"{cid}: {sum(roles.values())} entrants {roles}")
    return 0


def cmd_seed(args: argparse.Namespace) -> int:
    snapshot = load(args.snapshot)
    targets = list(COMPETITIONS) if args.competition == "all" else [args.competition]
    snapshot["season_label"] = f"{args.season}-{str(args.season + 1)[2:]}"
    for cid in targets:
        spec = spec_for(cid)
        snapshot = upgrade(snapshot)
        if not any(str(c.get("id")) == cid for c in snapshot["competitions"]):
            snapshot["competitions"].append({
                "id": cid, "name": spec["name"], "short_name": spec["short_name"],
                "country": spec["country"], "espn": spec["espn"], "rules": spec["rules"],
            })
        seed_competition(cid, args.season, snapshot)
        print(f"seeded {cid}: {len(comp_clubs(snapshot, cid))} clubs")
    snapshot = remap_ids(snapshot)
    snapshot["db_version"] = int(snapshot.get("db_version", 1)) + (1 if args.bump_version else 0)
    snapshot["schema_version"] = SCHEMA_VERSION
    save(args.snapshot, snapshot)
    return 0


def cmd_fetch(args: argparse.Namespace) -> int:
    if args.source != SOURCE_ESPN:
        raise SystemExit("only --source espn is implemented; do not mix sources in one run")
    snapshot = load(args.snapshot)
    targets = list(COMPETITIONS) if args.competition == "all" else [args.competition]
    snapshot["source"] = "ESPN"
    snapshot["snapshot_date"] = args.date or time.strftime("%Y-%m-%d", time.gmtime())
    snapshot["season_label"] = f"{args.season}-{str(args.season + 1)[2:]}"
    for cid in targets:
        need = CLUB_COUNTS[cid]
        if len(comp_clubs(snapshot, cid)) < need:
            raise SystemExit(f"{cid} has no seeded clubs; run seed --competition {cid} first")
        espn_ids = fetch_table(cid, args.season, snapshot)
        if len(espn_ids) < need:
            raise SystemExit(f"ESPN standings covered {len(espn_ids)} {cid} clubs; expected {need}")
        fixtures = fetch_fixtures(cid, args.season, espn_ids)
        others = [fx for fx in snapshot.get("fixtures", [])
                  if str(fx.get("competition_id", "PL")) != cid]
        snapshot["fixtures"] = others + fixtures
        fetch_players(cid, args.season, snapshot, espn_ids)
        print(f"fetched {cid}: {len(fixtures)} fixtures")
    snapshot = remap_ids(snapshot)
    snapshot["db_version"] = int(snapshot.get("db_version", 1)) + (1 if args.bump_version else 0)
    snapshot["schema_version"] = SCHEMA_VERSION
    save(args.snapshot, snapshot)
    print(
        f"snapshot {snapshot['season_label']}: {len(snapshot['table'])} table rows, "
        f"{len(snapshot['fixtures'])} fixtures, {len(snapshot['season_stats'])} season stat lines, "
        f"db_version {snapshot['db_version']}"
    )
    return 0


# ----------------------------------------------------------------- ratings --


def slug_name(name: str) -> str:
    return " ".join(slug(name).split("-"))


def sheet_rows(path: Path = RATINGS_SHEET) -> list[dict]:
    """Read the ratings sheet (the Sofifa-sourced FC card export)."""
    if not path.exists():
        raise SystemExit(
            f"missing the ratings sheet at {path.relative_to(ROOT)}; "
            "export it with the Sofifa scrape (see docs/data.md) and commit it"
        )
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _sheet_int(row: dict, column: str) -> int | None:
    raw = (row.get(column) or "").strip()
    if raw in ("", "nan"):
        return None
    try:
        return int(float(raw.split("+")[0]))
    except ValueError:
        return None


def sheet_player(row: dict) -> dict | None:
    """One sheet row as sub-stats plus card extras, or None if it is short."""
    subs: dict[str, int] = {}
    for key, column in SHEET_COLUMNS.items():
        value = _sheet_int(row, column)
        if value is None:
            return None
        subs[key] = value
    extras = {
        "potential": _sheet_int(row, "potential") or 0,
        "weak_foot": _sheet_int(row, "weak_foot") or 0,
        "skill_moves": _sheet_int(row, "skill_moves") or 0,
        "work_rate": str(row.get("work_rate") or "").strip(),
        "play_styles": str(row.get("player_tags") or "").replace("\xa0", " ").strip(),
        "traits": str(row.get("player_traits") or "").strip(),
        "international_reputation": _sheet_int(row, "international_reputation") or 1,
    }
    positions = [
        part.strip().upper()
        for part in str(row.get("player_positions") or "").split(",")
        if part.strip()
    ]
    return {
        "player_id": str(row.get("player_id") or ""),
        "subs": subs,
        "extras": extras,
        "positions": positions,
        "overall": _sheet_int(row, "overall") or 0,
        "club": str(row.get("club_name") or "").strip(),
        "short_name": str(row.get("short_name") or "").strip(),
        "long_name": str(row.get("long_name") or "").strip(),
        "dob": str(row.get("dob") or "").strip(),
    }


def _name_key(text: str) -> str:
    return slug_name(text).replace(" ", "")


def _surname_initial(text: str) -> tuple[str, str]:
    words = slug_name(text).split()
    if not words:
        return "", ""
    return words[-1], (words[0][0] if len(words) > 1 else "")


def match_club(club: dict, by_club: dict[str, list[dict]]) -> str:
    """The sheet club name a shipped club's squad is read from."""
    wanted = CLUB_ALIASES.get(str(club["name"]), str(club["name"]))
    key = slug_name(wanted)
    if key in by_club:
        return key
    return ""


def remap_ratings(snapshot: dict, sheet: list[dict]) -> dict:
    """Derive every player's card from a sub-stat sheet; synthesize the rest."""
    by_club: dict[str, list[dict]] = {}
    by_dob: dict[str, list[dict]] = {}
    by_name: dict[str, list[dict]] = {}
    parsed: list[dict] = []
    for row in sheet:
        entry = sheet_player(row)
        if entry is None:
            continue
        parsed.append(entry)
        if entry["club"]:
            by_club.setdefault(slug_name(entry["club"]), []).append(entry)
        if entry["dob"]:
            by_dob.setdefault(entry["dob"], []).append(entry)
        by_name.setdefault(_name_key(entry["short_name"]), []).append(entry)
    if not parsed:
        raise SystemExit("the ratings sheet carried no usable player row")

    taken: set[str] = set()
    assigned: dict[str, dict] = {}
    matched: dict[str, int] = {}
    totals: dict[str, int] = {}
    xi_matched: dict[str, int] = {}
    xi_totals: dict[str, int] = {}
    squad_rows: list[tuple[dict, list[dict]]] = []
    for club in snapshot["clubs"]:
        competition_id = str(club.get("competition_id", "PL"))
        key = match_club(club, by_club)
        options = by_club.get(key, []) if key else []
        if int(club.get("stub", 0)):
            options = []
        squad_rows.append((club, options))
        for player in club["players"]:
            starter = str(player.get("squad")) != "bench"
            totals[competition_id] = totals.get(competition_id, 0) + 1
            if starter:
                xi_totals[competition_id] = xi_totals.get(competition_id, 0) + 1
    for club, options in squad_rows:
        for player in club["players"]:
            row = _lookup_local(player, options, taken)
            if row is not None:
                taken.add(row["player_id"])
                assigned[str(player["id"])] = row
    for club, options in squad_rows:
        if int(club.get("stub", 0)):
            continue
        for player in club["players"]:
            if str(player["id"]) in assigned:
                continue
            row = _lookup_anywhere(player, by_dob, by_name, taken)
            if row is not None:
                taken.add(row["player_id"])
                assigned[str(player["id"])] = row
    for club, options in squad_rows:
        competition_id = str(club.get("competition_id", "PL"))
        for player in club["players"]:
            starter = str(player.get("squad")) != "bench"
            row = assigned.get(str(player["id"]))
            role = str(player["role"])
            if row is not None:
                player["subs"] = row["subs"]
                player["extras"] = row["extras"]
                player["ratings_matched"] = 1
                intl_rep = int(row["extras"]["international_reputation"])
                matched[competition_id] = matched.get(competition_id, 0) + 1
                if starter:
                    xi_matched[competition_id] = xi_matched.get(competition_id, 0) + 1
            else:
                authored = player.get("subs") if int(club.get("stub", 0)) else None
                if authored:
                    player["subs"] = authored
                else:
                    club_base = float(player.get("club_base", 0.0)) or _club_base(snapshot, club)
                    player["club_base"] = club_base
                    player["subs"] = fc_ratings.synthesize(
                        club_base, role, _wobble(str(player["name"])))
                player["extras"] = {
                    "potential": 0, "weak_foot": 0, "skill_moves": 0, "work_rate": "",
                    "play_styles": "", "traits": "", "international_reputation": 1,
                }
                player["ratings_matched"] = 0
                intl_rep = 1
            card = _card_from_subs(player["subs"], role, intl_rep)
            for attr in PLAYER_ATTRS:
                player[attr] = int(card[attr])
            player["gk"] = card["gk"]
    return {
        "matched": matched,
        "totals": totals,
        "xi_matched": xi_matched,
        "xi_totals": xi_totals,
        "cover": {
            cid: (matched.get(cid, 0) / totals[cid] if totals.get(cid) else 0.0)
            for cid in totals
        },
        "xi_cover": {
            cid: (xi_matched.get(cid, 0) / xi_totals[cid] if xi_totals.get(cid) else 0.0)
            for cid in xi_totals
        },
    }


def _same_person(player: dict, row: dict) -> bool:
    """Two dates of birth that disagree are two different footballers."""
    dob = str(player.get("date_of_birth", ""))
    if dob and row["dob"] and dob != row["dob"]:
        return False
    return True


def _card_fits(player: dict, row: dict) -> bool:
    """Does this sheet person's card plausibly derive to the role this squad lists?

    The identity check that survives a coincidental birthday: derive the card
    from the row's sub-stats under this player's own role and compare it with the
    overall the sheet printed. A defender handed a striker's sheet derives a
    dozen points short, so the pair cannot be the same man.
    """
    printed = int(row.get("overall") or 0)
    if printed <= 0:
        return True
    role = str(player.get("role", ""))
    return abs(fc_ratings.overall(row["subs"], role, 1) - printed) <= 5


def _same_line(player: dict, row: dict) -> bool:
    return compatible(str(player.get("role", "")), row["positions"])


def _surname_open(player: dict, row: dict) -> bool:
    surname, initial = _surname_initial(str(player["name"]))
    other_surname, other_initial = _surname_initial(row["short_name"])
    if other_surname != surname:
        return False
    return initial == "" or other_initial == initial


def _lookup_local(player: dict, options: list[dict], taken: set[str]) -> dict | None:
    """The row in this club's own squad that is this player, if any.

    A squad-level birthday is the strongest reading there is; then the printed
    name; then a surname and initial that this club carries exactly once. Every
    candidate has to read as this player's line of the pitch.
    """
    dob = str(player.get("date_of_birth", ""))
    if dob:
        found = _free(
            [row for row in options if row["dob"] == dob and _same_line(player, row)], taken)
        if found is not None:
            return found
    key = _name_key(str(player["name"]))
    found = _free(
        [row for row in options
         if _name_key(row["short_name"]) == key and _same_line(player, row)], taken)
    if found is not None:
        return found
    if _surname_initial(str(player["name"]))[0] == "":
        return None
    surnames = [row for row in options if _surname_open(player, row) and _same_line(player, row)]
    return _free(surnames, taken) if len(surnames) == 1 else None


def _lookup_anywhere(
    player: dict,
    by_dob: dict[str, list[dict]],
    by_name: dict[str, list[dict]],
    taken: set[str],
) -> dict | None:
    """A sheet row for a player this club does not carry — a transfer, usually.

    Name first: a printed name is that man. Then the birthday, read only where a
    surname or the card itself corroborates the role — a shared birthday alone has
    already handed a centre-back a winger's sheet in this repo. Last, a surname
    and initial the whole sheet carries exactly once.
    """
    key = _name_key(str(player["name"]))
    dob = str(player.get("date_of_birth", ""))
    named = [row for row in by_name.get(key, [])
             if _same_line(player, row)]
    if named:
        same_dob = [row for row in named if dob and row["dob"] == dob]
        return _free(same_dob, taken) if same_dob else _free(named, taken)
    if dob:
        born = [row for row in by_dob.get(dob, []) if _same_line(player, row)]
        named_born = [row for row in born if _surname_open(player, row)]
        found = _free(named_born, taken) if named_born else _free(
            [row for row in born if _card_fits(player, row)], taken)
        if found is not None:
            return found
    if _surname_initial(str(player["name"]))[0] == "":
        return None
    near = [
        row for rows in by_name.values() for row in rows
        if _surname_open(player, row) and _same_line(player, row)
    ]
    if len(near) == 1:
        return _free(near, taken)
    return None


def _free(rows: list[dict], taken: set[str]) -> dict | None:
    for row in rows:
        if row["player_id"] not in taken:
            return row
    return None


def _club_base(snapshot: dict, club: dict) -> float:
    """The strength band a synthesized squad sits in, from its table place.

    A cup stub never sits in a shipped table, so its place cannot answer; its
    tier does. The bands are the ones the stub squads were authored at, read off
    `cup_seed_data`'s own ladder, so a fifth-tier cup entry does not come out
    stronger than the League One side it plays.
    """
    rows = [r for r in snapshot.get("table", [])
            if str(r.get("club_id", "")) == str(club["id"])]
    place = int(rows[0]["position"]) if rows else 0
    if place <= 0:
        if int(club.get("stub", 0)):
            return float(STUB_TIER_BASE.get(int(club.get("tier", 5)), 57.0))
        return 76.0
    size = max(CLUB_COUNTS.get(str(club.get("competition_id", "PL")), 20), 2)
    high, low = 80.0, 66.0
    return high - float(place - 1) * ((high - low) / float(size - 1))


def cmd_ratings(args: argparse.Namespace) -> int:
    snapshot = load(args.snapshot)
    sheet = sheet_rows(Path(args.sheet))
    report = remap_ratings(snapshot, sheet)
    snapshot["ratings_source"] = (
        "Sofifa-sourced EA FC 26 player sheet "
        f"({Path(args.sheet).name}), every card derived from sub-stats"
    )
    snapshot["db_version"] = int(snapshot.get("db_version", 1)) + (1 if args.bump_version else 0)
    snapshot["schema_version"] = SCHEMA_VERSION
    save(args.snapshot, snapshot)
    for competition_id in sorted(report["totals"]):
        cover = report["cover"][competition_id]
        xi = report["xi_cover"].get(competition_id, 0.0)
        print(
            f"ratings {competition_id}: XI {report['xi_matched'].get(competition_id, 0)}"
            f"/{report['xi_totals'].get(competition_id, 0)} ({xi:.1%}), "
            f"squad {report['matched'].get(competition_id, 0)}"
            f"/{report['totals'][competition_id]} ({cover:.1%})"
        )
    short = [
        f"{cid} XI {report['xi_cover'].get(cid, 0.0):.1%} < {gate:.0%}"
        for cid, gate in RATINGS_GATE.items()
        if report["xi_cover"].get(cid, 0.0) < gate
    ]
    if short:
        print("FAIL the top leagues' XIs did not reach the match gate: " + ", ".join(short),
              file=sys.stderr)
        return 1
    print(f"ratings: {len(sheet)} sheet rows, db_version {snapshot['db_version']}")
    return 0


# -------------------------------------------------------------------- build --


def build_db(snapshot: dict) -> dict:
    competitions = snapshot["competitions"]
    primary = competitions[0]
    meta = {
        "schema_version": str(SCHEMA_VERSION),
        "db_version": str(snapshot["db_version"]),
        "season_label": snapshot["season_label"],
        "snapshot_date": snapshot["snapshot_date"],
        "source": snapshot["source"],
        "ratings_source": snapshot.get("ratings_source", ""),
        "league_name": primary["name"],
        "competition_ids": ",".join(str(c["id"]) for c in competitions),
        "referee": snapshot.get("referee", ""),
    }
    SEED_DB.unlink(missing_ok=True)
    con = sqlite3.connect(SEED_DB)
    con.executescript(SCHEMA)
    con.executemany("INSERT INTO metadata VALUES (?, ?)", meta.items())
    for comp in competitions:
        con.execute(
            "INSERT INTO competition (id, name, short_name, season_label, country, rules) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (comp["id"], comp["name"], comp["short_name"], snapshot["season_label"],
             comp.get("country", ""), json.dumps(comp.get("rules", {}), sort_keys=True)),
        )
    for club in snapshot["clubs"]:
        comp_id = str(club.get("competition_id", primary["id"]))
        style = club.get("style", {})
        con.execute(
            "INSERT INTO club VALUES (" + ",".join("?" * 30) + ")",
            (
                club["id"], comp_id, str(club.get("country", "")),
                club["name"], club["short"], club["abbr"],
                club.get("nickname", ""), club.get("manager", ""), club["stadium"],
                club["city"], int(club["capacity"]), club["formation"],
                club["color"], club["color_dark"], club["color_light"],
                club["shorts"], club["gk_color"], club["text"],
                *[float(style.get(k, 0.5)) for k in STYLE_KEYS],
                int(club.get("stub", 0)), int(club.get("tier", 0)), str(club.get("region", "")),
                str(club.get("reserve_of", "")),
            ),
        )
        if not int(club.get("stub", 0)):
            con.execute(
                "INSERT INTO competition_member (competition_id, member_kind, member_id, role) "
                "VALUES (?, 'club', ?, 'member');", (comp_id, club["id"]))
        for ord, p in enumerate(club["players"]):
            gk = p.get("gk") or {}
            con.execute(
                "INSERT INTO player VALUES (" + ",".join("?" * 28) + ")",
                (
                    p["id"], club["id"], p["name"], int(p["number"]), p["role"], p["pos"],
                    *[int(p[a]) for a in PLAYER_ATTRS], int(p.get("height", 180)),
                    *[int(gk.get(a, 30)) if gk else None for a in GK_ATTRS],
                    p["squad"], ord, p.get("espn_id"), int(p.get("age", 0) or 0),
                    p.get("nationality", ""), p.get("date_of_birth", ""),
                    json.dumps(p.get("subs", {}), sort_keys=True),
                    json.dumps(p.get("extras", {}), sort_keys=True),
                    1 if p.get("ratings_matched") else 0,
                ),
            )
            con.execute(
                "INSERT OR IGNORE INTO competition_member (competition_id, member_kind, member_id, role) "
                "VALUES (?, 'player', ?, 'player');", (comp_id, p["id"]))
    for member in snapshot.get("members", []):
        con.execute(
            "INSERT OR IGNORE INTO competition_member (competition_id, member_kind, member_id, role) "
            "VALUES (?, 'club', ?, ?);",
            (str(member["competition_id"]), str(member["member_id"]), str(member.get("role", "member"))),
        )
    for row in snapshot.get("table", []):
        comp_id = str(row.get("competition_id", primary["id"]))
        con.execute(
            "INSERT INTO table_row VALUES (?,?,?,?,?,?,?,?,?,?)",
            (row["club_id"], comp_id, row["position"], row["played"], row["won"],
             row["drawn"], row["lost"], row["gf"], row["ga"], row["points"]),
        )
    for fx in snapshot.get("fixtures", []):
        comp_id = str(fx.get("competition_id", primary["id"]))
        con.execute(
            "INSERT INTO fixture VALUES (?,?,?,?,?,?,?,?,?)",
            (fx["id"], comp_id, fx["matchday"], fx["kickoff"], fx["home"], fx["away"],
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
    comps = con.execute("SELECT COUNT(*) FROM competition").fetchone()[0]
    con.close()
    return {"clubs": clubs, "players": players, "competitions": comps, "bytes": SEED_DB.stat().st_size}


def cmd_build(args: argparse.Namespace) -> int:
    snapshot = load(args.snapshot)
    summary = build_db(snapshot)
    print(
        f"seed {SEED_DB.relative_to(ROOT)}: {summary['competitions']} competitions, "
        f"{summary['clubs']} clubs, {summary['players']} players, {summary['bytes']} bytes, "
        f"db_version {snapshot['db_version']}"
    )
    return 0


def remap_ids(snapshot: dict) -> dict:
    """Mint the ids the seed ships: country-stable clubs, UUID players.

    One-time and idempotent: a club or player that already carries a valid id
    keeps it, so running the command twice changes nothing. New ids are minted
    in competition-then-club-name order so the same clubs always get the same
    suffixes.
    """
    order = {cid: i for i, cid in enumerate(COMPETITIONS)}
    clubs = snapshot["clubs"]

    def by_club(club: dict) -> tuple[int, str]:
        return (order.get(str(club.get("competition_id", "PL")), len(order)),
                str(club.get("name", "")))

    club_map: dict[str, str] = {}
    taken_clubs: set[str] = set()
    pending: list[dict] = []
    for club in clubs:
        old = str(club["id"])
        if CLUB_ID_RE.match(old):
            club_map[old] = old
            taken_clubs.add(old)
        else:
            pending.append(club)
    for club in sorted(pending, key=by_club):
        cid = str(club.get("competition_id", "PL"))
        minted = club_id_for(cid, str(club["abbr"]), taken_clubs,
                             str(club.get("country", "")))
        club_map[str(club["id"])] = minted
        taken_clubs.add(minted)

    player_map: dict[str, str] = {}
    taken_players: set[str] = set()
    pending_players: list[tuple[dict, dict]] = []
    for club in clubs:
        for player in club["players"]:
            old = str(player["id"])
            if PLAYER_ID_RE.match(old):
                player_map[old] = old
                taken_players.add(old)
            else:
                pending_players.append((club, player))
    for club, player in sorted(pending_players, key=lambda pair: by_club(pair[0])):
        minted = player_id_for(str(player.get("espn_id", "")), str(club["name"]),
                               str(player["name"]), taken_players)
        player_map[str(player["id"])] = minted
        taken_players.add(minted)

    for club in clubs:
        club["id"] = club_map[str(club["id"])]
        club["country"] = club_country(str(club.get("competition_id", "PL")), str(club["abbr"]),
                                       str(club.get("country", "")))
        for player in club["players"]:
            player["id"] = player_map[str(player["id"])]
    for row in snapshot.get("table", []):
        row["club_id"] = club_map.get(str(row["club_id"]), str(row["club_id"]))
    for member in snapshot.get("members", []):
        member["member_id"] = club_map.get(str(member["member_id"]), str(member["member_id"]))
    for fixture in snapshot.get("fixtures", []):
        for side in ("home", "away"):
            fixture[side] = club_map.get(str(fixture[side]), str(fixture[side]))
    # A stat line can outlive its player (a squad trimmed after a refresh). The
    # line still needs a UUID, so it is detached from the old club-embedded id.
    for stat in snapshot.get("season_stats", []):
        stat["player_id"] = _stat_player_id(str(stat["player_id"]), player_map)
    for career in snapshot.get("career", []):
        career["player_id"] = _stat_player_id(str(career["player_id"]), player_map)
    return snapshot


def _stat_player_id(old: str, player_map: dict[str, str]) -> str:
    if old in player_map:
        return player_map[old]
    if PLAYER_ID_RE.match(old):
        return old
    return str(uuid.uuid5(PLAYER_NAMESPACE, f"stat:{old}"))


def cmd_remap(args: argparse.Namespace) -> int:
    snapshot = load(args.snapshot)
    snapshot = remap_ids(snapshot)
    snapshot["db_version"] = int(snapshot.get("db_version", 1)) + (1 if args.bump_version else 0)
    snapshot["schema_version"] = SCHEMA_VERSION
    save(args.snapshot, snapshot)
    clubs = len(snapshot["clubs"])
    players = sum(len(c["players"]) for c in snapshot["clubs"])
    print(f"remapped {clubs} clubs and {players} players; db_version {snapshot['db_version']}")
    return 0


def _audit_ids(snapshot: dict) -> list[str]:
    problems: list[str] = []
    clubs = snapshot["clubs"]
    club_ids = [str(c["id"]) for c in clubs]
    if len(club_ids) != len(set(club_ids)):
        problems.append("club ids collide across competitions")
    for club in clubs:
        club_id = str(club["id"])
        if club_id == str(club.get("abbr", "")):
            problems.append(f"{club_id}: a club id is never a bare abbreviation")
        match = CLUB_ID_RE.match(club_id)
        if match is None:
            problems.append(f"{club_id}: club id is not {{FIFA country}}-{{abbr}}{{N}}")
            continue
        country = club_country(str(club.get("competition_id", "PL")), str(club["abbr"]),
                               str(club.get("country", "")))
        if match.group(1) != country:
            problems.append(f"{club_id}: club id country is not {country}")
        if match.group(2) != str(club.get("abbr", "")):
            problems.append(f"{club_id}: club id does not carry its abbreviation")
    player_ids = [str(p["id"]) for c in clubs for p in c["players"]]
    if len(player_ids) != len(set(player_ids)):
        problems.append("player ids collide across competitions")
    bad_players = [pid for pid in player_ids if not PLAYER_ID_RE.match(pid)]
    if bad_players:
        problems.append(f"{len(bad_players)} player ids are not UUIDs, first {bad_players[0]}")
    fixture_ids = [str(fx["id"]) for fx in snapshot.get("fixtures", [])]
    if len(fixture_ids) != len(set(fixture_ids)):
        problems.append("fixture ids collide across competitions")
    known_clubs = set(club_ids)
    for row in snapshot.get("table", []):
        if str(row["club_id"]) not in known_clubs:
            problems.append(f"table row names an unknown club {row['club_id']}")
    for fixture in snapshot.get("fixtures", []):
        for side in ("home", "away"):
            if str(fixture[side]) not in known_clubs:
                problems.append(f"fixture {fixture['id']} names an unknown club {fixture[side]}")
    bad_stats = [str(stat["player_id"]) for stat in snapshot.get("season_stats", [])
                 + snapshot.get("career", []) if not PLAYER_ID_RE.match(str(stat["player_id"]))]
    if bad_stats:
        problems.append(f"{len(bad_stats)} stat lines carry no UUID player id, first {bad_stats[0]}")
    return problems


def _audit_card(club_id: str, player: dict) -> list[str]:
    """A snapshot player must ship a full sub-stat sheet and a derived card."""
    problems: list[str] = []
    subs = player.get("subs") or {}
    if not subs:
        return [f"{club_id}/{player['id']}: no sub-stat sheet"]
    missing = [key for key in fc_ratings.load_model()["sub_stats"] if key not in subs]
    if missing:
        problems.append(f"{club_id}/{player['id']}: missing sub-stats {', '.join(missing[:4])}")
        return problems
    extras = player.get("extras") or {}
    if int(extras.get("international_reputation", 0)) < 1:
        problems.append(f"{club_id}/{player['id']}: no international reputation")
    card = _card_from_subs(subs, str(player["role"]), int(extras.get("international_reputation", 1)))
    for attr in PLAYER_ATTRS:
        if int(player.get(attr, -1)) != int(card[attr]):
            problems.append(
                f"{club_id}/{player['id']}: {attr} is {player.get(attr)}, "
                f"derived {card[attr]}"
            )
    stored_gk = player.get("gk") or {}
    for bar in GK_ATTRS:
        if int(stored_gk.get(bar, -1)) != int(card["gk"].get(bar, -2)):
            problems.append(f"{club_id}/{player['id']}: gk.{bar} is not derived")
    return problems


def cmd_verify(args: argparse.Namespace) -> int:
    snapshot = load(args.snapshot)
    problems: list[str] = []
    comps = [str(c["id"]) for c in snapshot["competitions"]]
    if SEED_DB.exists():
        con = sqlite3.connect(SEED_DB)
        meta = dict(con.execute("SELECT key, value FROM metadata").fetchall())
        clubs = con.execute("SELECT COUNT(*) FROM club").fetchone()[0]
        players = con.execute("SELECT COUNT(*) FROM player").fetchone()[0]
        starters = con.execute("SELECT COUNT(*) FROM player WHERE squad='starter'").fetchone()[0]
        comp_rows = [r[0] for r in con.execute("SELECT id FROM competition ORDER BY id;").fetchall()]
        memberships = con.execute("SELECT COUNT(*) FROM competition_member;").fetchone()[0]
        con.close()
        if meta.get("db_version") != str(snapshot["db_version"]):
            problems.append("seed db_version does not match the snapshot; run build")
        if meta.get("schema_version") != str(SCHEMA_VERSION):
            problems.append("seed schema_version does not match the tool; run build")
        if clubs != len(snapshot["clubs"]):
            problems.append("club count differs from the snapshot")
        if sorted(comp_rows) != sorted(comps):
            problems.append("competition rows differ from the snapshot")
        if memberships < clubs + players // 2:
            problems.append("competition membership rows are missing")
        if starters != 11 * len(snapshot["clubs"]):
            problems.append("every club must ship eleven starters")
        print(f"seed: {len(comp_rows)} competitions, {clubs} clubs, {players} players, "
              f"starters {starters}, metadata {meta}")
    else:
        problems.append(f"missing {SEED_DB.relative_to(ROOT)}; run build")
    known_clubs = {str(c["id"]) for c in snapshot["clubs"]}
    for cid in comps:
        if cid in UEFA_COMPETITIONS:
            for row in snapshot.get("members", []):
                if str(row.get("competition_id", "")) != cid:
                    continue
                if str(row.get("member_id", "")) not in known_clubs:
                    problems.append(f"{cid}: entry {row.get('member_id', '')} has no club")
            continue
        if cid in CUPS:
            roles: dict[str, int] = {}
            for row in snapshot.get("members", []):
                if str(row.get("competition_id", "")) != cid:
                    continue
                roles[str(row.get("role", ""))] = roles.get(str(row.get("role", "")), 0) + 1
                if str(row.get("member_id", "")) not in known_clubs:
                    problems.append(f"{cid}: entry {row.get('member_id', '')} has no club")
            for role, need in CUPS[cid]["rules"].get("entrants", {}).items():
                if roles.get(role, 0) != need:
                    problems.append(f"{cid}: {roles.get(role, 0)} entrants in {role}, expected {need}")
            if cid in ("CS", "DFLS", "SCE") and CUPS[cid]["rules"].get("entrants"):
                pass
            continue
        need = CLUB_COUNTS.get(cid, 20)
        clubs = comp_clubs(snapshot, cid)
        if len(clubs) != need:
            problems.append(f"{cid}: {len(clubs)} clubs, expected {need}")
        table_rows = [r for r in snapshot.get("table", [])
                      if str(r.get("competition_id", "PL")) == cid]
        if len(table_rows) != need:
            problems.append(f"{cid}: {len(table_rows)} table rows, expected {need}")
        fixtures = [fx for fx in snapshot.get("fixtures", [])
                    if str(fx.get("competition_id", "PL")) == cid]
        expected_fixtures = need * (need - 1)
        if len(fixtures) != expected_fixtures:
            problems.append(f"{cid}: {len(fixtures)} fixtures, expected {expected_fixtures}")
    for club in snapshot["clubs"]:
        ids = [p["id"] for p in club["players"]]
        if len(ids) != len(set(ids)):
            problems.append(f"{club['id']}: duplicate player ids")
        if sum(1 for p in club["players"] if p["squad"] == "starter") != 11:
            problems.append(f"{club['id']}: needs eleven starters")
        senior = str(club.get("reserve_of", ""))
        if senior != "" and senior not in known_clubs:
            problems.append(f"{club['id']}: reserve_of {senior} is not a club")
        for p in club["players"]:
            problems.extend(_audit_card(club["id"], p))
    for abbr in RESERVE_OF.get("LL2", {}):
        for club in snapshot["clubs"]:
            if str(club.get("competition_id", "")) != "LL2" or str(club.get("abbr", "")) != abbr:
                continue
            if str(club.get("reserve_of", "")) == "":
                problems.append(f"{club['id']}: a reserve side with no senior club")
    problems.extend(_audit_ids(snapshot))
    if problems:
        print("\n".join(f"FAIL {p}" for p in problems), file=sys.stderr)
        return 1
    print("verify: OK")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, default=SNAPSHOT)
    sub = parser.add_subparsers(dest="cmd", required=True)
    seed = sub.add_parser("seed", help="create a competition's clubs and squads from ESPN")
    seed.add_argument("--competition", default="LL", choices=list(COMPETITIONS) + ["all"])
    seed.add_argument("--season", type=int, default=2026)
    seed.add_argument("--bump-version", action="store_true")
    seed.set_defaults(func=cmd_seed)
    fetch = sub.add_parser("fetch", help="refresh league data from one source")
    fetch.add_argument("--source", default=SOURCE_ESPN)
    fetch.add_argument("--season", type=int, default=2026)
    fetch.add_argument("--competition", default="all", choices=list(COMPETITIONS) + ["all"])
    fetch.add_argument("--date", default="")
    fetch.add_argument("--bump-version", action="store_true")
    fetch.set_defaults(func=cmd_fetch)
    remap = sub.add_parser("remap", help="mint country-stable club ids and UUID player ids")
    remap.add_argument("--bump-version", action="store_true")
    remap.set_defaults(func=cmd_remap)
    cups = sub.add_parser("cups", help="add the cup catalogue, stubs, entry pools and priors")
    cups.add_argument("--season", type=int, default=2026)
    cups.add_argument("--bump-version", action="store_true")
    cups.set_defaults(func=cmd_seed_cups)
    uefa = sub.add_parser("uefa", help="add UCL/UEL/UECL, their entrants and stub clubs")
    uefa.add_argument("--season", type=int, default=2026)
    uefa.add_argument("--bump-version", action="store_true")
    uefa.set_defaults(func=cmd_seed_uefa)
    build = sub.add_parser("build", help="write data/pl_seed.sqlite from the snapshot")
    build.set_defaults(func=cmd_build)
    verify = sub.add_parser("verify", help="check the shipped seed against the snapshot")
    verify.set_defaults(func=cmd_verify)
    ratings = sub.add_parser(
        "ratings",
        help="rebuild every card from the Sofifa-sourced sub-stat sheet",
    )
    ratings.add_argument("--sheet", default=str(RATINGS_SHEET))
    ratings.add_argument("--bump-version", action="store_true")
    ratings.set_defaults(func=cmd_ratings)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
