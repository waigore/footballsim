class_name LeagueSaveSchema
extends RefCounted


const SIDE_COLUMNS := [
	"home_played", "home_won", "home_drawn", "home_lost", "home_gf", "home_ga",
	"away_played", "away_won", "away_drawn", "away_lost", "away_gf", "away_ga",
]

const TABLES := [
	"CREATE TABLE IF NOT EXISTS save_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
	"CREATE TABLE IF NOT EXISTS save_competition (competition_id TEXT PRIMARY KEY, "
	+ "active INTEGER NOT NULL DEFAULT 1, position INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS league_interest (club_id TEXT PRIMARY KEY);",
	"CREATE TABLE IF NOT EXISTS cup_round (competition_id TEXT NOT NULL, "
	+ "round_id TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, "
	+ "status TEXT NOT NULL DEFAULT 'open', PRIMARY KEY (competition_id, round_id));",
	"CREATE TABLE IF NOT EXISTS cup_tie (competition_id TEXT NOT NULL, "
	+ "round_id TEXT NOT NULL, tie_index INTEGER NOT NULL, "
	+ "home_club_id TEXT NOT NULL, away_club_id TEXT NOT NULL, "
	+ "winner_club_id TEXT NOT NULL DEFAULT '', home_goals INTEGER NOT NULL DEFAULT 0, "
	+ "away_goals INTEGER NOT NULL DEFAULT 0, pens_home INTEGER NOT NULL DEFAULT -1, "
	+ "pens_away INTEGER NOT NULL DEFAULT -1, extra_time INTEGER NOT NULL DEFAULT 0, "
	+ "PRIMARY KEY (competition_id, round_id, tie_index));",
	"CREATE TABLE IF NOT EXISTS league_fixture (id TEXT PRIMARY KEY, "
	+ "competition_id TEXT NOT NULL DEFAULT '', matchday INTEGER NOT NULL, "
	+ "kickoff TEXT NOT NULL, kickoff_time TEXT NOT NULL DEFAULT '', "
	+ "home_club_id TEXT NOT NULL, away_club_id TEXT NOT NULL, "
	+ "home_goals INTEGER NOT NULL DEFAULT 0, away_goals INTEGER NOT NULL DEFAULT 0, "
	+ "status TEXT NOT NULL DEFAULT 'pending', watched INTEGER NOT NULL DEFAULT 0, "
	+ "suggested INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS league_table (club_id TEXT PRIMARY KEY, "
	+ "competition_id TEXT NOT NULL DEFAULT '', "
	+ "played INTEGER NOT NULL DEFAULT 0, won INTEGER NOT NULL DEFAULT 0, "
	+ "drawn INTEGER NOT NULL DEFAULT 0, lost INTEGER NOT NULL DEFAULT 0, "
	+ "gf INTEGER NOT NULL DEFAULT 0, ga INTEGER NOT NULL DEFAULT 0, "
	+ "points INTEGER NOT NULL DEFAULT 0, "
	+ "home_played INTEGER NOT NULL DEFAULT 0, home_won INTEGER NOT NULL DEFAULT 0, "
	+ "home_drawn INTEGER NOT NULL DEFAULT 0, home_lost INTEGER NOT NULL DEFAULT 0, "
	+ "home_gf INTEGER NOT NULL DEFAULT 0, home_ga INTEGER NOT NULL DEFAULT 0, "
	+ "away_played INTEGER NOT NULL DEFAULT 0, away_won INTEGER NOT NULL DEFAULT 0, "
	+ "away_drawn INTEGER NOT NULL DEFAULT 0, away_lost INTEGER NOT NULL DEFAULT 0, "
	+ "away_gf INTEGER NOT NULL DEFAULT 0, away_ga INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS match_event (id INTEGER PRIMARY KEY AUTOINCREMENT, "
	+ "fixture_id TEXT NOT NULL, minute INTEGER NOT NULL, kind TEXT NOT NULL, "
	+ "player_id TEXT NOT NULL DEFAULT '', club_id TEXT NOT NULL DEFAULT '', "
	+ "detail TEXT NOT NULL DEFAULT '', penalty INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS league_player_stat (player_id TEXT PRIMARY KEY, "
	+ "competition_id TEXT NOT NULL DEFAULT '', club_id TEXT NOT NULL, "
	+ "apps INTEGER NOT NULL DEFAULT 0, goals INTEGER NOT NULL DEFAULT 0, "
	+ "assists INTEGER NOT NULL DEFAULT 0, yellow INTEGER NOT NULL DEFAULT 0, "
	+ "red INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS league_absence (player_id TEXT PRIMARY KEY, "
	+ "club_id TEXT NOT NULL, kind TEXT NOT NULL, grade TEXT NOT NULL DEFAULT '', "
	+ "days_left INTEGER NOT NULL DEFAULT 0, matches_left INTEGER NOT NULL DEFAULT 0, "
	+ "started_on TEXT NOT NULL DEFAULT '', due_on TEXT NOT NULL DEFAULT '', "
	+ "rate REAL NOT NULL DEFAULT 1.0);",
	"CREATE TABLE IF NOT EXISTS league_discipline (player_id TEXT PRIMARY KEY, "
	+ "club_id TEXT NOT NULL, yellow_mark INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS goal_highlight (id INTEGER PRIMARY KEY AUTOINCREMENT, "
	+ "fixture_id TEXT NOT NULL, goal_index INTEGER NOT NULL, "
	+ "match_event_id INTEGER NOT NULL DEFAULT 0, minute INTEGER NOT NULL DEFAULT 0, "
	+ "club_id TEXT NOT NULL DEFAULT '', scorer_id TEXT NOT NULL DEFAULT '', "
	+ "scorer_name TEXT NOT NULL DEFAULT '', assist_id TEXT NOT NULL DEFAULT '', "
	+ "assist_name TEXT NOT NULL DEFAULT '', commentary TEXT NOT NULL DEFAULT '', "
	+ "source TEXT NOT NULL DEFAULT 'auto', codec TEXT NOT NULL DEFAULT '', "
	+ "version INTEGER NOT NULL DEFAULT 0, home_club_id TEXT NOT NULL DEFAULT '', "
	+ "away_club_id TEXT NOT NULL DEFAULT '', bytes BLOB, "
	+ "penalty INTEGER NOT NULL DEFAULT 0, UNIQUE(fixture_id, goal_index));",
]

