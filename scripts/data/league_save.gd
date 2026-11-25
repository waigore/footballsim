class_name LeagueSave
extends RefCounted

## One named god-mode season saved as a self-contained SQLite file.
##
## Creating a save copies the shipped seed (competition, clubs, squads) into
## `user://saves/<slug>.sqlite`, adds the league tables the season owns —
## fixtures, results, match events, live table, season player stats — and
## stamps a `save_meta` row plus a private `league_rules` copy. Nothing about a
## save is shared with the single-match cache, so a seed refresh can never
## disturb a season in progress.

const DEFAULT_DIR := "user://saves"
const EXT := ".sqlite"

## Side aggregates added after the first season saves shipped (#73). A save
## written before them gets the columns on open; the season then rebuilds every
## row from its played fixtures, so no player-visible migration step is needed.
const SIDE_COLUMNS := [
	"home_played", "home_won", "home_drawn", "home_lost", "home_gf", "home_ga",
	"away_played", "away_won", "away_drawn", "away_lost", "away_gf", "away_ga",
]

## All league tables live beside the seed tables, in the same file.
const SCHEMA := [
	"CREATE TABLE IF NOT EXISTS save_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
	# The clubs this season follows (#104). A set of club ids, so a save written
	# before Teams of Interest simply opens with an empty shortlist.
	"CREATE TABLE IF NOT EXISTS league_interest (club_id TEXT PRIMARY KEY);",
	"CREATE TABLE IF NOT EXISTS league_fixture (id TEXT PRIMARY KEY, matchday INTEGER NOT NULL, "
	+ "kickoff TEXT NOT NULL, kickoff_time TEXT NOT NULL DEFAULT '', "
	+ "home_club_id TEXT NOT NULL, away_club_id TEXT NOT NULL, "
	+ "home_goals INTEGER NOT NULL DEFAULT 0, away_goals INTEGER NOT NULL DEFAULT 0, "
	+ "status TEXT NOT NULL DEFAULT 'pending', watched INTEGER NOT NULL DEFAULT 0, "
	+ "suggested INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS league_table (club_id TEXT PRIMARY KEY, "
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
	+ "detail TEXT NOT NULL DEFAULT '');",
	"CREATE TABLE IF NOT EXISTS league_player_stat (player_id TEXT PRIMARY KEY, "
	+ "club_id TEXT NOT NULL, apps INTEGER NOT NULL DEFAULT 0, "
	+ "goals INTEGER NOT NULL DEFAULT 0, assists INTEGER NOT NULL DEFAULT 0, "
	+ "yellow INTEGER NOT NULL DEFAULT 0, red INTEGER NOT NULL DEFAULT 0);",
	# Season availability (#155, #156): the injuries and suspensions a club
	# carries between fixtures. `days_left` and `due_on` are the hidden injury
	# clock — the screens only ever read weeks or months.
	"CREATE TABLE IF NOT EXISTS league_absence (player_id TEXT PRIMARY KEY, "
	+ "club_id TEXT NOT NULL, kind TEXT NOT NULL, grade TEXT NOT NULL DEFAULT '', "
	+ "days_left INTEGER NOT NULL DEFAULT 0, matches_left INTEGER NOT NULL DEFAULT 0, "
	+ "started_on TEXT NOT NULL DEFAULT '', due_on TEXT NOT NULL DEFAULT '', "
	+ "rate REAL NOT NULL DEFAULT 1.0);",
	# How far up the yellow table a player has already been punished: the mark
	# that stops ten cards paying twice for five (#156).
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
	+ "UNIQUE(fixture_id, goal_index));",
	"CREATE INDEX IF NOT EXISTS league_fixture_kickoff_idx ON league_fixture (kickoff);",
	"CREATE INDEX IF NOT EXISTS match_event_fixture_idx ON match_event (fixture_id);",
	"CREATE INDEX IF NOT EXISTS goal_highlight_fixture_idx ON goal_highlight (fixture_id);",
]

## Save directory this run uses (tests point it at a scratch folder).
static var dir := DEFAULT_DIR
static var current: LeagueSave = null

var slug := ""
var path := ""
var meta: Dictionary = {}
var rules: Dictionary = {}
static var last_error := ""

# ------------------------------------------------------------------ files ---

