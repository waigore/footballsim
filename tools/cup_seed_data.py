"""Cup competitions, entry stubs and frozen priors for the shipped seed.

The cup catalogue is data, not code: each entry names its rounds, the round a
club enters, the tie rules that round plays under and the European slot its
winner fills. The stub lists are the clubs outside the shipped tiers that the
cup entry pools need, drawn from the 2025-26 Primera Federacion and Segunda
Federacion (Spain), the 2026-27 DFB-Pokal participants outside the Bundesliga
pair (Germany) and the National League North and South (England). A stub is an
identity and a rating band only: the seed mints a synthetic squad, never a
licensed one.

`tools/pl_snapshot.py` imports this module; nothing here runs at game time.
"""

## Round shape: id, name, date, ties, legs, extra time, host, regional.
## `entrants` counts the clubs that enter that round (not the round's field).
## Extra time only where the real competition plays it: the Carabao rounds 1-4
## and both one-match supercups go straight to penalties.

FA_CUP = {
    "id": "FAC", "name": "FA Cup", "short_name": "FA CUP", "country": "England",
    "prefix": "FAC-", "kind": "cup",
    "rules": {
        "season_start": "2026-11-07", "season_end": "2027-05-22",
        "entrants": {"R1": 80, "R3": 44},
        "rounds": [
            {"id": "R1", "name": "First round", "date": "2026-11-07", "ties": 40, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R2", "name": "Second round", "date": "2026-12-05", "ties": 20, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R3", "name": "Third round", "date": "2027-01-09", "ties": 32, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R4", "name": "Fourth round", "date": "2027-02-13", "ties": 16, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R5", "name": "Fifth round", "date": "2027-03-06", "ties": 8, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "QF", "name": "Quarter-finals", "date": "2027-04-03", "ties": 4, "legs": 1, "extra_time": True, "host": "draw", "regional": False},
            {"id": "SF", "name": "Semi-finals", "date": "2027-04-24", "ties": 2, "legs": 1, "extra_time": True, "host": "neutral", "regional": False},
            {"id": "F", "name": "Final", "date": "2027-05-22", "ties": 1, "legs": 1, "extra_time": True, "host": "neutral", "regional": False},
        ],
        "europe": {"competition": "UEL", "round": "LP"},
    },
}

CARABAO_CUP = {
    "id": "EFLC", "name": "Carabao Cup", "short_name": "CARABAO CUP", "country": "England",
    "prefix": "EFLC-", "kind": "cup",
    "rules": {
        "season_start": "2026-07-27", "season_end": "2027-03-21",
        "entrants": {"PR": 4, "R1": 68, "R2": 11, "R3": 9},
        "rounds": [
            {"id": "PR", "name": "Preliminary round", "date": "2026-07-27", "ties": 2, "legs": 1, "extra_time": False, "host": "draw", "regional": True},
            {"id": "R1", "name": "First round", "date": "2026-08-03", "ties": 35, "legs": 1, "extra_time": False, "host": "lower", "regional": True},
            {"id": "R2", "name": "Second round", "date": "2026-08-24", "ties": 23, "legs": 1, "extra_time": False, "host": "lower", "regional": True},
            {"id": "R3", "name": "Third round", "date": "2026-09-07", "ties": 16, "legs": 1, "extra_time": False, "host": "lower", "regional": False},
            {"id": "R4", "name": "Fourth round", "date": "2026-10-26", "ties": 8, "legs": 1, "extra_time": False, "host": "lower", "regional": False},
            {"id": "QF", "name": "Quarter-finals", "date": "2026-12-14", "ties": 4, "legs": 1, "extra_time": False, "host": "draw", "regional": False},
            {"id": "SF", "name": "Semi-finals", "date": "2027-01-11", "second_leg": "2027-02-01", "legs": 2, "extra_time": True, "host": "draw", "regional": False},
            {"id": "F", "name": "Final", "date": "2027-03-21", "ties": 1, "legs": 1, "extra_time": True, "host": "neutral", "regional": False},
        ],
        "europe": {"competition": "UECL", "round": "PO"},
    },
}

COMMUNITY_SHIELD = {
    "id": "CS", "name": "Community Shield", "short_name": "COMMUNITY SHIELD", "country": "England",
    "prefix": "CS-", "kind": "supercup",
    "rules": {
        "season_start": "2026-08-16", "season_end": "2026-08-16",
        "entrants": {"F": 2},
        "rounds": [{"id": "F", "name": "Final", "date": "2026-08-16", "ties": 1, "legs": 1, "extra_time": False, "host": "neutral", "regional": False}],
        "europe": {},
    },
}