const INDEXES := [
	"CREATE INDEX IF NOT EXISTS league_fixture_kickoff_idx ON league_fixture (kickoff);",
	"CREATE INDEX IF NOT EXISTS league_fixture_comp_idx ON league_fixture (competition_id);",
	"CREATE INDEX IF NOT EXISTS match_event_fixture_idx ON match_event (fixture_id);",
	"CREATE INDEX IF NOT EXISTS goal_highlight_fixture_idx ON goal_highlight (fixture_id);",
	"CREATE INDEX IF NOT EXISTS cup_tie_round_idx ON cup_tie (competition_id, round_id);",
]


static func active_from_disk() -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT competition_id FROM save_competition WHERE active = 1 ORDER BY position, competition_id;"):
		out.append(str(row["competition_id"]))
	if not out.is_empty():
		return out
	return hint()


static func hint() -> Array:
	var row := PLDatabase.row("SELECT value FROM save_meta WHERE key = 'competitions';")
	if not row.is_empty() and str(row.get("value", "")) != "":
		var out: Array = []
		for part in str(row["value"]).split(",", false):
			if part != "":
				out.append(part)
		if not out.is_empty():
			return out
	var fx := PLDatabase.row("SELECT competition_id FROM league_fixture WHERE competition_id <> '' LIMIT 1;")
	if not fx.is_empty():
		return [str(fx["competition_id"])]
	var comp := PLDatabase.row("SELECT id FROM competition ORDER BY rowid LIMIT 1;")
	return [str(comp.get("id", "PL"))] if not comp.is_empty() else ["PL"]


static func valid(wanted: Array) -> Array:
	var known: Array = []
	for row in PLDatabase.rows("SELECT id FROM competition ORDER BY rowid;"):
		known.append(str(row["id"]))
	var out: Array = []
	for cid in wanted:
		var key := str(cid)
		if known.has(key) and not out.has(key):
			out.append(key)
	if out.is_empty():
		out.append("PL" if known.has("PL") or known.is_empty() else str(known[0]))
	return out


static func migrate() -> void:
	for sql in TABLES:
		PLDatabase.execute(sql)
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		add_column(table, "competition_id", "TEXT NOT NULL DEFAULT ''")
	add_column("league_fixture", "stage", "TEXT NOT NULL DEFAULT ''")
	add_column("league_fixture", "leg", "INTEGER NOT NULL DEFAULT 0")
	var hint_rows := hint()
	var owner := str(hint_rows[0]) if not hint_rows.is_empty() else "PL"
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		backfill(table, owner)
	for sql in INDEXES:
		PLDatabase.execute(sql)
	LeagueRules.migrate(owner)


static func ensure_schema(save: LeagueSave) -> void:
	if not save.ensure_open():
		return
	for column in SIDE_COLUMNS:
		add_column("league_table", column)
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		add_column(table, "competition_id", "TEXT NOT NULL DEFAULT ''")
		backfill(table, str(save.actives[0]) if not save.actives.is_empty() else "")


	add_column("match_event", "penalty")
	add_column("goal_highlight", "penalty")
	add_column("league_fixture", "stage", "TEXT NOT NULL DEFAULT ''")
	add_column("league_fixture", "leg", "INTEGER NOT NULL DEFAULT 0")
	for cid in save.actives:
		PLDatabase.execute(
			"INSERT INTO save_competition (competition_id, active, position) VALUES (?, 1, ?) "
			+ "ON CONFLICT(competition_id) DO UPDATE SET active = 1;",
			[str(cid), save.actives.find(cid)])


static func add_column(table: String, column: String,
		spec: String = "INTEGER NOT NULL DEFAULT 0") -> void:
	var have := {}
	for row in PLDatabase.rows("PRAGMA table_info(%s);" % table):
		have[str(row["name"])] = true
	if have.has(column):
		return
	PLDatabase.execute("ALTER TABLE %s ADD COLUMN %s %s;" % [table, column, spec])


static func backfill(table: String, competition_id: String) -> void:
	if competition_id == "":
		return
	PLDatabase.execute(
		"UPDATE %s SET competition_id = ? WHERE competition_id = '' OR competition_id IS NULL;"
		% table, [competition_id])