static func slugify(name: String) -> String:
	var out := ""
	var last_dash := true
	for i in range(name.length()):
		var ch := name.substr(i, 1).to_lower()
		var ok := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		if ok:
			out += ch
			last_dash = false
		elif not last_dash:
			out += "-"
			last_dash = true
	return out.strip_edges().trim_suffix("-")

static func unique_slug(base: String) -> String:
	var stem := slugify(base)
	if stem == "":
		stem = "league"
	var candidate := stem
	var n := 2
	while FileAccess.file_exists(dir.path_join(candidate + EXT)):
		candidate = "%s-%d" % [stem, n]
		n += 1
	return candidate

## Every save on disk, newest first. Reads only `save_meta` from each file, so
## listing never disturbs the connection a running season is using.
static func list() -> Array:
	var out: Array = []
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		if not name.ends_with(EXT):
			continue
		var file := dir.path_join(name)
		var info := _peek(file)
		if info.is_empty():
			continue
		out.append({
			"slug": name.trim_suffix(EXT),
			"path": file,
			"name": str(info.get("name", name)),
			"status": str(info.get("status", "in_progress")),
			"current_date": str(info.get("current_date", "")),
			"matchday": int(info.get("matchday", 1)),
			"modified": FileAccess.get_modified_time(file),
		})
	out.sort_custom(func(a, b): return int(a["modified"]) > int(b["modified"]))
	return out

static func _peek(file: String) -> Dictionary:
	var db := SQLite.new()
	db.path = file
	if not db.open_db():
		return {}
	var out := {}
	if db.query("SELECT key, value FROM save_meta;"):
		for row in db.query_result:
			out[str(row["key"])] = str(row["value"])
	db.close_db()
	return out

## Copy the seed and lay out an empty league. Fixtures and the table are filled
## by the season layer (`LeagueSeason`), so this file stays about storage.
static func create(name: String, rules: Dictionary, seed: int = 0) -> LeagueSave:
	if not FileAccess.file_exists(PLDatabase.SEED_PATH):
		last_error = "the shipped seed is missing"
		return null
	DirAccess.make_dir_recursive_absolute(dir)
	var save := LeagueSave.new()
	save.slug = unique_slug(name)
	save.path = dir.path_join(save.slug + EXT)
	var bytes := FileAccess.get_file_as_bytes(PLDatabase.SEED_PATH)
	var out := FileAccess.open(save.path, FileAccess.WRITE)
	if out == null or bytes.is_empty():
		last_error = "cannot write %s" % save.path
		return null
	out.store_buffer(bytes)
	out.close()
	if not PLDatabase.open_path(save.path):
		last_error = "cannot open %s" % save.path
		return null
	migrate()
	save.rules = LeagueRules.normalize(rules)
	LeagueRules.write(save.rules)
	save.meta = {}
	save.put_meta("name", name.strip_edges() if name.strip_edges() != "" else "New League")
	save.put_meta("created_at", Time.get_datetime_string_from_system(true, true))
	save.put_meta("status", "in_progress")
	save.put_meta("seed", str(seed))
	save.put_meta("matchday", "1")
	save.put_meta("calendar_mode", str(save.rules["calendar_mode"]))
	save.put_meta("advance_mode", str(save.rules["advance_mode"]))
	var season := PLDatabase.row("SELECT value FROM metadata WHERE key = 'season_label';")
	save.put_meta("season_label", str(season.get("value", "")))
	PLRepository.shared().invalidate()
	current = save
	return save

## Open an existing save and bind the game's static connection to it.
static func open(slug_or_path: String) -> LeagueSave:
	var file := slug_or_path
	if not file.ends_with(EXT):
		file = dir.path_join(slug_or_path + EXT)
	if not FileAccess.file_exists(file):
		return null
	if not PLDatabase.open_path(file):
		return null
	PLRepository.shared().invalidate()
	migrate()
	var save := LeagueSave.new()
	save.path = file
	save.slug = file.get_file().trim_suffix(EXT)
	save.meta = save.read_meta()
	if save.meta.is_empty():
		PLDatabase.reset()
		return null
	save.rules = LeagueRules.read()
	save.ensure_schema()
	current = save
	return save

