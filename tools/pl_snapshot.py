#!/usr/bin/env python3
"""Build, refresh and ship the multi-competition football seed snapshot.

The snapshot is `data/pl_snapshot.json` (readable source of truth) and the game
loads the SQLite copy `data/pl_seed.sqlite` it produces. Rebuild the database
after every snapshot edit; bump `db_version` so the game replaces its cache.

The seed holds more than one competition: the Premier League and La Liga share
one database, one season window and one set of stable ids. Club ids carry the
competition's namespace (`LL-` for La Liga) so a refresh can never collide a
Spanish club with an English one.

Usage:
    python tools/pl_snapshot.py seed --competition LL --season 2026
    python tools/pl_snapshot.py fetch --source espn --season 2026 --competition all
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
import hashlib
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

SCHEMA_VERSION = 2
SOURCE_ESPN = "espn"
ESPN_SITE = "https://site.api.espn.com/apis/site/v2/sports"
ESPN_CORE = "https://sports.core.api.espn.com/v2"

## One row per shipped competition. `prefix` namespaces every id the league
## owns; the Premier League keeps the bare ids the first seed shipped with.
COMPETITIONS = {
    "PL": {
        "espn": "eng.1",
        "name": "Premier League",
        "short_name": "PREMIER LEAGUE",
        "country": "England",
        "prefix": "",
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
        "prefix": "LL-",
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
    "BL": {
        "espn": "ger.1",
        "name": "Bundesliga",
        "short_name": "BUNDESLIGA",
        "country": "Germany",
        "prefix": "BL-",
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
        "prefix": "BL2-",
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
        "prefix": "CH-",
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
        "prefix": "L1-",
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
        "prefix": "L2-",
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
        "prefix": "NL-",
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
        "prefix": "SA-",
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
        "prefix": "SB-",
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
}

SCHEMA = """
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE competition (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, short_name TEXT NOT NULL,
    season_label TEXT NOT NULL, country TEXT NOT NULL DEFAULT '',
    rules TEXT NOT NULL DEFAULT '{}'
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
    nationality TEXT, date_of_birth TEXT
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
    if competition_id not in COMPETITIONS:
        raise SystemExit(f"unknown competition {competition_id}; known: {', '.join(COMPETITIONS)}")
    return COMPETITIONS[competition_id]


def club_id_for(competition_id: str, abbr: str, espn_id: str = "") -> str:
    return spec_for(competition_id)["prefix"] + shippable_abbr(competition_id, abbr, espn_id)


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


def _attributes(club_base: float, role: str, name: str) -> dict:
    wobble = _jitter(name, 3)
    base = club_base + wobble
    if role == "GK":
        return {
            "ovr": _clamp(base + 1), "pac": _clamp(base - 24), "sho": _clamp(base - 50),
            "pas": _clamp(base - 20), "dri": _clamp(base - 24), "def": _clamp(base - 48),
            "phy": _clamp(base - 4),
            "gk": {
                "div": _clamp(base + 2), "han": _clamp(base + 1), "kic": _clamp(base - 8),
                "ref": _clamp(base + 2), "spd": _clamp(base - 22),
            },
        }
    line = "D" if role in ("RB", "RCB", "LCB", "LB") else (
        "F" if role in ("ST", "RW", "LW") else "M")
    if line == "D":
        attrs = {"pac": base - 2, "sho": base - 26, "pas": base - 7,
                 "dri": base - 10, "def": base + 4, "phy": base + 3}
    elif line == "F":
        attrs = {"pac": base + 2, "sho": base + 5, "pas": base - 2,
                 "dri": base + 4, "def": base - 21, "phy": base - 3}
    else:
        attrs = {"pac": base - 1, "sho": base - 8, "pas": base + 3,
                 "dri": base + 2, "def": base - 4, "phy": base - 2}
    attrs = {k: _clamp(v) for k, v in attrs.items()}
    attrs["ovr"] = _clamp(club_base + wobble / 2.0)
    return attrs


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

    def build(entry: dict) -> dict:
        team = entry["team"]
        abbr = shippable_abbr(competition_id, team["abbreviation"], team.get("id", ""))
        club_id = club_id_for(competition_id, abbr)
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
        seen_ids: set[str] = set()
        role_counts: dict[str, int] = {}
        for athlete in roster:
            name = str(athlete.get("shortName") or athlete.get("displayName") or "")
            if name == "":
                continue
            group = str((athlete.get("position") or {}).get("abbreviation", "M"))
            role = _role_for(group, role_counts)
            role_counts[role] = role_counts.get(role, 0) + 1
            suffix = f"{slug(initial_key(name))}-{slug(name.split()[-1])}" if initial_key(name) else slug(name)
            player_id = f"{club_id}-{suffix}"
            n = 2
            while player_id in seen_ids:
                player_id = f"{club_id}-{suffix}-{n}"
                n += 1
            seen_ids.add(player_id)
            attrs = _attributes(club_base, role, name + club_id)
            height = athlete.get("height")
            cm = int(round(float(height) * 2.54)) if height else 180
            player = {
                "id": player_id, "name": name,
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
        used: set[str] = set()
        for role in ROLE_ORDER:
            pool = [p for p in players if p["role"] == role and p["id"] not in used]
            if pool:
                best = max(pool, key=lambda p: p["ovr"])
                used.add(best["id"])
            elif len(used) < 11:
                rest = [p for p in players if p["id"] not in used]
                if rest:
                    used.add(max(rest, key=lambda p: p["ovr"])["id"])
        for player in players:
            player["squad"] = "starter" if player["id"] in used else "bench"
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
        }

    with ThreadPoolExecutor(max_workers=4) as pool:
        seeded = list(pool.map(build, entries))
    kept = [c for c in snapshot.get("clubs", [])
            if str(c.get("competition_id", "PL")) != competition_id]
    snapshot["clubs"] = kept + seeded


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
    snapshot["db_version"] = int(snapshot.get("db_version", 1)) + (1 if args.bump_version else 0)
    snapshot["schema_version"] = SCHEMA_VERSION
    save(args.snapshot, snapshot)
    print(
        f"snapshot {snapshot['season_label']}: {len(snapshot['table'])} table rows, "
        f"{len(snapshot['fixtures'])} fixtures, {len(snapshot['season_stats'])} season stat lines, "
        f"db_version {snapshot['db_version']}"
    )
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
            "INSERT INTO club VALUES (" + ",".join("?" * 25) + ")",
            (
                club["id"], comp_id, club["name"], club["short"], club["abbr"],
                club.get("nickname", ""), club.get("manager", ""), club["stadium"],
                club["city"], int(club["capacity"]), club["formation"],
                club["color"], club["color_dark"], club["color_light"],
                club["shorts"], club["gk_color"], club["text"],
                *[float(style.get(k, 0.5)) for k in STYLE_KEYS],
            ),
        )
        con.execute(
            "INSERT INTO competition_member (competition_id, member_kind, member_id, role) "
            "VALUES (?, 'club', ?, 'member');", (comp_id, club["id"]))
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
            con.execute(
                "INSERT OR IGNORE INTO competition_member (competition_id, member_kind, member_id, role) "
                "VALUES (?, 'player', ?, 'player');", (comp_id, p["id"]))
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


def _audit_ids(snapshot: dict) -> list[str]:
    problems: list[str] = []
    club_ids = [str(c["id"]) for c in snapshot["clubs"]]
    if len(club_ids) != len(set(club_ids)):
        problems.append("club ids collide across competitions")
    player_ids = [str(p["id"]) for c in snapshot["clubs"] for p in c["players"]]
    if len(player_ids) != len(set(player_ids)):
        problems.append("player ids collide across competitions")
    fixture_ids = [str(fx["id"]) for fx in snapshot.get("fixtures", [])]
    if len(fixture_ids) != len(set(fixture_ids)):
        problems.append("fixture ids collide across competitions")
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
    for cid in comps:
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
    build = sub.add_parser("build", help="write data/pl_seed.sqlite from the snapshot")
    build.set_defaults(func=cmd_build)
    verify = sub.add_parser("verify", help="check the shipped seed against the snapshot")
    verify.set_defaults(func=cmd_verify)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