COPA_DEL_REY = {
    "id": "CDR", "name": "Copa del Rey", "short_name": "COPA DEL REY", "country": "Spain",
    "prefix": "CDR-", "kind": "cup",
    "rules": {
        "season_start": "2026-09-26", "season_end": "2027-04-24",
        "entrants": {"PR": 20, "R1": 102, "R32": 4},
        "rounds": [
            {"id": "PR", "name": "Preliminary round", "date": "2026-09-26", "second_leg": "2026-10-03", "ties": 10, "legs": 2, "extra_time": True, "host": "draw", "regional": False},
            {"id": "R1", "name": "First round", "date": "2026-10-27", "ties": 56, "legs": 1, "extra_time": True, "host": "lower", "regional": True},
            {"id": "R2", "name": "Second round", "date": "2026-12-02", "ties": 28, "legs": 1, "extra_time": True, "host": "lower", "regional": True},
            {"id": "R32", "name": "Round of 32", "date": "2026-12-16", "ties": 16, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R16", "name": "Round of 16", "date": "2027-01-06", "ties": 8, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "QF", "name": "Quarter-finals", "date": "2027-01-13", "ties": 4, "legs": 1, "extra_time": True, "host": "draw", "regional": False},
            {"id": "SF", "name": "Semi-finals", "date": "2027-02-10", "second_leg": "2027-03-03", "ties": 2, "legs": 2, "extra_time": True, "host": "lower", "regional": False},
            {"id": "F", "name": "Final", "date": "2027-04-24", "ties": 1, "legs": 1, "extra_time": True, "host": "neutral", "regional": False},
        ],
        "europe": {"competition": "UEL", "round": "LP"},
    },
}

SUPERCOPA = {
    "id": "SCE", "name": "Supercopa de España", "short_name": "SUPERCOPA", "country": "Spain",
    "prefix": "SCE-", "kind": "supercup",
    "rules": {
        "season_start": "2027-02-02", "season_end": "2027-02-06",
        "entrants": {"SF": 4},
        "rounds": [
            {"id": "SF", "name": "Semi-finals", "date": "2027-02-02", "ties": 2, "legs": 1, "extra_time": True, "host": "neutral", "regional": False},
            {"id": "F", "name": "Final", "date": "2027-02-06", "ties": 1, "legs": 1, "extra_time": True, "host": "neutral", "regional": False},
        ],
        "europe": {},
    },
}

DFB_POKAL = {
    "id": "DFBP", "name": "DFB-Pokal", "short_name": "DFB-POKAL", "country": "Germany",
    "prefix": "DFBP-", "kind": "cup",
    "rules": {
        "season_start": "2026-08-21", "season_end": "2027-05-29",
        "entrants": {"R1": 64},
        "rounds": [
            {"id": "R1", "name": "First round", "date": "2026-08-21", "ties": 32, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R2", "name": "Second round", "date": "2026-10-27", "ties": 16, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R16", "name": "Round of 16", "date": "2026-12-01", "ties": 8, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "QF", "name": "Quarter-finals", "date": "2027-02-02", "ties": 4, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "SF", "name": "Semi-finals", "date": "2027-04-20", "ties": 2, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "F", "name": "Final", "date": "2027-05-29", "ties": 1, "legs": 1, "extra_time": True, "host": "neutral", "regional": False},
        ],
        "europe": {"competition": "UEL", "round": "LP"},
    },
}

DFL_SUPERCUP = {
    "id": "DFLS", "name": "DFL-Supercup", "short_name": "DFL-SUPERCUP", "country": "Germany",
    "prefix": "DFLS-", "kind": "supercup",
    "rules": {
        "season_start": "2026-08-22", "season_end": "2026-08-22",
        "entrants": {"F": 2},
        "rounds": [{"id": "F", "name": "Final", "date": "2026-08-22", "ties": 1, "legs": 1, "extra_time": False, "host": "neutral", "regional": False}],
        "europe": {},
    },
}

## The 44-club Coppa Italia of the real 2026/27 calendar: a preliminary round of
## eight (four Serie B, four Serie C), a round of 32, a round of 16 joined by the
## eight seeded Serie A clubs (the 2025/26 holders and the league's ranked 2-8),
## then quarter-finals, two-leg semi-finals and a final in its own weekend slot.
## The single-leg rounds play extra time and penalties; the lower-division club
## hosts until the semis hand the first leg to the club drawn first.
COPPA_ITALIA = {
    "id": "CI", "name": "Coppa Italia", "short_name": "COPPA ITALIA", "country": "Italy",
    "prefix": "CI-", "kind": "cup",
    "rules": {
        "season_start": "2026-08-08", "season_end": "2027-05-15",
        "entrants": {"PR": 8, "R1": 28, "R16": 8},
        "rounds": [
            {"id": "PR", "name": "Preliminary round", "date": "2026-08-08", "ties": 4, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R1", "name": "First round", "date": "2026-08-14", "ties": 16, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R2", "name": "Second round", "date": "2026-09-01", "ties": 8, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "R16", "name": "Round of 16", "date": "2026-12-02", "ties": 8, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "QF", "name": "Quarter-finals", "date": "2027-02-03", "ties": 4, "legs": 1, "extra_time": True, "host": "lower", "regional": False},
            {"id": "SF", "name": "Semi-finals", "date": "2027-03-02", "second_leg": "2027-04-20", "ties": 2, "legs": 2, "extra_time": True, "host": "draw", "regional": False},
            {"id": "F", "name": "Final", "date": "2027-05-15", "ties": 1, "legs": 1, "extra_time": True, "host": "neutral", "regional": False},
        ],
        "europe": {"competition": "UEL", "round": "LP"},
    },
}

## The Supercoppa reverted to the two-team match from 2026/27: the Serie A
## champion against the Coppa winner, in January, extra time then penalties.
SUPERCOPPA_ITALIANA = {
    "id": "SCI", "name": "Supercoppa Italiana", "short_name": "SUPERCOPPA", "country": "Italy",
    "prefix": "SCI-", "kind": "supercup",
    "rules": {
        "season_start": "2027-01-06", "season_end": "2027-01-06",
        "entrants": {"F": 2},
        "rounds": [{"id": "F", "name": "Final", "date": "2027-01-06", "ties": 1, "legs": 1, "extra_time": True, "host": "neutral", "regional": False}],
        "europe": {},
    },
}

CUPS = {c["id"]: c for c in (FA_CUP, CARABAO_CUP, COMMUNITY_SHIELD, COPA_DEL_REY, SUPERCOPA, DFB_POKAL, DFL_SUPERCUP, COPPA_ITALIA, SUPERCOPPA_ITALIANA)}

## Season one's results, by club name so a refresh can rename a club without
## moving its prior slot. The Community Shield pairs the 2025-26 champion with
## the FA Cup winner; the DFL-Supercup pairs the double winner with the league
## runner-up; the Supercopa is the four-team field and its fixed semi-finals;
## the Supercoppa pairs the double winner with the Serie A runner-up.
PRIORS = {
    "CS": {"entrants": ["Arsenal", "Manchester City"], "host": "Arsenal"},
    "DFLS": {"entrants": ["Borussia Dortmund", "Bayern Munich"], "host": "Borussia Dortmund"},
    "SCE": {
        "entrants": ["Barcelona", "Atlético Madrid", "Real Sociedad", "Real Madrid"],
        "semi_finals": [["Barcelona", "Atlético Madrid"], ["Real Sociedad", "Real Madrid"]],
    },
    "SCI": {"entrants": ["Internazionale", "Napoli"], "host": "Napoli"},
}

## Entry pools for the cups that draw on the shipped leagues. A role is the
## round a club enters. The Carabao's 9/11 Premier League split is the 2026-27
## European field, and the four lowest League Two clubs play the preliminary
## round.
PL_EUROPE = ["Arsenal", "Manchester City", "Manchester United", "Aston Villa",
             "Liverpool", "AFC Bournemouth", "Sunderland", "Crystal Palace", "Brighton & Hove Albion"]

## The Coppa Italia's frozen 2026/27 splits: the four Serie B clubs of the real
## preliminary round, and the eight seeded Serie A clubs that wait for the round
## of 16 (the 2025/26 holders Internazionale and the league's ranked 2-8).
CI_PRELIMINARY = ["Vicenza", "Ascoli", "Arezzo", "Benevento"]
CI_SEEDS = ["Internazionale", "Napoli", "AS Roma", "Como", "AC Milan", "Juventus",
            "Atalanta", "Bologna"]

ENGLISH_STUBS = [
    ('Macclesfield', 'MAC', 'Macclesfield', 6, 'north', 55),
    ('Weston-super-Mare', 'WES', 'Weston', 6, 'south', 55),
    ('Buxton', 'BUX', 'Buxton', 6, 'north', 55),
    ('Chelmsford City', 'CCH', 'Chelmsford', 6, 'south', 55),
    ('Slough Town', 'STL', 'Slough', 6, 'south', 55),
    ('Scarborough Athletic', 'SAC', 'Scarborough', 6, 'north', 55),
    ('Dorking Wanderers', 'DWO', 'Dorking', 6, 'south', 55),
    ('Hemel Hempstead Town', 'HHT', 'Hemel', 6, 'south', 55),
]

GERMAN_STUBS = [
    ('VfL Osnabrück', 'OSN', 'Osnabrück', 3, 'north', 64),
    ('FC Energie Cottbus', 'ECN', 'Cottbus', 3, 'south', 64),
    ('Rot-Weiss Essen', 'REO', 'Essen', 3, 'north', 64),
    ('MSV Duisburg', 'DUI', 'Duisburg', 3, 'south', 64),
    ('SV Waldhof Mannheim', 'WMA', 'Mannheim', 4, 'north', 58),
    ('TSV 1860 Munich', 'MUN', 'Munich', 4, 'south', 58),
    ('FC Würzburger Kickers', 'WKR', 'Kickers', 4, 'north', 58),
    ('VSG Altglienicke', 'ALT', 'Altglienicke', 4, 'south', 58),
    ('VfB Krieschow', 'KRI', 'Krieschow', 4, 'north', 58),
    ('SV Hemelingen', 'HEM', 'Hemelingen', 4, 'south', 58),
    ('Hamburg-Eimsbütteler Ballspiel-Club', 'HBA', 'Ballspiel-Club', 4, 'north', 58),
    ('SV Wehen Wiesbaden', 'WWE', 'Wiesbaden', 4, 'south', 58),
    ('SC St. Tönis 11/20', 'STT', 'Tönis', 4, 'north', 58),
    ('SSV Jeddeloh', 'JED', 'Jeddeloh', 4, 'south', 58),
    ('Lüneburger SK Hansa', 'LSH', 'Hansa', 4, 'north', 58),
    ('FC Hansa Rostock', 'HRA', 'Rostock', 4, 'south', 58),
    ('FC Viktoria Köln', 'VKI', 'Köln', 4, 'north', 58),
    ('SV Eintracht Trier 05', 'ETI', 'Trier', 4, 'south', 58),
    ('1. FC Saarbrücken', 'SAA', 'Saarbrücken', 4, 'north', 58),
    ('FC Erzgebirge Aue', 'EAR', 'Aue', 4, 'south', 58),
    ('Hallescher FC', 'HAL', 'Hallescher', 4, 'north', 58),
    ('1. FC Phönix Lübeck', 'PLH', 'Lübeck', 4, 'south', 58),
    ('Bahlinger SC', 'BAH', 'Bahlinger', 4, 'north', 58),
    ('TSV Schott Mainz', 'SMC', 'Mainz', 4, 'south', 58),
    ('FC Carl Zeiss Jena', 'CZJ', 'Jena', 4, 'north', 58),
    ('SC Verl', 'VER', 'Verl', 4, 'south', 58),
    ('Westfalia Rhynern', 'WRE', 'Rhynern', 4, 'north', 58),
    ('SG Sonnenhof Großaspach', 'SGO', 'Großaspach', 4, 'south', 58),
]

SPANISH_STUBS = [
    ('UB Conquense', 'CON', 'Conquense', 5, 'south', 57),
    ('CD Coria', 'COR', 'Coria', 5, 'south', 57),
    ('Elche CF Ilicitano', 'EIL', 'Ilicitano', 5, 'south', 57),
    ('CF Intercity', 'INT', 'Intercity', 5, 'south', 57),
    ('Orihuela CF', 'ORI', 'Orihuela', 5, 'south', 57),
    ('CD Quintanar del Rey', 'QDR', 'Rey', 5, 'south', 57),
    ('UD Socuéllamos', 'SOC', 'Socuéllamos', 5, 'south', 57),
    ('UD Las Palmas Atlético', 'LPA', 'Atlético', 5, 'south', 57),
    ('CD Tenerife B', 'TBE', 'B', 5, 'south', 57),
    ('RSD Alcalá', 'ALC', 'Alcalá', 5, 'south', 57),
    ('CF Fuenlabrada', 'FUE', 'Fuenlabrada', 5, 'south', 57),
    ('Getafe CF B', 'GBE', 'B', 5, 'south', 57),
    ('Águilas FC', 'GUI', 'Águilas', 5, 'south', 57),
    ('UD Almería B', 'ABL', 'B', 5, 'south', 57),
    ('CA Antoniano', 'ANT', 'Antoniano', 5, 'south', 57),
    ('Atlético Malagueño', 'AMT', 'Malagueño', 5, 'south', 57),
    ('CD Estepona FS', 'EST', 'Estepona', 5, 'south', 57),
    ('CD Extremadura', 'EXT', 'Extremadura', 5, 'south', 57),
    ('Real Jaén', 'RJE', 'Jaén', 5, 'south', 57),
    ('Linares Deportivo', 'LDI', 'Deportivo', 5, 'south', 57),
    ('Arenas Club de Getxo', 'ACD', 'Getxo', 3, 'north', 66),
    ('CD Arenteiro', 'ARE', 'Arenteiro', 3, 'north', 66),
    ('Real Avilés Industrial', 'RAI', 'Industrial', 3, 'north', 66),
    ('Barakaldo CF', 'BAR', 'Barakaldo', 3, 'north', 66),
    ('Bilbao Athletic', 'BAI', 'Athletic', 3, 'north', 66),
    ('CP Cacereño', 'CAC', 'Cacereño', 3, 'north', 66),
    ('RC Celta Fortuna', 'CFE', 'Fortuna', 3, 'north', 66),
    ('CD Guadalajara', 'GUA', 'Guadalajara', 3, 'north', 66),
    ('CD Lugo', 'LUG', 'Lugo', 3, 'north', 66),
    ('Mérida AD', 'MRI', 'Mérida', 3, 'north', 66),
    ('CA Osasuna B', 'OBS', 'B', 3, 'north', 66),
    ('Ourense CF', 'OUR', 'Ourense', 3, 'north', 66),
    ('SD Ponferradina', 'PON', 'Ponferradina', 3, 'north', 66),
    ('Pontevedra CF', 'PON', 'Pontevedra', 3, 'north', 66),
    ('Racing de Ferrol', 'RDF', 'Ferrol', 3, 'north', 66),
    ('Real Madrid Castilla', 'RMC', 'Castilla', 3, 'north', 66),
    ('CF Talavera de la Reina', 'TDL', 'Reina', 3, 'north', 66),
    ('Unionistas de Salamanca CF', 'UDS', 'Salamanca', 3, 'north', 66),
    ('Zamora CF', 'ZAM', 'Zamora', 3, 'north', 66),
    ('AD Alcorcón', 'ALC', 'Alcorcón', 3, 'south', 66),
    ('Algeciras CF', 'ALG', 'Algeciras', 3, 'south', 66),
    ('Antequera CF', 'ANT', 'Antequera', 3, 'south', 66),
    ('Atlético Madrileño', 'AMT', 'Madrileño', 3, 'south', 66),
    ('Atlético Sanluqueño CF', 'AST', 'Sanluqueño', 3, 'south', 66),
    ('Betis Deportivo', 'BDE', 'Deportivo', 3, 'south', 66),
    ('FC Cartagena', 'CAR', 'Cartagena', 3, 'south', 66),
    ('CD Eldense', 'ELD', 'Eldense', 3, 'south', 66),
    ('CE Europa', 'EUR', 'Europa', 3, 'south', 66),
    ('Gimnàstic de Tarragona', 'GDT', 'Tarragona', 3, 'south', 66),
    ('Hércules CF', 'HRC', 'Hércules', 3, 'south', 66),
    ('UD Ibiza', 'IBI', 'Ibiza', 3, 'south', 66),
    ('Juventud de Torremolinos CF', 'JDT', 'Torremolinos', 3, 'south', 66),
    ('Marbella FC', 'MAR', 'Marbella', 3, 'south', 66),
    ('Real Murcia', 'RME', 'Murcia', 3, 'south', 66),
    ('CE Sabadell FC', 'SAB', 'Sabadell', 3, 'south', 66),
    ('Sevilla Atlético', 'SAE', 'Atlético', 3, 'south', 66),
    ('SD Tarazona', 'TAR', 'Tarazona', 3, 'south', 66),
    ('CD Teruel', 'TER', 'Teruel', 3, 'south', 66),
    ('Villarreal CF B', 'VBI', 'B', 3, 'south', 66),
    ('Atlético Astorga FC', 'AAT', 'Astorga', 4, 'north', 62),
    ('Real Ávila CF', 'REA', 'Ávila', 4, 'north', 62),
    ('Bergantiños CF', 'BER', 'Bergantiños', 4, 'north', 62),
    ('Burgos CF Promesas', 'BPU', 'Promesas', 4, 'north', 62),
    ('Coruxo FC', 'COR', 'Coruxo', 4, 'north', 62),
    ('Deportivo Fabril', 'DFE', 'Fabril', 4, 'north', 62),
    ('Gimnástica Segoviana CF', 'GSI', 'Segoviana', 4, 'north', 62),
    ('UP Langreo', 'LAN', 'Langreo', 4, 'north', 62),
    ('CD Lealtad', 'LEA', 'Lealtad', 4, 'north', 62),
    ('Marino de Luanco', 'MDL', 'Luanco', 4, 'north', 62),
    ('CD Numancia', 'NUM', 'Numancia', 4, 'north', 62),
    ('UD Ourense', 'OUR', 'Ourense', 4, 'north', 62),
    ('Rayo Cantabria', 'RCA', 'Cantabria', 4, 'north', 62),
    ('Real Oviedo Vetusta', 'ROV', 'Vetusta', 4, 'north', 62),
    ('Salamanca CF UDS', 'SUA', 'UDS', 4, 'north', 62),
    ('UD Sámano', 'SMA', 'Sámano', 4, 'north', 62),
    ('SD Sarriana', 'SAR', 'Sarriana', 4, 'north', 62),
    ('Real Valladolid Promesas', 'RVP', 'Promesas', 4, 'north', 62),
    ('CD Alfaro', 'ALF', 'Alfaro', 4, 'north', 62),
    ('Deportivo Aragón', 'DAE', 'Aragón', 4, 'north', 62),
    ('CD Ebro', 'EBR', 'Ebro', 4, 'north', 62),
    ('SD Ejea', 'EJE', 'Ejea', 4, 'north', 62),
    ('SD Logroñés', 'LOG', 'Logroñés', 4, 'north', 62),
    ('UD Logroñés', 'LOG', 'Logroñés', 4, 'north', 62),
    ('UD Mutilvera', 'MUT', 'Mutilvera', 4, 'north', 62),
    ('Náxara CD', 'NXA', 'Náxara', 4, 'north', 62),
    ('CD Tudelano', 'TUD', 'Tudelano', 4, 'north', 62),
    ('Utebo FC', 'UTE', 'Utebo', 4, 'north', 62),
    ('Deportivo Alavés B', 'DAB', 'B', 4, 'north', 62),
    ('SD Amorebieta', 'AMO', 'Amorebieta', 4, 'north', 62),
    ('CD Basconia', 'BAS', 'Basconia', 4, 'north', 62),
    ('SD Beasain', 'BEA', 'Beasain', 4, 'north', 62),
    ('SD Eibar B', 'EBI', 'B', 4, 'north', 62),
    ('Gernika Club', 'GCE', 'Club', 4, 'north', 62),
    ('Real Unión', 'RUE', 'Unión', 4, 'north', 62),
    ('Sestao River Club', 'SRC', 'Club', 4, 'north', 62),
    ('CE Atlètic Lleida', 'ALT', 'Lleida', 4, 'south', 62),
    ('CD Alcoyano', 'ALC', 'Alcoyano', 4, 'south', 62),
    ('CE Andratx', 'AND', 'Andratx', 4, 'south', 62),
    ('CD Atlético Baleares', 'ABT', 'Baleares', 4, 'south', 62),
    ('UD Barbastro', 'BAR', 'Barbastro', 4, 'south', 62),
    ('CD Castellón B', 'CBA', 'B', 4, 'south', 62),
    ('Girona FC B', 'GBI', 'B', 4, 'south', 62),
    ('CD Ibiza Islas Pitiusas', 'IIP', 'Pitiusas', 4, 'south', 62),
    ('UE Olot', 'OLO', 'Olot', 4, 'south', 62),
    ('UD Poblense', 'POB', 'Poblense', 4, 'south', 62),
    ('UE Porreres', 'POR', 'Porreres', 4, 'south', 62),
]

## The four Serie C clubs of the real 2026/27 preliminary round. The seed ships
## no Italian third tier, so the Coppa's lower pool is an identity and a band.
ITALIAN_STUBS = [
    ('Catania', 'CTA', 'Catania', 3, 'south', 65),
    ('Potenza', 'POT', 'Potenza', 3, 'south', 65),
    ('Ravenna', 'RAV', 'Ravenna', 3, 'north', 65),
    ('Union Brescia', 'BRE', 'Brescia', 3, 'north', 65),
]


## Synthetic squad names for stubs. Real enough to read on a team sheet, and
## deliberately plain: a stub is an identity, not a licensed roster.
NAME_POOLS = {
    "England": {
        "first": ["J.", "H.", "C.", "L.", "M.", "D.", "S.", "R.", "A.", "T.", "B.", "K.", "N.", "P.", "E.", "O."],
        "last": ["Smith", "Taylor", "Brown", "Wilson", "Davies", "Evans", "Thomas", "Roberts", "Walker", "Wright", "Robinson", "Thompson", "Hughes", "Green", "Hall", "Wood", "Harris", "Clarke", "Baker", "Turner", "Hill", "Moore", "Cooper", "Ward"],
    },
    "Spain": {
        "first": ["A.", "J.", "M.", "C.", "D.", "P.", "L.", "S.", "R.", "E.", "F.", "I.", "N.", "G.", "V.", "Ó."],
        "last": ["García", "Martínez", "López", "Sánchez", "Pérez", "Gómez", "Fernández", "Ruiz", "Díaz", "Moreno", "Álvarez", "Romero", "Alonso", "Gutiérrez", "Navarro", "Torres", "Domínguez", "Vázquez", "Ramos", "Gil", "Serrano", "Blanco", "Molina", "Morales"],
    },
    "Germany": {
        "first": ["L.", "M.", "J.", "T.", "S.", "N.", "F.", "D.", "P.", "K.", "A.", "B.", "C.", "E.", "H.", "R."],
        "last": ["Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker", "Hoffmann", "Schulz", "Koch", "Richter", "Klein", "Wolf", "Neumann", "Schwarz", "Zimmermann", "Braun", "Krüger", "Hartmann", "Lange", "Werner", "Krause", "Lehmann"],
    },
    "Italy": {
        "first": ["A.", "M.", "G.", "L.", "F.", "D.", "S.", "R.", "P.", "E.", "N.", "C.", "V.", "T.", "M.", "A."],
        "last": ["Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Bruno", "Gallo", "Conti", "De Luca", "Costa", "Giordano", "Mancini", "Rizzo", "Lombardi", "Moretti", "Barbieri", "Fontana", "Santoro", "Mariani"],
    },
}


## North/south bands for the early rounds that split their draw. The seed has
## cities, not coordinates, so a curated city set is the band: a club whose city
## is listed plays in the northern section. Midlands cities sit north, which
## keeps the two sections balanced; the Copa's La Liga clubs use the same idea.
NORTH_CITIES = {
    "Manchester", "Liverpool", "Leeds", "Newcastle", "Sunderland", "Hull",
    "Blackburn", "Bolton", "Burnley", "Middlesbrough", "Preston", "Sheffield",
    "Stoke-on-Trent", "West Bromwich", "Wolverhampton", "Wrexham", "Blackpool",
    "Bradford", "Doncaster", "Huddersfield", "Stockport", "Wigan", "Accrington",
    "Birkenhead", "Chesterfield", "Crewe", "Fleetwood", "Grimsby", "Oldham",
    "Rochdale", "Rotherham", "Salford", "Shrewsbury", "Walsall", "York",
    "Barrow-in-Furness", "Carlisle", "Gateshead", "Halifax", "Harrogate",
    "Hartlepool", "Scunthorpe", "Kidderminster", "Solihull", "Tamworth",
    "Mansfield", "Nottingham", "Derby", "Leicester", "Birmingham", "Coventry",
    "Burton-upon-Trent, Staffordshire", "Lincoln", "Boston, Lincolnshire",
    "Northampton", "Peterborough",
}

SPANISH_NORTH = {
    "A Coruña", "Barcelona", "Bilbao", "Getafe", "Madrid", "Pamplona",
    "San Sebastián", "Santander", "Valencia", "Vigo", "Villarreal", "Vitoria-Gasteiz",
}