## Lay every season table onto whichever file is bound. Every statement is
## `IF NOT EXISTS`, so this is both the create path and the migration that gives
## a save written by an older build the tables it is missing (goal clips).
static func migrate() -> void:
	for sql in SCHEMA:
		PLDatabase.execute(sql)
	PLDatabase.execute(LeagueRules.CREATE_SQL)

static func remove(slug: String) -> bool:
	var file := dir.path_join(slug + EXT)
	if not FileAccess.file_exists(file):
		return false
	if PLDatabase.current_path() == file:
		close()
	PLRepository.shared().invalidate()
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK

## Leave the save; the next read lazily reopens the cached seed.
static func close() -> void:
	if current != null and current.path == PLDatabase.current_path():
		PLDatabase.reset()
	current = null
	PLRepository.shared().invalidate()

## Quick Save: play writes to the save as it goes, so this stamps the file and
## proves it is still bound and writable. False means the write did not land.
func touch() -> bool:
	if not ensure_open():
		return false
	var stamp := Time.get_datetime_string_from_system(true, true)
	if not put_meta("saved_at", stamp):
		return false
	meta["saved_at"] = stamp
	return true

## Save As: write this save's file under another name and leave the season on its
## own file — the copy is a named restore point. Naming the season's own save
## rewrites it in place. Returns the copy's slug, or "" when nothing was written.
func write_copy(name: String) -> String:
	var typed := name.strip_edges()
	if typed == "" or not ensure_open():
		return ""
	var slug := slugify(typed)
	if slug == "" or slug == self.slug:
		return self.slug if touch() else ""
	DirAccess.make_dir_recursive_absolute(dir)
	var target := dir.path_join(slug + EXT)
	# Close the live file first: a copy taken under an open handle can miss the
	# last commit.
	PLDatabase.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	var out := FileAccess.open(target, FileAccess.WRITE)
	if out == null or bytes.is_empty():
		last_error = "cannot write %s" % target
		ensure_open()
		return ""
	out.store_buffer(bytes)
	out.close()
	var copy := open(target)
	if copy == null:
		ensure_open()
		return ""
	copy.put_meta("name", typed)
	copy.put_meta("saved_at", Time.get_datetime_string_from_system(true, true))
	# Back to the season's own file so play continues where it was.
	ensure_open()
	current = self
	PLRepository.shared().invalidate()
	return slug

# ------------------------------------------------------------------- meta ---

## Every read and write goes to this save's own file, even when another save was
## bound in between (listing, switching seasons): rebind when needed.
func ensure_open() -> bool:
	if PLDatabase.current_path() == path and PLDatabase.get_db() != null:
		return true
	if not PLDatabase.open_path(path):
		return false
	PLRepository.shared().invalidate()
	return true

func read_meta() -> Dictionary:
	if not ensure_open():
		return {}
	var out := {}
	for row in PLDatabase.rows("SELECT key, value FROM save_meta;"):
		out[str(row["key"])] = str(row["value"])
	return out

## Bring a save written before the home/away columns up to the current table.
## Adding a column leaves every existing row on zero; the season rebuilds the
## aggregates from its played fixtures when it opens.
func ensure_schema() -> void:
	if not ensure_open():
		return
	var have := {}
	for row in PLDatabase.rows("PRAGMA table_info(league_table);"):
		have[str(row["name"])] = true
	for column in SIDE_COLUMNS:
		if not have.has(column):
			PLDatabase.execute(
				"ALTER TABLE league_table ADD COLUMN %s INTEGER NOT NULL DEFAULT 0;" % column)

func put_meta(key: String, value: String) -> bool:
	if not ensure_open():
		return false
	var ok := PLDatabase.execute(
		"INSERT INTO save_meta (key, value) VALUES (?, ?) "
		+ "ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
		[key, value],
	)
	if ok:
		meta[key] = value
	return ok

func name() -> String:
	return str(meta.get("name", slug))

func status() -> String:
	return str(meta.get("status", "in_progress"))

func set_status(value: String) -> void:
	put_meta("status", value)

func current_date() -> String:
	return str(meta.get("current_date", ""))

func set_date(value: String) -> bool:
	return put_meta("current_date", value)

func matchday() -> int:
	return int(meta.get("matchday", "1"))

func set_matchday(value: int) -> void:
	put_meta("matchday", str(maxi(value, 1)))

func reload() -> void:
	if not ensure_open():
		return
	meta = read_meta()
	rules = LeagueRules.read()
